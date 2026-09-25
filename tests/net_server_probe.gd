extends Node
## M09: the dedicated server's side of a tests/net_test.gd scenario. Attached
## under the root by DedicatedServer when `--net-test=` is given; watches the
## session and keeps `--result=` up to date ("ok" once the scenario's
## server-side expectations hold, else "fail: <why so far>"). The orchestrator
## reads it after the clients are done and then stops the server.

var scenario := ""
var result_path := ""
var _max_roster := 0
var _joins := 0
var _leaves := 0
var _ready_peers := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--net-test="):
			scenario = arg.trim_prefix("--net-test=")
		elif arg.begins_with("--result="):
			result_path = arg.trim_prefix("--result=")
	Net.roster_changed.connect(_on_roster)
	Net.peer_left.connect(func(_id: int) -> void:
		_leaves += 1
		_update())
	Net.peer_ready.connect(func(_id: int) -> void:
		_ready_peers += 1
		_update())
	_update()


func _on_roster() -> void:
	if Net.roster.size() > _max_roster:
		_joins += Net.roster.size() - _max_roster
	_max_roster = maxi(_max_roster, Net.roster.size())
	_update()


func _update() -> void:
	var verdict := "fail: unknown scenario " + scenario
	match scenario:
		"handshake":
			if _max_roster < 2:
				verdict = "fail: only %d player(s) joined" % _max_roster
			elif _ready_peers < 2:
				verdict = "fail: only %d player(s) reported the zone loaded" % _ready_peers
			elif _leaves < 1:
				verdict = "fail: nobody left"
			else:
				verdict = "ok"
		"highlands":
			var zone := get_tree().current_scene as ZoneBase
			if not zone is AshenHighlands:
				verdict = "fail: the server is not in the Highlands"
			elif _ready_peers < 1:
				verdict = "fail: the client never reported the zone loaded"
			elif zone.player != null:
				verdict = "fail: the dedicated server spawned a local hero"
			else:
				verdict = "ok"
		"echo":
			verdict = "ok" if _ready_peers >= 1 else "fail: the client never reported the zone loaded"
		"reject_version":
			verdict = "ok" if _max_roster == 0 else "fail: a wrong version was let in"
		"full":
			if _max_roster > 1:
				verdict = "fail: %d players on a 1-player server" % _max_roster
			elif _max_roster == 1:
				verdict = "ok"
			else:
				verdict = "fail: nobody joined"
	var f := FileAccess.open(result_path, FileAccess.WRITE)
	if f != null:
		f.store_string(verdict + "\n")
		f.close()
