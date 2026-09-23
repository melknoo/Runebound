class_name SpireZone
extends ZoneBase
## THE SHATTERED SPIRE — interior dungeon: entry hall, broken gallery with
## raised platforms, rune vault, and the Vessel boss chamber. Dark, torch-lit,
## telegraphs carry the readability.

const WIDTH := 50.0
const LENGTH := 72.0

var boss: ShatteredVessel = null
var boss_portal: Portal
var _boss_trigger_pos := Vector3(0, 0, -22)
var _boss_started: bool = false
var _arena_center := Vector3(0, 0, -29)


func _player_spawn_point() -> Vector3:
	return Vector3(0, 0.2, 27)


## Interior: near-black background, heavy violet fog, no sun — crystals and
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


func _build_zone() -> void:
	var floor_mat := _material_from_texture("res://assets/textures/spire_floor.png", Color(0.16, 0.13, 0.22), 16.0)
	var wall_mat := _material_from_texture("res://assets/textures/spire_wall.png", Color(0.22, 0.18, 0.32), 2.5)
	var accent_mat := _material_from_texture("res://assets/textures/rune_stone.png", Color(0.3, 0.4, 0.45), 1.0)

	var hw := WIDTH * 0.5
	var hl := LENGTH * 0.5
	_add_box(Vector3(0, -0.5, 0), Vector3(WIDTH, 1.0, LENGTH), floor_mat)
	# Perimeter walls, tall — it's a tower interior.
	_add_box(Vector3(0, 5.0, -hl), Vector3(WIDTH, 10, 2), wall_mat)
	_add_box(Vector3(0, 5.0, hl), Vector3(WIDTH, 10, 2), wall_mat)
	_add_box(Vector3(-hw, 5.0, 0), Vector3(2, 10, LENGTH), wall_mat)
	_add_box(Vector3(hw, 5.0, 0), Vector3(2, 10, LENGTH), wall_mat)

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
	_add_box(Vector3(-14, 1.0, 18), Vector3(3, 2, 3), accent_mat)
	_add_box(Vector3(13, 1.25, 10), Vector3(2.5, 2.5, 2.5), accent_mat)

	# --- Section 2: broken gallery (verticality) ---
	# Raised side platforms with ramps; casters shoot from above.
	_add_box(Vector3(-13, 0.9, 0), Vector3(10, 1.8, 8), wall_mat)   # west platform
	_add_box(Vector3(13, 0.9, 0), Vector3(10, 1.8, 8), wall_mat)    # east platform
	_add_box(Vector3(7.2, 0.7, 4.5), Vector3(4, 0.4, 5), wall_mat, Vector3(-20, 0, 0))  # ramp east
	_add_camp(Vector3(-13, 2.0, 0), ["caster"] as Array[String], 14.0)
	_add_camp(Vector3(13, 2.0, 0), ["caster"] as Array[String], 14.0)
	_add_camp(Vector3(0, 0, -2), ["assassin", "assassin"] as Array[String], 11.0)
	_torch(Vector3(-6, 0, 2))
	_torch(Vector3(6, 0, -6))

	# Treasure alcove west, guarded by a warden.
	_add_box(Vector3(-19, 2.5, -8.5), Vector3(12, 5, 1.5), wall_mat)
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
	_add_box(Vector3(-12, 2.0, -19), Vector3(1.2, 4, 1.2), accent_mat, Vector3(0, 25, 0))
	_add_box(Vector3(12, 2.0, -13), Vector3(1.2, 4, 1.2), accent_mat, Vector3(0, -15, 0))

	# --- Boss chamber ---
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


func _divider(z: float, door_x: float, mat: Material) -> void:
	# Wall across the width with an 8m door gap centered on door_x.
	var hw := WIDTH * 0.5
	var left_width := (door_x - 4.0) - (-hw)
	var right_width := hw - (door_x + 4.0)
	if left_width > 0.5:
		_add_box(Vector3(-hw + left_width * 0.5, 3.0, z), Vector3(left_width, 6, 1.5), mat)
	if right_width > 0.5:
		_add_box(Vector3(hw - right_width * 0.5, 3.0, z), Vector3(right_width, 6, 1.5), mat)


func _torch(pos: Vector3) -> void:
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
	if player.global_position.distance_to(_boss_trigger_pos) <= 10.0:
		_start_boss_fight()


func _start_boss_fight() -> void:
	_boss_started = true
	boss = ShatteredVessel.new()
	var anchors: Array[Vector3] = [_arena_center]
	for i in 4:
		var a := TAU * i / 4.0 + 0.4
		anchors.append(_arena_center + Vector3(cos(a) * 7.0, 0, sin(a) * 7.0))
	boss.setup_arena(_arena_center, anchors)
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
	boss_portal.set_locked(false)
	SaveGame.set_flag(&"spire_cleansed")
	spawn_item_drop(ItemGenerator.generate_legendary(), boss_portal.global_position + Vector3(-2, 0, 3))
	for i in 2:
		var rare := ItemGenerator.generate(2)
		spawn_item_drop(rare, boss_portal.global_position + Vector3(1 + i * 1.5, 0, 3))
	hud.toast("The Shattered Rune falls silent", Color(0.8, 0.6, 1.0))
