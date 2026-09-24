class_name AshenHighlands
extends ZoneBase
## The open Ashen Highlands (M08): a 384 m heightmap zone built from the
## baked layout (assets/world/highlands, tools/worldgen). Routes, ridges and
## pads come from the terrain; every point of interest is data the
## PoiBuilder turns into camps, ruins, chests, landmarks, gates and the
## Colossus arena on the north plateau. Level bands rise from the south
## slopes (1) over the middle (2) to the north and the Emberfall Ridge (3).

const LAYOUT_DIR := "res://assets/world/highlands"
const SCATTER_SEED := 2609

var layout: ZoneLayout
var boss: AshveinColossus = null
var boss_portal: Portal
var spire_portal: Portal
## Camp / ambush spawners by POI id.
var camps: Dictionary = {}
## Chests by POI id.
var chests: Dictionary = {}
var arena_centre: Vector3 = Vector3.ZERO
var _boss_spawn: Vector3 = Vector3.ZERO
var _boss_started: bool = false
var _boss_trigger: EncounterSpawner
var _blockers: Array[StaticBody3D] = []


## M06 gold-standard look (ember dusk). Palette from assets/art_spec.json;
## key light low from the west-southwest = side light on a S->N path, so
## chunky forms read in two values with long shadows across the path.
func _zone_look() -> ZoneLook:
	var l := ZoneLook.new()
	l.sky_top = ArtKit.color("palettes.highlands.sky.top")
	l.sky_mid = ArtKit.color("palettes.highlands.sky.mid")
	l.sky_horizon = ArtKit.color("palettes.highlands.sky.horizon")
	l.sun_disc = ArtKit.color("palettes.highlands.sky.sun")
	l.fog_color = ArtKit.color("palettes.highlands.fog")
	l.ambient_color = ArtKit.color("palettes.highlands.ambient")
	l.ambient_energy = 1.35
	l.sun_rotation_deg = Vector3(-40, -67.5, 0)
	l.sun_color = Color(1.0, 0.8, 0.6)
	l.sun_energy = 1.3
	l.rim_rotation_deg = Vector3(-25, 112.5, 0)
	l.rim_color = Color(0.42, 0.38, 0.78)
	l.rim_energy = 0.5
	l.silhouette_far = Color(0.29, 0.15, 0.22)
	l.silhouette_near = Color(0.17, 0.1, 0.14)
	l.cloud_color = Color(0.38, 0.18, 0.27)
	l.cloud_lit_color = Color(0.7, 0.35, 0.3)
	l.cloud_amount = 0.42
	l.split_shadows = Color(0.47, 0.46, 0.56)
	l.split_highlights = Color(0.56, 0.5, 0.44)
	l.split_amount = 0.35
	l.vignette = 0.18
	l.ash_fall = 1.0
	# M08 open zone: haze hides the far edge (the rim mountains and the sky
	# LUT carry the horizon); height fog pools in the valleys.
	l.camera_far = 560.0
	l.fog_density = 0.016
	l.fog_height = 12.0
	l.fog_height_density = 0.03
	return l


func _zone_music() -> String:
	return "highlands"


func zone_title() -> String:
	return "ASHEN HIGHLANDS"


## Level bands from the layout grid (south 1, middle 2, north + east ridge 3);
## the Colossus is always 3.
func _enemy_level(enemy: EnemyBase, pos: Vector3) -> int:
	if enemy is AshveinColossus:
		return 3
	return layout.level_at(pos.x, pos.z) if layout != null else 1


func _warm_up_ids() -> Array[String]:
	return ["rusher", "caster", "assassin", "brute", "colossus"]


func _environment_colors() -> Dictionary:
	return {
		"sky_top": Color(0.14, 0.07, 0.16),
		"sky_horizon": Color(0.7, 0.3, 0.22),  # ember haze
		"fog": Color(0.4, 0.22, 0.2),
		"sun": Color(1.0, 0.72, 0.5),
		"sun_energy": 1.15,
	}


func _player_spawn_point() -> Vector3:
	return poi_position("spawn") + Vector3(0, 0.2, 0)


