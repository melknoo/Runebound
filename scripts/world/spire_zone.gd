class_name SpireZone
extends ZoneBase
## THE SHATTERED SPIRE â€” interior dungeon: entry hall, broken gallery with
## raised platforms, rune vault, and the Vessel boss chamber. Dark, torch-lit,
## telegraphs carry the readability.

const WIDTH := 50.0
const LENGTH := 72.0

var boss: ShatteredVessel = null
var boss_portal: Portal
var _boss_trigger_pos := Vector3(0, 0, -22)
var _boss_started: bool = false
var _arena_center := Vector3(0, 0, -29)

## Boss chamber interior: north wall inner face â†’ vault divider's north face.
## Only 10.75 m deep, so blink anchors sit on a flat ellipse, not a circle.
const CHAMBER_MIN_Z := -35.0
const CHAMBER_MAX_Z := -24.25
const BLINK_RADIUS_X := 7.0
const BLINK_RADIUS_Z := 3.5


func _player_spawn_point() -> Vector3:
	return Vector3(0, 0.2, 27)


## Interior: near-black background, heavy violet fog, no sun â€” crystals and
## torches carry the light. Telegraphs must glow against this.
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.02, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.2, 0.38)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 1.0
	env.set_glow_level(4, 0.0)  # level 3 only, as in ZoneBase (perf + tighter bloom)
	env.fog_enabled = true
	env.fog_light_color = Color(0.2, 0.12, 0.3)
	env.fog_density = 0.028
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	world.add_child(world_env)

	# Faint cold top light so silhouettes never fully vanish.
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-70, 20, 0)
	moon.light_color = Color(0.5, 0.45, 0.8)
	moon.light_energy = 0.35
	moon.shadow_enabled = true
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	moon.directional_shadow_max_distance = 60.0
	world.add_child(moon)


## M06 C4: interior ZoneLook (no sun, cold top light, crystal light).
func _zone_look() -> ZoneLook:
	return ZoneLook.spire_interior()


func zone_title() -> String:
	return "THE SHATTERED SPIRE"


## The whole Spire 3, the Vessel 4 (players arrive around level 4-5).
func _enemy_level(enemy: EnemyBase, _pos: Vector3) -> int:
	return 4 if enemy is ShatteredVessel else 3


func _warm_up_ids() -> Array[String]:
	return ["rusher", "caster", "assassin", "warden", "vessel"]


func _zone_music() -> String:
	return "spire"


var _art := false
var _walls: Array[StaticBody3D] = []    # dressed as coursed walls
var _blocks: Array[StaticBody3D] = []   # platforms, cover blocks, ramp
var _pillars: Array[StaticBody3D] = []  # accent pillars -> crystal pillars


