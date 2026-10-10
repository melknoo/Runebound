extends Node
## M10 phase 4: can each class clear the Ashen Highlands alone? Headless, one
## bot hero of the chosen class at a slice-clear level with the trainer kit it
## could afford by then and rolled gear (no talents): it fights every camp in
## turn, then the Colossus. The bot walks in or kites and uses its class's kit
## but never reads a telegraph (it dodges at random), so the numbers are a
## floor for a player, and comparable between the classes.
## Every fight starts at full health (the game has no healing between fights
## yet; the sum of damage taken shows how far one health bar goes).
##   godot --headless --fixed-fps 60 --path . res://tests/solo_check.tscn -- --class=elementalist --level=6
## (`tools\run_godot.cmd solocheck <class> [level]`)
## M13: `--dungeon=cistern` takes a dungeon's camps and its bosses instead.
## Its puzzles count as solved; in the boss fights the test plays the room's
## part a player would (it drains the basin again a few seconds after the
## water comes back, it strikes a frost pylon soon after the heart floods).

const CAMP_TIMEOUT := 90.0    # simulated seconds per camp
const BOSS_TIMEOUT := 240.0   # simulated seconds for the Colossus
const APPROACH := 11.0        # the hero starts this far from a camp (inside its trigger radius)
const GEAR_ITEM_LEVEL := 3    # the Highlands' top band
const DRAIN_AFTER := 6.0      # dungeon: seconds a player needs to run the sluices again
const FREEZE_AFTER := 2.0     # dungeon: seconds before a player strikes a pylon

var class_id: StringName = &"elementalist"
var level: int = 6
## --trace: log the fight every 5 s (who is where, in which state).
var trace: bool = false
## --only=<camp id>[,<id>]: just these fights (no Colossus), e.g. to trace one.
var only: PackedStringArray = PackedStringArray()
## --dungeon=<id>: the DungeonRegistry id to clear instead of the Highlands.
var dungeon: String = ""
var zone: ZoneBase
var hero: Player

var _results: Array[Dictionary] = []
var _damage_taken: float = 0.0
var _died: bool = false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--class="):
			class_id = StringName(arg.trim_prefix("--class="))
		elif arg.begins_with("--level="):
			level = clampi(arg.trim_prefix("--level=").to_int(), 1, Progression.LEVEL_CAP)
		elif arg == "--trace":
			trace = true
		elif arg.begins_with("--only="):
			only = arg.trim_prefix("--only=").split(",")
		elif arg.begins_with("--dungeon="):
			dungeon = arg.trim_prefix("--dungeon=")
	_run.call_deferred()


func _run() -> void:
	seed(10)  # the same gear every run (the fights still vary a little with frame timing)
	SaveGame.save_path = "user://solo_check_save.json"  # never touch the real save
	SaveGame.wipe()
	var scene_path := "res://scenes/ashen_highlands.tscn"
	if dungeon != "":
		scene_path = String(DungeonRegistry.info(dungeon).get("scene", ""))
		if scene_path == "":
			push_error("solo_check: unknown dungeon %s" % dungeon)
			get_tree().quit(1)
			return
	var scene: Node = (load(scene_path) as PackedScene).instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	zone = scene as ZoneBase
	for i in 5:
		await get_tree().physics_frame
	if ClassData.load_by_id(class_id) == null:
		push_error("solo_check: unknown class %s" % class_id)
		get_tree().quit(1)
		return
	hero = zone.debug_swap_class(class_id)
	_prepare_hero()
	print("== RUNEBOUND solo check: %s, level %d%s ==" % [hero.class_data.display_name, level,
		"" if dungeon == "" else ", " + zone.zone_title()])
	print("health %.0f | loadout %s | gear: %s" % [hero.health.max_health, ", ".join(hero.loadout),
		", ".join(_gear_names())])
	for id in _camp_ids():
		if not only.is_empty() and not only.has(id):
			continue
		var sp := _camps()[id] as EncounterSpawner
		await _fight_camp(id, sp)
	if only.is_empty():
		if zone is DungeonZone:
			for arena in _arenas():
				await _fight_arena(arena)
		else:
			await _fight_boss()
	_report()
	get_tree().quit(0)


