extends Node
## M09 multi-process co-op tests. One Godot process can host only one zone
## (current_scene), so every scenario starts a real dedicated server and
## headless test clients as separate processes (the same binary), waits for
## them and collects their verdicts. Runs the same on Windows and on the
## Linux server laptop:
##   godot --headless --path . res://tests/net_test.tscn -- [--scenario=all|handshake|...]
## (`tools\run_godot.cmd net [scenario]`, `tools/server/run_godot.sh net [scenario]`)
##
## Each child gets `--net-test=<scenario> --role=<role> --result=<file>` and
## writes "ok" or "fail: <why>" there (tests/net_client.gd, net_server_probe.gd);
## its log goes to user://net_test/<role>.log (printed when it fails, and
## scanned for SCRIPT ERROR).

const BASE_PORT := 17780
const DIR := "user://net_test/"
const SERVER_BOOT_TIMEOUT := 60.0
## M09b: these also run over WebSocket (the Tailscale Funnel path) as
## "<name>@ws": part of "all", or all of them with `--scenario=ws`. The server
## then needs an invite list; roles without a code of their own get one.
const WS_SCENARIOS: Array[String] = ["handshake", "invite", "travel", "server_gone"]
const WS_PORT_OFFSET := 60

## role "srv" = the dedicated server (omit `server` for a client-only case).
const SCENARIOS := {
	"handshake": {
		"server": [],
		"clients": [{"role": "c1", "delay": 0.0}, {"role": "c2", "delay": 1.0}],
		"timeout": 120.0,
	},
	"reject_version": {
		"server": [],
		"clients": [{"role": "c1", "delay": 0.0, "args": ["--protocol=999"]}],
		"timeout": 60.0,
	},
	"full": {
		"server": ["--max-players=1"],
		"clients": [{"role": "c1", "delay": 0.0}, {"role": "c2", "delay": 5.0}],
		"timeout": 120.0,
	},
	"highlands": {
		"server": ["--zone=res://scenes/ashen_highlands.tscn"],
		"clients": [{"role": "c1", "delay": 0.0}],
		"timeout": 120.0,
	},
	"echo": {
		"server": [],
		"clients": [{"role": "c1", "delay": 0.0}],
		"timeout": 90.0,
	},
	"heroes": {
		"server": [],
		"clients": [{"role": "c1", "delay": 0.0}, {"role": "c2", "delay": 0.5, "args": ["--netsim=100,20,2"]}],
		"timeout": 150.0,
	},
	"enemies": {
		"server": ["--zone=res://scenes/combat_lab.tscn"],
		"clients": [{"role": "c1", "delay": 0.0}, {"role": "c2", "delay": 0.5, "args": ["--netsim=100,20,2"]}],
		"timeout": 150.0,
	},
	"enemy_types": {
		"server": ["--zone=res://scenes/combat_lab.tscn"],
		"clients": [{"role": "c1", "delay": 0.0}, {"role": "c2", "delay": 0.5, "args": ["--netsim=80,20,1"]}],
		"timeout": 180.0,
	},
	"rewards": {
		"server": ["--zone=res://scenes/ashen_highlands.tscn"],
		"clients": [{"role": "c1", "delay": 0.0}, {"role": "c2", "delay": 0.5}],
		"timeout": 180.0,
	},
	"travel": {
		"server": [],
		"clients": [{"role": "c1", "delay": 0.0}, {"role": "c2", "delay": 0.5, "args": ["--netsim=80,20,1"]},
			{"role": "c3", "delay": 22.0}],
		"timeout": 180.0,
	},
	"server_gone": {
		"server": [],
		"clients": [{"role": "c1", "delay": 0.0}],
		"timeout": 90.0,
	},
	"companions": {
		"server": [],
		"clients": [{"role": "c1", "delay": 0.0, "args": ["--net-test=companion", "--name=Sigmund", "--duration=80"]},
			{"role": "c2", "delay": 0.5, "args": ["--net-test=companion", "--name=Brynja", "--duration=80"]},
			{"role": "c3", "delay": 1.0, "args": ["--net-test=lead", "--name=Melvin"]}],
		"timeout": 180.0,
	},
	"soak": {
		# 10 minutes: four bots fight at four camps (cycling), one windowed
		# client watches; the server's node and orphan counts must stay flat.
		"server": ["--zone=res://scenes/ashen_highlands.tscn"],
		"clients": [
			{"role": "c1", "delay": 0.0, "args": ["--net-test=roam", "--camps=camp_1,camp_2", "--duration=600"]},
			{"role": "c2", "delay": 1.0, "args": ["--net-test=roam", "--camps=camp_3,camp_4", "--duration=600", "--netsim=100,20,2"]},
			{"role": "c3", "delay": 2.0, "args": ["--net-test=roam", "--camps=camp_5,camp_6", "--duration=600"]},
			{"role": "c4", "delay": 3.0, "args": ["--net-test=roam", "--camps=camp_7,camp_8", "--duration=600"]},
			{"role": "w1", "delay": 4.0, "windowed": true, "args": ["--net-test=roam", "--camps=camp_1", "--duration=600", "--watch"]},
		],
		"timeout": 800.0,
		"only_named": true,
	},
	"godot_versions": {
		"server": [],
		"clients": [{"role": "c1", "delay": 0.0, "args": ["--godot=4.6.0-stable (official)"]},
			{"role": "c2", "delay": 3.0, "args": ["--godot=4.5.2-stable (official)"]}],
		"timeout": 90.0,
	},
	# M09b: invite codes (NetTestCodes); the orchestrator writes the list.
	"invite": {
		"server": [],
		"invites": {"c1": NetTestCodes.C1},
		"clients": [{"role": "c1", "delay": 0.0, "args": ["--invite=" + NetTestCodes.C1]},
			{"role": "c2", "delay": 1.0, "args": ["--invite=" + NetTestCodes.UNKNOWN]},
			{"role": "c3", "delay": 2.0}],
		"timeout": 90.0,
	},
	"invite_live": {
		"server": [],
		"invites": {"c1": NetTestCodes.C1, "shared": NetTestCodes.SHARED},
		"clients": [{"role": "c1", "delay": 0.0, "args": ["--invite=" + NetTestCodes.C1]},
			{"role": "c2", "delay": 0.5, "args": ["--invite=" + NetTestCodes.SHARED]},
			{"role": "c3", "delay": 12.0, "args": ["--invite=" + NetTestCodes.SHARED]}],
		"timeout": 120.0,
	},
	"auth_garbage": {
		"server": [],
		"invites": {"c1": NetTestCodes.C1},
		"clients": [{"role": "flood", "delay": 0.0, "args": ["--connections=12", "--hold=14"]},
			{"role": "j1", "delay": 1.0, "args": ["--auth=junk"]},
			{"role": "j2", "delay": 1.5, "args": ["--auth=junk_magic"]},
			{"role": "o1", "delay": 2.0, "args": ["--auth=old"]},
			{"role": "c1", "delay": 3.0, "args": ["--invite=" + NetTestCodes.C1]}],
		"timeout": 90.0,
	},
	"dns": {
		"clients": [{"role": "c1", "delay": 0.0, "args": ["--connect=nohost.invalid:7777"]}],
		"timeout": 45.0,
	},
}

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var wanted := "all"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="):
			wanted = arg.trim_prefix("--scenario=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	print("== RUNEBOUND net test (%s) ==" % wanted)
	var index := 0
	for scenario: String in SCENARIOS:
		if wanted == scenario or (wanted == "all" and not bool((SCENARIOS[scenario] as Dictionary).get("only_named", false))):
			await _run_scenario(scenario, SCENARIOS[scenario] as Dictionary, BASE_PORT + index)
		index += 1
	for i in WS_SCENARIOS.size():
		var ws_name := WS_SCENARIOS[i] + "@ws"
		if wanted == ws_name or wanted == "all" or wanted == "ws":
			await _run_scenario(ws_name, SCENARIOS[WS_SCENARIOS[i]] as Dictionary, BASE_PORT + WS_PORT_OFFSET + i)
	if _failures.is_empty():
		print("== net test: all scenarios passed ==")
		get_tree().quit(0)
	else:
		print("== net test: %d failure(s) ==" % _failures.size())
		for f in _failures:
			print("  FAIL: " + f)
		get_tree().quit(1)


func _run_scenario(scenario: String, spec: Dictionary, port: int) -> void:
	print("-- %s (port %d)" % [scenario, port])
	var over_ws := scenario.ends_with("@ws")
	var test_name := scenario.trim_suffix("@ws")  # what the children play
	var procs: Dictionary = {}  # role -> pid
	var roles: Array[String] = []
	var has_server := spec.has("server")
	var invites: Dictionary = (spec.get("invites", {}) as Dictionary).duplicate()
	var role_codes: Dictionary = {}  # role -> a code made up for it (WebSocket needs invites)
	if over_ws and invites.is_empty():
		for c: Dictionary in spec["clients"]:
			var code := NetAuth.generate_code()
			invites[String(c["role"])] = code
			role_codes[String(c["role"])] = code
	if has_server:
		var srv_args: Array = ["res://scenes/dedicated_server.tscn", "--", "--port=%d" % port,
			"--save=user://net_test/srv_save.json"]
		if not invites.is_empty():
			var lines := "# net test invites\n"
			for invite_name: String in invites:
				lines += "%s\t%s\ttest\n" % [invite_name, str(invites[invite_name])]
			var f := FileAccess.open(DIR + "invites.txt", FileAccess.WRITE)
			f.store_string(lines)
			f.close()
			srv_args.append("--invites=" + DIR + "invites.txt")
		if over_ws:
			srv_args.append("--transport=ws")
		srv_args.append_array(spec["server"] as Array)
		_clean("srv")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR + "srv_save.json"))
		procs["srv"] = _launch("srv", test_name, srv_args)
		roles.append("srv")
		if not await _wait_for_log("srv", "(epoch 1)", SERVER_BOOT_TIMEOUT):
			_fail(scenario, "srv", "the server did not start")
			_kill_all(procs)
			return
	var started := Time.get_ticks_msec()
	for c: Dictionary in spec["clients"]:
		var role := String(c["role"])
		var delay := float(c.get("delay", 0.0))
		while float(Time.get_ticks_msec() - started) / 1000.0 < delay:
			await get_tree().process_frame
		var target := ("ws://127.0.0.1:%d" if over_ws else "127.0.0.1:%d") % port
		var args: Array = ["res://tests/net_client.tscn", "--", "--connect=" + target,
			"--save=user://net_test/%s_save.json" % role, "--name=%s" % role.to_upper()]
		if role_codes.has(role):
			args.append("--invite=" + str(role_codes[role]))
		args.append_array(c.get("args", []) as Array)
		if bool(c.get("windowed", false)):
			args.insert(0, "--windowed-client")  # _launch drops --headless for it
		_clean(role)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR + role + "_save.json"))
		procs[role] = _launch(role, test_name, args)
		roles.append(role)
	# Clients finish on their own; the server runs until it is told to stop.
	var deadline := Time.get_ticks_msec() + int(float(spec["timeout"]) * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var running := false
		for role: String in procs:
			if role != "srv" and OS.is_process_running(int(procs[role])):
				running = true
		if not running:
			break
		await get_tree().create_timer(0.25).timeout
	if has_server:
		await get_tree().create_timer(1.5).timeout  # let the server note the last leave
	_kill_all(procs)
	await get_tree().create_timer(0.5).timeout
	for role in roles:
		var verdict := _read(DIR + role + ".result")
		var errors := _script_errors(role)
		if verdict == "":
			verdict = "fail: no result (timed out or crashed)"
		if errors != "":
			verdict = "fail: script error: " + errors
		if verdict == "ok":
			print("   ok  %s" % role)
		else:
			_fail(scenario, role, verdict.trim_prefix("fail: "))


func _launch(role: String, scenario: String, args: Array) -> int:
	var full: PackedStringArray = ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--log-file", ProjectSettings.globalize_path(DIR + role + ".log")]
	if not args.is_empty() and str(args[0]) == "--windowed-client":
		args = args.slice(1)
		full[0] = "--resolution"
		full.insert(1, "1280x720")
	# The scenario's own flags go right after "--", the per-process args after
	# them: the driver takes the last value, so a client can play another part
	# (companions: --net-test=companion / lead).
	var fixed: Array[String] = ["--net-test=%s" % scenario, "--role=%s" % role, "--result=%s" % (DIR + role + ".result")]
	var inserted := false
	for a in args:
		full.append(str(a))
		if str(a) == "--" and not inserted:
			full.append_array(PackedStringArray(fixed))
			inserted = true
	if not inserted:
		full.append("--")
		full.append_array(PackedStringArray(fixed))
	return OS.create_process(OS.get_executable_path(), full)


func _wait_for_log(role: String, needle: String, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if _read(DIR + role + ".log").contains(needle):
			return true
		await get_tree().create_timer(0.25).timeout
	return false


func _kill_all(procs: Dictionary) -> void:
	for role: String in procs:
		var pid := int(procs[role])
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)


func _clean(role: String) -> void:
	for ext in [".result", ".log"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR + role + ext))


func _fail(scenario: String, role: String, why: String) -> void:
	_failures.append("%s/%s: %s" % [scenario, role, why])
	print("   FAIL %s: %s" % [role, why])
	var log_lines := _read(DIR + role + ".log").split("\n")
	var first := maxi(log_lines.size() - 25, 0)
	for i in range(first, log_lines.size()):
		if log_lines[i].strip_edges() != "":
			print("      | " + log_lines[i])


func _script_errors(role: String) -> String:
	for line in _read(DIR + role + ".log").split("\n"):
		if line.contains("SCRIPT ERROR") or line.contains("Parse Error"):
			return line.strip_edges()
	return ""


static func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text().strip_edges()
	f.close()
	return text
