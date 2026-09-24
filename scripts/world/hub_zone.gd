class_name HubZone
extends ZoneBase
## RUNEHOLD — small safe settlement: campfire, stone shelters, portals out.

const SIZE := 34.0
const FIRE_POS := Vector3(0, 0, -2)
## [position, yaw, door on the back]: doors face the hearth.
const HUTS := [
	[Vector3(-10, 0, -8), 0.0, false], [Vector3(10, 0, -9), 25.0, false], [Vector3(-11, 0, 6), -20.0, true],
]
const PORTAL_SPOTS := {"highlands": Vector3(0, 0, -13), "lab": Vector3(13, 0, 0), "spire": Vector3(-13, 0, -2)}
## M07b: Sigrun stands north of the west hut, by the training gear, facing the hearth.
const TRAINER_SPOT := Vector3(-14.2, 0, -11.6)


## M06 Phase C: the Runehold kit look (warm dawn, granite, sod roofs).
func _zone_look() -> ZoneLook:
	return ZoneLook.runehold()


func _zone_music() -> String:
	return "runehold"


func zone_title() -> String:
	return "RUNEHOLD"


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
	var art := look != null and look.art_pass
	var floor_mat: Material = _paved_ground() if art else \
		_material_from_texture("res://assets/textures/floor.png", Color(0.32, 0.28, 0.3), 9.0)
	var stone_mat := _material_from_texture("res://assets/textures/stone.png", Color(0.4, 0.36, 0.42), 2.0)
	var accent_mat := _material_from_texture("res://assets/textures/rune_stone.png", Color(0.3, 0.4, 0.45), 1.0)

	var half := SIZE * 0.5
	_add_box(Vector3(0, -0.5, 0), Vector3(SIZE, 1.0, SIZE), floor_mat)
	var walls: Array[StaticBody3D] = []
	for wall in [
		[Vector3(0, 1.25, -half), Vector3(SIZE, 2.5, 1)],
		[Vector3(0, 1.25, half), Vector3(SIZE, 2.5, 1)],
		[Vector3(-half, 1.25, 0), Vector3(1, 2.5, SIZE)],
		[Vector3(half, 1.25, 0), Vector3(1, 2.5, SIZE)],
	]:
		walls.append(_add_box(wall[0], wall[1], stone_mat))

	# Shelters: simple stone huts with rune-marked lintels.
	var huts: Array[StaticBody3D] = []
	var roofs: Array[StaticBody3D] = []
	for hut in HUTS:
		var base: Vector3 = hut[0]
		var yaw: float = hut[1]
		huts.append(_add_box(base + Vector3(0, 1.4, 0), Vector3(5, 2.8, 4.4), stone_mat, Vector3(0, yaw, 0)))
		roofs.append(_add_box(base + Vector3(0, 3.0, 0), Vector3(5.8, 0.5, 5.2), accent_mat, Vector3(0, yaw, 0)))

	# Campfire: the heart of the hub.
	var stones: Array[StaticBody3D] = []
	for i in 6:
		var a := TAU * i / 6.0
		stones.append(_add_box(FIRE_POS + Vector3(cos(a) * 1.1, 0.15, sin(a) * 1.1), Vector3(0.35, 0.3, 0.35), stone_mat))
	var log_mat := StandardMaterial3D.new()
	log_mat.albedo_color = Color(0.32, 0.22, 0.15)
	var logs: Array[StaticBody3D] = [
		_add_box(FIRE_POS + Vector3(0, 0.15, 0), Vector3(0.8, 0.18, 0.25), log_mat, Vector3(0, 30, 0)),
		_add_box(FIRE_POS + Vector3(0, 0.3, 0), Vector3(0.7, 0.16, 0.22), log_mat, Vector3(0, -40, 0)),
	]
	if art:
		_dress_runehold(walls, huts, roofs, stones, logs)
	else:
		_legacy_fire()

	# M07b: the trainer (abilities for gold and level).
	var trainer := TrainerNpc.new()
	trainer.name = "Trainer"
	world.add_child(trainer)
	trainer.global_position = TRAINER_SPOT
	var to_fire := FIRE_POS - TRAINER_SPOT
	trainer.rotation.y = atan2(-to_fire.x, -to_fire.z)

	# Portals.
	var highlands := Portal.new()
	highlands.destination_scene = "res://scenes/ashen_highlands.tscn"
	highlands.label_text = "ASHEN HIGHLANDS"
	world.add_child(highlands)
	highlands.global_position = PORTAL_SPOTS["highlands"]

	var lab := Portal.new()
	lab.destination_scene = "res://scenes/combat_lab.tscn"
	lab.label_text = "TRAINING GROUNDS"
	world.add_child(lab)
	lab.global_position = PORTAL_SPOTS["lab"]

	# Shortcut to the Spire once the Colossus has fallen.
	if SaveGame.has_flag(&"colossus_defeated"):
		var spire := Portal.new()
		spire.destination_scene = "res://scenes/shattered_spire.tscn"
		spire.label_text = "THE SHATTERED SPIRE"
		world.add_child(spire)
		spire.global_position = PORTAL_SPOTS["spire"]


