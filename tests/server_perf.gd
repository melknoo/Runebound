extends Node
## M09 Spike A: what does one simulation tick of the Ashen Highlands cost with
## a full party fighting, on the server laptop? Headless, one process, no
## networking yet: N bot heroes (BotInputSource, healed every frame) fight at N
## different camps while every camp in the zone is spawned; a cleared camp
## comes back after a few seconds so the load stays up.
##
## Run with --fixed-fps 60: every frame is then exactly one physics tick, and
## the wall time between frames is what a tick costs on this machine.
##   godot --headless --fixed-fps 60 --path . res://tests/server_perf.tscn -- --heroes=5 --seconds=60
## (`tools\run_godot.cmd serverperf [heroes]`, `tools/server/run_godot.sh serverperf [heroes]`)
##
## Today's zone still builds every visual, the HUD and the camera even
## headless, so this is an upper bound for the dedicated server.

const WARMUP_SEC := 8.0      # simulated seconds before recording (spawns, first fights)
const REPORT_EVERY := 10.0   # simulated seconds between progress lines
const REARM_DELAY := 4.0     # simulated seconds until a cleared camp spawns again
const BUDGET_MS := 1000.0 / 60.0
## Enemy health multiplier: level-1 packs melt in seconds against five bots
## with the full kit, so without it the fights (the load we want to measure)
## would mostly be re-arm pauses. --tanky=1 measures the natural rhythm.
const TANKY_DEFAULT := 25.0

var heroes: int = 5
var seconds: float = 60.0
var tanky: float = TANKY_DEFAULT
## --strip=anim,ui,enemies,sleep: switch parts off to see what the base load
## is made of (animation, HUD/UI/camera, all enemies, idle enemies far from
## every hero).
var strip: PackedStringArray = PackedStringArray()
## --dedicated: the zone boots in Net's SERVER mode (no local hero, camera,
## UI, rigs, particles, sounds) and every hero is a bot, like the real server.
var dedicated: bool = false
var _sleep_left: float = 0.0
var zone: AshenHighlands

var _samples := PackedFloat32Array()
var _last_us: int = 0
var _phase: String = "boot"  # boot -> warmup -> record -> done
var _sim: float = 0.0
var _enemy_frames: int = 0
var _engaged_frames: int = 0
var _record_start_us: int = 0
var _next_report: float = REPORT_EVERY
var _toughened: Dictionary = {}  # enemy instance id -> true


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--heroes="):
			heroes = clampi(arg.trim_prefix("--heroes=").to_int(), 1, 8)
		elif arg.begins_with("--seconds="):
			seconds = maxf(arg.trim_prefix("--seconds=").to_float(), 5.0)
		elif arg == "--dedicated":
			dedicated = true
		elif arg.begins_with("--strip="):
			strip = arg.trim_prefix("--strip=").split(",", false)
		elif arg.begins_with("--tanky="):
			tanky = maxf(arg.trim_prefix("--tanky=").to_float(), 1.0)
	_run.call_deferred()


