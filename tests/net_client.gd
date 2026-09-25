class_name NetClient
extends Node
## M09: headless test client for tests/net_test.gd. Joins the server given by
## `--connect=`, plays its `--role` in the `--net-test=` scenario and writes
## "ok" / "fail: <why>" to `--result=`. The driver lives under the root, so it
## survives the zone change that joining causes.


## Walks the hero to `target` and presses queued actions (heroes scenario).
class Goto extends InputSource:
	var target := Vector3.INF
	var queue: Array[StringName] = []

	func poll(intent: PlayerIntent, player: Player) -> void:
		intent.pressed.append_array(queue)
		queue.clear()
		if target == Vector3.INF:
			return
		var d := target - player.global_position
		d.y = 0.0
		if d.length() > 0.2:
			intent.move_dir = d.normalized()


## Where each test role walks in the heroes scenario: beside the zone spawn.
static func hero_target(zone: ZoneBase, role: String) -> Vector3:
	return zone._player_spawn_point() + Vector3(4.0 if role == "c1" else -4.0, 0.0, 0.0)


func _ready() -> void:
	Engine.max_fps = 60
	var driver := Driver.new()
	driver.name = "NetTestDriver"
	get_tree().root.add_child.call_deferred(driver)


const COMPANION_NAMES: Array[String] = ["Sigmund", "Brynja", "Halvard", "Yrsa"]


