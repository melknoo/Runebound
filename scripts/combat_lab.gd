class_name CombatLab
extends ZoneBase
## The gameplay laboratory: greybox arena + debug spawns + capture hook.
## All bootstrap lives in ZoneBase; this zone is geometry + test tooling.

const ARENA_SIZE := 56.0
const WALL_HEIGHT := 4.0


func _build_zone() -> void:
	var floor_mat := _material_from_texture("res://assets/textures/floor.png", Color(0.3, 0.26, 0.32), 14.0)
	var stone_mat := _material_from_texture("res://assets/textures/stone.png", Color(0.36, 0.33, 0.42), 2.0)
	var accent_mat := _material_from_texture("res://assets/textures/rune_stone.png", Color(0.3, 0.4, 0.45), 1.0)

	_add_box(Vector3(0, -0.5, 0), Vector3(ARENA_SIZE, 1.0, ARENA_SIZE), floor_mat)

	var half := ARENA_SIZE * 0.5
	_add_box(Vector3(0, WALL_HEIGHT * 0.5, -half), Vector3(ARENA_SIZE, WALL_HEIGHT, 1), stone_mat)
	_add_box(Vector3(0, WALL_HEIGHT * 0.5, half), Vector3(ARENA_SIZE, WALL_HEIGHT, 1), stone_mat)
	_add_box(Vector3(-half, WALL_HEIGHT * 0.5, 0), Vector3(1, WALL_HEIGHT, ARENA_SIZE), stone_mat)
	_add_box(Vector3(half, WALL_HEIGHT * 0.5, 0), Vector3(1, WALL_HEIGHT, ARENA_SIZE), stone_mat)

	# Scattered cover blocks: camera collision + line-of-sight testing.
	_add_box(Vector3(-8, 1.0, -6), Vector3(3, 2, 3), accent_mat)
	_add_box(Vector3(9, 1.25, -10), Vector3(2.5, 2.5, 2.5), accent_mat)
	_add_box(Vector3(6, 0.75, 8), Vector3(4, 1.5, 2), stone_mat)
	_add_box(Vector3(-12, 1.5, 10), Vector3(2, 3, 2), accent_mat)
	_add_box(Vector3(0, 1.0, -16), Vector3(6, 2, 1.5), stone_mat)

	# Steps + ramp: traversal tests.
	for i in 3:
		_add_box(Vector3(14.0 + i * 1.2, 0.15 + i * 0.3, 4), Vector3(1.2, 0.3 + i * 0.6, 6), stone_mat)
	_add_box(Vector3(-16, 0.8, -14), Vector3(6, 0.5, 8), stone_mat, Vector3(-15, 0, 0))

	# Portal back to the hub.
	var portal := Portal.new()
	portal.destination_scene = "res://scenes/hub.tscn"
	portal.label_text = "RUNEHOLD"
	world.add_child(portal)
	portal.global_position = Vector3(24, 0, 24)


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