func _build_zone() -> void:
	_art = look != null and look.art_pass
	var floor_mat: Material = _rune_floor() if _art else \
		_material_from_texture("res://assets/textures/spire_floor.png", Color(0.16, 0.13, 0.22), 16.0)
	var wall_mat := _material_from_texture("res://assets/textures/spire_wall.png", Color(0.22, 0.18, 0.32), 2.5)
	var accent_mat := _material_from_texture("res://assets/textures/rune_stone.png", Color(0.3, 0.4, 0.45), 1.0)

	var hw := WIDTH * 0.5
	var hl := LENGTH * 0.5
	_add_box(Vector3(0, -0.5, 0), Vector3(WIDTH, 1.0, LENGTH), floor_mat)
	# Perimeter walls, tall â€” it's a tower interior.
	_walls.append(_add_box(Vector3(0, 5.0, -hl), Vector3(WIDTH, 10, 2), wall_mat))
	_walls.append(_add_box(Vector3(0, 5.0, hl), Vector3(WIDTH, 10, 2), wall_mat))
	_walls.append(_add_box(Vector3(-hw, 5.0, 0), Vector3(2, 10, LENGTH), wall_mat))
	_walls.append(_add_box(Vector3(hw, 5.0, 0), Vector3(2, 10, LENGTH), wall_mat))

	# Section dividers with door gaps (gap ~8 wide at varying x).
	_divider(8.0, -4.0, wall_mat)     # hall -> gallery, door west of center
	_divider(-11.0, 5.0, wall_mat)    # gallery -> vault, door east of center
	_divider(-23.5, 0.0, wall_mat)    # vault -> boss chamber, centered door

	# --- Section 1: entry hall ---
	_torch(Vector3(-8, 0, 24))
	_torch(Vector3(8, 0, 24))
	_torch(Vector3(-10, 0, 12))
	_torch(Vector3(10, 0, 12))
	_add_camp(Vector3(0, 0, 14), ["rusher", "caster", "warden"] as Array[String], 11.0)
	_blocks.append(_add_box(Vector3(-14, 1.0, 18), Vector3(3, 2, 3), accent_mat))
	_blocks.append(_add_box(Vector3(13, 1.25, 10), Vector3(2.5, 2.5, 2.5), accent_mat))

	# --- Section 2: broken gallery (verticality) ---
	# Raised side platforms with ramps; casters shoot from above.
	_blocks.append(_add_box(Vector3(-13, 0.9, 0), Vector3(10, 1.8, 8), wall_mat))   # west platform
	_blocks.append(_add_box(Vector3(13, 0.9, 0), Vector3(10, 1.8, 8), wall_mat))    # east platform
	_add_ramp(Vector2(2.8, 8.0), 1.8, Vector2(1.5, 4.0), wall_mat)  # up to the east platform's west edge
	_add_camp(Vector3(-13, 2.0, 0), ["caster"] as Array[String], 14.0)
	_add_camp(Vector3(13, 2.0, 0), ["caster"] as Array[String], 14.0)
	_add_camp(Vector3(0, 0, -2), ["assassin", "assassin"] as Array[String], 11.0)
	_torch(Vector3(-6, 0, 2))
	_torch(Vector3(6, 0, -6))

	# Treasure alcove west, guarded by a warden.
	_walls.append(_add_box(Vector3(-19, 2.5, -8.5), Vector3(12, 5, 1.5), wall_mat))
	_add_camp(Vector3(-19, 0, -5), ["warden"] as Array[String], 7.0)
	var chest1 := TreasureChest.new()
	chest1.min_rarity_bias = 1
	world.add_child(chest1)
	chest1.global_position = Vector3(-21, 0, -6)
	_torch(Vector3(-17, 0, -5))

	# --- Section 3: rune vault ---
	_add_camp(Vector3(0, 0, -16), ["elite", "warden", "caster"] as Array[String], 11.0)
	var chest2 := TreasureChest.new()
	chest2.min_rarity_bias = 1
	world.add_child(chest2)
	chest2.global_position = Vector3(11, 0, -20)
	_torch(Vector3(-9, 0, -14))
	_torch(Vector3(9, 0, -14))
	_pillars.append(_add_box(Vector3(-12, 2.0, -19), Vector3(1.2, 4, 1.2), accent_mat, Vector3(0, 25, 0)))
	_pillars.append(_add_box(Vector3(12, 2.0, -13), Vector3(1.2, 4, 1.2), accent_mat, Vector3(0, -15, 0)))

	# --- Boss chamber ---
	if _art:
		# Torch v2 ring re-placed inside the chamber (the old r = 9.5 circle
		# put torches inside the north wall and out in the vault).
		for i in 8:
			var a := TAU * i / 8.0 + PI / 8.0
			_torch(Vector3(cos(a) * 10.5, 0, -29.6 + sin(a) * 4.2))
	else:
		for i in 8:
			var a := TAU * i / 8.0
			_torch(_arena_center + Vector3(cos(a) * 9.5, 0, sin(a) * 9.5))

	boss_portal = Portal.new()
	boss_portal.destination_scene = "res://scenes/hub.tscn"
	boss_portal.label_text = "RUNEHOLD"
	boss_portal.locked = true
	world.add_child(boss_portal)
	boss_portal.global_position = Vector3(0, 0, -33.5)

	var back := Portal.new()
	back.destination_scene = "res://scenes/ashen_highlands.tscn"
	back.label_text = "ASHEN HIGHLANDS"
	world.add_child(back)
	back.global_position = Vector3(0, 0, 31)

	_add_ambience("spire_drone_loop", Vector3.INF, -12.0)
	if _art:
		_dress_spire()


