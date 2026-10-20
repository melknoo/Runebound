class_name AshRoadZone
extends AshenHighlands
## M14a phase 5: the prologue, "The Ash Road" (STORY_DESIGN "The campaign"):
## a night road from the edge of Ashwick down to Runehold, baked like the
## Highlands (tools/worldgen/ash_road_layout.py -> assets/world/ash_road), so
## it borrows their open-zone plumbing - terrain, POIs through PoiBuilder,
## the map and compass, area names, the dressing - and builds its own story
## pieces: walls that keep the road linear, the bridge over the gorge (it
## breaks behind the hero, `story_fx("bridge_collapse")`), the Reeve at his
## toll gate, and death back at the last place the story reached. The quest
## `p_ash_road` and the stage (Edda, the supply cart) are data. New
## characters start here; there is no shrine and no discovery card (the
## camera pan's act card opens the prologue).

const DIR := "res://assets/world/ash_road"
const SCENE := "res://scenes/ash_road.tscn"
## Where a hero who fell comes back, by the prologue's current step.
const CHECKPOINTS := {"wake": "spawn", "road": "spawn", "shard_talk": "clearing", "cart": "clearing",
	"bridge": "clearing", "toll": "bridge_n", "gate": "toll", "runehold": "toll"}
const VALLEY_HALF := 44.0
const GORGE_Z := -40.0
const GORGE_RIM := 9.5
const BRIDGE_HALF_WIDTH := 1.9
const TOLL_TRIGGER := 13.0
const TOLL_HALF := 15.0

var bridge_deck: Node3D = null
var bridge_down: bool = false
var reeve: RisenReeve = null
var _reeve_started: bool = false
var _bridge_gate: StaticBody3D = null


## Night on the ash road: the ember haze gone dark, a cold rim, ash falling.
func _zone_look() -> ZoneLook:
	var l := super()
	l.sky_top = Color(0.04, 0.03, 0.08)
	l.sky_mid = Color(0.09, 0.06, 0.13)
	l.sky_horizon = Color(0.3, 0.12, 0.1)
	l.sun_disc = Color(0.75, 0.32, 0.18)
	l.fog_color = Color(0.13, 0.09, 0.13)
	l.ambient_color = Color(0.32, 0.3, 0.48)
	l.ambient_energy = 0.85
	l.sun_rotation_deg = Vector3(-28, -40, 0)
	l.sun_color = Color(0.85, 0.48, 0.32)
	l.sun_energy = 0.6
	l.rim_color = Color(0.36, 0.42, 0.78)
	l.rim_energy = 0.55
	l.cloud_color = Color(0.12, 0.08, 0.14)
	l.cloud_lit_color = Color(0.45, 0.2, 0.18)
	l.camera_far = 380.0
	l.fog_density = 0.022
	l.ash_fall = 1.3
	return l


func zone_title() -> String:
	return ""  # no discovery card or XP: the prologue's camera pan carries the act card


func _enemy_level(_enemy: EnemyBase, _pos: Vector3) -> int:
	return 1


func _warm_up_ids() -> Array[String]:
	return ["rusher", "caster", "grave_shambler", "risen_reeve"]


func _build_zone() -> void:
	layout = ZoneLayout.load_from(DIR + "/layout.json")
	var ground_mat: ShaderMaterial = ArtKit.masked(&"highlands_ground",
		load(DIR + "/path_mask.png") as Texture2D, layout.bounds())
	terrain = Terrain.load_from(DIR, ground_mat)
	world.add_child(terrain)
	_map_texture = load(DIR + "/map.png") as Texture2D
	for poi in layout.pois:
		var made := PoiBuilder.build(self, poi)
		var id := String(poi.get("id", ""))
		match String(poi.get("type", "")):
			"ambush":
				camps[id] = made["spawner"]
			"portal":
				if made.get("portal") != null:
					boss_portal = made["portal"]  # the gate to Runehold (sealed until the Reeve falls)
	_build_walls()
	_build_bridge()
	if boss_portal != null:
		boss_portal.set_locked(true)
	_dress_ridges()
	_dress_rim()
	_dress_story_places()
	_scatter()
	critter_field = CritterField.create(self, layout)
	_add_ambience("wind_loop", Vector3.INF, -12.0)


