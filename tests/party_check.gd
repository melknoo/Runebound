extends Node
## M13b phase 6: the co-op dungeon's party check. Headless and offline: a
## party of bot heroes (default a tank, a druid and an Elementalist) at a
## level with rolled gear of that level and the trainer kit fights through
## the Stormwatch - every camp, then the Stormsworn, the Galebinder and the
## Last Stormcaller. The tank leads; the others follow it, heal, revive and
## take the places of the Stormcaller's chain like they would beside a
## player. Offline nothing scales with the party, so the check gives every
## enemy the server's health for the party (+70 % per extra hero). Bots
## never read a telegraph: the numbers are a floor for players, and the
## point is the comparison - with the three roles against a party without a
## tank or a healer (`--party=elementalist,elementalist,elementalist`).
## Every fight starts at full health (a hero who falls lies downed; a wipe
## ends the fight as lost).
##   godot --headless --fixed-fps 60 --path . res://tests/party_check.tscn -- --party=runebreaker,druid,elementalist --level=8
## (`tools\run_godot.cmd partycheck [party] [level]`)

const CAMP_TIMEOUT := 120.0
const BOSS_TIMEOUT := 360.0

var classes: Array[StringName] = [&"runebreaker", &"druid", &"elementalist"]
var level: int = 8
var trace: bool = false
var only: PackedStringArray = PackedStringArray()
var zone: DungeonZone
var heroes: Array[Player] = []
var lead: Player

var _results: Array[Dictionary] = []
var _downs: int = 0
var _damage: Dictionary = {}  # hero instance id -> damage taken this fight


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--party="):
			classes.clear()
			for c in arg.trim_prefix("--party=").split(","):
				classes.append(StringName(c.strip_edges()))
		elif arg.begins_with("--level="):
			level = clampi(arg.trim_prefix("--level=").to_int(), 1, Progression.LEVEL_CAP)
		elif arg == "--trace":
			trace = true
		elif arg.begins_with("--only="):
			only = arg.trim_prefix("--only=").split(",")
	_run.call_deferred()


