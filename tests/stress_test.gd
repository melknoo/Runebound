extends Node
## Windowed performance stress: 29 enemies, constant casting, heavy VFX.
## Run via `tools/run_godot.ps1 stress` (passes `--stress`, so SaveGame uses the
## scratch save). Logs frame statistics; exits 1 when the full-combat phase
## averages below BUDGET_FPS.

const BUDGET_FPS := 60.0

var lab: CombatLab
var _frames: Array[float] = []
var _phys: Array[float] = []


func _ready() -> void:
	_run.call_deferred()


func _process(delta: float) -> void:
	_frames.append(delta)
	_phys.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS))


func _report(phase: String) -> float:
	var total := 0.0
	var worst := 0.0
	for f in _frames:
		total += f
		worst = maxf(worst, f)
	var ptotal := 0.0
	for p in _phys:
		ptotal += p
	var n := maxf(_frames.size(), 1)
	var fps := n / maxf(total, 0.001)
	print("stress[%s]: frames=%d avg=%.2f ms (%.0f FPS) worst=%.2f ms physics_avg=%.2f ms" % [
		phase, _frames.size(), total / n * 1000.0, fps, worst * 1000.0, ptotal / n * 1000.0])
	_frames.clear()
	_phys.clear()
	return fps


func _run() -> void:
	# Uncapped: vsync rounds every slightly-late frame up to a whole interval,
	# hiding the real cost.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	lab = (load("res://scenes/combat_lab.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(lab)
	get_tree().current_scene = lab
	await get_tree().create_timer(1.0).timeout

	var player := lab.player
	player.god_mode = true
	player.debug_learn_all()  # M07b: harness runs know the whole kit
	_frames.clear()
	_phys.clear()
	await get_tree().create_timer(2.0).timeout
	_report("baseline_3_enemies")

	lab.stress_test()
	lab.stress_test()  # 2x = 26 spawned + the lab's initial 3
	print("stress: enemies=", lab.enemy_count())
	await get_tree().create_timer(3.0).timeout
	_report("29_enemies_no_combat")

	# ~16 seconds of constant combat: move, swing, cast, slam.
	for cycle in 24:
		Input.action_press(&"move_forward" if cycle % 4 < 2 else &"move_left")
		player.gain_resonance(100.0)
		player.reset_cooldowns()
		player.try_melee()
		await get_tree().create_timer(0.2).timeout
		player.try_ember()
		await get_tree().create_timer(0.15).timeout
		if cycle % 3 == 0:
			player.try_earthbreaker()
			await get_tree().create_timer(0.15).timeout
		if cycle % 3 == 1:
			player.try_chain_spark()
			await get_tree().create_timer(0.1).timeout
		if cycle % 3 == 2:
			player.try_storm_step()
			await get_tree().create_timer(0.25).timeout
			player.try_fracture_rune()
		player.try_dodge()
		await get_tree().create_timer(0.15).timeout
		Input.action_release(&"move_forward")
		Input.action_release(&"move_left")

	var combat_fps := _report("full_combat")
	print("stress: draw_calls=%d  primitives=%d  nodes=%d  video_mem=%.1f MB  enemies_left=%d" % [
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		lab.enemy_count()])
	var passed := combat_fps >= BUDGET_FPS
	print("stress: full_combat %.1f FPS vs budget %.0f -> %s" % [combat_fps, BUDGET_FPS, "PASS" if passed else "FAIL"])
	get_tree().quit(0 if passed else 1)
