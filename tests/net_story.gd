class_name NetStory
extends RefCounted
## M14a phase 4: the co-op story scenario `story_boss` for tests/net_test.gd.
## The server stands in the Highlands with the Colossus long beaten (its world
## flag set). C1 is a veteran (its story has the beat `boss:colossus`), C2 a
## newcomer whose story still needs it:
##   1. C1 alone at the arena: the Colossus stays down.
##   2. C2 arrives: it stands again, both clients see it; the server kills it.
##   3. Only C2 gets the beat (its own director, within 60 m) and the boss's
##      legendary; the server credits C2 and the Colossus doesn't come back.
## Client side: `client(driver, role)` (tests/net_client.gd delegates), server
## side: `server_verdict(probe)` (tests/net_server_probe.gd delegates).

static var _phase := ""
static var _spawned_at := -1.0
static var _died_at := -1.0
static var _respawned := false
static var _credit_seen := false


# ---------------------------------------------------------------------------
# Client
# ---------------------------------------------------------------------------

static func client(d: Variant, role: String) -> void:
	if not await d._in_zone():
		return
	var tree: SceneTree = (d as Node).get_tree()
	var zone := tree.current_scene as AshenHighlands
	if zone == null:
		d._finish("fail: not in the Highlands")
		return
	var hero := zone.player
	var ql := QuestLog.of(hero)
	ql.from_dict({"v": 1, "act": 1, "beats": ["boss:colossus"] if role == "c1" else []})
	ql.bind(hero)
	zone.quest_director.begin()  # the story arrived after the zone began (a fresh test character)
	if zone.net_world != null:
		zone.net_world.mark_character_dirty()  # the server learns the story
	var trigger: Vector3 = zone.get(&"_boss_trigger").global_position
	if role == "c1":
		_place(hero, zone, trigger + Vector3(2, 0, 0))
		if not await d._until(func() -> bool: return _colossus() != null, 60.0, "the Colossus standing again for C2"):
			return
		if not await d._until(func() -> bool: return _colossus() == null, 40.0, "the Colossus beaten"):
			return
		await d._seconds(12.0)
		var legendary := _own_legendary(zone, hero)
		d._finish("ok" if legendary == 0 and ql.has_beat("boss:colossus") else
			"fail: the veteran got %d legendary drops" % legendary)
		return
	# c2 waits away from the arena first: C1 alone must not wake the boss
	_place(hero, zone, trigger + Vector3(0, 0, 70))
	await d._seconds(8.0)
	if _colossus() != null:
		d._finish("fail: the Colossus stood up for the veteran alone")
		return
	_place(hero, zone, trigger + Vector3(-2, 0, 0))
	if not await d._until(func() -> bool: return _colossus() != null, 30.0, "the Colossus for the newcomer"):
		return
	if not await d._until(func() -> bool: return _colossus() == null, 40.0, "the Colossus beaten"):
		return
	if not await d._until(func() -> bool: return ql.has_beat("boss:colossus") and _own_legendary(zone, hero) >= 1, 15.0,
			"C2's beat and its legendary"):
		return
	await d._seconds(10.0)  # stay while the server watches for a respawn
	if _colossus() != null:
		d._finish("fail: the Colossus came back for nobody")
		return
	d._finish("ok")


static func _place(hero: Player, zone: ZoneBase, at: Vector3) -> void:
	hero.global_position = zone.ground_point(at, 0.2)
	hero.velocity = Vector3.ZERO
	hero.teleports += 1


static func _colossus() -> EnemyBase:
	for e in EnemyBase.all_enemies:
		if is_instance_valid(e) and e.type_id == "colossus" and e.ai_state != EnemyBase.AIState.DEAD 				and e.process_mode != Node.PROCESS_MODE_DISABLED:  # not the zone's warm-up copy
			return e
	return null


## Legendary drops lying in the world for `hero` (its personal loot).
static func _own_legendary(zone: ZoneBase, hero: Player) -> int:
	var n := 0
	for child in zone.world.get_children():
		if child is ItemDrop and (child as ItemDrop).player == hero and (child as ItemDrop).item != null \
				and (child as ItemDrop).item.rarity == ItemData.Rarity.LEGENDARY:
			n += 1
	for item in hero.equipment.inventory:
		if item.rarity == ItemData.Rarity.LEGENDARY:
			n += 1
	return n


# ---------------------------------------------------------------------------
# Server
# ---------------------------------------------------------------------------

## Called twice a second by the probe; returns the verdict so far.
static func server_verdict(probe: Node) -> String:
	var zone := probe.get_tree().current_scene as AshenHighlands
	if zone == null:
		return "fail: the server is not in the Highlands"
	var now := Time.get_ticks_msec() / 1000.0
	if _phase == "":
		SaveGame.set_flag(&"colossus_defeated")  # beaten long ago on this server
		_phase = "alone"
	var c2 := int(probe.call(&"_roster_peer", "C2"))
	var boss := _colossus()
	match _phase:
		"alone":
			if boss != null:
				_spawned_at = now
				_phase = "fight"
			return "fail: waiting for C2 to wake the Colossus"
		"fight":
			if boss != null and now - _spawned_at > 3.0:
				boss.take_hit(HitInfo.create(99999.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.HEAVY, boss.global_position))
			if boss == null:
				_died_at = now
				_phase = "after"
			return "fail: the Colossus still stands"
		"after":
			if boss != null:
				_respawned = true
			if _respawned:
				return "fail: the Colossus came back although nobody needs it now"
			if c2 != 0 and not StoryBosses.needs(zone.net_world.heroes.get(c2) as Player, "colossus"):
				_credit_seen = true
			if not _credit_seen:
				return "fail: C2 not credited with the Colossus on the server"
			if now - _died_at < 8.0:
				return "fail: watching for a respawn"
			return "ok"
	return "fail: phase " + _phase
