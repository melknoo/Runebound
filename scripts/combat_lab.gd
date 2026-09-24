class_name CombatLab
extends ZoneBase
## The gameplay laboratory: greybox arena + debug spawns + capture hook.
## All bootstrap lives in ZoneBase; this zone is geometry + test tooling.
## M06 dresses it as Runehold's training grounds from the hub kit; the layout
## (and every collider) is the same as before.

const ARENA_SIZE := 56.0
const WALL_HEIGHT := 4.0
const PORTAL_POS := Vector3(24, 0, 24)


func _zone_look() -> ZoneLook:
	return ZoneLook.runehold()


func _zone_music() -> String:
	return "runehold"


func _build_zone() -> void:
	var art := look != null and look.art_pass
	var floor_mat: Material = _training_ground() if art else \
		_material_from_texture("res://assets/textures/floor.png", Color(0.3, 0.26, 0.32), 14.0)
	var stone_mat := _material_from_texture("res://assets/textures/stone.png", Color(0.36, 0.33, 0.42), 2.0)
	var accent_mat := _material_from_texture("res://assets/textures/rune_stone.png", Color(0.3, 0.4, 0.45), 1.0)

	_add_box(Vector3(0, -0.5, 0), Vector3(ARENA_SIZE, 1.0, ARENA_SIZE), floor_mat)

	var half := ARENA_SIZE * 0.5
	var walls: Array[StaticBody3D] = [
		_add_box(Vector3(0, WALL_HEIGHT * 0.5, -half), Vector3(ARENA_SIZE, WALL_HEIGHT, 1), stone_mat),
		_add_box(Vector3(0, WALL_HEIGHT * 0.5, half), Vector3(ARENA_SIZE, WALL_HEIGHT, 1), stone_mat),
		_add_box(Vector3(-half, WALL_HEIGHT * 0.5, 0), Vector3(1, WALL_HEIGHT, ARENA_SIZE), stone_mat),
		_add_box(Vector3(half, WALL_HEIGHT * 0.5, 0), Vector3(1, WALL_HEIGHT, ARENA_SIZE), stone_mat),
	]

	# Scattered cover blocks: camera collision + line-of-sight testing.
	var blocks: Array[StaticBody3D] = [
		_add_box(Vector3(-8, 1.0, -6), Vector3(3, 2, 3), accent_mat),
		_add_box(Vector3(9, 1.25, -10), Vector3(2.5, 2.5, 2.5), accent_mat),
		_add_box(Vector3(6, 0.75, 8), Vector3(4, 1.5, 2), stone_mat),
		_add_box(Vector3(-12, 1.5, 10), Vector3(2, 3, 2), accent_mat),
		_add_box(Vector3(0, 1.0, -16), Vector3(6, 2, 1.5), stone_mat),
	]

	# Steps + ramp: traversal tests.
	for i in 3:
		blocks.append(_add_box(Vector3(14.0 + i * 1.2, 0.15 + i * 0.3, 4), Vector3(1.2, 0.3 + i * 0.6, 6), stone_mat))
	blocks.append(_add_box(Vector3(-16, 0.8, -14), Vector3(6, 0.5, 8), stone_mat, Vector3(-15, 0, 0)))

	if art:
		_dress_training_grounds(walls, blocks)

	# Portal back to the hub.
	var portal := Portal.new()
	portal.destination_scene = "res://scenes/hub.tscn"
	portal.label_text = "RUNEHOLD"
	world.add_child(portal)
	portal.global_position = PORTAL_POS


## Packed earth with a flagstone sparring ring and a path to the portal.
func _training_ground() -> Material:
	var ring := Vector3(0, -4, 9.5)
	var paths: Array[Vector4] = [Vector4(6.5, 3.0, PORTAL_POS.x, PORTAL_POS.z)]
	return ArtKit.paved(&"runehold_ground", [ring] as Array[Vector3], paths, 2.0)