func _prepare_hero() -> void:
	hero.input_source = BotInputSource.new(7)
	hero.camera_rig = null  # no camera: every ability aims along the bot's aim_dir
	hero.targeting = null
	var xp := 0
	for lvl in range(1, level):
		xp += Progression.xp_to_next(lvl)
	hero.progression.add_xp(xp)
	for data in hero.class_data.trainer_abilities():
		if data.learn_level <= level:
			hero.learn_ability(data.id)
	for slot in ItemData.SLOT_COUNT:
		var item := ItemGenerator.generate(1, hero.class_data.id)
		for tries in 200:  # the generator rolls the slot: keep rolling until it fits
			if int(item.slot) == slot:
				break
			item = ItemGenerator.generate(1, hero.class_data.id)
		ItemGenerator.apply_item_level(item, GEAR_ITEM_LEVEL)
		hero.equipment.add_item(item)  # equip() takes from the bag
		hero.equipment.equip(item)
	hero.health.heal_full()
	hero.health.damaged.connect(func(hit: HitInfo) -> void: _damage_taken += hit.damage)
	hero.health.dot_damaged.connect(func(amount: float, _type: HitInfo.DamageType) -> void: _damage_taken += amount)
	hero.player_died.connect(func() -> void: _died = true)


func _gear_names() -> Array[String]:
	var out: Array[String] = []
	for item: ItemData in hero.equipment.equipped.values():
		if item != null:
			out.append("%s (%s)" % [item.display_name, ItemData.Rarity.keys()[item.rarity].to_lower()])
	return out


func _camps() -> Dictionary:
	return zone.get(&"camps") as Dictionary


## Stationary camps, ordered by level band (ambushes and patrols have no home to walk to).
func _camp_ids() -> Array[String]:
	var camps := _camps()
	var ids: Array[String] = []
	for id: String in camps.keys():
		var sp := camps[id] as EncounterSpawner
		if not sp.around_players and sp.patrol.is_empty():
			ids.append(id)
	ids.sort_custom(func(a: String, b: String) -> bool:
		var la := _band(camps[a] as EncounterSpawner)
		var lb := _band(camps[b] as EncounterSpawner)
		return la < lb if la != lb else a < b)
	return ids


func _band(sp: EncounterSpawner) -> int:
	if zone is DungeonZone:
		return int((zone as DungeonZone).info.get("level", 1))
	var hl := zone as AshenHighlands
	return hl.layout.level_at(sp.global_position.x, sp.global_position.z) if hl != null and hl.layout != null else 1


## A dungeon's arenas, the mid-boss before the end boss.
func _arenas() -> Array[BossArena]:
	var out: Array[BossArena] = []
	for key: String in (zone as DungeonZone).arenas:
		out.append((zone as DungeonZone).arenas[key] as BossArena)
	out.sort_custom(func(a: BossArena, b: BossArena) -> bool: return a.reward == "mid" and b.reward != "mid")
	return out


## Where the hero starts a camp fight: the Highlands' fixed approach; in a
## dungeon a walkable spot in the camp's own room, a few metres off.
func _approach(home: Vector3) -> Vector3:
	var dz := zone as DungeonZone
	if dz == null:
		return home + Vector3(APPROACH, 0.0, 0.0)
	for dist: float in [7.0, 5.0, 3.0]:
		for k in 8:
			var p := home + Vector3(cos(k * TAU / 8.0), 0.0, sin(k * TAU / 8.0)) * dist
			if dz.layout.is_walkable(p.x, p.z) and not dz.layout.in_channel(p.x, p.z) and dz.room_id_at(p) == dz.room_id_at(home):
				return p
	return home


func _fight_camp(id: String, sp: EncounterSpawner) -> void:
	_clear_leftovers()
	var home := sp.global_position
	_place_hero(_approach(home))
	var cleared := [false]
	var on_clear := func() -> void: cleared[0] = true
	sp.cleared.connect(on_clear)
	# always afresh: a neighbour fight may have woken this camp (its pack went
	# with _clear_leftovers, the spawner would wait for it forever)
	sp.reset()
	sp.trigger(zone, hero)
	if id.begins_with("lurker"):
		await get_tree().create_timer(1.0).timeout
		var tree_at := home
		for e in sp.pack():
			if is_instance_valid(e):
				tree_at = e.global_position
		_place_hero(tree_at + Vector3(3.0, 0.0, 0.0))  # M12: walk past the "tree" like a player would
	var t := await _fight(func() -> bool: return cleared[0], CAMP_TIMEOUT)
	sp.cleared.disconnect(on_clear)
	_record("camp %s (L%d, %s)" % [id, _band(sp), "+".join(sp.composition)], t, cleared[0])


func _fight_boss() -> void:
	_clear_leftovers()
	var spawn: Vector3 = zone.get(&"_boss_spawn")
	_place_hero(spawn + Vector3(0.0, 0.0, 14.0))
	zone.call(&"_start_boss_fight")
	var boss: AshveinColossus = (zone as AshenHighlands).boss
	var t := await _fight(func() -> bool:
		return boss == null or not is_instance_valid(boss) or boss.ai_state == EnemyBase.AIState.DEAD, BOSS_TIMEOUT)
	var down := boss == null or not is_instance_valid(boss) or boss.ai_state == EnemyBase.AIState.DEAD
	var left := "" if down else " - Colossus at %.0f %%" % (100.0 * boss.health.current_health / boss.health.max_health)
	_record("Ashvein Colossus (L3)%s" % left, t, down)


