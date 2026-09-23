class_name HubZone
extends ZoneBase
## RUNEHOLD — small safe settlement: campfire, stone shelters, portals out.

const SIZE := 34.0


func _environment_colors() -> Dictionary:
	return {
		"sky_top": Color(0.16, 0.1, 0.24),
		"sky_horizon": Color(0.75, 0.45, 0.3),  # warm dawn band
		"fog": Color(0.45, 0.3, 0.3),
		"sun": Color(1.0, 0.82, 0.6),
		"sun_energy": 1.35,
	}


func _player_spawn_point() -> Vector3:
	return Vector3(0, 0.2, 10)


func _build_zone() -> void:
	var floor_mat := _material_from_texture("res://assets/textures/floor.png", Color(0.32, 0.28, 0.3), 9.0)
	var stone_mat := _material_from_texture("res://assets/textures/stone.png", Color(0.4, 0.36, 0.42), 2.0)
	var accent_mat := _material_from_texture("res://assets/textures/rune_stone.png", Color(0.3, 0.4, 0.45), 1.0)

	var half := SIZE * 0.5
	_add_box(Vector3(0, -0.5, 0), Vector3(SIZE, 1.0, SIZE), floor_mat)
	for wall in [
		[Vector3(0, 1.25, -half), Vector3(SIZE, 2.5, 1)],
		[Vector3(0, 1.25, half), Vector3(SIZE, 2.5, 1)],
		[Vector3(-half, 1.25, 0), Vector3(1, 2.5, SIZE)],
		[Vector3(half, 1.25, 0), Vector3(1, 2.5, SIZE)],
	]:
		_add_box(wall[0], wall[1], stone_mat)

	# Shelters: simple stone huts with rune-marked lintels.
	for hut in [
		[Vector3(-10, 0, -8), 0.0], [Vector3(10, 0, -9), 25.0], [Vector3(-11, 0, 6), -20.0],
	]:
		var base: Vector3 = hut[0]
		var yaw: float = hut[1]
		_add_box(base + Vector3(0, 1.4, 0), Vector3(5, 2.8, 4.4), stone_mat, Vector3(0, yaw, 0))
		_add_box(base + Vector3(0, 3.0, 0), Vector3(5.8, 0.5, 5.2), accent_mat, Vector3(0, yaw, 0))

	# Campfire: the heart of the hub.
	var fire_pos := Vector3(0, 0, -2)
	for i in 6:
		var a := TAU * i / 6.0
		_add_box(fire_pos + Vector3(cos(a) * 1.1, 0.15, sin(a) * 1.1), Vector3(0.35, 0.3, 0.35), stone_mat)
	var log_mat := StandardMaterial3D.new()
	log_mat.albedo_color = Color(0.32, 0.22, 0.15)
	_add_box(fire_pos + Vector3(0, 0.15, 0), Vector3(0.8, 0.18, 0.25), log_mat, Vector3(0, 30, 0))
	_add_box(fire_pos + Vector3(0, 0.3, 0), Vector3(0.7, 0.16, 0.22), log_mat, Vector3(0, -40, 0))

	var flame_light := OmniLight3D.new()
	flame_light.light_color = Color(1.0, 0.6, 0.25)
	flame_light.light_energy = 2.2
	flame_light.omni_range = 9.0
	flame_light.position = fire_pos + Vector3(0, 1.0, 0)
	world.add_child(flame_light)
	var flicker := flame_light.create_tween().set_loops()
	flicker.tween_property(flame_light, "light_energy", 1.7, 0.35).set_trans(Tween.TRANS_SINE)
	flicker.tween_property(flame_light, "light_energy", 2.3, 0.42).set_trans(Tween.TRANS_SINE)

	var embers := GPUParticles3D.new()
	embers.amount = 22
	embers.lifetime = 1.6
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 16.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 2.0
	pm.gravity = Vector3(0, 0.6, 0)
	pm.scale_min = 0.7
	pm.scale_max = 1.4
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.35
	embers.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.14)
	var ember_mat := StandardMaterial3D.new()
	ember_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ember_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	ember_mat.alpha_scissor_threshold = 0.35
	ember_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	ember_mat.billboard_keep_scale = true
	ember_mat.albedo_color = Color(1.0, 0.7, 0.3)
	if ResourceLoader.exists("res://assets/vfx/ember.png"):
		ember_mat.albedo_texture = load("res://assets/vfx/ember.png")
	ember_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	quad.material = ember_mat
	embers.draw_pass_1 = quad
	world.add_child(embers)
	embers.global_position = fire_pos + Vector3(0, 0.5, 0)

	_add_ambience("campfire_loop", fire_pos + Vector3(0, 0.5, 0), -6.0)

	# Portals.
	var highlands := Portal.new()
	highlands.destination_scene = "res://scenes/ashen_highlands.tscn"
	highlands.label_text = "ASHEN HIGHLANDS"
	world.add_child(highlands)
	highlands.global_position = Vector3(0, 0, -13)

	var lab := Portal.new()
	lab.destination_scene = "res://scenes/combat_lab.tscn"
	lab.label_text = "TRAINING GROUNDS"
	world.add_child(lab)
	lab.global_position = Vector3(13, 0, 0)

	# Shortcut to the Spire once the Colossus has fallen.
	if SaveGame.has_flag(&"colossus_defeated"):
		var spire := Portal.new()
		spire.destination_scene = "res://scenes/shattered_spire.tscn"
		spire.label_text = "THE SHATTERED SPIRE"
		world.add_child(spire)
		spire.global_position = Vector3(-13, 0, -2)