## Hub kit on the existing lab layout: coursed walls with banners, masonry
## cover blocks, training gear hugging the walls, a meadow and trees beyond.
func _dress_training_grounds(walls: Array[StaticBody3D], blocks: Array[StaticBody3D]) -> void:
	var half := ARENA_SIZE * 0.5
	var inner := half - 0.5
	for i in walls.size():
		var piers := SetPieces.masonry_wall(walls[i], &"runehold_wall", 7.0, i < 2)
		for k in piers.size() - 1:
			var mid := (piers[k] + piers[k + 1]) * 0.5
			if k % 2 == 1:
				continue  # banners on every other bay
			match i:
				0: SetPieces.wall_banner(self, Vector3(mid, WALL_HEIGHT - 0.1, -inner), Vector3.BACK)
				1: SetPieces.wall_banner(self, Vector3(mid, WALL_HEIGHT - 0.1, inner), Vector3.FORWARD)
				2: SetPieces.wall_banner(self, Vector3(-inner, WALL_HEIGHT - 0.1, mid), Vector3.RIGHT)
				3: SetPieces.wall_banner(self, Vector3(inner, WALL_HEIGHT - 0.1, mid), Vector3.LEFT)
		# Racks and pells in the bays without banners (wall-hugging, <= 0.28 m).
		for k in piers.size() - 1:
			if k % 2 == 0 or k == 0 or k == piers.size() - 2:
				continue
			var mid := (piers[k] + piers[k + 1]) * 0.5
			var kind := "rh_weapon_rack" if (k + i) % 4 < 2 else "rh_training_post"
			match i:
				0: SetPieces.prop(dressing(), kind, Vector3(mid, 0, -inner + 0.14), 0.0)
				1: SetPieces.prop(dressing(), kind, Vector3(mid, 0, inner - 0.14), PI)
				2: SetPieces.prop(dressing(), kind, Vector3(-inner + 0.14, 0, mid), PI * 0.5)
				3: SetPieces.prop(dressing(), kind, Vector3(inner - 0.14, 0, mid), -PI * 0.5)
	for body in blocks:
		((body.get_child(0) as MeshInstance3D).mesh as BoxMesh).material = ArtKit.material(&"runehold_wall")
	_add_ground_skirt(&"runehold_meadow", 180.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7307
	for k in 30:
		var along := rng.randf_range(-half - 8.0, half + 8.0)
		var out := rng.randf_range(half + 3.0, half + 13.0)
		var pos: Vector3 = [Vector3(along, 0, -out), Vector3(along, 0, out), Vector3(-out, 0, along),
			Vector3(out, 0, along)][k % 4]
		SetPieces.prop(dressing(), "rh_pine" if rng.randf() < 0.65 else "rh_oak", pos,
			rng.randf_range(0.0, TAU), rng.randf_range(1.0, 1.45))
	var bodies: Array[StaticBody3D] = []
	bodies.append_array(walls)
	bodies.append_array(blocks)
	# The lab's test area (spawn, the space ahead of it) and the portal stay clean.
	var keep_clear: Array[Vector3] = [Vector3(0, 6, 5.0), Vector3(0, -4, 10.0),
		Vector3(PORTAL_POS.x, PORTAL_POS.z, 2.6)]
	Scatter.populate(self, {
		"area": Rect2(-half - 4.0, -half - 4.0, ARENA_SIZE + 8.0, ARENA_SIZE + 8.0),
		"obstacles": scatter_obstacles(bodies),
		"exclude": keep_clear,
		"seed": 3301,
		"items": [
			{"prop": "rh_grass_tuft", "per_m": 0.9, "band": Vector2(0.3, 1.5), "scale": Vector2(0.8, 1.35),
				"cluster": Vector2i(2, 5), "spread": 0.4},
			{"prop": "rh_stone_cluster", "per_m": 0.2, "band": Vector2(0.25, 0.8), "scale": Vector2(0.8, 1.5),
				"cluster": Vector2i(1, 2), "spread": 0.3},
		],
	})


func _zone_ready() -> void:
	_spawn_initial_enemies()
	if "--capture" in OS.get_cmdline_user_args():
		var capture: Node = (load("res://tests/playtest_capture.gd") as GDScript).new()
		add_child(capture)


func _spawn_initial_enemies() -> void:
	spawn_rusher(Vector3(-6, 0.2, -8))
	spawn_rusher(Vector3(4, 0.2, -12))
	spawn_caster(Vector3(10, 0.2, -14))


func reset_lab() -> void:
	super()
	_spawn_initial_enemies.call_deferred()
