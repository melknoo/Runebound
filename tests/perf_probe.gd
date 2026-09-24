extends Node
## Scripted-fight performance probe: `tools\run_godot.ps1 perf <scenario> [label]`
## launches the scenario's zone with `-- --perf=<json>`; ZoneBase attaches this.
## Each repeat clears the arena, spawns the wave and fights it with the stress
## rotation for `duration` seconds while recording frame time plus the
## renderer's measured CPU and GPU time. The median repeat is compared with
## `budget_fps` (exit code 1 below budget) and appended to
## captures_perf/<scenario>.json so look features can be compared over time.

var scenario_path: String = ""

var _zone: ZoneBase
var _scn: Dictionary = {}
var _frames: Array[float] = []
var _gpu: Array[float] = []
var _cpu: Array[float] = []
var _recording: bool = false
var _vp: RID
## Spike attribution: frames over SPIKE_MS are logged with the fight step that
## preceded them (first-use hitches show up in repeat #1 only).
const SPIKE_MS := 50.0
var _step: String = "-"
var _spikes: Array[String] = []
var _record_t: float = 0.0
var _last_pipelines: int = 0


## Pipelines compiled so far (all kinds): a spike that coincides with new
## compiles is a first-draw hitch, not a steady-state cost.
static func _pipeline_compiles() -> int:
	var total := 0
	for info in [RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION]:
		total += RenderingServer.get_rendering_info(info)
	return total


func _ready() -> void:
	_zone = get_parent() as ZoneBase
	if FileAccess.file_exists(scenario_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(scenario_path))
		if parsed is Dictionary:
			_scn = parsed
	if _scn.is_empty():
		push_error("perf_probe: cannot read scenario '%s'" % scenario_path)
		get_tree().quit(1)
		return
	var zone_path: String = _scn.get("zone", "")
	if zone_path != "" and _zone.scene_file_path != zone_path:
		get_tree().change_scene_to_file.call_deferred(zone_path)
		return
	# Uncapped: vsync would round every late frame up and hide the real cost.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_vp = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)
	_run.call_deferred()


