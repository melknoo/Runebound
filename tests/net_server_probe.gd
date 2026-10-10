extends Node
## M09: the dedicated server's side of a tests/net_test.gd scenario. Attached
## under the root by DedicatedServer when `--net-test=` is given; watches the
## session and keeps `--result=` up to date ("ok" once the scenario's
## server-side expectations hold, else "fail: <why so far>"). The orchestrator
## reads it after the clients are done and then stops the server.

## Scenarios whose server-side verdict is re-checked twice a second.
const LIVE_SCENARIOS: Array[String] = ["heroes", "enemies", "threat", "heal", "enemy_types", "look_boss", "rewards", "puzzles", "trial",
	"dungeon", "dungeon_boss", "puzzle_kit", "warrens_boss",
	"travel", "companions", "soak", "load", "invite", "invite_live", "auth_garbage", "deploy_notice"]

var scenario := ""
var result_path := ""
var _max_roster := 0
var _revoked := false
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


## The peer id of the player with that name (0 = not in the roster).
func _roster_peer(player: String) -> int:
	for peer: int in Net.roster:
		if str((Net.roster[peer] as Dictionary).get("name", "")) == player:
			return peer
	return 0


func _on_roster() -> void:
	if Net.roster.size() > _max_roster:
		_joins += Net.roster.size() - _max_roster
	_max_roster = maxi(_max_roster, Net.roster.size())
	_update()


func _physics_process(_delta: float) -> void:
	if scenario in LIVE_SCENARIOS and Engine.get_physics_frames() % 30 == 0:
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


var _threat_dummy: EnemyBase = null
var _threat_spawned := false
var _saw_on_caster := false
var _saw_taunt := false


## M10: a dummy (huge health, never moves) that c1 hurts first and c2 taunts.
func _threat_verdict() -> String:
	var zone := get_tree().current_scene as ZoneBase
	if zone == null or zone.net_world == null:
		return "fail: no zone replication on the server"
	if not _threat_spawned:
		if zone.net_world.heroes.size() < 2 or Net.ready_peers().size() < 2:
			return "fail: waiting for both heroes"
		_threat_spawned = true
		for child in zone.enemies_root.get_children():
			child.queue_free()  # the lab's first wave would only get in the way
		_threat_dummy = ZoneBase.make_enemy("rusher")
		zone._spawn_enemy(_threat_dummy, zone._player_spawn_point() + Vector3(0, 0, -6))
		_threat_dummy.health.max_health = 1.0e6
		_threat_dummy.health.heal_full()
		_threat_dummy.move_speed = 0.0
		return "fail: the dummy just spawned"
	if not is_instance_valid(_threat_dummy):
		return "fail: the dummy is gone"
	var target := _threat_dummy.target
	if target != null and is_instance_valid(target) and _role_of(target) == "c1":
		_saw_on_caster = true
	var taunter := _threat_dummy.taunted_by()
	if taunter != null and _role_of(taunter) == "c2":
		_saw_taunt = true
	if _saw_on_caster and _saw_taunt:
		return "ok"
	return "fail: hunted the caster %s, taunted by the tank %s" % [_saw_on_caster, _saw_taunt]


## M11: the same dummy as `threat`; the druid's heal on the tank must show up
## as the druid's threat on it (the server books it when it relays the heal).
func _heal_verdict() -> String:
	var zone := get_tree().current_scene as ZoneBase
	if zone == null or zone.net_world == null:
		return "fail: no zone replication on the server"
	if not _threat_spawned:
		return _threat_verdict()  # spawns the dummy once both heroes are in
	if not is_instance_valid(_threat_dummy):
		return "fail: the dummy is gone"
	for peer: int in zone.net_world.heroes:
		var h := zone.net_world.heroes[peer] as Player
		if h != null and is_instance_valid(h) and _role_of(h) == "c1" and _threat_dummy.threat_of(h) > 0.0:
			_saw_heal_threat = true
	return "ok" if _saw_heal_threat else "fail: no heal threat from the druid yet"


var _saw_heal_threat := false


func _role_of(p: Player) -> String:
	return str((Net.roster.get(p.peer_id, {}) as Dictionary).get("name", "")).to_lower()


var _types_spawned := false
## rewards (M10b): one draught granted to the hero at the chest, once.
var _draught_granted := false
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
	if _types_kills < 15:  # M12: + the six new family enemies
		return "fail: %d of 15 enemies killed" % _types_kills
	if _types_credited < _types_kills:
		return "fail: %d of %d kills credited to a player" % [_types_credited, _types_kills]
	if _fx_count < 1:
		return "fail: no enemy action (play_fx) was sent"
	return "ok"


