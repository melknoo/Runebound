class_name BossArena
extends Node3D
## M13: a dungeon boss's room. The authority (offline this machine, online
## the server) wakes the boss when a living hero comes within
## `trigger_radius` inside the room, keeps it in the room, and resets the
## fight - the boss is dismissed and the arena re-arms, so the next try meets
## it at full health and scaled to the party then - once no living hero has
## stood in the room for RESET_GRACE seconds (everyone fell and woke at a
## rune, or walked out). The server never sees a dead proxy (its owner
## respawns it at once), so the rule is by position. The kill sets the
## arena's world flag (the server tells everyone: FLAG), opens what waits on
## it and hands out the boss's loot. A set flag means the boss stays dead.

const RESET_GRACE := 6.0
const CHECK_INTERVAL := 0.25

var arena_id: String = ""
## make_enemy id of the boss (ZoneBase.BOSS_TYPES).
var boss_id: String = "dungeon_boss"
## World flag set by the kill.
var flag: StringName = &""
## The arena room on XZ (DungeonLayout rect).
var rect: Rect2 = Rect2()
var trigger_radius: float = 9.0
## "mid" (a rare per hero) or "end" (a legendary and a rare per hero).
var reward: String = "mid"

var boss: EnemyBase = null
## Tests: fights started and resets so far (authority).
var starts: int = 0
var resets: int = 0
var _empty_for: float = 0.0
var _check_left: float = 0.0


func is_done() -> bool:
	return flag != &"" and SaveGame.has_flag(flag)


func fighting() -> bool:
	return boss != null and is_instance_valid(boss) and boss.ai_state != EnemyBase.AIState.DEAD


func _zone() -> ZoneBase:
	return ZoneBase.zone_of(self)


## Living heroes standing in the arena room.
func heroes_inside() -> Array[Player]:
	var out: Array[Player] = []
	var zone := _zone()
	if zone == null:
		return out
	for p in zone.players:
		if p != null and is_instance_valid(p) and not p.health.is_dead \
				and rect.has_point(Vector2(p.global_position.x, p.global_position.z)):
			out.append(p)
	return out


func _physics_process(delta: float) -> void:
	if Net.is_client() or is_done():
		return
	_check_left -= delta
	if _check_left > 0.0:
		return
	var step := CHECK_INTERVAL - _check_left
	_check_left = CHECK_INTERVAL
	var inside := heroes_inside()
	if not fighting():
		for p in inside:
			if p.global_position.distance_to(global_position) <= trigger_radius:
				start()
				return
		return
	if inside.is_empty():
		_empty_for += step
		if _empty_for >= RESET_GRACE:
			reset()
	else:
		_empty_for = 0.0


## Authority: the boss wakes in the middle of the room.
func start() -> void:
	var zone := _zone()
	if zone == null or fighting() or is_done():
		return
	starts += 1
	_empty_for = 0.0
	boss = ZoneBase.make_enemy(boss_id)
	if boss is DungeonBoss:
		(boss as DungeonBoss).arena_rect = rect
	zone._spawn_enemy(boss, zone.ground_point(global_position, 0.2))
	boss.enemy_died.connect(_on_boss_died)
	if zone.hud != null and boss.has_signal(&"boss_health_changed"):  # offline: the bar (clients get it with the puppet)
		zone.hud.show_boss_bar(boss.display_name.to_upper())
		boss.connect(&"boss_health_changed", zone.hud.update_boss_bar)
	Sfx.play("boss_roar", global_position, -4.0)
	GameFeel.camera_shake(0.3)


## Authority: nobody left to fight - the boss goes (on every machine), the
## arena waits for the next try.
func reset() -> void:
	resets += 1
	_empty_for = 0.0
	if fighting():
		boss.dismiss()
	boss = null
	var zone := _zone()
	if zone != null and zone.hud != null:
		zone.hud.hide_boss_bar()


func _on_boss_died(_e: EnemyBase) -> void:
	var zone := _zone()
	var at := boss.global_position if boss != null and is_instance_valid(boss) else global_position
	boss = null
	if flag != &"":
		SaveGame.set_flag(flag)  # co-op: the server tells every client (FLAG)
	if zone == null:
		return
	zone.apply_world_flag(flag)
	var ilvl := int((zone as DungeonZone).info.get("boss_level", 4)) if zone is DungeonZone else 4
	for hero in zone.party():  # personal loot (M09): every hero its own rolls
		var items: Array[ItemData] = []
		if reward == "end":
			var legendary := ItemGenerator.generate_legendary(hero.class_data.id)
			ItemGenerator.apply_item_level(legendary, ilvl)
			items.append(legendary)
		var rare := ItemGenerator.generate(2, hero.class_data.id)
		ItemGenerator.apply_item_level(rare, ilvl)
		items.append(rare)
		zone.give_reward(hero, 0, 0, 0, items, at)
