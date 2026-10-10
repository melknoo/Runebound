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
		# M10: `--class=elementalist` plays that class (a fresh character in this client's save)
		var want_class := _arg("--class=", "")
		if want_class != "" and String(SaveGame.active_class_id()) != want_class:
			SaveGame.create_character(StringName(want_class), player_name)
		Net.join(address, player_name, SaveGame.active_class_id(), 1, invite)
		match scenario:
			"handshake":
				if not await _in_zone():
					return
				if not await _until(func() -> bool: return Net.roster.size() == 2, 30.0, "both players in the roster"):
					return
				if role == "c2":
					await _seconds(2.0)
					# M17a: the Esc menu online - the world keeps running, the hero
					# stands still, and "Leave the server" leaves (no warning after).
					var zone := get_tree().current_scene as ZoneBase
					zone.pause_menu.open()
					if get_tree().paused or not zone.player.input_locked or not PauseMenu.showing:
						_finish("fail: the online menu paused the game (%s) or left the hero free" % get_tree().paused)
						return
					(zone.pause_menu.get(&"_back_btn") as Button).pressed.emit()
					if not await _until(func() -> bool:
						var scene := get_tree().current_scene
						return scene != null and scene.scene_file_path == Net.TITLE_SCENE, 15.0, "the title after Leave the server"):
						return
					if Net.last_reason != Net.LEFT_REASON or SaveGame.online or PauseMenu.showing or Net.is_online():
						_finish("fail: after leaving: reason \"%s\", online save %s" % [Net.last_reason, SaveGame.online])
						return
					_finish("ok")
					return
				if not await _until(func() -> bool: return Net.roster.size() == 1, 30.0, "c2 leaving the roster"):
					return
				_finish("ok")
			"reject_version":
				# c1 is newer than the server (protocol 999), c2 older (protocol 1):
				# the reason says which side has to update.
				if await _until(func() -> bool: return _failed_reason != "", 30.0, "a refusal"):
					_expect_reason("older RUNEBOUND" if role == "c1" else "Update your game")
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
			"threat":
				# M10: c1 (Elementalist) hurts the server's dummy until it hunts c1; c2
				# (Runebreaker) then walks up and pulls it away with Rune Challenge.
				if not await _in_zone():
					return
				var tz := get_tree().current_scene as ZoneBase
				var tworld := tz.net_world
				tz.player.god_mode = true
				if not await _until(func() -> bool: return _threat_dummy(tworld) != null, 40.0, "the server's dummy"):
					return
				var dummy := _threat_dummy(tworld)
				var me := Net.my_id()
				if role == "c1":
					for i in 6:
						var bolt_hit := tz.player.roll_ability_hit(tz.player.ability(&"rune_bolt"))
						dummy.take_hit(bolt_hit)
						await _seconds(0.25)
					if not await _until(func() -> bool: return dummy.target_peer == me, 20.0, "the dummy hunting the caster"):
						return
					if not await _until(func() -> bool: return dummy.target_peer != 0 and dummy.target_peer != me, 50.0,
							"the tank's taunt taking the dummy away"):
						return
					_finish("ok")
				else:
					await _seconds(4.0)  # the caster's bolts land first
					if not await _until(func() -> bool: return dummy.target_peer != 0 and dummy.target_peer != me, 40.0,
							"the dummy on the caster first"):
						return
					var walk := Goto.new()
					tz.player.input_source = walk
					var near_dummy := func() -> bool:
						walk.target = dummy.global_position + Vector3(2.5, 0, 0)
						return tz.player.global_position.distance_to(dummy.global_position) < 5.0
					if not await _until(near_dummy, 25.0, "the tank next to the dummy"):
						return
					tz.player.learn_ability(&"rune_challenge")
					if not tz.player.try_ability(&"rune_challenge"):
						_finish("fail: Rune Challenge refused")
						return
					if not await _until(func() -> bool: return dummy.target_peer == me, 20.0, "the taunt pulling the dummy onto the tank"):
						return
					await _seconds(3.0)  # stay while the server and the caster see the taunt
					_finish("ok")
			"heal":
				# M11: c2 (a hurt Runebreaker) keeps the server's dummy busy; c1 (a
				# Druid) heals it with Mending Bloom and wraps it in a shield - both
				# cross the server as HERO_FX and land on c2's own hero. M12: then c2
				# is slowed, and c1's Rootwalk bloom beside it takes the slow away.
				if not await _in_zone():
					return
				var hz := get_tree().current_scene as ZoneBase
				var hworld := hz.net_world
				if not await _until(func() -> bool: return _threat_dummy(hworld) != null, 40.0, "the server's dummy"):
					return
				var hdummy := _threat_dummy(hworld)
				if role == "c2":
					var hero := hz.player
					hero.god_mode = true  # nothing but the druid changes its health
					hero.health.current_health = hero.health.max_health * 0.4
					for i in 4:
						hdummy.take_hit(hero.roll_ability_hit(hero.ability(&"rune_cleave")))
						await _seconds(0.25)
					if not await _until(func() -> bool: return hero.health.current_health >= hero.health.max_health * 0.6,
							40.0, "the druid's heal arriving (%.0f)" % hero.health.current_health):
						return
					if not await _until(func() -> bool: return hero.barrier > 0.0, 20.0, "the druid's shield arriving"):
						return
					hero.apply_slow(0.4, 60.0)
					if not await _until(func() -> bool: return is_zero_approx(hero.slow_pct), 40.0,
							"the druid's Rootwalk taking the slow (%.0f %%)" % (hero.slow_pct * 100.0)):
						return
					await _seconds(2.0)  # stay while the druid finishes
					_finish("ok")
				else:
					var druid := hz.player as DruidHero
					if druid == null:
						_finish("fail: c1 is no druid")
						return
					var hurt := func() -> Player:
						for peer: int in hworld.heroes:
							var h := hworld.heroes[peer] as Player
							if h != null and is_instance_valid(h) and h.health.current_health < h.health.max_health * 0.5:
								return h
						return null
					if not await _until(func() -> bool: return hurt.call() != null, 40.0, "the tank hurt in the snapshots"):
						return
					var tank := hurt.call() as Player
					if not await _until(func() -> bool: return hdummy.target_peer != 0, 30.0, "the dummy fighting the tank"):
						return
					if druid.pick_heal_target() != tank:
						_finish("fail: the heal would not go to the hurt tank")
						return
					if not druid.try_mending_bloom():
						_finish("fail: Mending Bloom refused")
						return
					druid.hero_fx(&"ally_shield", [hz.hero_ref(tank), 30.0, 8.0])
					if not await _until(func() -> bool: return tank.barrier > 0.0, 20.0, "the tank's shield in its state"):
						return
					await _seconds(1.0)
					# M12: beside the tank, then down into the roots: the bloom where it starts
					druid.global_position = hz.ground_point(tank.global_position + Vector3(1.5, 0, 0), 0.2)
					druid.velocity = Vector3.ZERO
					await _seconds(1.0)
					druid.learn_ability(&"rootwalk")
					druid.reset_cooldowns()
					druid.resonance = druid.class_data.max_resource
					if not druid.try_rootwalk():
						_finish("fail: Rootwalk refused")
						return
					await _seconds(3.0)
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
				var wanted: Array[String] = ["rusher", "caster", "brute", "assassin", "warden", "colossus", "vessel",
					"grave_shambler", "mourner", "cinderbark", "smoulder_wisp", "ash_jackal", "carrion_vulture"]
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
					var left: Array[String] = []
					for id: int in world.enemies:
						var e := world.enemies[id] as EnemyBase
						if is_instance_valid(e):
							left.append("%s %s" % [e.type_id, EnemyBase.AIState.keys()[e.ai_state]])
					print("[test %s] still alive: %s" % [role, ", ".join(left)])
					return
				if not boss_bar[0]:
					_finish("fail: no boss bar while a boss was up")
					return
				await _seconds(2.0)
				_finish("ok")
			"puzzles":
				# M12: c1 lights two of Ashwick's braziers, c2 the third (each a
				# POI_ACT); both see it solved. c3 joins late and gets the solved
				# state (POI_STATE replay) and the crypt chest.
				if not await _in_zone():
					return
				var zone := get_tree().current_scene as AshenHighlands
				var world := zone.net_world
				var braz := zone.puzzles["braziers_v"] as BrazierPuzzle
				var hero := zone.player
				hero.god_mode = true
				hero.input_source = InputSource.new()
				hero.global_position = zone.ground_point(braz.global_position + Vector3(0, 0, 2), 0.2)
				hero.velocity = Vector3.ZERO
				await _seconds(1.5)  # the server's proxy follows us there (it judges the reach)
				if role == "c3":
					if not await _until(func() -> bool: return braz.is_solved() and world.poi_states_received >= 1,
							30.0, "the solved braziers for a late joiner"):
						return
					if not await _until(func() -> bool: return zone.world.get_node_or_null("PuzzleChest_braziers_v") != null,
							10.0, "the crypt chest"):
						return
					_finish("ok")
					return
				if not await _until(func() -> bool: return Net.roster.size() >= 2, 30.0, "both heroes"):
					return
				if role == "c1":
					braz.strike(0, hero)
					braz.strike(1, hero)
				else:
					if not await _until(func() -> bool:
						var lit: Array = braz.state.get("lit", [])
						return lit.size() == 3 and bool(lit[0]) and bool(lit[1]), 30.0, "c1's two braziers alight here"):
						return
					braz.strike(2, hero)
				if not await _until(func() -> bool: return braz.is_solved(), 20.0, "the braziers solved"):
					return
				# stay until the late joiner is in (the server keeps the world)
				await _until(func() -> bool: return Net.roster.size() >= 3, 40.0, "c3 to join")
				await _seconds(2.0)
				_finish("ok")
			"trial":
				# M12 phase 6: c1 and c2 take the Charwood's trial; c1 starts it (a
				# POI_ACT), both strike its waves (each hit forwarded), c2 is struck
				# past the limit on purpose. Cleared: c1 carries the blessing, c2
				# does not (each owner judged its own hero).
				if not await _in_zone():
					return
				var zone := get_tree().current_scene as AshenHighlands
				var world := zone.net_world
				var trial := zone.puzzles["trial_f"] as TrialShrine
				var hero := zone.player
				hero.input_source = InputSource.new()
				hero.god_mode = role == "c1"
				hero.health.max_health = 5000.0  # c2 must live through the waves while being struck
				hero.health.current_health = 5000.0
				hero.global_position = zone.ground_point(trial.global_position + Vector3(2.0 if role == "c1" else -2.0, 0, 3.0), 0.2)
				hero.velocity = Vector3.ZERO
				await _seconds(1.5)  # the server's proxy follows us there (it judges the reach)
				if not await _until(func() -> bool: return Net.roster.size() >= 2, 30.0, "both heroes"):
					return
				if role == "c1":
					await _seconds(1.0)
					trial.switch.use_by(hero)
				if not await _until(func() -> bool: return trial.phase() == "running" and trial.joined_seq > 0, 30.0, "the trial running"):
					return
				if role == "c2":
					for i in TrialShrine.DEFS["trial_f"]["hits"] + 1:
						hero.take_hit(HitInfo.create(1.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, hero.global_position))
				var struck_at := {}
				var cleared := func() -> bool:
					if trial.phase() == "cleared":
						return true
					var now := Time.get_ticks_msec()
					for id: int in world.enemies:
						var e := world.enemies[id] as EnemyBase
						if not is_instance_valid(e) or not e.targetable or e.global_position.distance_to(trial.global_position) > 30.0:
							continue
						if now - int(struck_at.get(id, 0)) < 250:
							continue
						struck_at[id] = now
						e.take_hit(hero.roll_ability_hit(hero.ability(&"rune_cleave")))
					return false
				if not await _until(cleared, 100.0, "the trial cleared (wave %d)" % int(trial.state.get("wave", 0))):
					return
				await _seconds(1.0)
				if role == "c1" and not hero.blessings.has("charwood"):
					_finish("fail: c1 cleared the trial unstruck but has no blessing")
					return
				if role == "c2" and (hero.blessings.has("charwood") or trial.joined_seq != -1):
					_finish("fail: c2 was struck %d times and still got the blessing" % trial.hits)
					return
				await _seconds(2.0)
				_finish("ok")
			"dungeon":
				# M13 phase 1: in the Hollow Cistern c1 wakes a rune (POI_ACT) and
				# opens a chest that opens once; c2 sees the rune lit, falls and
				# wakes beside it; c3 joins late and gets the rune and the open
				# chest (POI_STATE / CHEST_OPENED replays).
				if not await _in_zone():
					return
				var zone := get_tree().current_scene as CisternZone
				if zone == null:
					_finish("fail: not in the Hollow Cistern")
					return
				var rune := zone.runes["ci_rune_ante"] as DungeonRune
				var chest := zone.chests["ci_chest_pump"] as TreasureChest
				var hero := zone.player
				hero.input_source = InputSource.new()
				hero.god_mode = true
				if role == "c3":
					if not await _until(func() -> bool: return rune.is_solved() and chest.opened, 30.0,
							"the lit rune and the open chest for a late joiner"):
						return
					_finish("ok")
					return
				if not await _until(func() -> bool: return Net.roster.size() >= 2, 30.0, "both heroes"):
					return
				if role == "c1":
					hero.global_position = rune.global_position + Vector3(0, 0.2, 1.5)
					hero.velocity = Vector3.ZERO
					if not await _until(func() -> bool: return rune.is_solved(), 20.0, "the rune lit by c1"):
						return
					hero.global_position = chest.global_position + Vector3(1.5, 0.2, 0)
					hero.velocity = Vector3.ZERO
					await _seconds(1.5)  # the server's proxy follows (it judges the reach)
					zone.net_world.request_chest(chest)
					if not await _until(func() -> bool: return chest.opened, 20.0, "the pump chamber's chest open"):
						return
				else:
					if not await _until(func() -> bool: return rune.is_solved(), 30.0, "c1's rune lit here"):
						return
					hero.god_mode = false
					hero.global_position = Vector3(-4, 2.2, -30)  # the basin, far from the boss's trigger and its levers
					hero.velocity = Vector3.ZERO
					await _seconds(0.5)
					hero.take_hit(HitInfo.create(99999.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, hero.global_position))
					await _seconds(0.3)
					if hero.health.is_dead or hero.global_position.distance_to(rune.respawn_point()) > 1.0:
						_finish("fail: c2 did not wake at the lit rune (at %s)" % hero.global_position)
						return
				await _until(func() -> bool: return Net.roster.size() >= 3, 40.0, "c3 to join")
				await _seconds(3.0)
				_finish("ok")
			"dungeon_boss":
				# M13 phase 1: c1 and c2 wake the Cistern's mid-boss (scaled for two),
				# both walk out (the arena resets: the boss is gone on both), c1
				# wakes it again, both strike it down: the flag reaches both and
				# the gate behind it opens.
				if not await _in_zone():
					return
				var zone := get_tree().current_scene as CisternZone
				if zone == null:
					_finish("fail: not in the Hollow Cistern")
					return
				var world := zone.net_world
				var gate := zone.gates["ci_d_basin_run"] as DungeonGate
				var hero := zone.player
				hero.input_source = InputSource.new()
				hero.god_mode = true
				var outside := Vector3(-16, 2.2, -38) if role == "c1" else Vector3(-14, 2.2, -38)
				var inside := Vector3(10, 2.2, -35) if role == "c1" else Vector3(12, 2.2, -35)
				hero.global_position = outside
				if not await _until(func() -> bool: return Net.roster.size() >= 2, 30.0, "both heroes"):
					return
				await _seconds(2.0)
				var find_boss := func() -> EnemyBase:
					for id: int in world.enemies:
						var e := world.enemies[id] as EnemyBase
						if e != null and is_instance_valid(e) and e is DungeonBoss and e.ai_state != EnemyBase.AIState.DEAD:
							return e
					return null
				hero.global_position = inside
				hero.velocity = Vector3.ZERO
				if not await _until(func() -> bool: return find_boss.call() != null, 20.0, "the mid-boss"):
					return
				var first := find_boss.call() as EnemyBase
				if not await _until(func() -> bool: return is_instance_valid(first) and first.health.max_health > 1500.0, 10.0,
						"the boss scaled for two heroes"):
					return
				if zone.hud._boss_root == null or not zone.hud._boss_root.visible:
					_finish("fail: no boss bar")
					return
				await _seconds(2.0)
				hero.global_position = outside  # both leave: the fight resets
				hero.velocity = Vector3.ZERO
				if not await _until(func() -> bool: return find_boss.call() == null, 20.0, "the boss gone after the reset"):
					return
				if not await _until(func() -> bool: return not zone.hud._boss_root.visible, 5.0, "the boss bar gone after the reset"):
					return  # the puppet fades out first, the bar goes with it
				await _seconds(2.0)
				hero.global_position = inside
				hero.velocity = Vector3.ZERO
				if not await _until(func() -> bool: return find_boss.call() != null, 20.0, "the mid-boss again"):
					return
				var struck_at := {"t": 0}
				var felled := func() -> bool:
					if SaveGame.has_flag(&"ci_keeper_down"):
						return true
					var b := find_boss.call() as EnemyBase
					if b != null and Time.get_ticks_msec() - int(struck_at["t"]) > 300:
						struck_at["t"] = Time.get_ticks_msec()
						var hit := hero.roll_ability_hit(hero.ability(&"rune_cleave"))
						hit.damage = 250.0
						b.take_hit(hit)
					return false
				if not await _until(felled, 60.0, "the mid-boss felled (the flag)"):
					return
				if not await _until(func() -> bool: return gate.is_open, 10.0, "the gate behind the boss open"):
					return
				await _seconds(2.0)
				_finish("ok")
			"warrens_boss":
				# M13 phase 9: both heroes wake the Slag Reeve by the west trough;
				# the slag he spews reaches the clients as lumps; once he stands
				# beside the trough c1 pulls its chain (a request) and his crust
				# cracks on every machine; then both strike him down.
				if not await _in_zone():
					return
				var zone := get_tree().current_scene as WarrensZone
				if zone == null:
					_finish("fail: not in the Ember Warrens")
					return
				var world := zone.net_world
				var hero := zone.player
				hero.input_source = InputSource.new()
				hero.god_mode = true
				var trough := zone.puzzles["wa_quench_w"] as QuenchTrough
				var spot := trough.global_position + (Vector3(1.4, 0.2, 1.6) if role == "c1" else Vector3(1.9, 0.2, 1.0))
				hero.global_position = spot
				if not await _until(func() -> bool: return Net.roster.size() >= 2, 30.0, "both heroes"):
					return
				var find_reeve := func() -> SlagReeve:
					for id: int in world.enemies:
						var e := world.enemies[id] as SlagReeve
						if e != null and is_instance_valid(e) and e.ai_state != EnemyBase.AIState.DEAD:
							return e
					return null
				# the arena wakes once a hero is within 9 m of its middle: step in, then back to the trough
				hero.global_position = Vector3(74, 0.2, 21) if role == "c1" else Vector3(75, 0.2, 22)
				if not await _until(func() -> bool: return find_reeve.call() != null, 20.0, "the Slag Reeve"):
					return
				hero.global_position = spot
				hero.velocity = Vector3.ZERO
				var reeve := find_reeve.call() as SlagReeve
				if not await _until(func() -> bool: return is_instance_valid(reeve) and reeve.health.max_health > 1500.0, 10.0,
						"the Reeve scaled for two heroes"):
					return
				var lumps := {"n": 0}
				var lump_seen := func() -> bool:
					for node in get_tree().current_scene.get_children():
						if node is EmberLump:
							lumps["n"] = int(lumps["n"]) + 1
					return int(lumps["n"]) > 0
				if not await _until(lump_seen, 40.0, "a slag lump from the Reeve"):
					return
				if role == "c1":
					var pulled := {"t": 0}
					var quenched := func() -> bool:
						if not is_instance_valid(reeve):
							return false
						if reeve.is_cooled():
							return true
						var flat := Vector2(reeve.global_position.x - trough.global_position.x, reeve.global_position.z - trough.global_position.z)
						if flat.length() < SlagReeve.QUENCH_RADIUS - 0.6 and trough.is_ready() and Time.get_ticks_msec() - int(pulled["t"]) > 800:
							pulled["t"] = Time.get_ticks_msec()
							trough.request("pull", 0, hero)
						return false
					var q_deadline := Time.get_ticks_msec() + 60000
					var q_ok := false
					var q_near := INF
					while Time.get_ticks_msec() < q_deadline:
						if bool(quenched.call()):
							q_ok = true
							break
						if is_instance_valid(reeve):
							q_near = minf(q_near, Vector2(reeve.global_position.x - trough.global_position.x,
								reeve.global_position.z - trough.global_position.z).length())
						await get_tree().process_frame
					if not q_ok:
						_finish("fail: the Reeve was never quenched (closest %.1f m to the trough, %s pulls)" % [q_near,
							trough.state.get("pulls", 0)])
						return
				else:
					if not await _until(func() -> bool: return is_instance_valid(reeve) and reeve.is_cooled(), 70.0,
							"the Reeve's crust cracked (seen on the other client)"):
						return
				var struck_at := {"t": 0}
				var felled := func() -> bool:
					if SaveGame.has_flag(&"wa_reeve_down"):
						return true
					var r := find_reeve.call() as SlagReeve
					if r != null and Time.get_ticks_msec() - int(struck_at["t"]) > 300:
						struck_at["t"] = Time.get_ticks_msec()
						var hit := hero.roll_ability_hit(hero.ability(&"rune_cleave"))
						hit.damage = 250.0
						r.take_hit(hit)
					return false
				if not await _until(felled, 60.0, "the Reeve felled (the flag)"):
					return
				if not await _until(func() -> bool: return (zone.gates["wa_d_smelter_jets"] as DungeonGate).is_open, 10.0,
						"the jet run open"):
					return
				await _seconds(2.0)
				_finish("ok")
			"puzzle_kit":
				# M13 phase 2: the puzzle lab for two - c1 pulls the lever, c2 holds
				# the latching plate (judged from its proxy on the server), c1
				# pushes the block onto the other plate (requests checked against
				# its proxy), c2 turns the crystals, each pulls a valve; c3 joins
				# late and finds it all as it was left.
				if not await _in_zone():
					return
				var zone := get_tree().current_scene as PuzzleLabZone
				if zone == null:
					_finish("fail: not in the puzzle lab")
					return
				var hero := zone.player
				hero.input_source = InputSource.new()
				hero.god_mode = true
				var lever := zone.puzzles["lab_lever"] as PuzzleLever
				var plate_a := zone.puzzles["lab_plate_a"] as PressurePlate
				var plate_b := zone.puzzles["lab_plate_b"] as PressurePlate
				var block := zone.puzzles["lab_block"] as PushBlock
				var beam := zone.puzzles["lab_light"] as BeamPuzzle
				var water := zone.waters["lab_water_ch"] as WaterChannel
				var kilns := zone.puzzles["lab_kilns"] as ElementPuzzle
				var posts := zone.puzzles["lab_posts"] as ElementPuzzle
				var ice := zone.puzzles["lab_ice"] as IceBridge
				var all_done := func() -> bool:
					return lever.is_on() and plate_b.is_down() and plate_a.is_down() and block.cell_of() == Vector2i(0, -5) \
						and beam.is_solved() and water.drained and (zone.gates["lab_d_plates_beam"] as DungeonGate).is_open \
						and kilns.is_solved() and posts.is_solved()
				if role == "c3":
					if not await _until(all_done, 30.0, "the lab as the others left it (a late joiner)"):
						return
					_finish("ok")
					return
				if not await _until(func() -> bool: return Net.roster.size() >= 2, 30.0, "both heroes"):
					return
				var go := func(at: Vector3) -> void:
					hero.global_position = at + Vector3(0, 0.2, 0)
					hero.velocity = Vector3.ZERO
				if role == "c1":
					go.call(lever.global_position + Vector3(-1.5, 0, 0))
					await _seconds(1.0)  # the proxy follows (the server judges the reach)
					lever.request("pull", 0, hero)
					if not await _until(func() -> bool: return lever.is_on() and (zone.gates["lab_d_hub_c2"] as DungeonGate).is_open,
							15.0, "the lever pulled, its gate open"):
						return
					for push_i in 8:
						if block.cell_of().y <= -5:
							break
						go.call(block.rest_position() + Vector3(0, 0, 2.2))
						await _seconds(0.8)
						var before := block.cell_of()
						block.request("push", [0, -1], hero)
						await _until(func() -> bool: return block.cell_of() != before, 3.0, "a push to land")
					if not await _until(func() -> bool: return plate_a.is_down(), 15.0, "the block on plate a"):
						return
					go.call(Vector3(12, 0, -27))
					await _seconds(1.0)
					(zone.puzzles["lab_valve_a"] as PuzzleLever).request("pull", 0, hero)
				else:
					go.call(plate_b.global_position)
					if not await _until(func() -> bool: return plate_b.is_down(), 15.0, "plate b down under c2's proxy"):
						return
					go.call(Vector3(48, 0, -30))
					await _seconds(1.0)
					if not await _until(func() -> bool: return plate_a.is_down(), 60.0, "c1's block on plate a"):
						return
					for turn_i in 5:
						beam.request("turn", 0, hero)
						await _seconds(0.25)
					for turn_i in 5:
						beam.request("turn", 1, hero)
						await _seconds(0.25)
					if not await _until(func() -> bool: return beam.is_solved(), 15.0, "the beam solved"):
						return
					go.call(Vector3(24, 0, -25))
					await _seconds(1.0)
					(zone.puzzles["lab_valve_b"] as PuzzleLever).request("pull", 0, hero)
				# phase 3: c1 takes fire from the bowl (its aura reaches c2) and
				# lights the kilns, then freezes the frost channel (c2 sees the
				# ice); c2 leads the spark along the posts
				var other_aura := func() -> bool:
					for p in zone.players:
						if p != hero and is_instance_valid(p) and p.get_node_or_null("ElementAura") != null:
							return true
					return false
				var plain := HitInfo.create(10.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, Vector3.ZERO)
				if role == "c1":
					go.call(Vector3(-39, 0, 25))
					await _seconds(1.0)
					(zone.carriers["lab_bowl"] as ElementCarrier).take_hit(plain)
					if ElementCharge.carried(hero) != HitInfo.DamageType.FIRE:
						_finish("fail: no fire from the bowl")
						return
					for ki in 3:
						kilns._sockets[ki].take_hit(plain)
						await _seconds(0.3)
					if not await _until(func() -> bool: return kilns.is_solved(), 15.0, "the kilns lit"):
						return
					go.call(Vector3(-62, 0, 34))
					await _seconds(1.0)
					(zone.carriers["lab_frost_crystal"] as ElementCarrier).take_hit(plain)
					ice.socket.take_hit(plain)
					if not await _until(func() -> bool: return ice.is_active(), 10.0, "the ice frozen"):
						return
				else:
					if not await _until(other_aura, 30.0, "c1's fire aura on its puppet"):
						return
					go.call(Vector3(-36, 0, 52))
					await _seconds(1.0)
					for post_i in 4:
						posts.struck(post_i, HitInfo.DamageType.LIGHTNING, hero)
						await _until(func() -> bool: return posts.lit_count() > post_i or posts.is_solved(), 5.0, "a post to take the spark")
					if not await _until(func() -> bool: return posts.is_solved(), 15.0, "the posts solved"):
						return
					if not await _until(func() -> bool: return (zone.waters["lab_frost_water"] as WaterChannel).ice_active(0), 30.0,
							"c1's ice on the frost channel here"):
						return
				if not await _until(all_done, 40.0, "the whole lab solved here"):
					return
				await _until(func() -> bool: return Net.roster.size() >= 3, 50.0, "c3 to join")
				await _seconds(3.0)
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
						if child is ItemDrop or child is GoldDrop or child is ConsumableDrop:
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
				# M10b: the server grants us one draught by the chest (GRANT element 7)
				if not await _until(func() -> bool:
					if hero.consumable_count(Consumables.HEALING_DRAUGHT) > 0:
						return true
					for child in zone.world.get_children():
						if child is ConsumableDrop and (child as ConsumableDrop).player == hero:
							return true
					return false, 20.0, "a Healing Draught from the server's GRANT"):
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
			"deploy_notice":
				var notices: Array[String] = []
				Net.notice_received.connect(func(text: String) -> void: notices.append(text))
				var gone := [""]
				Net.session_ended.connect(func(reason: String) -> void: gone[0] = reason)
				if not await _in_zone():
					return
				if not await _until(func() -> bool: return gone[0] != "", 60.0, "the update restart"):
					return
				var saw_countdown := notices.any(func(t: String) -> bool: return t.contains("restart in"))
				_finish("ok" if saw_countdown and gone[0].contains("restarting for an update") else
					"fail: notices %s, ended with \"%s\"" % [notices, gone[0]])
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
			if int(payload[0]) < 0:
				return  # Net's own WebSocket ping
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

	## M10 threat scenario: the server's big dummy among the puppets.
	func _threat_dummy(world: NetWorld) -> EnemyBase:
		for id: int in world.enemies:
			var e := world.enemies[id] as EnemyBase
			if e != null and is_instance_valid(e) and e.health.max_health > 10000.0:
				return e
		return null

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
