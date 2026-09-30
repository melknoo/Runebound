class_name BotInputSource
extends InputSource
## M09: a scripted hero for load tests and headless co-op bots. M10: plays its
## class - a melee hero walks in, cleaves and slams with Earthbreaker when it
## can pay for it; a ranged hero (ClassData.preferred_range) keeps its
## distance, fires Rune Bolts and Ember Lances, drops Fracture Runes and
## escapes with Storm Step when an enemy gets close. Both dodge now and then.
## With no enemy in range it follows `leader` (when set). Bots have no camera:
## they aim with PlayerIntent.aim_dir, straight at their target. A caster
## whose shots would hit a wall walks in until it has a clear line (M10 solo
## check: two casters on either side of a ruin wall stood there forever).
## M11: a healer (ClassData.role "Healer") first looks after the party - the
## heals go where Player.pick_heal_target says (the most wounded) - then
## fights like a caster with its own thorns and roots.

const RETARGET_EVERY := 0.5   # seconds between nearest-enemy scans
const ENGAGE_RADIUS := 35.0   # enemies farther than this are ignored
const MELEE_REACH := 2.2      # cleave when the target is this close
const STAND_OFF := 1.4        # stop walking inside this distance
const FOLLOW_DISTANCE := 5.0  # trail the leader at about this distance
## With a leader: never fight further than this from it (run back instead).
const LEADER_LEASH := 22.0

var leader: Player = null
var engage_radius: float = ENGAGE_RADIUS
var target: EnemyBase = null

var _rng := RandomNumberGenerator.new()
var _retarget_left: float = 0.0
## Whether a wall stands between the muzzle and the target (checked with the
## retarget scan, not every frame).
var _blocked: bool = false
## Action id -> seconds until the bot presses it again (its own pacing on top
## of the real cooldowns, so presses spread out like a person's).
var _wait: Dictionary = {}
## M10: action id -> seconds the bot keeps holding its key (Rune Wall).
var _hold: Dictionary = {}


func _init(seed_value: int = 0) -> void:
	_rng.seed = seed_value


func poll(intent: PlayerIntent, player: Player) -> void:
	if player.input_locked:
		return
	var dt := player.get_physics_process_delta_time()
	for id: StringName in _wait.keys():
		_wait[id] = float(_wait[id]) - dt
	for id: StringName in _hold.keys():
		_hold[id] = float(_hold[id]) - dt
		if float(_hold[id]) <= 0.0:
			_hold.erase(id)
		else:
			intent.held.append(id)
	_retarget_left -= dt
	if _retarget_left <= 0.0 or not _alive(target):
		_retarget_left = RETARGET_EVERY
		target = _nearest_enemy(player.global_position)
		_blocked = _alive(target) and _wall_between(player, target)
	if leader != null and is_instance_valid(leader) and leader != player \
			and leader.global_position.distance_to(player.global_position) > LEADER_LEASH:
		target = null  # too far from the leader: catch up first
	if player.class_data.role == "Healer":
		_heal_party(intent, player)
	if target == null:
		_follow(intent, player)
		return
	var to_target := target.global_position - player.global_position
	to_target.y = 0.0
	var dist := to_target.length()
	var dir := to_target / dist if dist > 0.01 else player.facing()
	intent.aim_dir = (target.global_position + Vector3(0, 1.0, 0) - player.muzzle_position()).normalized()
	if player.class_data.preferred_range > MELEE_REACH:
		_ranged(intent, player, dir, dist, player.class_data.preferred_range)
		if player.class_data.role == "Healer":
			_druid_fight(intent, player, dist)
		return
	if dist > STAND_OFF:
		intent.move_dir = dir
	if dist <= MELEE_REACH:
		_press(intent, player, &"rune_cleave", 0.35)
		_press(intent, player, &"earthbreaker", 3.0)
		# M10 tank: a wind-up aimed at us -> raise Rune Wall and parry it
		if target.ai_state == EnemyBase.AIState.WINDUP and target.target == player \
				and player.can_use(&"rune_wall") and not _hold.has(&"rune_wall"):
			_press(intent, player, &"rune_wall", 0.5)
			_hold[&"rune_wall"] = 0.7
			intent.held.append(&"rune_wall")
		elif not _hold.has(&"rune_wall"):
			_press(intent, player, &"dodge", 6.0)
	_tank_tools(intent, player, dist)


## M10: the tank's pulls, shouts and wards (a class without them presses nothing).
func _tank_tools(intent: PlayerIntent, player: Player, dist: float) -> void:
	if _enemies_within(player.global_position, 8.0) >= 2:
		_press(intent, player, &"rune_challenge", 12.0)
	if dist > 6.0 and dist < 10.0:
		_press(intent, player, &"warden_leap", 9.0)
	elif dist > 5.0 and dist < 15.0:
		_press(intent, player, &"rune_chain", 10.0)
	if player.in_combat() and player.health.current_health < player.health.max_health * 0.6:
		_press(intent, player, &"warding_rune", 18.0)
		_press(intent, player, &"runic_guard", 12.0)