## Flagstone plaza around the hearth, paths out to the portals, the spawn and
## the hut doors (shader-side paving, see ArtKit.paved).
func _paved_ground() -> Material:
	var f := Vector2(FIRE_POS.x, FIRE_POS.z)
	var paths: Array[Vector4] = []
	for spot: Vector3 in PORTAL_SPOTS.values():
		paths.append(Vector4(f.x, f.y, spot.x, spot.z))
	paths.append(Vector4(f.x, f.y, 0.0, 12.0))  # spawn
	paths.append(Vector4(f.x, f.y, TRAINER_SPOT.x + 1.2, TRAINER_SPOT.z + 0.8))  # M07b trainer
	for hut in HUTS:
		var door := _hut_door(hut)
		paths.append(Vector4(door.x, door.y, lerpf(door.x, f.x, 0.55), lerpf(door.y, f.y, 0.55)))
	return ArtKit.paved(&"runehold_ground", [Vector3(f.x, f.y, 5.2)] as Array[Vector3], paths, 1.7)


## Door spot in front of a hut (XZ), from its yaw and door side.
static func _hut_door(hut: Array) -> Vector2:
	var base: Vector3 = hut[0]
	var front := Vector3(0, 0, 1).rotated(Vector3.UP, deg_to_rad(hut[1])) * (-1.0 if hut[2] else 1.0)
	var door := base + front * 2.6
	return Vector2(door.x, door.z)


## Kit dressing on the existing layout (no coordinates changed, no collision
## added): coursed walls with piers and banners, sod-roofed huts, the hearth,
## a meadow and trees beyond the walls, rule-placed scatter.
func _dress_runehold(walls: Array[StaticBody3D], huts: Array[StaticBody3D], roofs: Array[StaticBody3D],
		stones: Array[StaticBody3D], logs: Array[StaticBody3D]) -> void:
	var half := SIZE * 0.5
	var inner := half - 0.5
	for i in walls.size():
		var piers := SetPieces.masonry_wall(walls[i], &"runehold_wall", 6.0, i < 2)  # N/S walls own the corners
		# Banners between the piers flanking each gate side (north: Highlands,
		# east: training grounds, south: behind the spawn).
		for k in piers.size() - 1:
			var mid := (piers[k] + piers[k + 1]) * 0.5
			if absf(mid) > 4.0:
				continue
			match i:
				0: SetPieces.wall_banner(self, Vector3(mid, 2.42, -inner), Vector3.BACK)
				1: SetPieces.wall_banner(self, Vector3(mid, 2.42, inner), Vector3.FORWARD)
				3: SetPieces.wall_banner(self, Vector3(inner, 2.42, mid), Vector3.LEFT)
	for i in huts.size():
		SetPieces.hut(huts[i], roofs[i], &"runehold_wall", &"runehold_roof", HUTS[i][2])
	SetPieces.hearth(self, FIRE_POS, stones, logs)
	_add_ground_skirt(&"runehold_meadow", 140.0)
	_plant_trees()
	# Training gear against the west wall (wall-hugging, <= 0.28 m deep).
	for z: float in [-9.0, -7.2]:
		SetPieces.prop(dressing(), "rh_weapon_rack" if z < -8.0 else "rh_training_post",
			Vector3(-inner, 0, z) + Vector3.RIGHT * 0.14, PI * 0.5)
	var keep_clear: Array[Vector3] = [Vector3(0, 10, 3.0), Vector3(FIRE_POS.x, FIRE_POS.z, 6.0),
		Vector3(TRAINER_SPOT.x, TRAINER_SPOT.z, 2.2)]
	for spot: Vector3 in PORTAL_SPOTS.values():
		keep_clear.append(Vector3(spot.x, spot.z, 2.6))
	for hut in HUTS:
		var door := _hut_door(hut)
		keep_clear.append(Vector3(door.x, door.y, 1.4))
	var bodies: Array[StaticBody3D] = []
	bodies.append_array(walls)
	bodies.append_array(huts)
	var obstacles := scatter_obstacles(bodies)
	Scatter.populate(self, {
		"area": Rect2(-half - 4.0, -half - 4.0, SIZE + 8.0, SIZE + 8.0),
		"obstacles": obstacles,
		"exclude": keep_clear,
		"seed": 4127,
		"items": [
			{"prop": "rh_grass_tuft", "per_m": 1.1, "band": Vector2(0.3, 1.6), "scale": Vector2(0.8, 1.35),
				"cluster": Vector2i(2, 5), "spread": 0.4},
			{"prop": "rh_stone_cluster", "per_m": 0.22, "band": Vector2(0.25, 0.8), "scale": Vector2(0.8, 1.5),
				"cluster": Vector2i(1, 2), "spread": 0.3},
		],
	})


## Pines and oaks on the meadow beyond the walls (deterministic ring).
func _plant_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5501
	var half := SIZE * 0.5
	for k in 26:
		var side := k % 4
		var along := rng.randf_range(-half - 6.0, half + 6.0)
		var out := rng.randf_range(half + 2.6, half + 11.0)
		var pos: Vector3
		match side:
			0: pos = Vector3(along, 0, -out)
			1: pos = Vector3(along, 0, out)
			2: pos = Vector3(-out, 0, along)
			_: pos = Vector3(out, 0, along)
		var kind := "rh_pine" if rng.randf() < 0.6 else "rh_oak"
		SetPieces.prop(dressing(), kind, pos, rng.randf_range(0.0, TAU), rng.randf_range(0.85, 1.3))


## Pre-M06 hub fire (legacy look / --legacy-look before-after captures).
func _legacy_fire() -> void:
	var flame_light := OmniLight3D.new()
	flame_light.light_color = Color(1.0, 0.6, 0.25)
	flame_light.light_energy = 2.2
	flame_light.omni_range = 9.0
	flame_light.position = FIRE_POS + Vector3(0, 1.0, 0)
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
	embers.global_position = FIRE_POS + Vector3(0, 0.5, 0)

	_add_ambience("campfire_loop", FIRE_POS + Vector3(0, 0.5, 0), -6.0)