## Every type once, in front of the heroes, with little health.
func _spawn_roster(zone: ZoneBase) -> void:
	var spots := [Vector3(-6, 0.2, -4), Vector3(-3, 0.2, -6), Vector3(0, 0.2, -7), Vector3(3, 0.2, -6),
		Vector3(6, 0.2, -4), Vector3(-5, 0.2, -9), Vector3(5, 0.2, -9),
		Vector3(-8, 0.2, -7), Vector3(8, 0.2, -7), Vector3(-2, 0.2, -11), Vector3(2, 0.2, -11),
		Vector3(-6, 0.2, -12), Vector3(6, 0.2, -12)]
	var ids := ["brute", "assassin", "warden", "caster", "rusher", "colossus", "vessel",
		"grave_shambler", "mourner", "cinderbark", "smoulder_wisp", "ash_jackal", "carrion_vulture"]  # M12 families
	var spawned: Array[EnemyBase] = []
	for i in ids.size():
		var e := ZoneBase.make_enemy(ids[i])
		if e is ShatteredVessel:
			var c := Vector3(0, 0, -8)
			(e as ShatteredVessel).setup_arena(c, [c, c + Vector3(4, 0, 0), c + Vector3(-4, 0, 0)] as Array[Vector3])
		zone._spawn_enemy(e, spots[i])
		if e is Cinderbark:
			(e as Cinderbark).wake()  # no hero walks up to it here
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


var _quitting := false
## Load test (the server laptop with remote bots): cleared camps come back
## after LOAD_REARM seconds and every enemy has LOAD_HEALTH x its health, so
## the heroes fight without pause. Run: dedicated_server.tscn -- --net-test=load
const LOAD_REARM := 5.0
const LOAD_HEALTH := 10.0
var _load_hooked := false
var _load_tough: Dictionary = {}


func _load_tick() -> String:
	var zone := get_tree().current_scene as AshenHighlands
	if zone == null:
		return "ok"
	if not _load_hooked:
		_load_hooked = true
		for sp: EncounterSpawner in zone.camps.values():
			sp.cleared.connect(func() -> void:
				await get_tree().create_timer(LOAD_REARM).timeout
				if is_instance_valid(sp):
					sp.reset()
					sp.trigger(zone, null))
	for e in EnemyBase.all_enemies:
		if is_instance_valid(e) and not _load_tough.has(e.get_instance_id()) and e.net_id != 0:
			_load_tough[e.get_instance_id()] = true
			e.health.max_health *= LOAD_HEALTH
			e.health.current_health = e.health.max_health
	return "ok"


var _soak_base_nodes := -1
var _soak_last := ""