func _enemies_within(from: Vector3, radius: float) -> int:
	var n := 0
	for e in EnemyBase.all_enemies:
		if _alive(e) and e.global_position.distance_to(from) <= radius:
			n += 1
	return n


## A caster's fight: hold the preferred range, back off when an enemy closes in.
func _ranged(intent: PlayerIntent, player: Player, dir: Vector3, dist: float, preferred: float) -> void:
	if dist > preferred or (_blocked and dist > 3.0):
		intent.move_dir = dir
	elif dist < preferred * 0.5:
		intent.move_dir = -dir
		if dist < 3.0:
			_press(intent, player, &"storm_step", 5.0)  # dashes along the retreat
			_press(intent, player, &"dodge", 4.0)
	if dist < 4.0:
		_press(intent, player, &"frost_nova", 10.0)  # too close: freeze them off
	if dist < 24.0:
		_press(intent, player, &"rune_bolt", 0.3)
		_press(intent, player, &"ember_lance", 1.4)
		if dist > 4.5 and dist < 11.0:
			_press(intent, player, &"fracture_rune", 7.0)  # lands 6 m along the aim
		if dist > 5.0 and dist < 12.0:
			_press(intent, player, &"flame_wall", 12.0)
		if dist < 15.0:
			_press(intent, player, &"ball_lightning", 9.0)
		if dist < 16.0 and player.resonance >= 60.0:
			_press(intent, player, &"ember_fall", 14.0)


## M11: a healer's first job - the wounded (Player.pick_heal_target picks
## whom; without a camera it is the lowest health share in reach).
func _heal_party(intent: PlayerIntent, player: Player) -> void:
	var zone := ZoneBase.zone_of(player)
	if zone == null:
		return
	var wounded := 0
	var badly := 0
	for ally in zone.players_within(player.global_position, Player.ALLY_RANGE):
		var frac := ally.health.current_health / maxf(ally.health.max_health, 1.0)
		if frac < 0.8:
			wounded += 1
		if frac < 0.4:
			badly += 1
	var mine := player.health.current_health / maxf(player.health.max_health, 1.0)
	if badly >= 2 or mine < 0.3:
		_press(intent, player, &"wild_bloom", 2.0)
	var t := player.pick_heal_target()
	var frac_t := t.health.current_health / maxf(t.health.max_health, 1.0)
	if frac_t < 0.6:
		_press(intent, player, &"mending_bloom", 0.9)
	if frac_t < 0.75 and t.in_combat():
		_press(intent, player, &"barkskin", 3.0)
	if frac_t < 0.85:
		_press(intent, player, &"regrowth", 3.0)
	if wounded >= 2:
		_press(intent, player, &"renewal_grove", 4.0)


## M11: the druid's own damage and control on top of its thorns.
func _druid_fight(intent: PlayerIntent, player: Player, dist: float) -> void:
	if dist < 24.0:
		_press(intent, player, &"thorn_volley", 0.3)
	if player.in_combat():
		_press(intent, player, &"growth_totem", 8.0)
	if dist < 16.0:
		_press(intent, player, &"root_grasp", 6.0)
	if dist < 5.0:
		_press(intent, player, &"wild_bloom", 20.0)  # too close: throw them back
	if dist > 3.0 and dist < 14.0:
		_press(intent, player, &"thornfield", 8.0)


func _follow(intent: PlayerIntent, player: Player) -> void:
	if leader == null or not is_instance_valid(leader) or leader == player:
		return
	var to_leader := leader.global_position - player.global_position
	to_leader.y = 0.0
	if to_leader.length() > FOLLOW_DISTANCE:
		intent.move_dir = to_leader.normalized()


func _press(intent: PlayerIntent, player: Player, id: StringName, every: float) -> void:
	if float(_wait.get(id, 0.0)) > 0.0 or not player.can_use(id):
		return
	intent.pressed.append(id)
	_wait[id] = every * _rng.randf_range(0.8, 1.25)


## A world wall (layer 1) between the hero's muzzle and the target's chest.
func _wall_between(player: Player, e: EnemyBase) -> bool:
	if not player.is_inside_tree():
		return false
	var q := PhysicsRayQueryParameters3D.create(player.muzzle_position(), e.global_position + Vector3(0, 1.0, 0), 1)
	q.exclude = [player.get_rid()]
	return not player.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


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


## Untyped on purpose: a typed EnemyBase parameter errors on a freed target
## before is_instance_valid could say so.
static func _alive(e: Variant) -> bool:
	if e == null or not is_instance_valid(e):
		return false
	var enemy := e as EnemyBase
	return enemy != null and enemy.ai_state != EnemyBase.AIState.DEAD