## M13: a dungeon boss in its arena. The test plays the room for the hero
## (see the header): the basin's sluices, the heart's frost pylons.
func _fight_arena(arena: BossArena) -> void:
	_clear_leftovers()
	_place_hero((zone as DungeonZone).safe_spawn(arena.global_position + Vector3(0.0, 0.0, 6.0)))
	arena.start()
	var boss := arena.boss
	var wet := [0.0]
	var flooded := [0.0]
	var t := await _fight(func() -> bool:
		if boss == null or not is_instance_valid(boss) or boss.ai_state == EnemyBase.AIState.DEAD:
			return true
		var step := get_physics_process_delta_time()
		var keeper := boss as BloatedKeeper
		if keeper != null and keeper.drain() != null and not keeper.is_dry():
			wet[0] += step
			if wet[0] >= DRAIN_AFTER:
				wet[0] = 0.0
				for i in keeper.drain().levers.size():
					keeper.drain().request("pull", i, hero)
		var maw := boss as Deepmaw
		if maw != null and maw.flood == "up":
			flooded[0] += step
			if flooded[0] >= FREEZE_AFTER:
				flooded[0] = 0.0
				maw.freeze_flood()
		return false, BOSS_TIMEOUT)
	var down := boss == null or not is_instance_valid(boss) or boss.ai_state == EnemyBase.AIState.DEAD
	var left := "" if down else " - at %.0f %%" % (100.0 * boss.health.current_health / boss.health.max_health)
	_record("%s (L%d)%s" % [arena.boss_id, int((zone as DungeonZone).info.get("boss_level", 1)), left], t, down)


## Runs the simulation until `done` says so, the hero dies or `timeout`
## passes; returns the simulated seconds.
func _fight(done: Callable, timeout: float) -> float:
	_damage_taken = 0.0
	_died = false
	var t := 0.0
	var next_trace := 0.0
	while t < timeout:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if _died or bool(done.call()):
			break
		if trace and t >= next_trace:
			next_trace += 5.0
			_trace(t)
	return t


## --trace: every 5 s where the hero stands and what the enemies do.
func _trace(t: float) -> void:
	var parts: Array[String] = []
	for e in EnemyBase.all_enemies:
		if is_instance_valid(e) and e.ai_state != EnemyBase.AIState.DEAD:
			parts.append("%s %s %.0fm hp%.0f%s" % [(e.get_script() as Script).get_global_name(),
				EnemyBase.AIState.keys()[e.ai_state], e.global_position.distance_to(hero.global_position),
				e.health.current_health, (" bred %d" % (e as EnemyNest).bred) if e is EnemyNest else ""])
	print("    t=%4.0f hero %s state %s | %s" % [t, hero.global_position.snapped(Vector3.ONE),
		Player.State.keys()[hero.state], "; ".join(parts)])


func _record(label: String, t: float, won: bool) -> void:
	var result := "died" if _died else ("clear" if won else "timeout")
	_results.append({"label": label, "result": result, "time": t, "damage": _damage_taken,
		"hp_pct": 100.0 * hero.health.current_health / hero.health.max_health})
	print("  %-58s %-7s %5.1f s  took %4.0f  hp %3.0f %%" % [label, result, t, _damage_taken,
		0.0 if _died else 100.0 * hero.health.current_health / hero.health.max_health])


func _place_hero(pos: Vector3) -> void:
	hero.health.heal_full()
	hero.resonance = 0.0
	hero.reset_cooldowns()
	hero.global_position = zone.ground_point(pos, 0.2)
	hero.velocity = Vector3.ZERO


## Enemies still alive from the fight before (a timeout, a neighbour camp the
## bot woke) would only muddy the next one.
func _clear_leftovers() -> void:
	for child in zone.enemies_root.get_children():
		child.free()


func _report() -> void:
	var cleared := 0
	var deaths := 0
	var damage := 0.0
	var time := 0.0
	for r in _results:
		cleared += 1 if r["result"] == "clear" else 0
		deaths += 1 if r["result"] == "died" else 0
		damage += float(r["damage"])
		time += float(r["time"])
	print("== %s L%d: %d/%d fights won, %d deaths, %.0f s fighting, %.0f damage taken (%.1f health bars) ==" % [
		hero.class_data.display_name, level, cleared, _results.size(), deaths, time, damage,
		damage / hero.health.max_health])
