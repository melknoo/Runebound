extends Node
## M09: headless test client for tests/net_test.gd. Joins the server given by
## `--connect=`, plays its `--role` in the `--net-test=` scenario and writes
## "ok" / "fail: <why>" to `--result=`. The driver lives under the root, so it
## survives the zone change that joining causes.


func _ready() -> void:
	Engine.max_fps = 60
	var driver := Driver.new()
	driver.name = "NetTestDriver"
	get_tree().root.add_child.call_deferred(driver)


class Driver extends Node:
	var scenario := ""
	var role := ""
	var address := ""
	var result_path := ""
	var player_name := "BOT"
	var _failed_reason := ""
	var _started := false
	var _max_roster := 0

	func _ready() -> void:
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--net-test="):
				scenario = arg.trim_prefix("--net-test=")
			elif arg.begins_with("--role="):
				role = arg.trim_prefix("--role=")
			elif arg.begins_with("--connect="):
				address = arg.trim_prefix("--connect=")  # the last one wins (scenarios override)
			elif arg.begins_with("--result="):
				result_path = arg.trim_prefix("--result=")
			elif arg.begins_with("--name="):
				player_name = arg.trim_prefix("--name=")
		Net.session_failed.connect(func(reason: String) -> void: _failed_reason = reason)
		Net.session_started.connect(func(_w: Dictionary) -> void: _started = true)
		Net.roster_changed.connect(func() -> void: _max_roster = maxi(_max_roster, Net.roster.size()))
		_play()

	func _play() -> void:
		print("[test %s] %s -> %s" % [role, scenario, address])
		Net.join(address, player_name, SaveGame.active_class_id(), 1)
		match scenario:
			"handshake":
				if not await _in_zone():
					return
				if not await _until(func() -> bool: return Net.roster.size() == 2, 30.0, "both players in the roster"):
					return
				if role == "c2":
					await _seconds(2.0)
					Net.leave()
					_finish("ok")
					return
				if not await _until(func() -> bool: return Net.roster.size() == 1, 30.0, "c2 leaving the roster"):
					return
				_finish("ok")
			"reject_version":
				if await _until(func() -> bool: return _failed_reason != "", 30.0, "a refusal"):
					_expect_reason("Version mismatch")
			"full":
				if role == "c1":
					if not await _in_zone():
						return
					await _seconds(10.0)  # stay while c2 tries
					_finish("ok")
				elif await _until(func() -> bool: return _failed_reason != "", 30.0, "a refusal"):
					_expect_reason("full")
			"highlands":
				if not await _in_zone():
					return
				var zone := get_tree().current_scene as ZoneBase
				if not zone is AshenHighlands:
					_finish("fail: joined %s, not the Highlands" % zone.scene_file_path)
					return
				await _seconds(4.0)
				# Camps near the spawn must not fire locally: the server owns them.
				if not EnemyBase.all_enemies.is_empty():
					_finish("fail: the client spawned %d enemies of its own" % EnemyBase.all_enemies.size())
					return
				if SaveGame.save_path.contains("net_test") and SaveGame.online:
					_finish("ok")
				else:
					_finish("fail: not in an online save session (%s)" % SaveGame.save_path)
			"echo":
				if not await _in_zone():
					return
				await _echo_test(20.0)
			"dns":
				if await _until(func() -> bool: return _failed_reason != "", 40.0, "a lookup failure"):
					_expect_reason("Could not find")
			_:
				_finish("fail: unknown scenario " + scenario)

	## Joined and standing in the server's zone (as a client, zone built).
	func _in_zone() -> bool:
		if not await _until(func() -> bool: return _started or _failed_reason != "", 30.0, "the handshake"):
			return false
		if _failed_reason != "":
			_finish("fail: refused: " + _failed_reason)
			return false
		var ok: bool = await _until(func() -> bool:
			var zone := get_tree().current_scene as ZoneBase
			return zone != null and zone.player != null and zone.scene_file_path == Net.zone_scene, 60.0, "the zone")
		if ok and not Net.is_client():
			_finish("fail: not a client after joining")
			return false
		return ok

	## 20 Hz of ~900-byte unreliable packets (snapshot-sized) bounced by the
	## server: round-trip times, loss. Fails on steady loss above MAX_STEADY_LOSS
	## (the WAN run over Tailscale reports rather than judges).
	const WARMUP_PACKETS := 20
	const MAX_STEADY_LOSS := 5.0

	func _echo_test(seconds: float) -> void:
		var rtts: Array[float] = []  # an Array: the lambda below must append to this one, not a copy
		var seqs: Array[int] = []
		var handler := func(_from: int, payload: Array) -> void:
			rtts.append(float(Time.get_ticks_usec() - int(payload[1])) / 1000.0)
			seqs.append(int(payload[0]))
		Net.on(NetMsg.ECHO, handler)
		var padding := PackedByteArray()
		padding.resize(900)
		var sent := 0
		var end := Time.get_ticks_msec() + int(seconds * 1000.0)
		while Time.get_ticks_msec() < end:
			Net.send_to_server(NetMsg.ECHO, [sent, Time.get_ticks_usec(), padding], Net.CH_SNAPSHOT, false)
			sent += 1
			await get_tree().create_timer(0.05).timeout
		await _seconds(1.5)  # the last answers
		Net.off(NetMsg.ECHO, handler)
		rtts.sort()
		var n := rtts.size()
		if n == 0:
			_finish("fail: no echo came back (%d sent)" % sent)
			return
		# ENet's packet throttle can still be low from the zone build's stall and
		# recovers with its next RTT sample: the first second may lose packets.
		# What matters for snapshots is the steady state after it.
		var steady_sent := maxi(sent - WARMUP_PACKETS, 1)
		var steady_back := 0
		for s in seqs:
			if s >= WARMUP_PACKETS:
				steady_back += 1
		var loss := 100.0 * float(sent - n) / float(maxi(sent, 1))
		var steady_loss := 100.0 * float(steady_sent - steady_back) / float(steady_sent)
		print("[test %s] echo: %d sent, %d back (%.1f %% lost, %.1f %% after the first second) | rtt p50 %.0f / p95 %.0f / max %.0f ms | ENet rtt %d ms" % [
			role, sent, n, loss, steady_loss, rtts[int(n * 0.5)], rtts[mini(int(n * 0.95), n - 1)], rtts[n - 1], Net.ping_ms()])
		_finish("ok" if steady_loss <= MAX_STEADY_LOSS else "fail: %.0f %% of the packets were lost" % steady_loss)

	func _expect_reason(needle: String) -> void:
		if _failed_reason.contains(needle):
			_finish("ok")
		else:
			_finish("fail: expected a reason with \"%s\", got \"%s\"" % [needle, _failed_reason])

	func _until(cond: Callable, timeout: float, what: String) -> bool:
		var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
		while Time.get_ticks_msec() < deadline:
			if bool(cond.call()):
				return true
			await get_tree().process_frame
		_finish("fail: timed out waiting for " + what)
		return false

	func _seconds(s: float) -> void:
		await get_tree().create_timer(s).timeout

	func _finish(verdict: String) -> void:
		print("[test %s] %s" % [role, verdict])
		var f := FileAccess.open(result_path, FileAccess.WRITE)
		if f != null:
			f.store_string(verdict + "\n")
			f.close()
		get_tree().quit(0 if verdict == "ok" else 1)
