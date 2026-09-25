class_name BotInputSource
extends InputSource
## M09: a scripted hero for load tests and headless co-op bots. Walks to the
## nearest living enemy, cleaves in reach, throws Ember Lance / Fracture Rune
## from range, closes gaps with Storm Step, slams with Earthbreaker when it
## can pay for it and dodges now and then. With no enemy in range it follows
## `leader` (when set). Bots have no camera: every ability aims along the
## hero's facing, and walking at the target is what turns the hero to it.

const RETARGET_EVERY := 0.5   # seconds between nearest-enemy scans
const ENGAGE_RADIUS := 35.0   # enemies farther than this are ignored
const MELEE_REACH := 2.2      # cleave when the target is this close
const STAND_OFF := 1.4        # stop walking inside this distance
const FOLLOW_DISTANCE := 5.0  # trail the leader at about this distance

var leader: Player = null
var engage_radius: float = ENGAGE_RADIUS
var target: EnemyBase = null

var _rng := RandomNumberGenerator.new()
var _retarget_left: float = 0.0
## Action id -> seconds until the bot presses it again (its own pacing on top
## of the real cooldowns, so presses spread out like a person's).
var _wait: Dictionary = {}


func _init(seed_value: int = 0) -> void:
	_rng.seed = seed_value


func poll(intent: PlayerIntent, player: Player) -> void:
	if player.input_locked:
		return
	var dt := player.get_physics_process_delta_time()
	for id: StringName in _wait.keys():
		_wait[id] = float(_wait[id]) - dt
	_retarget_left -= dt
	if _retarget_left <= 0.0 or not _alive(target):
		_retarget_left = RETARGET_EVERY
		target = _nearest_enemy(player.global_position)
	if target == null:
		_follow(intent, player)
		return
	var to_target := target.global_position - player.global_position
	to_target.y = 0.0
	var dist := to_target.length()
	var dir := to_target / dist if dist > 0.01 else player.facing()
	if dist > STAND_OFF:
		intent.move_dir = dir
	if dist <= MELEE_REACH:
		_press(intent, player, &"rune_cleave", 0.35)
		_press(intent, player, &"earthbreaker", 3.0)
		_press(intent, player, &"dodge", 6.0)
	elif dist < 22.0:
		_press(intent, player, &"ember_lance", 1.4)
		if dist > 5.0 and dist < 12.0:
			_press(intent, player, &"storm_step", 5.0)
		if dist > 4.5 and dist < 8.0:
			_press(intent, player, &"fracture_rune", 7.0)  # lands 6 m ahead of the hero


func _follow(intent: PlayerIntent, player: Player) -> void:
	if leader == null or not is_instance_valid(leader) or leader == player:
		return
	var to_leader := leader.global_position - player.global_position
	to_leader.y = 0.0
	if to_leader.length() > FOLLOW_DISTANCE:
		intent.move_dir = to_leader.normalized()


func _press(intent: PlayerIntent, player: Player, id: StringName, every: float) -> void:
	if float(_wait.get(id, 0.0)) > 0.0 or not player.knows(id):
		return
	intent.pressed.append(id)
	_wait[id] = every * _rng.randf_range(0.8, 1.25)


func _nearest_enemy(from: Vector3) -> EnemyBase:
	var best: EnemyBase = null
	var best_d := engage_radius
	for e in EnemyBase.all_enemies:
		if not _alive(e):
			continue
		var d := e.global_position.distance_to(from)
		if d < best_d:
			best_d = d
			best = e
	return best


static func _alive(e: EnemyBase) -> bool:
	return e != null and is_instance_valid(e) and e.ai_state != EnemyBase.AIState.DEAD