class Driver extends Node:
	var scenario := ""
	var role := ""
	var address := ""
	var result_path := ""
	var player_name := "BOT"
	var invite := ""
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
			elif arg.begins_with("--invite="):
				invite = arg.trim_prefix("--invite=")
		Net.session_failed.connect(func(reason: String) -> void: _failed_reason = reason)
		Net.session_started.connect(func(_w: Dictionary) -> void: _started = true)
		Net.roster_changed.connect(func() -> void: _max_roster = maxi(_max_roster, Net.roster.size()))
		_play()

	func _play() -> void:
		print("[test %s] %s -> %s" % [role, scenario, address])
		if role == "flood":
			await _flood(int(_arg("--connections=", "12")), _arg_float("--hold=", 12.0))
			return
		Net.join(address, player_name, SaveGame.active_class_id(), 1, invite)
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
			"heroes":
				if not await _in_zone():
					return
				var zone := get_tree().current_scene as ZoneBase
				var hero := zone.player
				var other_role := "c2" if role == "c1" else "c1"
				var goto := Goto.new()
				goto.target = NetClient.hero_target(zone, role)
				hero.input_source = goto
				if not await _until(func() -> bool: return zone.net_world.heroes.size() == 1, 30.0, "the other hero to appear"):
					return
				var other := zone.net_world.heroes.values()[0] as Player
				if not await _until(func() -> bool:
					return Vector2(hero.global_position.x - goto.target.x, hero.global_position.z - goto.target.z).length() < 0.3,
					20.0, "our hero to reach its spot"):
					return
				await _seconds(1.0)
				goto.queue.append(&"dodge")  # an action the other side must replay
				if role == "c2":
					hero.progression.add_xp(5000)  # levels up: the character goes to the server again
				var their_spot := NetClient.hero_target(zone, other_role)
				if not await _until(func() -> bool:
					return Vector2(other.global_position.x - their_spot.x, other.global_position.z - their_spot.z).length() < 0.6,
					30.0, "the other hero's puppet at its spot"):
					return
				if not await _until(func() -> bool: return zone.net_world.replayed_actions >= 1, 20.0, "the other hero's dodge"):
					return
				if not await _until(func() -> bool: return zone.net_world.hero_fx_seen >= 1, 10.0, "the other hero's dodge dust (HeroFx)"):
					return
				if role == "c1" and not await _until(func() -> bool:
					var entry: Dictionary = Net.roster.get(other.peer_id, {})
					return int(entry.get("level", 1)) > 1, 20.0, "c2's new level in the roster"):
					return
				if other.net_role != Player.NetRole.PUPPET or other.is_local or other.collision_layer != 0:
					_finish("fail: the other hero is not a puppet")
					return
				if zone.party_panel == null or not zone.party_panel.visible:
					_finish("fail: no party panel")
					return
				await _seconds(3.0)  # stay while the other side finishes its checks
				_finish("ok")
			"bot":
				# A co-op stand-in (tools: run_godot coop): walks a loop in front of
				# the spawn and dodges now and then until `--duration=` runs out.
				if not await _in_zone():
					return
				var zone := get_tree().current_scene as ZoneBase
				if "--fight" in OS.get_cmdline_user_args():  # fight whatever the server sends instead
					var fighter := BotInputSource.new(3)
					fighter.engage_radius = 60.0
					zone.player.input_source = fighter
					zone.player.camera_rig = null
					zone.player.targeting = null
					zone.player.debug_learn_all()
					await _seconds(_arg_float("--duration=", 120.0))
					_finish("ok")
					return
				var goto := Goto.new()
				zone.player.input_source = goto
				var base := zone._player_spawn_point()
				var loop: Array[Vector3] = [base + Vector3(-3, 0, -6), base + Vector3(3, 0, -6), base + Vector3(3, 0, -3),
					base + Vector3(-3, 0, -3)]
				var end := Time.get_ticks_msec() + int(_arg_float("--duration=", 120.0) * 1000.0)
				var i := 0
				while Time.get_ticks_msec() < end and Net.is_client():
					goto.target = loop[i % loop.size()]
					i += 1
					await _seconds(1.6)
					goto.queue.append(&"dodge" if i % 3 == 0 else &"rune_cleave")
				_finish("ok")
			"companion":
				# A co-op buddy for playtests (run_godot coop): follows the first
				# non-bot hero, fights what comes near, follows party travel.
				if not await _in_zone():
					return
				var end := Time.get_ticks_msec() + int(_arg_float("--duration=", 7200.0) * 1000.0)
				var bound: ZoneBase = null
				var bot: BotInputSource = null
				while Net.is_client() and Time.get_ticks_msec() < end:
					var zone := get_tree().current_scene as ZoneBase
					if zone != null and zone != bound and zone.player != null and zone.net_world != null:
						bound = zone
						bot = BotInputSource.new(hash(player_name))
						bot.engage_radius = 18.0
						zone.player.input_source = bot
						zone.player.camera_rig = null
						zone.player.targeting = null
						zone.player.debug_learn_all()
					if bound != null and is_instance_valid(bound) and bot != null:
						bot.leader = null
						for peer: int in bound.net_world.heroes:
							var hero_name := str((Net.roster.get(peer, {}) as Dictionary).get("name", ""))
							if not NetClient.COMPANION_NAMES.has(hero_name.get_slice(" ", 0)):
								bot.leader = bound.net_world.heroes[peer] as Player
								break
					await _seconds(0.5)
				_finish("ok")
			"lead":
				# The human stand-in for the companions scenario: waits for its two
				# buddies, takes the party to the Highlands, stands at camp_1.
				if not await _in_zone():
					return
				var zone := get_tree().current_scene as ZoneBase
				zone.player.input_source = InputSource.new()
				if not await _until(func() -> bool: return zone.net_world.heroes.size() >= 2, 40.0, "two companions"):
					return
				await _seconds(2.0)
				zone.travel_to("res://scenes/ashen_highlands.tscn", "gate_south")
				if not await _until(func() -> bool:
					var z := get_tree().current_scene as ZoneBase
					return z is AshenHighlands and z.player != null and z.net_world != null 						and z.net_world.heroes.size() >= 2, 40.0, "the party in the Highlands"):
					return
				var hl := get_tree().current_scene as ZoneBase
				hl.player.input_source = InputSource.new()
				hl.player.god_mode = true
				hl.player.global_position = hl.ground_point(hl.poi_position("camp_1") + Vector3(3, 0, 3), 0.2)
				hl.player.velocity = Vector3.ZERO
				if not await _until(func() -> bool: return hl.net_world.loot_grants_received >= 1, 90.0,
						"loot from the companions' kills near us"):
					return
				_finish("ok")
			"roam":
				# Load and soak tests: fight at the given camps in turn (god mode),
				# a minute each, for --duration seconds. --watch only follows.
				if not await _in_zone():
					return
				var zone := get_tree().current_scene as ZoneBase
				var camps := _arg("--camps=", "camp_1").split(",")
				var hero := zone.player
				hero.god_mode = true
				hero.camera_rig = null if not "--watch" in OS.get_cmdline_user_args() else hero.camera_rig
				hero.targeting = null
				hero.debug_learn_all()
				var bot := BotInputSource.new(hash(role))
				bot.engage_radius = 30.0
				hero.input_source = InputSource.new() if "--watch" in OS.get_cmdline_user_args() else bot
				var end := Time.get_ticks_msec() + int(_arg_float("--duration=", 600.0) * 1000.0)
				var i := 0
				while Net.is_client() and Time.get_ticks_msec() < end:
					var spot := zone.poi_position(camps[i % camps.size()])
					if spot != Vector3.INF:
						hero.global_position = zone.ground_point(spot + Vector3(5, 0, 5), 0.2)
						hero.velocity = Vector3.ZERO
					i += 1
					await _seconds(60.0)
				if not Net.is_client():
					_finish("fail: lost the server during the run")
					return
				print("[test %s] hits sent %d, grants %d" % [role, zone.net_world.hits_sent, zone.net_world.grants_received])
				_finish("ok")
			"watch":
				# Windowed look at the other heroes: a screenshot to `--snap=`.
				if not await _in_zone():
					return
				var zone := get_tree().current_scene as ZoneBase
				zone.player.input_source = InputSource.new()
				if not await _until(func() -> bool: return not zone.net_world.heroes.is_empty(), 30.0, "another hero"):
					return
				await _seconds(_arg_float("--snap-after=", 4.0))
				var shots := int(_arg_float("--snaps=", 1.0))
				var path := _arg("--snap=", "user://net_test/watch.png")
				for i in shots:
					var img := get_viewport().get_texture().get_image()
					img.save_png(path if shots == 1 else path.get_basename() + "_%d.png" % i)
					await _seconds(_arg_float("--snap-every=", 0.5))
				_finish("ok")
			"enemies":
				# Bots fight the lab's puppets until the server has killed them all.
				if not await _in_zone():
					return
				var zone := get_tree().current_scene as ZoneBase
				var world := zone.net_world
				if not await _until(func() -> bool: return world.enemies.size() >= 3, 30.0, "the lab's 3 enemies as puppets"):
					return
				for e in EnemyBase.all_enemies:
					# (the zone's shader warm-up instances sit frozen under the floor for 0.3 s)
					if not e.net_puppet and e.process_mode != Node.PROCESS_MODE_DISABLED:
						_finish("fail: a client-side enemy that is not a puppet (%s)" % e.name)
						return
				var bot := BotInputSource.new(7 if role == "c1" else 11)
				bot.engage_radius = 60.0
				zone.player.input_source = bot
				zone.player.camera_rig = null  # bots aim along their facing
				zone.player.targeting = null
				zone.player.debug_learn_all()
				if not await _until(func() -> bool: return world.enemies.is_empty(), 90.0, "every enemy dead"):
					return
				if world.hits_sent == 0:
					_finish("fail: this client never hit anything")
					return
				print("[test %s] hits sent %d, hurts taken %d, dodged %d" % [role, world.hits_sent, world.hurts_taken,
					world.hurts_dodged])
				await _seconds(2.0)
				_finish("ok")
			"enemy_types":
				# The server spawns every enemy type (low health) once both heroes are in.
				if not await _in_zone():
					return
				var zone := get_tree().current_scene as ZoneBase
				var world := zone.net_world
				var seen: Dictionary = {}
				var elites: Dictionary = {}
				var boss_bar := [false]
				var watch := func() -> void:
					for id: int in world.enemies:
						var e := world.enemies[id] as EnemyBase
						if is_instance_valid(e):
							seen[e.type_id] = true
							var m := e.get_node_or_null(^"EliteModifier") as EliteModifier
							if m != null:
								elites[int(m.kind)] = true
					if zone.hud._boss_root != null and zone.hud._boss_root.visible:
						boss_bar[0] = true
				var bot := BotInputSource.new(5 if role == "c1" else 9)
				bot.engage_radius = 60.0
				zone.player.input_source = bot
				zone.player.camera_rig = null
				zone.player.targeting = null
				zone.player.debug_learn_all()
				zone.player.god_mode = true  # the bosses' hits must not end the run
				var wanted: Array[String] = ["rusher", "caster", "brute", "assassin", "warden", "colossus", "vessel"]
				var all_seen := func() -> bool:
					watch.call()
					for t in wanted:
						if not seen.has(t):
							return false
					return elites.size() == 2
				if not await _until(all_seen, 60.0, "every enemy type as a puppet (seen %s)" % [seen.keys()]):
					return
				if not await _until(func() -> bool:
					watch.call()
					return world.enemies.is_empty(), 100.0, "every enemy dead"):
					return
				if not boss_bar[0]:
					_finish("fail: no boss bar while a boss was up")
					return
				await _seconds(2.0)
				_finish("ok")
			"rewards":
				# c1 clears camp_1 and opens chest_south; c2 waits 108 m away.
				if not await _in_zone():
					return
				var zone := get_tree().current_scene as ZoneBase
				var world := zone.net_world
				var chest := (zone as AshenHighlands).chests["chest_south"] as TreasureChest
				var hero := zone.player
				hero.god_mode = true
				hero.input_source = InputSource.new()
				var spot := zone.poi_position("camp_1" if role == "c1" else "grove_se") + Vector3(4, 0, 4)
				hero.global_position = zone.ground_point(spot, 0.2)
				hero.velocity = Vector3.ZERO
				if not await _until(func() -> bool: return Net.roster.size() == 2, 30.0, "both heroes"):
					return
				if role == "c2":
					if not await _until(func() -> bool: return chest.opened, 120.0, "c1's chest to open here too"):
						return
					await _seconds(3.0)
					var drops := 0
					for child in zone.world.get_children():
						if child is ItemDrop or child is GoldDrop:
							drops += 1
					if world.loot_grants_received != 0 or drops != 0:
						_finish("fail: the far hero got loot (%d grants, %d drops)" % [world.loot_grants_received, drops])
						return
					if world.grants_received < 1:
						_finish("fail: the party's camp bonus never arrived")
						return
					_finish("ok")
					return
				var bot := BotInputSource.new(13)
				bot.engage_radius = 30.0
				hero.camera_rig = null
				hero.targeting = null
				hero.debug_learn_all()
				hero.input_source = bot
				if not await _until(func() -> bool: return world.loot_grants_received >= 2, 90.0, "loot for the camp kills"):
					return
				if not await _until(func() -> bool:
					return world.grants_received >= world.loot_grants_received + 1, 30.0, "the camp bonus"):
					return
				hero.input_source = InputSource.new()
				hero.global_position = zone.ground_point(chest.global_position + Vector3(1.2, 0, 0), 0.2)
				hero.velocity = Vector3.ZERO
				await _seconds(0.5)
				var before := world.loot_grants_received
				world.request_chest(chest)
				if not await _until(func() -> bool: return chest.opened and world.loot_grants_received > before,
						20.0, "the chest to open with our purse"):
					return
				await _seconds(2.0)
				var mine := 0
				for child in zone.world.get_children():
					if child is ItemDrop and (child as ItemDrop).player == hero:
						mine += 1
				if mine < 1 and hero.equipment.inventory.is_empty():
					_finish("fail: the purse spawned no items for us")
					return
				await _seconds(4.0)  # c2 checks meanwhile
				_finish("ok")
			"travel":
				if not await _in_zone():
					return
				var zone := get_tree().current_scene as ZoneBase
				zone.player.input_source = InputSource.new()
				if role == "c3":
					# The late joiner: straight into the Highlands, next to the party.
					if not zone is AshenHighlands:
						_finish("fail: the late joiner landed in %s" % zone.scene_file_path)
						return
					if not await _until(func() -> bool: return zone.net_world.heroes.size() >= 2, 20.0, "the party's puppets"):
						return
					var nearest := INF
					for peer: int in zone.net_world.heroes:
						var h := zone.net_world.heroes[peer] as Player
						nearest = minf(nearest, h.global_position.distance_to(zone.player.global_position))
					if nearest > 6.0:
						_finish("fail: the late joiner appeared %.1f m from the nearest hero" % nearest)
						return
					await _seconds(3.0)
					_finish("ok")
					return
				if not await _until(func() -> bool: return Net.roster.size() >= 2, 30.0, "both heroes"):
					return
				var world := zone.net_world
				if role == "c1":
					await _seconds(1.0)
					zone.travel_to("res://scenes/ashen_highlands.tscn", "gate_south")
				if not await _until(func() -> bool: return world.travel_countdowns_seen >= 1, 15.0, "the countdown"):
					return
				if role == "c2":
					Net.send_to_server(NetMsg.TRAVEL_CANCEL, [])  # what [X] does
				if not await _until(func() -> bool: return world.travel_cancels_seen >= 1, 15.0, "the cancel"):
					return
				if role == "c1":
					await _seconds(1.0)
					zone._travelling = false
					zone.travel_to("res://scenes/ashen_highlands.tscn", "gate_south")
				if not await _until(func() -> bool:
					var z := get_tree().current_scene as ZoneBase
					return z is AshenHighlands and z.player != null and z.net_world != null, 30.0, "arriving in the Highlands"):
					return
				var hl := get_tree().current_scene as ZoneBase
				var gate := hl._arrival_point("gate_south")
				if hl.player.global_position.distance_to(gate) > 6.0:
					_finish("fail: arrived %.1f m from the south gate" % hl.player.global_position.distance_to(gate))
					return
				if not await _until(func() -> bool: return hl.net_world.heroes.size() >= 1, 20.0, "the other hero in the new zone"):
					return
				if not await _until(func() -> bool: return Net.roster.size() >= 3 and hl.net_world.heroes.size() >= 2,
						60.0, "the late joiner"):
					return
				await _seconds(3.0)
				_finish("ok")
			"server_gone":
				if not await _in_zone():
					return
				var ended := [""]
				Net.session_ended.connect(func(reason: String) -> void: ended[0] = reason)
				if not await _until(func() -> bool: return ended[0] != "", 40.0, "the session to end with the server"):
					return
				if not await _until(func() -> bool:
					var scene := get_tree().current_scene
					return scene != null and scene.scene_file_path == Net.TITLE_SCENE, 10.0, "the title screen"):
					return
				if not ended[0].contains("Lost the connection") or SaveGame.online:
					_finish("fail: ended with \"%s\" (online save %s)" % [ended[0], SaveGame.online])
					return
				_finish("ok")
			"godot_versions":
				if role == "c1":  # another 4.6 patch release: welcome
					if not await _in_zone():
						return
					await _seconds(6.0)  # stay while c2 is refused
					_finish("ok")
				elif await _until(func() -> bool: return _failed_reason != "", 30.0, "a refusal"):
					_expect_reason("Use Godot 4.6.x")
			"dns":
				if await _until(func() -> bool: return _failed_reason != "", 40.0, "a lookup failure"):
					_expect_reason("Could not find")
			"invite":
				if role == "c1":  # a listed code
					if not await _in_zone():
						return
					await _seconds(6.0)  # stay while the others are turned away
					_finish("ok")
				elif await _until(func() -> bool: return _failed_reason != "", 30.0, "a refusal"):
					_expect_reason("not accepted" if role == "c2" else "needs an invite code")
			"invite_live":
				# c1: the host revokes its code. c2 and c3 share one code: c3
				# joining replaces c2's session.
				var ended := [""]
				Net.session_ended.connect(func(reason: String) -> void: ended[0] = reason)
				if not await _in_zone():
					return
				if role == "c3":
					await _seconds(4.0)
					_finish("ok" if Net.is_client() else "fail: c3 lost its session: " + Net.last_reason)
					return
				if not await _until(func() -> bool: return ended[0] != "", 40.0, "the kick"):
					return
				var want := "revoked" if role == "c1" else "another game"
				_finish("ok" if ended[0].contains(want) else "fail: kicked with \"%s\", expected \"%s\"" % [ended[0], want])
			"auth_garbage":
				# Noise and old games get a readable no; c1 still gets in
				# through the flood's waiting room.
				if role == "c1":
					if not await _in_zone():
						return
					await _seconds(2.0)
					_finish("ok")
				elif await _until(func() -> bool: return _failed_reason != "", 30.0, "a refusal"):
					_expect_reason("not accepted" if role == "j2" else "newer version")
			_:
				_finish("fail: unknown scenario " + scenario)

	## Opens `n` raw ENet connections that never answer the handshake (a scan,
	## a flood) and holds them; the server must keep room for real players.
	## Each sends a peer id >= 2 like a Godot client does: ENetMultiplayerPeer
	## silently resets connections without one (plain ENet noise never even
	## reaches the handshake).
	func _flood(n: int, hold: float) -> void:
		var parsed := NetAddress.parse(address, Net.DEFAULT_PORT)
		var hosts: Array[ENetConnection] = []
		for i in n:
			var h := ENetConnection.new()
			if h.create_host(1, Net.CHANNELS) == OK:
				h.connect_to_host(str(parsed["host"]), int(parsed["port"]), Net.CHANNELS, randi_range(2, 0x7FFFFFFF))
				hosts.append(h)
		var connected := 0
		var dropped := 0
		var end := Time.get_ticks_msec() + int(hold * 1000.0)
		while Time.get_ticks_msec() < end:
			for h in hosts:
				while true:
					var ev: Array = h.service(0)
					var kind := int(ev[0])
					if kind == ENetConnection.EVENT_CONNECT:
						connected += 1
					elif kind == ENetConnection.EVENT_DISCONNECT:
						dropped += 1
					elif kind != ENetConnection.EVENT_RECEIVE:
						break  # NONE or ERROR: nothing more this frame
			await get_tree().process_frame
		for h in hosts:
			h.destroy()
		print("[test %s] flood: %d of %d connected, %d dropped by the server" % [role, connected, n, dropped])
		_finish("ok" if connected >= n - 2 and dropped >= 1 else
			"fail: %d of %d raw connections, %d dropped" % [connected, n, dropped])

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

	func _arg(prefix: String, fallback: String) -> String:
		for a in OS.get_cmdline_user_args():
			if a.begins_with(prefix):
				return a.trim_prefix(prefix)
		return fallback

	func _arg_float(prefix: String, fallback: float) -> float:
		var v := _arg(prefix, "")
		return v.to_float() if v != "" else fallback

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
