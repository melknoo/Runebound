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
		if wanted == "all" or wanted == scenario:
			await _run_scenario(scenario, SCENARIOS[scenario] as Dictionary, BASE_PORT + index)
		index += 1
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
	var procs: Dictionary = {}  # role -> pid
	var roles: Array[String] = []
	var has_server := spec.has("server")
	if has_server:
		var srv_args: Array = ["res://scenes/dedicated_server.tscn", "--", "--port=%d" % port,
			"--save=user://net_test/srv_save.json"]
		srv_args.append_array(spec["server"] as Array)
		_clean("srv")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR + "srv_save.json"))
		procs["srv"] = _launch("srv", scenario, srv_args)
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
		var args: Array = ["res://tests/net_client.tscn", "--", "--connect=127.0.0.1:%d" % port,
			"--save=user://net_test/%s_save.json" % role, "--name=%s" % role.to_upper()]
		args.append_array(c.get("args", []) as Array)
		_clean(role)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR + role + "_save.json"))
		procs[role] = _launch(role, scenario, args)
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
	for a in args:
		full.append(str(a))
	full.append("--net-test=%s" % scenario)
	full.append("--role=%s" % role)
	full.append("--result=%s" % (DIR + role + ".result"))
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