## World position of a layout POI (ground height), Vector3.INF when unknown.
func poi_position(id: String) -> Vector3:
	if layout == null:
		return Vector3.INF
	var poi := layout.find(id)
	if poi.is_empty():
		# arena gates and other sub-entries
		for p in layout.pois:
			for sub in p.get("portals", []):
				if String(sub.get("id", "")) == id:
					return ZoneLayout.pos_of(sub)
		return Vector3.INF
	var pos := ZoneLayout.pos_of(poi)
	if terrain != null:
		pos.y = terrain.height_at(pos.x, pos.z)
	return pos


func _build_zone() -> void:
	layout = ZoneLayout.load_from(LAYOUT_DIR + "/layout.json")
	var ground_mat: Material = ArtKit.masked(&"highlands_ground",
		load(LAYOUT_DIR + "/path_mask.png") as Texture2D, layout.bounds())
	terrain = Terrain.load_from(LAYOUT_DIR, ground_mat)
	world.add_child(terrain)

	for poi in layout.pois:
		var made := PoiBuilder.build(self, poi)
		var id := String(poi.get("id", ""))
		match String(poi.get("type", "")):
			"camp", "ambush", "elite_patrol":
				camps[id] = made["spawner"]
			"chest":
				chests[id] = made["chest"]
			"ruin":
				if made.get("chest") != null:
					chests[id] = made["chest"]
				if made.get("spawner") != null:
					camps[id] = made["spawner"]
			"arena":
				arena_centre = made["centre"]
				_boss_spawn = made["boss_spawn"]
				_boss_trigger = made["trigger"]
				for p: Portal in made["portals"]:
					if p.get_meta(&"poi_id", "") == "gate_spire":
						spire_portal = p
					else:
						boss_portal = p
	_dress_ridges()
	_dress_rim()
	_scatter()
	_add_ambience("wind_loop", Vector3.INF, -14.0)


## Rock hulls along the baked ridge lines: silhouettes on the crests and
## cover along the passes. Routes and pads stay clear.
func _dress_ridges() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SCATTER_SEED
	var pads := _pads()
	var corridors := _route_segments()
	for ridge in layout.raw.get("ridges", []):
		var a := Vector2(float(ridge["a"][0]), float(ridge["a"][1]))
		var b := Vector2(float(ridge["b"][0]), float(ridge["b"][1]))
		var width := float(ridge["width"])
		var length := a.distance_to(b)
		var count := maxi(int(length / 9.0), 2)
		for i in count:
			var t := (float(i) + 0.5) / float(count)
			var side := (b - a).normalized().orthogonal()
			var p := a.lerp(b, t) + side * rng.randf_range(-width * 0.25, width * 0.25)
			if _near_pad(p, pads, 3.0) or _near_route(p, corridors, 3.5):
				continue
			var size := Vector3(rng.randf_range(2.0, 4.5), rng.randf_range(1.6, 3.4), rng.randf_range(1.6, 3.2))
			PoiBuilder.rock(self, Vector3(p.x, 0.0, p.y), size, rng.randf_range(0.0, TAU))


## Charred trees on the rim slopes all around (each on a thin collider).
func _dress_rim() -> void:
	if look == null or not look.art_pass:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = SCATTER_SEED + 7
	var rim := float(layout.raw.get("rim", {}).get("start_m", 176.0))
	for i in 40:
		var a := TAU * float(i) / 40.0 + rng.randf_range(-0.05, 0.05)
		var r := rim + rng.randf_range(3.0, 10.0)
		# square rim: project the angle onto the square's edge
		var d := Vector2(cos(a), sin(a))
		var scale := r / maxf(absf(d.x), absf(d.y))
		var p := d * scale
		var spot := Vector3(p.x, 0.0, p.y)
		spot.y = ground_y(spot)
		var blocker := PoiBuilder.blocker(self, spot, Vector3(0.6, 3.0, 0.6))
		_blockers.append(blocker)
		PoiBuilder.prop(self, "charred_tree", spot, rng.randf_range(0.0, TAU), rng.randf_range(1.1, 1.5))