## Processional rune channel from the entry to the Vessel's floor, through
## every door gap, and a rune octagon around the arena (lines, never rings).
func _rune_floor() -> Material:
	var path: Array[Vector2] = [Vector2(0, 33.5), Vector2(0, 12.5), Vector2(-4, 9.2), Vector2(-4, 6.8),
		Vector2(5, -9.8), Vector2(5, -12.2), Vector2(0, -22.3), Vector2(0, -26.2)]
	var segs: Array[Vector4] = []
	for i in path.size() - 1:
		segs.append(Vector4(path[i].x, path[i].y, path[i + 1].x, path[i + 1].y))
	var c := Vector2(_arena_center.x, -29.6)
	for i in 8:
		var a0 := TAU * i / 8.0 + PI / 8.0
		var a1 := TAU * (i + 1) / 8.0 + PI / 8.0
		segs.append(Vector4(c.x + cos(a0) * 4.6, c.y + sin(a0) * 3.6, c.x + cos(a1) * 4.6, c.y + sin(a1) * 3.6))
	return ArtKit.inlaid(&"spire_floor", segs, ArtKit.color("palettes.spire.rune"), 0.65)


## Spire kit on the existing layout (no coordinates changed, no collision):
## coursed walls with piers and relief arches, crystal pillars, masonry
## blocks, floating shards high overhead, rubble and crystal scatter.
func _dress_spire() -> void:
	for i in _walls.size():
		var body := _walls[i]
		var size := ((body.get_child(1) as CollisionShape3D).shape as BoxShape3D).size
		var piers := SetPieces.masonry_wall(body, &"spire_wall", 6.0, i < 2 or i >= 4)
		if i >= 4 or size.y < 9.0:
			continue
		# Relief arches in every other bay of the perimeter walls (<= 0.3 m).
		var along_x := size.x >= size.z
		var inward := Vector3.ZERO
		match i:
			0: inward = Vector3.BACK
			1: inward = Vector3.FORWARD
			2: inward = Vector3.RIGHT
			3: inward = Vector3.LEFT
		var face := body.global_position - inward * (size.z if along_x else size.x) * 0.5
		for k in piers.size() - 1:
			if k % 2 == 1:
				continue
			var mid := (piers[k] + piers[k + 1]) * 0.5
			var spot := face + (Vector3(mid, 0, 0) if along_x else Vector3(0, 0, mid))
			spot.y = 0.0
			SetPieces.prop(dressing(), "sp_wall_arch", spot, atan2(inward.x, inward.z))
	for body in _blocks:
		((body.get_child(0) as MeshInstance3D).mesh as BoxMesh).material = ArtKit.material(&"spire_wall")
	for body in _ramps:
		((body.get_child(0) as MeshInstance3D).mesh as BoxMesh).material = ArtKit.material(&"spire_wall")
	for body in _pillars:
		SetPieces.wrap_collider(body, "sp_crystal_pillar")
	# Crystals on the cover-block tops (on a collider top: out of the walk space).
	for body: StaticBody3D in _blocks.slice(0, 2):
		var top := body.global_position + Vector3(0, ((body.get_child(1) as CollisionShape3D).shape as BoxShape3D).size.y * 0.5, 0)
		SetPieces.prop(dressing(), "sp_crystal_cluster", top, fposmod(top.x, TAU), 3.2)
	# Floating debris high overhead (gallery and boss chamber), slow bob + turn.
	var rng := RandomNumberGenerator.new()
	rng.seed = 6173
	for k in 18:
		var in_chamber := k >= 10
		var pos := Vector3(rng.randf_range(-20, 20), rng.randf_range(5.0, 8.5),
			rng.randf_range(-33.5, -25.5) if in_chamber else rng.randf_range(-9.5, 6.5))
		var shard := SetPieces.prop(dressing(), "sp_shard", pos, rng.randf_range(0, TAU), rng.randf_range(0.8, 1.8))
		if shard == null:
			continue
		shard.rotation = Vector3(rng.randf_range(-0.6, 0.6), shard.rotation.y, rng.randf_range(-0.6, 0.6))
		for mi: MeshInstance3D in shard.find_children("*", "MeshInstance3D", true, false):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # no moving blots on fight floors
		var bob := shard.create_tween().set_loops()
		var rise := rng.randf_range(0.15, 0.35)
		bob.tween_property(shard, "position:y", pos.y + rise, rng.randf_range(2.2, 3.4)).set_trans(Tween.TRANS_SINE)
		bob.tween_property(shard, "position:y", pos.y - rise, rng.randf_range(2.2, 3.4)).set_trans(Tween.TRANS_SINE)
		var turn := shard.create_tween().set_loops()
		turn.tween_property(shard, "rotation:y", shard.rotation.y + TAU, rng.randf_range(14.0, 26.0))
	var bodies: Array[StaticBody3D] = []
	for group: Array[StaticBody3D] in [_walls, _blocks, _pillars]:
		bodies.append_array(group)
	var obstacles := scatter_obstacles(bodies)
	# Spawn, portals, chests, every camp's fight space and the Vessel's floor.
	var keep_clear: Array[Vector3] = [Vector3(0, 27, 3.0), Vector3(0, 31, 2.6), Vector3(0, -33.5, 2.6),
		Vector3(-21, -6, 1.6), Vector3(11, -20, 1.6), Vector3(0, 14, 3.5), Vector3(0, -2, 3.5),
		Vector3(-19, -5, 3.0), Vector3(0, -16, 3.5), Vector3(0, -29.6, 7.0)]
	Scatter.populate(self, {
		"area": Rect2(-WIDTH * 0.5 + 1.0, -LENGTH * 0.5 + 1.0, WIDTH - 2.0, LENGTH - 2.0),
		"obstacles": obstacles,
		"exclude": keep_clear,
		"seed": 7919,
		"items": [
			{"prop": "sp_rubble", "per_m": 0.35, "band": Vector2(0.25, 1.0), "scale": Vector2(0.8, 1.5),
				"cluster": Vector2i(1, 3), "spread": 0.35},
			{"prop": "sp_crystal_cluster", "per_m": 0.18, "band": Vector2(0.25, 0.7), "scale": Vector2(0.8, 1.4),
				"cluster": Vector2i(1, 2), "spread": 0.25},
		],
	})