func _process(delta: float) -> void:
	if not _recording:
		return
	_record_t += delta
	var pipelines := _pipeline_compiles()
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(_vp)
	var cpu := RenderingServer.viewport_get_measured_render_time_cpu(_vp) + RenderingServer.get_frame_setup_time_cpu()
	if delta * 1000.0 > SPIKE_MS:
		_spikes.append("%.0f ms @%.2fs after %s (gpu %.1f, render cpu %.1f, physics %.1f, process %.1f ms, +%d pipelines)" % [
			delta * 1000.0, _record_t, _step, gpu, cpu,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, pipelines - _last_pipelines])
	_last_pipelines = pipelines
	_frames.append(delta)
	_gpu.append(gpu)
	_cpu.append(cpu)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _run() -> void:
	var player := _zone.player
	player.god_mode = true
	player.debug_learn_all()  # M07b: harness runs know the whole kit
	for child in _zone.world.get_children():
		if child is EncounterSpawner:
			child.set_physics_process(false)
	# A/B variants: `"look": {...}` in the scenario, or `-- --look=key:value`.
	var look: Dictionary = _scn.get("look", {})
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--look="):
			var kv := arg.trim_prefix("--look=").split(":")
			look[kv[0]] = kv[1] == "true" if kv[1] in ["true", "false"] else kv[1]
	if not look.is_empty():
		LookDev.apply(look)
		print("perf: look variant ", look)
	await _wait(float(_scn.get("warmup", 2.0)))
	# First-use bisecting (`-- --prefire=chain_spark,storm_step` or
	# `vfx:storm_trail`): run things once before any recording starts.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--prefire="):
			for item in arg.trim_prefix("--prefire=").split(","):
				await _prefire(item)
			await _wait(1.0)

	# Interleaved A/B (`-- --ab=<lookdev key>`): the key toggles true/false every
	# repeat so both variants run in the same thermal state — this T-series
	# machine swings 20 % between back-to-back runs.
	var ab_key := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ab="):
			ab_key = arg.trim_prefix("--ab=")
	if ab_key != "":
		await _run_ab(ab_key)
		return

	var results: Array[Dictionary] = []
	for r in int(_scn.get("repeats", 3)):
		for child in _zone.enemies_root.get_children():
			child.free()
		player.global_position = _vec3(_scn.get("player", [0, 0.2, 6]))
		player.velocity = Vector3.ZERO
		_zone.camera_rig._yaw = float(_scn.get("yaw", 0.0))
		_zone.camera_rig._pitch = float(_scn.get("pitch", -0.3))
		for spec: Array in _scn.get("wave", []):
			var enemy := _zone.spawn_by_id(str(spec[0]), player.global_position + _vec3(spec[1]))
			if _scn.get("immortal_wave", true):
				# Constant load: the wave survives the whole window, so repeats
				# measure the same fight instead of however fast it died.
				enemy.health.max_health = 1.0e6
				enemy.health.heal_full()
		await _wait(0.5)
		_frames.clear()
		_gpu.clear()
		_cpu.clear()
		_spikes.clear()
		_record_t = 0.0
		_recording = true
		await _fight(float(_scn.get("duration", 12.0)))
		_recording = false
		var stats := _stats()
		results.append(stats)
		print("perf[%s #%d]: %.1f FPS  frame %.2f ms (p95 %.2f, worst %.2f)  cpu %.2f ms  gpu %.2f ms  enemies %d" % [
			scenario_path.get_file().get_basename(), r + 1, stats["fps"], stats["frame_ms"],
			stats["p95_ms"], stats["worst_ms"], stats["cpu_ms"], stats["gpu_ms"], _zone.enemy_count()])
		if not _spikes.is_empty():
			print("  spikes: ", ", ".join(_spikes))

	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["fps"] < b["fps"])
	var median: Dictionary = results[results.size() / 2]
	var budget := float(_scn.get("budget_fps", 60.0))
	var passed := float(median["fps"]) >= budget
	print("perf[%s]: MEDIAN %.1f FPS  cpu %.2f ms  gpu %.2f ms  draw_calls %d  budget %.0f -> %s" % [
		scenario_path.get_file().get_basename(), median["fps"], median["cpu_ms"], median["gpu_ms"],
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), budget,
		"PASS" if passed else "FAIL"])
	_append_history(median, passed)
	get_tree().quit(0 if passed else 1)


func _run_ab(key: String) -> void:
	var by_value := {true: [] as Array[Dictionary], false: [] as Array[Dictionary]}
	var rounds := int(_scn.get("ab_rounds", 3))
	for r in rounds * 2:
		var value := r % 2 == 0
		LookDev.apply({key: value})
		var stats := await _measure_repeat()
		(by_value[value] as Array[Dictionary]).append(stats)
		print("perf[ab %s=%s #%d]: %.1f FPS gpu %.2f ms" % [key, value, r / 2 + 1, stats["fps"], stats["gpu_ms"]])
	var med := {}
	for value: bool in [true, false]:
		var list: Array[Dictionary] = by_value[value]
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["gpu_ms"] < b["gpu_ms"])
		med[value] = list[list.size() / 2]
	print("perf[ab %s]: ON %.1f FPS gpu %.2f ms | OFF %.1f FPS gpu %.2f ms | cost %.2f ms GPU" % [
		key, med[true]["fps"], med[true]["gpu_ms"], med[false]["fps"], med[false]["gpu_ms"],
		float(med[true]["gpu_ms"]) - float(med[false]["gpu_ms"])])
	get_tree().quit(0)


func _prefire(item: String) -> void:
	var player := _zone.player
	var scene := get_tree().current_scene
	var at := player.global_position + Vector3(0, 0.5, -3)
	player.reset_cooldowns()
	print("perf: prefire ", item)
	match item:
		"chain_spark": player.try_chain_spark()
		"storm_step": player.try_storm_step()
		"vfx:storm_trail": VFX.storm_trail(scene, at, at + Vector3(0, 0, -5))
		"vfx:arc": VFX.lightning_arc(scene, at, at + Vector3(2, 0, -3), Color(0.8, 0.9, 1.0))
		"vfx:shock": VFX.shock_tick(scene, at)
		"anim:upper": player.animator.play_upper(&"chain_spark")
		"anim:storm": player.animator.play_one_shot(&"storm_step")
		"vfx:bolt":
			var bolt := EnemyBolt.new()
			bolt.setup(Vector3.UP, 1.0, 0.0)
			bolt.position = player.global_position + Vector3(0, 30, 0)  # drifts up, out of play
			scene.add_child(bolt)
		_: push_warning("perf: unknown prefire " + item)
	await _wait(0.6)