func _soak_verdict() -> String:
	var t := Time.get_ticks_msec() / 1000.0
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	if _soak_base_nodes < 0 and t > 90.0:
		_soak_base_nodes = nodes
	var line := "t %.0f s: nodes %d (base %d), orphans %d, enemies %d" % [t, nodes, _soak_base_nodes, orphans,
		EnemyBase.all_enemies.size()]
	if int(t) % 60 < 1 and line != _soak_last:
		_soak_last = line
		print("[soak] " + line)
	if orphans > 100:
		return "fail: %d orphan nodes (a leak)" % orphans
	if _soak_base_nodes > 0 and nodes > _soak_base_nodes * 1.3 + 200:
		return "fail: nodes grew from %d to %d" % [_soak_base_nodes, nodes]
	return "ok"
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
		"threat":
			verdict = _threat_verdict()
		"heal":
			verdict = _heal_verdict()
		"enemy_types":
			verdict = _types_verdict()
		"look_boss":
			# Manual looks only: a full-health colossus in front of the first hero.
			var zone := get_tree().current_scene as ZoneBase
			if not _types_spawned and zone != null and zone.net_world != null and not Net.ready_peers().is_empty():
				_types_spawned = true
				zone._spawn_enemy(ZoneBase.make_enemy("colossus"), Vector3(0, 0.2, -8))
			verdict = "ok"
		"puzzles":  # M12: the server holds the solved state and saved it in its world
			var pz := get_tree().current_scene as AshenHighlands
			if pz == null:
				verdict = "fail: the server is not in the Highlands"
			else:
				var braz := pz.puzzles.get("braziers_v") as BrazierPuzzle
				if braz == null or not braz.is_solved():
					verdict = "fail: the braziers are not solved on the server"
				elif not bool(SaveGame.poi_state("braziers_v").get("solved", false)):
					verdict = "fail: the server's world did not keep the solved braziers"
				elif pz.world.get_node_or_null("PuzzleChest_braziers_v") == null:
					verdict = "fail: no crypt chest on the server"
				else:
					verdict = "ok"
		"dungeon":  # M13: the server's world keeps the lit rune and the opened chest
			var dz := get_tree().current_scene as CisternZone
			if dz == null:
				verdict = "fail: the server is not in the Hollow Cistern"
			elif not bool(SaveGame.poi_state("ci_rune_ante").get("solved", false)):
				verdict = "fail: the server's world has no lit rune"
			elif not bool(SaveGame.poi_state("chest:ci_chest_pump").get("opened", false)):
				verdict = "fail: the server's world does not keep the opened chest"
			else:
				verdict = "ok"
		"puzzle_kit":  # M13: the server's world keeps every mechanism as the clients left it
			var lz := get_tree().current_scene as PuzzleLabZone
			if lz == null:
				verdict = "fail: the server is not in the puzzle lab"
			elif not bool(SaveGame.poi_state("lab_lever").get("on", false)):
				verdict = "fail: the lever is not pulled on the server"
			elif (lz.puzzles["lab_block"] as PushBlock).cell_of() != Vector2i(0, -5):
				verdict = "fail: the block is not on its plate on the server"
			elif not (lz.puzzles["lab_light"] as BeamPuzzle).is_solved():
				verdict = "fail: the beam is not solved on the server"
			elif not (lz.waters["lab_water_ch"] as WaterChannel).drained:
				verdict = "fail: the channel is not drained on the server"
			elif not bool(SaveGame.poi_state("lab_kilns").get("solved", false)) or not bool(SaveGame.poi_state("lab_posts").get("solved", false)):
				verdict = "fail: the kilns or the posts are not solved in the server's world"
			elif int(SaveGame.poi_state("lab_ice").get("seq", 0)) < 1:
				verdict = "fail: the ice was never frozen on the server"
			else:
				verdict = "ok"
		"dungeon_boss":  # M13: the arena reset once, started twice, its boss fell (the flag)
			var bz := get_tree().current_scene as CisternZone
			if bz == null:
				verdict = "fail: the server is not in the Hollow Cistern"
			else:
				var arena := bz.arenas["ci_arena_keeper"] as BossArena
				if arena.resets < 1:
					verdict = "fail: the arena never reset"
				elif arena.starts < 2:
					verdict = "fail: the boss woke %d times (2 expected)" % arena.starts
				elif not SaveGame.has_flag(&"ci_keeper_down"):
					verdict = "fail: the mid-boss's flag is not set on the server"
				else:
					verdict = "ok"
		"warrens_boss":  # M13: the Reeve was quenched at a trough a client pulled, and fell
			var wz := get_tree().current_scene as WarrensZone
			if wz == null:
				verdict = "fail: the server is not in the Ember Warrens"
			else:
				var cooled := int((wz.puzzles["wa_quench_w"] as QuenchTrough).state.get("cooled", 0)) \
					+ int((wz.puzzles["wa_quench_e"] as QuenchTrough).state.get("cooled", 0))
				if cooled < 1:
					verdict = "fail: no trough ever quenched the Reeve on the server"
				elif not SaveGame.has_flag(&"wa_reeve_down"):
					verdict = "fail: the Reeve's flag is not set on the server"
				else:
					verdict = "ok"
		"trial":  # M12 phase 6: the server ran the trial to its end and kept it in its world
			var tz := get_tree().current_scene as AshenHighlands
			if tz == null:
				verdict = "fail: the server is not in the Highlands"
			else:
				var trial := tz.puzzles.get("trial_f") as TrialShrine
				if trial == null or int(trial.state.get("seq", 0)) < 1:
					verdict = "fail: the trial never ran on the server"
				elif trial.phase() == "running":
					verdict = "fail: the trial is still running"
				elif trial.phase() == "failed":
					verdict = "fail: the trial failed on the server"
				elif int(SaveGame.poi_state("trial_f").get("seq", 0)) < 1:
					verdict = "fail: the server's world did not keep the trial"
				else:
					verdict = "ok"
		"rewards":
			var zone := get_tree().current_scene as AshenHighlands
			if zone == null:
				verdict = "fail: the server is not in the Highlands"
			else:
				var camp := zone.camps.get("camp_1") as EncounterSpawner
				var chest := zone.chests["chest_south"] as TreasureChest
				var server_drops := 0
				for child in zone.world.get_children():
					if child is ItemDrop or child is GoldDrop or child is ConsumableDrop:
						server_drops += 1
				# M10b: once the chest is open, hand the hero beside it one draught
				# through a real GRANT (element 7), so c1 can check it arrives.
				if chest.opened and not _draught_granted and zone.net_world != null:
					for proxy: Player in zone.net_world.heroes.values():
						if is_instance_valid(proxy) and proxy.global_position.distance_to(chest.global_position) < 12.0:
							_draught_granted = true
							zone.give_reward(proxy, 0, 0, 0, [] as Array[ItemData], chest.global_position + Vector3(0, 0, 2.5),
								"", false, 1)
				if camp == null or camp.state != EncounterSpawner.State.CLEARED:
					verdict = "fail: camp_1 not cleared"
				elif not chest.opened:
					verdict = "fail: chest_south still closed"
				elif server_drops > 0:
					verdict = "fail: the server spawned %d drops of its own" % server_drops
				else:
					verdict = "ok"
		"travel":
			var zone := get_tree().current_scene as ZoneBase
			if not zone is AshenHighlands:
				verdict = "fail: the server never left the hub"
			elif zone.net_world == null or zone.net_world.heroes.size() < 3 and _leaves == 0:
				verdict = "fail: %d proxies in the Highlands" % (zone.net_world.heroes.size() if zone.net_world != null else 0)
			elif Net.zone_epoch != 2:
				verdict = "fail: zone epoch %d after one travel" % Net.zone_epoch
			else:
				verdict = "ok"
		"server_gone":
			verdict = "ok"
			if _ready_peers >= 1 and not _quitting:
				_quitting = true
				get_tree().create_timer(2.0).timeout.connect(func() -> void: get_tree().quit())
		"companions":
			var zone := get_tree().current_scene as ZoneBase
			verdict = "ok" if zone is AshenHighlands else "fail: the party never reached the Highlands"
		"soak":
			verdict = _soak_verdict()
		"load":
			verdict = _load_tick()
		"godot_versions":
			verdict = "ok" if _max_roster == 1 and _ready_peers >= 1 else \
				"fail: expected the 4.6.0 client in and the 4.5.2 one out (max roster %d)" % _max_roster
		"reject_version":
			verdict = "ok" if _max_roster == 0 else "fail: a wrong version was let in"
		"deploy_notice":
			verdict = "ok" if Net.kicks >= 1 and FileAccess.file_exists(Net.STATUS_PATH) else \
				"fail: %d kicks, status file %s" % [Net.kicks, FileAccess.file_exists(Net.STATUS_PATH)]
		"invite":
			if _max_roster > 1:
				verdict = "fail: %d players got in with one valid code" % _max_roster
			elif _ready_peers < 1:
				verdict = "fail: the invited client never arrived"
			elif Net.refused_total < 2:
				verdict = "fail: %d refusals for a wrong code and a missing one" % Net.refused_total
			else:
				verdict = "ok"
		"invite_live":
			# The host revokes c1's code as soon as c1 is in (what invites.sh remove does).
			if not _revoked and Net.is_peer_ready(_roster_peer("C1")):
				_revoked = true
				var f := FileAccess.open(Net.invites_path, FileAccess.WRITE)
				f.store_string("# c1 revoked\nshared\t%s\ttest\n" % NetTestCodes.SHARED)
				f.close()
			verdict = "ok" if Net.kicks >= 2 else "fail: %d kicks (a revoke and a replaced session expected)" % Net.kicks
		"auth_garbage":
			if _max_roster != 1:
				verdict = "fail: roster reached %d (only c1 is invited)" % _max_roster
			elif Net.refused_total < 3:
				verdict = "fail: %d refusals for junk, junk with a MAC and an old game" % Net.refused_total
			elif Net.evicted_total < 1:
				verdict = "fail: the flood never filled the waiting room"
			else:
				verdict = "ok"
		"full":
			if _max_roster > 1:
				verdict = "fail: %d players on a 1-player server" % _max_roster
			elif _max_roster == 1:
				verdict = "ok"
			else:
				verdict = "fail: nobody joined"
	# Written aside and renamed over the result (M11): the orchestrator once read
	# the file in the moment a rewrite had emptied it ("no result").
	var tmp := result_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f != null:
		f.store_string(verdict + "\n")
		f.close()
		DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(result_path))
