class_name EncounterSpawner
extends Node3D
## Camp spawner (M04, M08 v2): when a hero enters the trigger radius it spawns
## its composition, one enemy per physics frame, around its home (or, as an
## ambush, around the hero who walked in). Cleared camps persist (SaveGame
## `world.camps`, keyed by `camp_id`) and re-arm `respawn_minutes` later,
## but only while no hero stands nearby. A pack with a `patrol` roams: the
## home walks the path while nobody is engaged and the enemies follow it
## through their leash. Enemies get `home` + `leash` so they come back and
## heal instead of chasing across the zone.

signal cleared  # every spawned enemy died
signal rearmed  # a cleared camp is live again

enum State { ARMED, ACTIVE, CLEARED }

const CLEAR_XP_PER_ENEMY := 15  # M07: camp bonus on top of the kills
const CHECK_INTERVAL := 0.5     # seconds between proximity checks
const PATROL_PAUSE := 4.0       # seconds a roaming pack rests at a waypoint

var composition: Array[String] = ["rusher", "rusher"]
var trigger_radius: float = 13.0
var elite_kind: int = -1  # forwarded when composition contains "elite"
## Persistence key ("" = never saved: re-arms only in this session).
var camp_id: String = ""
## Minutes until a cleared camp comes back (0 = never within a session).
var respawn_minutes: float = 10.0
## No re-arm while a hero is this close to the home spot.
var rearm_radius: float = 45.0
## Ambush: spawn on a ring around the hero who triggered it, not around home.
var around_players: bool = false
var ambush_ring: Vector2 = Vector2(6.0, 9.0)
## Enemies of this pack return home (and heal) beyond this distance (0 = none).
var leash: float = 26.0
## Roaming pack: world points the home walks between while nobody fights.
var patrol: PackedVector3Array = PackedVector3Array()
var patrol_speed: float = 1.6

var state: State = State.ARMED
## Legacy alias (M04 tests, runners): anything but ARMED.
var triggered: bool:
	get:
		return state != State.ARMED
var home: Vector3 = Vector3.INF
var _alive: int = 0
var _pack: Array[EnemyBase] = []
var _cleared_at: float = 0.0
var _check_left: float = 0.0
var _patrol_index: int = 0
var _patrol_pause: float = 0.0
var _spawning: bool = false
## Physics frame of every spawn of the current pack (tests: one per frame).
var spawn_frames: PackedInt64Array = PackedInt64Array()


func _ready() -> void:
	# `home` resolves lazily (_home): zones set the position after add_child.
	if camp_id != "":
		var at := SaveGame.camp_cleared_at(camp_id)
		if at > 0.0:
			if respawn_minutes > 0.0 and _now() - at >= respawn_minutes * 60.0:
				SaveGame.clear_camp(camp_id)  # expired while the hero was away
			else:
				state = State.CLEARED
				_cleared_at = at
	_check_left = randf() * CHECK_INTERVAL  # spread the checks over frames


static func _now() -> float:
	return Time.get_unix_time_from_system()


## The spot the pack belongs to (the spawner's position unless a roaming
## pack has walked it along its patrol).
func _home() -> Vector3:
	return home if home != Vector3.INF else global_position


func _physics_process(delta: float) -> void:
	match state:
		State.ARMED:
			_check_left -= delta
			if _check_left <= 0.0:
				_check_left = CHECK_INTERVAL
				var zone := _zone()
				if zone != null and not zone.players.is_empty():
					var near := zone.players_within(global_position, trigger_radius)  # M07b: any hero wakes the camp
					if not near.is_empty():
						trigger(zone, near[0])
		State.ACTIVE:
			if not patrol.is_empty():
				_roam(delta)
		State.CLEARED:
			_check_left -= delta
			if _check_left <= 0.0:
				_check_left = CHECK_INTERVAL
				check_rearm(_now())


func _zone() -> ZoneBase:
	return get_tree().current_scene as ZoneBase