func _zone_ready() -> void:
	# a hero who crossed before (saved past the bridge) finds it broken
	var ql := QuestLog.of(player) if player != null else null
	if ql != null and ql.has_beat("p_bridge_down"):
		story_fx("bridge_collapse", true)
	if ql != null and ql.has_beat("boss:risen_reeve") and boss_portal != null:
		boss_portal.set_locked(false)


## Invisible walls: both sides of the valley, its ends, and the gorge's rims
## except where the bridge lands.
func _build_walls() -> void:
	var h := 10.0
	for side in [-1.0, 1.0]:
		_wall(Vector3(side * VALLEY_HALF, 0, 0), Vector3(1.0, h, 240.0))
	_wall(Vector3(0, 0, 114.0), Vector3(VALLEY_HALF * 2.0, h, 1.0))
	_wall(Vector3(0, 0, -116.0), Vector3(VALLEY_HALF * 2.0, h, 1.0))
	for rim_z in [GORGE_Z + GORGE_RIM, GORGE_Z - GORGE_RIM]:
		var span := VALLEY_HALF - BRIDGE_HALF_WIDTH
		for side in [-1.0, 1.0]:
			var cx: float = side * (BRIDGE_HALF_WIDTH + span * 0.5)
			_wall(Vector3(cx, 0, rim_z), Vector3(span, h, 1.0))


func _wall(centre: Vector3, size: Vector3) -> StaticBody3D:
	var body := PoiBuilder.blocker(self, Vector3(centre.x, ground_y(centre) - 4.0, centre.z), size + Vector3(0, 4.0, 0))
	body.name = "Wall"
	_blockers.append(body)
	return body


## The old bridge: a plank deck from rim to rim with low rails, at the road's
## height; rails on colliders so nobody steps off it.
func _build_bridge() -> void:
	var south := poi_position("bridge_s")
	var north := poi_position("bridge_n")
	var a := Vector3(0.0, 0.0, GORGE_Z + GORGE_RIM + 2.0)
	var b := Vector3(0.0, 0.0, GORGE_Z - GORGE_RIM - 2.0)
	var y := (south.y + north.y) * 0.5
	bridge_deck = Node3D.new()
	bridge_deck.name = "Bridge"
	world.add_child(bridge_deck)
	var length := absf(a.z - b.z)
	var wood := _zone_material(&"highlands_ruin", "res://assets/textures/floor.png", Color(0.32, 0.24, 0.17), 1.5)
	var deck := _add_box(Vector3(0, y - 0.15, (a.z + b.z) * 0.5), Vector3(BRIDGE_HALF_WIDTH * 2.0, 0.3, length), wood)
	deck.name = "Deck"
	deck.reparent(bridge_deck)
	for side in [-1.0, 1.0]:
		var rail := _add_box(Vector3(side * (BRIDGE_HALF_WIDTH + 0.1), y + 0.45, (a.z + b.z) * 0.5),
			Vector3(0.2, 0.9, length), wood)
		rail.name = "Rail"
		rail.reparent(bridge_deck)