## One scripted-fight window with a fresh (immortal) wave; returns its stats.
func _measure_repeat() -> Dictionary:
	var player := _zone.player
	for child in _zone.enemies_root.get_children():
		child.free()
	player.global_position = _vec3(_scn.get("player", [0, 0.2, 6]))
	player.velocity = Vector3.ZERO
	_zone.camera_rig._yaw = float(_scn.get("yaw", 0.0))
	_zone.camera_rig._pitch = float(_scn.get("pitch", -0.3))
	for spec: Array in _scn.get("wave", []):
		var enemy := _zone.spawn_by_id(str(spec[0]), player.global_position + _vec3(spec[1]))
		enemy.health.max_health = 1.0e6
		enemy.health.heal_full()
	await _wait(0.5)
	_frames.clear()
	_gpu.clear()
	_cpu.clear()
	_recording = true
	await _fight(float(_scn.get("duration", 12.0)))
	_recording = false
	return _stats()


## The stress rotation, but moving forward/back so the fight stays in place.
func _fight(duration: float) -> void:
	var player := _zone.player
	var elapsed := 0.0
	var cycle := 0
	while elapsed < duration:
		var move := &"move_forward" if cycle % 2 == 0 else &"move_back"
		Input.action_press(move)
		player.gain_resonance(Player.MAX_RESONANCE)
		player.reset_cooldowns()
		_step = "melee"
		player.try_melee()
		await _wait(0.2)
		_step = "ember"
		player.try_ember()
		await _wait(0.15)
		elapsed += 0.35
		match cycle % 3:
			0:
				_step = "earthbreaker"
				player.try_earthbreaker()
				await _wait(0.15)
				elapsed += 0.15
			1:
				_step = "chain_spark"
				player.try_chain_spark()
				await _wait(0.1)
				elapsed += 0.1
			2:
				_step = "storm_step"
				player.try_storm_step()
				await _wait(0.25)
				_step = "fracture_rune"
				player.try_fracture_rune()
				elapsed += 0.25
		_step = "dodge"
		player.try_dodge()
		await _wait(0.15)
		elapsed += 0.15
		Input.action_release(move)
		cycle += 1


func _stats() -> Dictionary:
	var n := maxi(_frames.size(), 1)
	var total := 0.0
	var worst := 0.0
	for f in _frames:
		total += f
		worst = maxf(worst, f)
	var sorted := _frames.duplicate()
	sorted.sort()
	var p95: float = sorted[int(sorted.size() * 0.95)] if not sorted.is_empty() else 0.0
	return {
		"fps": n / maxf(total, 0.001),
		"frame_ms": total / n * 1000.0,
		"p95_ms": p95 * 1000.0,
		"worst_ms": worst * 1000.0,
		"cpu_ms": _avg(_cpu),
		"gpu_ms": _avg(_gpu),
		"frames": _frames.size(),
	}


static func _avg(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v in values:
		total += v
	return total / values.size()


func _append_history(median: Dictionary, passed: bool) -> void:
	var dir := ProjectSettings.globalize_path("res://captures_perf")
	DirAccess.make_dir_recursive_absolute(dir)
	if not FileAccess.file_exists(dir.path_join(".gdignore")):
		FileAccess.open(dir.path_join(".gdignore"), FileAccess.WRITE).close()
	var path := dir.path_join(scenario_path.get_file())
	var history: Dictionary = {"runs": []}
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			history = parsed
	var label := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="):
			label = arg.trim_prefix("--label=")
	var entry := median.duplicate()
	entry["label"] = label
	entry["time"] = Time.get_datetime_string_from_system()
	entry["passed"] = passed
	(history["runs"] as Array).append(entry)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(history, "\t"))
	file.close()


static func _vec3(v: Variant) -> Vector3:
	var a := v as Array
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