func _run() -> void:
	seed(10)
	SaveGame.save_path = "user://party_check_save.json"  # never touch the real save
	SaveGame.wipe()
	var scene: Node = (load(String(DungeonRegistry.info("stormwatch").get("scene", ""))) as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	zone = scene as DungeonZone
	for i in 5:
		await get_tree().physics_frame
	for i in classes.size():
		var cd := ClassData.load_by_id(classes[i])
		if cd == null:
			push_error("party_check: unknown class %s" % classes[i])
			get_tree().quit(1)
			return
		var h: Player
		if i == 0:
			h = zone.debug_swap_class(classes[i])
			h.camera_rig = null
			h.targeting = null
		else:
			h = Player.create(cd)
			h.is_local = false
			zone.add_player(h)
			h.global_position = zone._player_spawn_point() + Vector3(2.0 * i, 0, 0)
		heroes.append(h)
	lead = heroes[0]
	for i in heroes.size():
		_prepare(heroes[i], i)
	print("== RUNEBOUND party check: %s, level %d, the Stormwatch ==" % [
		", ".join(heroes.map(func(h: Player) -> String: return h.class_data.display_name)), level])
	for id in _camp_ids():
		if only.is_empty() or only.has(id):
			await _fight_camp(id, zone.camps[id] as EncounterSpawner)
	for arena in _arenas():
		if only.is_empty() or only.has(arena.arena_id):
			await _fight_arena(arena)
	_report()
	get_tree().quit(0)


func _prepare(h: Player, i: int) -> void:
	var bot := BotInputSource.new(11 + i)
	bot.leader = null if i == 0 else lead
	h.input_source = bot
	BotInputSource.outfit(h, level)
	for data in h.class_data.trainer_abilities():
		if data.learn_level <= level:
			h.learn_ability(data.id)
	h.health.heal_full()
	var id := h.get_instance_id()
	h.health.damaged.connect(func(hit: HitInfo) -> void: _damage[id] = float(_damage.get(id, 0.0)) + hit.damage)
	h.health.dot_damaged.connect(func(amount: float, _t: HitInfo.DamageType) -> void:
		_damage[id] = float(_damage.get(id, 0.0)) + amount)
	h.player_died.connect(func() -> void: _downs += 1)


func _camp_ids() -> Array[String]:
	var ids: Array[String] = []
	for poi in zone.layout.pois.pois:  # the way through, in the layout's order
		if String(poi.get("type", "")) == "camp":
			ids.append(String(poi["id"]))
	return ids


func _arenas() -> Array[BossArena]:
	var order: Array[String] = ["sw_arena_sworn", "sw_arena_gale", "sw_arena_caller"]
	var out: Array[BossArena] = []
	for id in order:
		if zone.arenas.has(id):
			out.append(zone.arenas[id] as BossArena)
	return out


## The party a few metres off `at`: the tank in front, the others behind it.
func _place(at: Vector3, toward: Vector3) -> void:
	_clear_leftovers()
	var back := (at - toward)
	back.y = 0.0
	back = back.normalized() if back.length() > 0.1 else Vector3.BACK
	var side := Vector3(-back.z, 0.0, back.x)
	for i in heroes.size():
		var h := heroes[i]
		h.downed = false
		h.health.heal_full()
		h.resonance = h.max_resource() * 0.5
		h.reset_cooldowns()
		var p := at + (back * 3.0 + side * (float(i) - 1.0) * 2.5 if i > 0 else Vector3.ZERO)
		h.global_position = zone.ground_point(zone.safe_spawn(p), 0.2)
		h.velocity = Vector3.ZERO
	_damage.clear()
	_downs = 0


func _approach(home: Vector3) -> Vector3:
	for dist: float in [7.0, 5.0, 3.0]:
		for k in 8:
			var p := home + Vector3(cos(k * TAU / 8.0), 0.0, sin(k * TAU / 8.0)) * dist
			if zone.layout.is_walkable(p.x, p.z) and not zone.layout.in_channel(p.x, p.z) and zone.room_id_at(p) == zone.room_id_at(home):
				return p
	return home


func _fight_camp(id: String, sp: EncounterSpawner) -> void:
	var home := sp.global_position
	_place(_approach(home), home)
	var cleared := [false]
	var on_clear := func() -> void: cleared[0] = true
	sp.cleared.connect(on_clear)
	sp.reset()
	sp.trigger(zone, lead)
	var r := await _fight(func() -> bool: return cleared[0], CAMP_TIMEOUT)
	sp.cleared.disconnect(on_clear)
	_record("camp %s (%s)" % [id, "+".join(sp.composition)], r, cleared[0])


func _fight_arena(arena: BossArena) -> void:
	_place(arena.global_position + Vector3(0.0, 0.0, 7.0), arena.global_position)
	arena.start()
	var boss_ref: WeakRef = weakref(arena.boss)  # the boss is freed after its death: never cast a freed one
	var tally := {"grounded": 0, "struck": 0}
	var r := await _fight(func() -> bool:
		var b := boss_ref.get_ref() as EnemyBase
		var caller := b as LastStormcaller
		if caller != null:
			tally["grounded"] = caller.grounded_claps
			tally["struck"] = caller.claps
		return b == null or b.ai_state == EnemyBase.AIState.DEAD, BOSS_TIMEOUT)
	var boss := boss_ref.get_ref() as EnemyBase
	var down := boss == null or boss.ai_state == EnemyBase.AIState.DEAD
	var note := ""
	if not down:
		note = " - at %.0f %%" % (100.0 * boss.health.current_health / boss.health.max_health)
	if arena.boss_id == "last_stormcaller":
		note += " (thunder grounded %d, struck %d)" % [int(tally["grounded"]), int(tally["struck"])]
	_record("%s%s" % [arena.boss_id, note], r, down)
	if is_instance_valid(boss) and boss.ai_state != EnemyBase.AIState.DEAD:
		arena.reset()


## Runs until `done`, a wipe or `timeout`: [simulated seconds, wiped].
func _fight(done: Callable, timeout: float) -> Array:
	var wipes0 := zone.revive_system.wipes if zone.revive_system != null else 0
	var t := 0.0
	var next_trace := 0.0
	var scale := 1.0 + NetWorld.HP_PER_EXTRA_HERO * float(heroes.size() - 1)
	while t < timeout:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		for e in EnemyBase.all_enemies:  # the server's health for this party
			if is_instance_valid(e) and not e.has_meta(&"party_scaled") and e.ai_state != EnemyBase.AIState.DEAD:
				e.set_meta(&"party_scaled", true)
				e.health.max_health *= scale
				e.health.current_health *= scale
		if zone.revive_system != null and zone.revive_system.wipes > wipes0:
			return [t, true]
		if bool(done.call()):
			return [t, false]
		if trace and t >= next_trace:
			next_trace += 5.0
			_trace(t)
	return [t, false]


func _trace(t: float) -> void:
	var parts: Array[String] = []
	for h in heroes:
		parts.append("%s %.0f%%%s" % [h.class_data.display_name, 100.0 * h.health.current_health / h.health.max_health,
			" DOWN" if h.health.is_dead else ""])
	for e in EnemyBase.all_enemies:
		if is_instance_valid(e) and e.ai_state != EnemyBase.AIState.DEAD:
			parts.append("%s %s hp%.0f" % [e.type_id, EnemyBase.AIState.keys()[e.ai_state], e.health.current_health])
	print("    t=%4.0f %s" % [t, "; ".join(parts)])


func _record(label: String, r: Array, won: bool) -> void:
	var result := "wipe" if bool(r[1]) else ("clear" if won else "timeout")
	var taken: Array[String] = []
	for h in heroes:
		taken.append("%s %.0f" % [h.class_data.display_name.left(5), float(_damage.get(h.get_instance_id(), 0.0))])
	_results.append({"label": label, "result": result, "time": float(r[0]), "downs": _downs})
	print("  %-62s %-7s %5.1f s  downs %d  took %s" % [label, result, float(r[0]), _downs, ", ".join(taken)])


func _clear_leftovers() -> void:
	for child in zone.enemies_root.get_children():
		child.free()


func _report() -> void:
	var won := 0
	var wipes := 0
	var downs := 0
	var time := 0.0
	for r in _results:
		won += 1 if r["result"] == "clear" else 0
		wipes += 1 if r["result"] == "wipe" else 0
		downs += int(r["downs"])
		time += float(r["time"])
	print("== party %s L%d: %d/%d fights won, %d wipes, %d downs, %.0f s fighting ==" % [
		"+".join(classes), level, won, _results.size(), wipes, downs, time])