## The story places from the kit: the last camp (its fire, a tent, the cart,
## the graveyard the dead climb out of behind it), charred trees along the
## road, the raiders' fire at the bend, the toll gate (two pillars and a
## beam across the road, the Reeve's booth, braziers) and braziers at the
## gate to Runehold. Solid pieces stand on blockers.
func _dress_story_places() -> void:
	if look == null or not look.art_pass:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 1411
	var camp := poi_position("spawn")
	SetPieces.bonfire(self, ground_point(camp + Vector3(6, 0, -2)))
	for k in 3:
		var a := TAU * float(k) / 3.0 + 0.4
		_prop("log_seat", camp + Vector3(6, 0, -2) + Vector3(cos(a), 0, sin(a)) * 1.6, PI * 0.5 - a)
	_prop("vg_tent", camp + Vector3(13, 0, -7), 0.7, 1.0, Vector3(3.0, 2.2, 3.0))
	_prop("vg_tent", camp + Vector3(-12, 0, -3), -0.4, 0.9, Vector3(2.8, 2.0, 2.8))
	_prop("vl_cart", camp + Vector3(-4, 0, 7), 1.1, 1.0, Vector3(1.6, 1.2, 2.6))
	for i in 7:  # Ashwick's graves behind the camp: the dead climb out of them
		var at := camp + Vector3(-15.0 + i * 5.0 + rng.randf_range(-1.0, 1.0), 0, 11.0 + rng.randf_range(-1.5, 1.5))
		_prop("vl_grave_cross" if i % 2 == 0 else "vl_grave", at, PI + rng.randf_range(-0.3, 0.3), 1.0, Vector3(0.6, 0.9, 0.35))
	_prop("vl_fence", camp + Vector3(-17, 0, 8), 0.0)
	_prop("vl_fence", camp + Vector3(17, 0, 8), 0.0)
	# charred trees along the road, left and right, never on it or on a pad
	var pads := _pads()
	var corridors := _route_segments()
	for route in layout.routes:
		var pts := layout.route_points(String(route.get("id", "")))
		var side := 1.0
		for i in pts.size() - 1:
			var a2 := pts[i]
			var b2 := pts[i + 1]
			var dir := (b2 - a2).normalized()
			var t := rng.randf_range(2.0, 6.0)
			while t < a2.distance_to(b2):
				var c := a2 + dir * t + dir.orthogonal() * side * rng.randf_range(5.5, 10.0)
				side = -side
				t += rng.randf_range(7.0, 12.0)
				if _near_pad(c, pads, 2.0) or _near_route(c, corridors, 3.0):
					continue
				var spot := Vector3(c.x, 0, c.y)
				_prop("charred_tree", spot, rng.randf_range(0.0, TAU), rng.randf_range(1.0, 1.5), Vector3(0.6, 3.0, 0.6))
	# the raiders at the bend: their fire, seats, bones and banners
	var bend := poi_position("ambush_raiders")
	SetPieces.raider_camp(self, ground_point(bend + Vector3(7, 0, -3)), [ground_point(bend + Vector3(10, 0, 2)) as Vector3])
	_prop("vl_barricade", bend + Vector3(-5, 0, 4), 0.5, 1.0, Vector3(3.0, 1.2, 0.6))
	_prop("vg_spears", bend + Vector3(9, 0, -7), 0.3)
	# the toll gate across the road north of the arena
	var gate_z := -93.0
	var road_x := 4.0
	var stone := _zone_material(&"highlands_ruin", "res://assets/textures/stone.png", Color(0.34, 0.31, 0.3), 1.5)
	for px in [road_x - 3.4, road_x + 3.4]:
		var base := Vector3(px, 0, gate_z)
		_add_box(Vector3(px, ground_y(base) + 2.0, gate_z), Vector3(1.0, 4.0, 1.0), stone)
	var beam_y := ground_y(Vector3(road_x, 0, gate_z)) + 4.2
	_add_box(Vector3(road_x, beam_y, gate_z), Vector3(8.2, 0.5, 0.6), stone)
	var booth_at := Vector3(road_x + 9.0, 0, gate_z + 4.0)
	_add_box(Vector3(booth_at.x, ground_y(booth_at) + 1.3, booth_at.z), Vector3(3.2, 2.6, 3.0), stone)
	_prop("vl_rafters", booth_at + Vector3(0, 2.6, 0), 0.0)
	for bx in [road_x - 5.0, road_x + 5.0]:
		_brazier(Vector3(bx, 0, gate_z + 1.0))
	var north := poi_position("gate_north")
	for bx in [-3.5, 3.5]:
		_brazier(north + Vector3(bx, 0, 2.0))


## A kit prop on the ground at `at` (y from the terrain), optionally on a
## blocker of `solid` size.
func _prop(prop_name: String, at: Vector3, yaw: float, scale: float = 1.0, solid: Vector3 = Vector3.ZERO) -> void:
	var spot := Vector3(at.x, ground_y(at), at.z)
	PoiBuilder.prop(self, prop_name, spot, yaw, scale)
	if solid != Vector3.ZERO:
		PoiBuilder.blocker(self, spot, solid * scale, yaw)


