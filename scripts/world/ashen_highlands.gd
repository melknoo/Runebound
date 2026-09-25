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
## Waypoint shrines by POI id.
var waypoints: Dictionary = {}
var arena_centre: Vector3 = Vector3.ZERO
var _boss_spawn: Vector3 = Vector3.ZERO
var _boss_started: bool = false
var _boss_trigger: EncounterSpawner
var _blockers: Array[StaticBody3D] = []
## M08 map: POIs a hero sees within `pad + DISCOVER_MARGIN`; named areas
## announce themselves once per visit.
const DISCOVER_MARGIN := 15.0
const DISCOVER_INTERVAL := 0.5
const COMPASS_CAMP_RANGE := 120.0
var _discover_left: float = 0.0
var _area_seen: Dictionary = {}
var _map_texture: Texture2D


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
	_map_texture = load(LAYOUT_DIR + "/map.png") as Texture2D

	for poi in layout.pois:
		var made := PoiBuilder.build(self, poi)
		var id := String(poi.get("id", ""))
		match String(poi.get("type", "")):
			"camp", "ambush", "elite_patrol":
				camps[id] = made["spawner"]
			"chest":
				chests[id] = made["chest"]
			"waypoint":
				waypoints[id] = made["waypoint"]
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


## Death: back at the nearest attuned shrine (else the spawn), healed.
func _on_player_died(p: Player) -> void:
	p.health.heal_full()
	p.global_position = _respawn_point(p)
	p.velocity = Vector3.ZERO
	p.feel_shake(0.4)


func _respawn_point(p: Player) -> Vector3:
	var best := _player_spawn_point()
	var best_d := INF
	for id: String in waypoints:
		var w := waypoints[id] as Waypoint
		if w.is_known(p):
			var d := w.global_position.distance_to(p.global_position)
			if d < best_d:
				best_d = d
				best = _arrival_point(id)
	return best


func _physics_process(delta: float) -> void:
	_discover_left -= delta
	if _discover_left <= 0.0:
		_discover_left = DISCOVER_INTERVAL
		_discover_tick()
	# Once beaten, the colossus stays beaten (world flag). M09: the server starts it.
	if Net.is_client() or _boss_started or _boss_trigger == null or players.is_empty() or SaveGame.has_flag(&"colossus_defeated"):
		return
	if not players_within(_boss_trigger.global_position, _boss_trigger.trigger_radius).is_empty():  # M07b: any hero
		_start_boss_fight()


# ---------------------------------------------------------------------------
# M08 map + compass
# ---------------------------------------------------------------------------

func map_texture() -> Texture2D:
	return _map_texture


func map_bounds() -> Rect2:
	return layout.bounds() if layout != null else Rect2(-192, -192, 384, 384)


## Marker icon per POI type ("" = never shown: ambushes and patrols stay secret).
static func marker_icon(poi: Dictionary) -> String:
	match String(poi.get("type", "")):
		"waypoint": return "waypoint"
		"portal": return "portal"
		"camp": return "camp"
		"chest": return "chest"
		"ruin": return "ruin"
		"landmark": return "landmark"
		"arena": return "boss"
		"dungeon": return "dungeon"
		_: return ""


static func marker_label(poi: Dictionary) -> String:
	match String(poi.get("type", "")):
		"waypoint": return "Shrine: " + String(poi.get("name", "Waypoint"))
		"portal": return "Gate: " + String(poi.get("label", "")).capitalize()
		"camp": return "Raider camp"
		"chest": return "Treasure"
		"ruin": return "Ruin"
		"landmark": return "Landmark"
		"arena": return "Colossus arena"
		"dungeon": return "Sealed gate: " + String(poi.get("label", "")).capitalize()
		_: return ""