## Spawns the composition (one enemy per physics frame so a big pack never
## hitches a frame). `hero` is who walked in (ambush centre).
func trigger(zone: ZoneBase, hero: Player = null) -> void:
	if state != State.ARMED or _spawning:
		return
	state = State.ACTIVE
	_alive = composition.size()
	_pack.clear()
	spawn_frames.clear()
	home = _home()
	var centre := home
	var ring := Vector2(1.5, 4.0)
	if around_players and hero != null and is_instance_valid(hero):
		centre = hero.global_position
		ring = ambush_ring
		Sfx.play("charge_horn", centre, -8.0, 0.1, 1.2)
	else:
		Sfx.play("telegraph", global_position, -6.0, 0.1, 0.7)
	_spawn_pack(zone, centre, ring)


func _spawn_pack(zone: ZoneBase, centre: Vector3, ring: Vector2) -> void:
	_spawning = true
	for i in composition.size():
		if i > 0:
			await get_tree().physics_frame
			if not is_inside_tree() or not is_instance_valid(zone):
				_spawning = false
				return
		var angle := TAU * float(i) / float(composition.size()) + randf() * 0.5
		var pos := zone.ground_point(centre + Vector3(cos(angle) * randf_range(ring.x, ring.y), 0.0,
			sin(angle) * randf_range(ring.x, ring.y)), 0.2)
		var enemy: EnemyBase
		if composition[i] == "elite":
			enemy = zone.spawn_elite(elite_kind, pos)
		else:
			enemy = zone.spawn_by_id(composition[i], pos)
		enemy.home = home
		enemy.leash = leash
		_pack.append(enemy)
		spawn_frames.append(Engine.get_physics_frames())
		enemy.enemy_died.connect(_on_pack_member_died.bind(zone))
	_spawning = false


func _on_pack_member_died(_e: EnemyBase, zone: ZoneBase) -> void:
	_alive -= 1
	if _alive > 0 or state != State.ACTIVE:
		return
	state = State.CLEARED
	_cleared_at = _now()
	if camp_id != "":
		SaveGame.mark_camp_cleared(camp_id, _cleared_at)
	_check_left = CHECK_INTERVAL
	cleared.emit()
	var bonus := CLEAR_XP_PER_ENEMY * composition.size()
	if is_instance_valid(zone):
		for hero in zone.players:  # M07b: the camp bonus goes to the whole party
			if hero != null and is_instance_valid(hero):
				hero.progression.add_xp(bonus)
		zone.hud.toast("Camp cleared  +%d XP" % bonus, ArtKit.color("color_roles.experience.body", Color(0.62, 0.7, 1.0)))


## Re-arm once the respawn time has passed and nobody is close.
func check_rearm(now: float) -> void:
	if state != State.CLEARED or respawn_minutes <= 0.0:
		return
	if now - _cleared_at < respawn_minutes * 60.0:
		return
	var zone := _zone()
	if zone != null and not zone.players_within(_home(), rearm_radius).is_empty():
		return
	reset()


## Back to ARMED (the save entry goes with it).
func reset() -> void:
	state = State.ARMED
	_alive = 0
	_pack.clear()
	_patrol_index = 0
	_patrol_pause = 0.0
	home = Vector3.INF  # back to the spawner's own spot
	if camp_id != "":
		SaveGame.clear_camp(camp_id)
	rearmed.emit()


## Roaming pack: the home walks the patrol while no member is fighting; the
## members follow it through their leash / idle return.
func _roam(delta: float) -> void:
	for e in _pack:
		if is_instance_valid(e) and e.ai_state in [EnemyBase.AIState.CHASE, EnemyBase.AIState.WINDUP,
				EnemyBase.AIState.ATTACK, EnemyBase.AIState.CIRCLE, EnemyBase.AIState.RETREAT]:
			return
	if _patrol_pause > 0.0:
		_patrol_pause -= delta
		return
	var goal := patrol[_patrol_index]
	var flat := Vector3(goal.x - home.x, 0.0, goal.z - home.z)
	if flat.length() < 0.5:
		_patrol_index = (_patrol_index + 1) % patrol.size()
		_patrol_pause = PATROL_PAUSE
		return
	home += flat.normalized() * minf(patrol_speed * delta, flat.length())
	home.y = goal.y
	for e in _pack:
		if is_instance_valid(e):
			e.home = home


## Live members (tests, debug).
func pack() -> Array[EnemyBase]:
	var out: Array[EnemyBase] = []
	for e in _pack:
		if is_instance_valid(e) and e.ai_state != EnemyBase.AIState.DEAD:
			out.append(e)
	return out