## Rule-placed scatter: tufts and stones at every rock base and ruin wall,
## plus sparse fields over the open ground (never on pads, never on steep
## slopes). Ground height and tilt come from the terrain.
func _scatter() -> void:
	if look == null or not look.art_pass:
		return
	var keep_clear: Array[Vector3] = []
	for pad in _pads():
		keep_clear.append(Vector3(pad.x, pad.y, pad.z + 0.5))
	var half := layout.size_m * 0.5 - 4.0
	Scatter.populate(self, {
		"area": Rect2(-half, -half, half * 2.0, half * 2.0),
		"obstacles": scatter_obstacles(),
		"exclude": keep_clear,
		"height_at": terrain.height_at,
		"normal_at": terrain.normal_at,
		"tilt": 0.6,
		"seed": SCATTER_SEED,
		"items": [
			{"prop": "ash_tuft", "per_m": 0.7, "band": Vector2(0.3, 1.4), "scale": Vector2(0.75, 1.3),
				"cluster": Vector2i(2, 5), "spread": 0.35},
			{"prop": "stone_cluster", "per_m": 0.25, "band": Vector2(0.25, 0.9), "scale": Vector2(0.8, 1.6),
				"cluster": Vector2i(1, 2), "spread": 0.3},
			{"prop": "ash_tuft", "field": true, "per_100m2": 0.55, "slope_max": 0.55, "scale": Vector2(0.7, 1.2),
				"cluster": Vector2i(2, 4), "spread": 0.6},
			{"prop": "stone_cluster", "field": true, "per_100m2": 0.22, "slope_max": 0.7, "scale": Vector2(0.7, 1.5),
				"cluster": Vector2i(1, 2), "spread": 0.4},
		],
	})


## Keep-clear circles (x, z, radius) of every flat pad in the layout.
func _pads() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for poi in layout.pois:
		var pad := float(poi.get("pad", 0.0))
		if pad > 0.0:
			var p := ZoneLayout.pos_of(poi)
			out.append(Vector3(p.x, p.z, pad))
		for sub in poi.get("portals", []):
			var sp := ZoneLayout.pos_of(sub)
			out.append(Vector3(sp.x, sp.z, 5.0))
	return out


func _near_pad(p: Vector2, pads: Array[Vector3], margin: float) -> bool:
	for pad in pads:
		if p.distance_to(Vector2(pad.x, pad.y)) < pad.z + margin:
			return true
	return false


## Route polylines as [a, b, half_width] segments.
func _route_segments() -> Array:
	var segs := []
	for route in layout.routes:
		var pts := layout.route_points(String(route.get("id", "")))
		var half_w := float(route.get("width", 3.0)) * 0.5
		for i in pts.size() - 1:
			segs.append([pts[i], pts[i + 1], half_w])
	return segs


func _near_route(p: Vector2, segs: Array, margin: float) -> bool:
	for seg: Array in segs:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-4), 0.0, 1.0)
		if p.distance_to(a + ab * t) < float(seg[2]) + margin:
			return true
	return false


func _physics_process(_delta: float) -> void:
	# Once beaten, the colossus stays beaten (world flag).
	if _boss_started or _boss_trigger == null or players.is_empty() or SaveGame.has_flag(&"colossus_defeated"):
		return
	if not players_within(_boss_trigger.global_position, _boss_trigger.trigger_radius).is_empty():  # M07b: any hero
		_start_boss_fight()


func _start_boss_fight() -> void:
	_boss_started = true
	boss = AshveinColossus.new()
	_spawn_enemy(boss, ground_point(_boss_spawn, 0.2))
	hud.show_boss_bar("ASHVEIN COLOSSUS")
	boss.boss_health_changed.connect(hud.update_boss_bar)
	boss.enemy_died.connect(_on_boss_died)
	GameFeel.camera_shake(0.3)


func _on_boss_died(_enemy: EnemyBase) -> void:
	hud.hide_boss_bar()
	if MusicDirector.instance != null:
		MusicDirector.instance.stinger("victory")
	boss_portal.set_locked(false)
	spire_portal.set_locked(false)
	SaveGame.set_flag(&"colossus_defeated")
	# Guaranteed legendary on top of the regular drop roll.
	var legendary := ItemGenerator.generate_legendary()
	ItemGenerator.apply_item_level(legendary, 3)
	spawn_item_drop(legendary, boss_portal.global_position + Vector3(1.5, 0, 3))
	hud.toast("The Shattered Spire stands unsealed", Color(0.7, 0.55, 1.0))