## A brazier with a small flickering fire light.
func _brazier(at: Vector3) -> void:
	var spot := Vector3(at.x, ground_y(at), at.z)
	var root := PoiBuilder.prop(self, "brazier", spot, 0.0)
	PoiBuilder.blocker(self, spot, Vector3(0.7, 1.0, 0.7))
	if root == null:
		return
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.3)
	light.light_energy = 1.3
	light.omni_range = 6.0
	light.shadow_enabled = false
	root.add_child(light)
	light.position = Vector3(0, 1.3, 0)
	var flicker := light.create_tween().set_loops()
	flicker.tween_property(light, "light_energy", 1.0, 0.27).set_trans(Tween.TRANS_SINE)
	flicker.tween_property(light, "light_energy", 1.45, 0.39).set_trans(Tween.TRANS_SINE)


## No Colossus, no Spire here (the Highlands' flags change nothing).
func apply_world_flag(_flag: StringName) -> void:
	pass


## Story effects the data names ({"zone": name}, a camera pan's "call" fx).
func story_fx(fx: String, instant: bool = false) -> void:
	match fx:
		"bridge_collapse":
			if bridge_down:
				return
			bridge_down = true
			# behind the hero now: the south end is gone, nobody walks back
			_bridge_gate = _wall(Vector3(0, 0, GORGE_Z - GORGE_RIM + 0.4), Vector3(BRIDGE_HALF_WIDTH * 2.0 + 0.4, 10.0, 1.0))
			if bridge_deck == null:
				return
			for c in bridge_deck.find_children("*", "CollisionShape3D", true, false):
				(c as CollisionShape3D).set_deferred(&"disabled", true)
			if instant or DisplayServer.get_name() == "headless":
				bridge_deck.visible = false
				return
			Sfx.play("earthbreaker_impact", bridge_deck.global_position + Vector3(0, 0, GORGE_Z), -2.0, 0.1, 0.6)
			if camera_rig != null:
				camera_rig.add_trauma(0.5)
			var tw := bridge_deck.create_tween()
			tw.tween_property(bridge_deck, "position:y", -24.0, 1.6).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			tw.parallel().tween_property(bridge_deck, "rotation:x", 0.35, 1.6)
			tw.tween_callback(func() -> void: bridge_deck.visible = false)


func _physics_process(delta: float) -> void:
	super(delta)
	if Net.is_client() or _reeve_started or players.is_empty():
		return
	var toll := poi_position("toll")
	if toll == Vector3.INF:
		return
	for p in players_within(toll, TOLL_TRIGGER):
		if not QuestLog.of(p).has_beat("boss:risen_reeve"):
			_start_reeve(toll)
			return


func _start_reeve(toll: Vector3) -> void:
	_reeve_started = true
	reeve = make_enemy("risen_reeve") as RisenReeve
	reeve.setup_arena(Rect2(toll.x - TOLL_HALF, toll.z - TOLL_HALF, TOLL_HALF * 2.0, TOLL_HALF * 2.0), {})
	_spawn_enemy(reeve, ground_point(toll + Vector3(0, 0, -7.0), 0.2))
	if hud != null:
		hud.show_boss_bar(reeve.display_name.to_upper())
		reeve.boss_health_changed.connect(hud.update_boss_bar)
	reeve.enemy_died.connect(_on_reeve_died)
	GameFeel.camera_shake(0.3)


func _on_reeve_died(_e: EnemyBase) -> void:
	if hud != null:
		hud.hide_boss_bar()
	if boss_portal != null:
		boss_portal.set_locked(false)
	if MusicDirector.instance != null:
		MusicDirector.instance.stinger("victory")


## Death: back where the story last stood (the prologue's checkpoints),
## healed; the Reeve gathers himself again if he still stands.
func _on_player_died(p: Player) -> void:
	p.health.heal_full()
	p.global_position = _respawn_point(p)
	p.velocity = Vector3.ZERO
	p.feel_shake(0.4)
	if reeve != null and is_instance_valid(reeve) and reeve.ai_state != EnemyBase.AIState.DEAD:
		reeve.health.heal_full()
		reeve.global_position = ground_point(poi_position("toll") + Vector3(0, 0, -7.0), 0.2)


func _respawn_point(p: Player) -> Vector3:
	var ql := QuestLog.of(p)
	var step := ql.step_id("p_ash_road") if ql.is_running("p_ash_road") else ""
	var at := poi_position(str(CHECKPOINTS.get(step, "spawn")))
	if at == Vector3.INF:
		return _player_spawn_point()
	return ground_point(at, 0.2)