## Everything the local hero has seen (shrines count once attuned); the
## spawn gate is always known.
func map_markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if layout == null or player == null or not is_instance_valid(player):
		return out
	for poi in layout.pois:
		var icon := marker_icon(poi)
		if icon == "":
			continue
		var id := String(poi.get("id", ""))
		var type := String(poi.get("type", ""))
		var known := player.map_discovered.has(id) or id == "gate_south"
		if type == "waypoint":
			known = known or player.knows_waypoint(WaypointRegistry.key_for(scene_file_path, id))
		if not known:
			continue
		if type == "camp" and camps.has(id) and (camps[id] as EncounterSpawner).state == EncounterSpawner.State.CLEARED:
			icon = "camp_cleared"
		out.append({"id": id, "pos": ZoneLayout.pos_of(poi), "icon": icon, "label": marker_label(poi), "kind": type})
		if type == "arena":
			for sub in poi.get("portals", []):
				out.append({"id": String(sub.get("id", "")), "pos": ZoneLayout.pos_of(sub), "icon": "portal",
					"label": "Gate: " + String(sub.get("label", "")).capitalize(), "kind": "portal"})
	return out


## The compass shows what guides at range: shrines, gates, the arena, sealed
## gates and armed camps within COMPASS_CAMP_RANGE.
func compass_markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var origin := player.global_position if player != null and is_instance_valid(player) else Vector3.ZERO
	for m in map_markers():
		var kind := String(m["kind"])
		if kind in ["chest", "landmark", "ruin"]:
			continue
		if kind == "camp":
			if String(m["icon"]) == "camp_cleared" or (m["pos"] as Vector3).distance_to(origin) > COMPASS_CAMP_RANGE:
				continue
			m["max_dist"] = COMPASS_CAMP_RANGE
		out.append(m)
	return out


func _discover_tick() -> void:
	if layout == null or players.is_empty():
		return
	for poi in layout.pois:
		if marker_icon(poi) == "":
			continue
		var id := String(poi.get("id", ""))
		var reach := float(poi.get("pad", 0.0)) + DISCOVER_MARGIN
		for p in players_within(ZoneLayout.pos_of(poi), reach):
			if p.discover_poi(id) and p.is_local and String(poi.get("type", "")) == "dungeon" and hud != null:
				hud.toast("A sealed gate: %s" % String(poi.get("label", "")), Color(0.7, 0.55, 1.0))
	if player == null or not is_instance_valid(player):
		return
	for area in layout.areas:
		var id := String(area.get("id", ""))
		if _area_seen.has(id):
			continue
		var centre := ZoneLayout.pos_of(area)
		if Vector2(player.global_position.x - centre.x, player.global_position.z - centre.z).length() <= float(area.get("radius", 50.0)):
			_area_seen[id] = true
			if hud != null:
				hud.area_name(String(area.get("name", id)))


func _start_boss_fight() -> void:
	_boss_started = true
	boss = AshveinColossus.new()
	_spawn_enemy(boss, ground_point(_boss_spawn, 0.2))
	if hud != null:
		hud.show_boss_bar("ASHVEIN COLOSSUS")
		boss.boss_health_changed.connect(hud.update_boss_bar)
	boss.enemy_died.connect(_on_boss_died)
	GameFeel.camera_shake(0.3)


func _on_boss_died(_enemy: EnemyBase) -> void:
	SaveGame.set_flag(&"colossus_defeated")  # co-op: the server tells every client (FLAG)
	apply_world_flag(&"colossus_defeated")
	# Guaranteed legendary on top of the regular drop roll, one per hero (M09).
	for hero in party():
		var legendary := ItemGenerator.generate_legendary()
		ItemGenerator.apply_item_level(legendary, 3)
		give_reward(hero, 0, 0, 0, [legendary] as Array[ItemData], boss_portal.global_position + Vector3(1.5, 0, 3))


func apply_world_flag(flag: StringName) -> void:
	if flag != &"colossus_defeated":
		return
	if hud != null:
		hud.hide_boss_bar()
		hud.toast("The Shattered Spire stands unsealed", Color(0.7, 0.55, 1.0))
	if MusicDirector.instance != null:
		MusicDirector.instance.stinger("victory")
	boss_portal.set_locked(false)
	spire_portal.set_locked(false)