var _ramps: Array[StaticBody3D] = []


## Ramp rising along +X from floor level at x_range.x to `height` at x_range.y,
## spanning z_range. The box is placed so its TOP face runs exactly between
## those two edges (the underside dips into the floor / platform).
func _add_ramp(x_range: Vector2, height: float, z_range: Vector2, mat: Material) -> void:
	const THICKNESS := 0.4
	var run := x_range.y - x_range.x
	var angle := atan2(height, run)
	var length := sqrt(run * run + height * height)
	var top_mid := Vector3((x_range.x + x_range.y) * 0.5, height * 0.5, (z_range.x + z_range.y) * 0.5)
	var up_normal := Vector3(-sin(angle), cos(angle), 0.0)
	_ramps.append(_add_box(top_mid - up_normal * THICKNESS * 0.5, Vector3(length, THICKNESS, z_range.y - z_range.x),
		mat, Vector3(0, 0, rad_to_deg(angle))))


## Vessel blink points: centre + 4 on an ellipse that stays â‰¥1.2 m inside the
## chamber walls (the old r = 7 circle put one anchor in the north wall and one
## in the vault doorway).
func blink_anchors() -> Array[Vector3]:
	var anchors: Array[Vector3] = [_arena_center]
	for i in 4:
		var a := TAU * i / 4.0 + 0.4
		anchors.append(_arena_center + Vector3(cos(a) * BLINK_RADIUS_X, 0, sin(a) * BLINK_RADIUS_Z))
	return anchors


func _divider(z: float, door_x: float, mat: Material) -> void:
	# Wall across the width with an 8m door gap centered on door_x.
	var hw := WIDTH * 0.5
	var left_width := (door_x - 4.0) - (-hw)
	var right_width := hw - (door_x + 4.0)
	if left_width > 0.5:
		_walls.append(_add_box(Vector3(-hw + left_width * 0.5, 3.0, z), Vector3(left_width, 6, 1.5), mat))
	if right_width > 0.5:
		_walls.append(_add_box(Vector3(hw - right_width * 0.5, 3.0, z), Vector3(right_width, 6, 1.5), mat))


