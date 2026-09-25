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


func _physics_process(_delta: float) -> void:
	if scenario in ["heroes", "enemies", "enemy_types", "look_boss"] and Engine.get_physics_frames() % 30 == 0:
		_update()


## Both proxies stand where their owners walked, one of them levelled up.
func _heroes_verdict() -> String:
	var zone := get_tree().current_scene as ZoneBase
	if zone == null or zone.net_world == null:
		return "fail: no zone replication on the server"
	var world := zone.net_world
	if _max_roster < 2:
		return "fail: only %d player(s) joined" % _max_roster
	if world.heroes.size() < 2 and _leaves == 0:
		return "fail: %d proxies for 2 players" % world.heroes.size()
	if _saw_both:
		return "ok" if _saw_level else "fail: no proxy levelled up (character sync)"
	var at_spot := 0
	for peer: int in world.heroes:
		var proxy := world.heroes[peer] as Player
		if proxy.net_role != Player.NetRole.PROXY or proxy.is_local:
			return "fail: a hero on the server is not a proxy"
		var role := str((Net.roster.get(peer, {}) as Dictionary).get("name", "")).to_lower()
		var spot := zone._player_spawn_point() + Vector3(4.0 if role == "c1" else -4.0, 0.0, 0.0)
		if Vector2(proxy.global_position.x - spot.x, proxy.global_position.z - spot.z).length() < 0.6:
			at_spot += 1
		if proxy.progression.level > 1:
			_saw_level = true
	if at_spot == 2:
		_saw_both = true
		return "ok" if _saw_level else "fail: no proxy levelled up (character sync)"
	return "fail: %d of 2 proxies reached their owner's spot" % at_spot


var _kills_credited := 0
var _kills := 0
var _hooked: Dictionary = {}


func _enemies_verdict() -> String:
	var zone := get_tree().current_scene as ZoneBase
	if zone == null or zone.net_world == null:
		return "fail: no zone replication on the server"
	for id: int in zone.net_world.enemies:
		var e := zone.net_world.enemies[id] as EnemyBase
		if is_instance_valid(e) and not _hooked.has(id):
			_hooked[id] = true
			e.enemy_died.connect(func(dead: EnemyBase) -> void:
				_kills += 1
				if dead.last_attacker() != null and dead.last_attacker().net_role == Player.NetRole.PROXY:
					_kills_credited += 1
				_update())
	if _kills < 3:
		return "fail: %d of 3 lab enemies killed" % _kills
	if _kills_credited < _kills:
		return "fail: %d of %d kills credited to a player" % [_kills_credited, _kills]
	if zone.net_world.hurts_forwarded < 1:
		return "fail: no enemy hit was forwarded to a hero's owner"
	return "ok"


var _types_spawned := false
var _types_kills := 0
var _types_credited := 0
var _fx_count := 0
var _scale_ok := false


func _types_verdict() -> String:
	var zone := get_tree().current_scene as ZoneBase
	if zone == null or zone.net_world == null:
		return "fail: no zone replication on the server"
	if not _types_spawned:
		if zone.net_world.heroes.size() < 2 or Net.ready_peers().size() < 2:
			return "fail: waiting for both heroes"
		_types_spawned = true
		_spawn_roster(zone)
		return "fail: roster spawned, nothing died yet"
	if not _scale_ok:
		return "fail: enemy health not scaled for 2 heroes"
	if _types_kills < 9:
		return "fail: %d of 9 enemies killed" % _types_kills
	if _types_credited < _types_kills:
		return "fail: %d of %d kills credited to a player" % [_types_credited, _types_kills]
	if _fx_count < 1:
		return "fail: no enemy action (play_fx) was sent"
	return "ok"


## Every type once, in front of the heroes, with little health.
func _spawn_roster(zone: ZoneBase) -> void:
	var spots := [Vector3(-6, 0.2, -4), Vector3(-3, 0.2, -6), Vector3(0, 0.2, -7), Vector3(3, 0.2, -6),
		Vector3(6, 0.2, -4), Vector3(-5, 0.2, -9), Vector3(5, 0.2, -9)]
	var ids := ["brute", "assassin", "warden", "caster", "rusher", "colossus", "vessel"]
	var spawned: Array[EnemyBase] = []
	for i in ids.size():
		var e := ZoneBase.make_enemy(ids[i])
		if e is ShatteredVessel:
			var c := Vector3(0, 0, -8)
			(e as ShatteredVessel).setup_arena(c, [c, c + Vector3(4, 0, 0), c + Vector3(-4, 0, 0)] as Array[Vector3])
		zone._spawn_enemy(e, spots[i])
		spawned.append(e)
	spawned.append(zone.spawn_elite(EliteModifier.Kind.EMBERBOUND, Vector3(-2, 0.2, -3)))
	spawned.append(zone.spawn_elite(EliteModifier.Kind.STORMTOUCHED, Vector3(2, 0.2, -3)))
	for e in spawned:
		e.health.max_health = 50.0  # before the deferred registration: 50 is the base, x1.7 for two
		e.health.current_health = 50.0
		e.fx_played.connect(func(_fx: StringName) -> void: _fx_count += 1)
		e.enemy_died.connect(func(dead: EnemyBase) -> void:
			_types_kills += 1
			if dead.last_attacker() != null and dead.last_attacker().net_role == Player.NetRole.PROXY:
				_types_credited += 1
			_update())
	await get_tree().process_frame
	await get_tree().process_frame
	var rusher := spawned[4]
	_scale_ok = is_instance_valid(rusher) and is_equal_approx(rusher.health.max_health, 50.0 * 1.7)
	_update()


var _saw_both := false
var _saw_level := false


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
		"heroes":
			verdict = _heroes_verdict()
		"enemies":
			verdict = _enemies_verdict()
		"enemy_types":
			verdict = _types_verdict()
		"look_boss":
			# Manual looks only: a full-health colossus in front of the first hero.
			var zone := get_tree().current_scene as ZoneBase
			if not _types_spawned and zone != null and zone.net_world != null and not Net.ready_peers().is_empty():
				_types_spawned = true
				zone._spawn_enemy(ZoneBase.make_enemy("colossus"), Vector3(0, 0.2, -8))
			verdict = "ok"
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