func _run() -> void:
	print("== RUNEBOUND server perf (Spike A) ==")
	print("cpu: %s x%d | heroes %d | %.0f s recorded | enemy hp x%.0f | physics %d Hz" % [
		OS.get_processor_name(), OS.get_processor_count(), heroes, seconds, tanky,
		Engine.physics_ticks_per_second])
	SaveGame.save_path = "user://server_perf_save.json"  # never touch the real save
	SaveGame.wipe()
	if dedicated:
		Net.mode = Net.Mode.SERVER  # no socket needed: only the zone's role matters here
		Engine.max_fps = 0  # --fixed-fps measures back-to-back ticks
	var t0 := Time.get_ticks_msec()
	var scene: Node = (load("res://scenes/ashen_highlands.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	zone = scene as AshenHighlands
	for i in 5:
		await get_tree().physics_frame
	print("zone built in %d ms" % (Time.get_ticks_msec() - t0))
	_setup_party()
	if "enemies" in strip:
		for sp: EncounterSpawner in zone.camps.values():
			sp.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		_spawn_every_camp()
	if "ui" in strip and not dedicated:
		for n: Node in [zone.hud, zone.hero_ui, zone.trainer_ui, zone.waypoint_ui, zone.map_ui,
				zone.debug_overlay, zone.camera_rig, zone.targeting]:
			if n != null:
				n.process_mode = Node.PROCESS_MODE_DISABLED
				if n is CanvasLayer:
					(n as CanvasLayer).visible = false
	if not strip.is_empty():
		print("stripped: %s" % ", ".join(strip))
	_phase = "warmup"
	_last_us = Time.get_ticks_usec()


func _setup_party() -> void:
	var party: Array[Player] = []
	if not dedicated:
		party.append(zone.player)
	for i in heroes - party.size():
		var p := Player.new()
		p.is_local = false
		p.input_source = BotInputSource.new(i + 2)  # before add_child: never the keyboard
		zone.add_player(p)
		party.append(p)
	# The local hero turns into a bot too; without camera or targeting every
	# ability aims along its facing, exactly like the others.
	if zone.player != null:
		zone.player.input_source = BotInputSource.new(1)
		zone.player.camera_rig = null
		zone.player.targeting = null
	var camp_ids: Array[String] = []
	for id: String in zone.camps.keys():
		var sp := zone.camps[id] as EncounterSpawner
		if not sp.around_players and sp.patrol.is_empty():
			camp_ids.append(id)
	camp_ids.sort()
	for i in party.size():
		var hero := party[i]
		hero.debug_learn_all()
		var home := (zone.camps[camp_ids[i % camp_ids.size()]] as EncounterSpawner).global_position
		var offset := Vector3(6.0, 0.0, 0.0).rotated(Vector3.UP, TAU * float(i) / float(party.size()))
		hero.global_position = zone.ground_point(home + offset, 0.2)
		hero.velocity = Vector3.ZERO
	print("party: %d heroes at camps %s" % [party.size(), ", ".join(camp_ids.slice(0, party.size()))])


func _spawn_every_camp() -> void:
	for id: String in zone.camps.keys():
		var sp := zone.camps[id] as EncounterSpawner
		sp.cleared.connect(_rearm.bind(sp))
		sp.trigger(zone, null)  # ambushes spawn around their home without a hero


func _rearm(sp: EncounterSpawner) -> void:
	await get_tree().create_timer(REARM_DELAY, false, true).timeout
	if _phase == "done" or not is_instance_valid(sp):
		return
	sp.reset()
	sp.trigger(zone, null)


func _process(delta: float) -> void:
	if _phase == "boot" or _phase == "done":
		return
	var now := Time.get_ticks_usec()
	var tick_ms := float(now - _last_us) / 1000.0
	_last_us = now
	_sim += delta
	# Immortal bots: a dead hero respawns at the zone spawn, far from any camp
	# (`health.invulnerable` does not survive the dodge's i-frames).
	for h in zone.players:
		h.health.current_health = h.health.max_health
	if "anim" in strip:
		for e in EnemyBase.all_enemies:
			if is_instance_valid(e) and e.animator != null and e.animator.is_physics_processing():
				e.animator.set_physics_process(false)
	if "sleep" in strip:
		_sleep_left -= delta
		if _sleep_left <= 0.0:
			_sleep_left = 0.5
			for e in EnemyBase.all_enemies:
				if is_instance_valid(e) and e.ai_state == EnemyBase.AIState.IDLE:
					var near := not zone.players_within(e.global_position, 60.0).is_empty()
					e.process_mode = Node.PROCESS_MODE_INHERIT if near else Node.PROCESS_MODE_DISABLED
	if _phase == "warmup":
		for e in EnemyBase.all_enemies:
			if is_instance_valid(e):
				_toughen(e)
		if _sim >= WARMUP_SEC:
			_phase = "record"
			_sim = 0.0
			_record_start_us = now
		return
	_samples.append(tick_ms)
	var alive := 0
	var engaged := 0
	for e in EnemyBase.all_enemies:
		if not is_instance_valid(e) or e.ai_state == EnemyBase.AIState.DEAD:
			continue
		_toughen(e)
		alive += 1
		if e.ai_state != EnemyBase.AIState.IDLE and e.ai_state != EnemyBase.AIState.RETURN:
			engaged += 1
	_enemy_frames += alive
	_engaged_frames += engaged
	if _sim >= _next_report:
		_next_report += REPORT_EVERY
		print("  t=%3.0fs  p50 %.2f ms  p95 %.2f ms  enemies %d (engaged %d)" % [_sim,
			_pct(_samples, 0.5), _pct(_samples, 0.95), alive, engaged])
	if _sim >= seconds:
		_finish(now)


func _finish(now: int) -> void:
	_phase = "done"
	var n := _samples.size()
	var total := 0.0
	var worst := 0.0
	var over := 0
	for s in _samples:
		total += s
		worst = maxf(worst, s)
		if s > BUDGET_MS:
			over += 1
	var wall := float(now - _record_start_us) / 1_000_000.0
	print("== result: %d heroes, %d ticks ==" % [heroes, n])
	print("tick ms  mean %.2f | p50 %.2f | p95 %.2f | p99 %.2f | max %.2f" % [total / n,
		_pct(_samples, 0.5), _pct(_samples, 0.95), _pct(_samples, 0.99), worst])
	print("over the 60 Hz budget (%.1f ms): %.1f %% of ticks" % [BUDGET_MS, 100.0 * over / n])
	print("enemies alive avg %.1f, engaged avg %.1f" % [float(_enemy_frames) / n, float(_engaged_frames) / n])
	print("simulated %.0f s in %.1f s wall (%.2fx real time)" % [_sim, wall, _sim / wall])
	get_tree().quit(0)


func _toughen(e: EnemyBase) -> void:
	var id := e.get_instance_id()
	if tanky <= 1.0 or _toughened.has(id):
		return
	_toughened[id] = true
	e.health.max_health *= tanky
	e.health.current_health = e.health.max_health


static func _pct(values: PackedFloat32Array, q: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(int(q * (sorted.size() - 1)), 0, sorted.size() - 1)]
