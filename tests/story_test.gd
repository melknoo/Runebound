extends Node
## M14a: the story checks alone (`tools\run_godot.cmd story`): boots the Combat
## Lab like the smoke test and runs tests/story_checks.gd - minutes faster
## than the whole smoke run while the story is built.
## Run: godot --headless --path . res://tests/story_test.tscn

const WATCHDOG_SEC := 150.0

var _failures: Array[String] = []
var lab: CombatLab


func _ready() -> void:
	get_tree().create_timer(WATCHDOG_SEC, true, false, true).timeout.connect(_on_watchdog)
	_run.call_deferred()


func _on_watchdog() -> void:
	printerr("  FAIL: story watchdog - run exceeded %d s" % int(WATCHDOG_SEC))
	get_tree().quit(2)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		_failures.append(label)
		printerr("  FAIL: " + label)


func _wait_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _run() -> void:
	print("== RUNEBOUND story checks ==")
	SaveGame.save_path = "user://story_test_save.json"
	SaveGame.wipe()
	var scene := (load("res://scenes/combat_lab.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	lab = scene as CombatLab
	await _wait_frames(5)
	var checks: Variant = (load("res://tests/story_checks.gd") as GDScript).new()
	await checks.run(self)
	SaveGame.wipe()
	print("== %d failures (%.0f s) ==" % [_failures.size(), Time.get_ticks_msec() / 1000.0])
	get_tree().quit(0 if _failures.is_empty() else 1)