func _torch(pos: Vector3) -> void:
	if _art:
		_beacon(pos)
		return
	var pillar := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.35, 1.6, 0.35)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.17, 0.3)
	mesh.material = mat
	pillar.mesh = mesh
	world.add_child(pillar)
	pillar.global_position = pos + Vector3(0, 0.8, 0)

	var crystal := MeshInstance3D.new()
	var c_mesh := PrismMesh.new()
	c_mesh.size = Vector3(0.3, 0.5, 0.3)
	var c_mat := StandardMaterial3D.new()
	c_mat.albedo_color = Color(0.55, 0.9, 0.85)
	c_mat.emission_enabled = true
	c_mat.emission = Color(0.4, 0.9, 0.85)
	c_mat.emission_energy_multiplier = 2.2
	c_mesh.material = c_mat
	crystal.mesh = c_mesh
	world.add_child(crystal)
	crystal.global_position = pos + Vector3(0, 1.85, 0)

	var light := OmniLight3D.new()
	light.light_color = Color(0.45, 0.85, 0.8)
	light.light_energy = 1.6
	light.omni_range = 9.0
	light.shadow_enabled = false
	world.add_child(light)
	light.global_position = pos + Vector3(0, 2.0, 0)


## Torch v2: a crystal floating above head height (bottom >= 2.05 m, never
## in the walk space), shards orbiting it, the same cold light as before.
func _beacon(pos: Vector3) -> void:
	var root := SetPieces.prop(dressing(), "sp_beacon", pos + Vector3(0, 2.55, 0), fposmod(pos.x * 1.3 + pos.z, TAU))
	if root == null:
		return
	var bob := root.create_tween().set_loops()
	bob.tween_property(root, "position:y", pos.y + 2.68, 1.6).set_trans(Tween.TRANS_SINE)
	bob.tween_property(root, "position:y", pos.y + 2.5, 1.6).set_trans(Tween.TRANS_SINE)
	var orbit := root.find_child("orbit", true, false) as Node3D
	if orbit != null:
		var spin := orbit.create_tween().set_loops()
		spin.tween_property(orbit, "rotation:y", TAU, 5.0).from(0.0)
	var light := OmniLight3D.new()
	light.light_color = Color(0.45, 0.85, 0.8)
	light.light_energy = 2.4
	light.omni_range = 10.0
	light.omni_attenuation = 0.7
	light.shadow_enabled = false
	root.add_child(light)


func _add_camp(pos: Vector3, composition: Array[String], radius: float) -> void:
	var spawner := EncounterSpawner.new()
	spawner.composition = composition
	spawner.trigger_radius = radius
	world.add_child(spawner)
	spawner.global_position = pos


func _physics_process(_delta: float) -> void:
	if _boss_started or player == null or SaveGame.has_flag(&"spire_cleansed"):
		if not _boss_started and SaveGame.has_flag(&"spire_cleansed") and boss_portal.locked:
			boss_portal.set_locked(false)
		return
	if not players_within(_boss_trigger_pos, 10.0).is_empty():  # M07b: any hero starts it
		_start_boss_fight()


func _start_boss_fight() -> void:
	_boss_started = true
	boss = ShatteredVessel.new()
	boss.setup_arena(_arena_center, blink_anchors())
	_spawn_enemy(boss, _arena_center)
	hud.show_boss_bar("VESSEL OF THE SHATTERED RUNE")
	boss.boss_health_changed.connect(hud.update_boss_bar)
	boss.summon_requested.connect(_on_boss_summon)
	boss.enemy_died.connect(_on_boss_died)
	GameFeel.camera_shake(0.4)


func _on_boss_summon(pos: Vector3) -> void:
	var add := spawn_by_id("rusher", pos)
	VFX.flash(get_tree().current_scene, pos + Vector3(0, 1.0, 0), Color(0.7, 0.4, 1.0), 1.2, 0.2)
	add.enemy_died.connect(func(_e: EnemyBase) -> void:
		if boss != null and is_instance_valid(boss):
			boss.notify_add_died()
	)


func _on_boss_died(_enemy: EnemyBase) -> void:
	hud.hide_boss_bar()
	if MusicDirector.instance != null:
		MusicDirector.instance.stinger("victory")
	boss_portal.set_locked(false)
	SaveGame.set_flag(&"spire_cleansed")
	var legendary := ItemGenerator.generate_legendary()
	ItemGenerator.apply_item_level(legendary, 4)
	spawn_item_drop(legendary, boss_portal.global_position + Vector3(-2, 0, 3))
	for i in 2:
		var rare := ItemGenerator.generate(2)
		ItemGenerator.apply_item_level(rare, 4)
		spawn_item_drop(rare, boss_portal.global_position + Vector3(1 + i * 1.5, 0, 3))
	hud.toast("The Shattered Rune falls silent", Color(0.8, 0.6, 1.0))
