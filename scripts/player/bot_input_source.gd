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

## M13b, the co-op dungeon: bots walk room by room (DungeonZone.bot_waypoint)
## and take on duties - a downed ally to revive (hold [E] beside it), a
## station of a co-op puzzle their leader stands at (a plate, a lever or
## coil - pulled the moment another one is, a place in the lightning chain).
## Helpers share the free stations in a fixed order (hero refs), so every
## bot's machine hands out the same places without talking.
const STATION_ARRIVE := 0.45
const DUTY_EVERY := 0.3
const WAYPOINT_EVERY := 0.25
const STUCK_AFTER := 1.0
## No revive while an enemy stands this close to the fallen ally.
const REVIVE_SAFE := 5.0
const REVIVE_SEEK := 40.0
var duty: Dictionary = {}
var _duty_left: float = 0.0
var _waypoint := Vector3.INF
var _waypoint_to := Vector3.INF
var _waypoint_left: float = 0.0
var _stuck_for: float = 0.0
var _last_pos := Vector3.INF
var _side_step := Vector3.ZERO
var _side_left: float = 0.0
var _pull_left: float = 0.0


func _init(seed_value: int = 0) -> void:
	_rng.seed = seed_value


## M13b: a bot hero brought up to `level` (the XP from where it stands) with a
## full set of rolled gear at that item level - dev companions in the co-op
## dungeon (`run_godot coop`), the party check. Never on a player's hero.
static func outfit(hero: Player, level: int, rarity_bias: int = 1) -> void:
	var xp := 0
	for lvl in range(hero.progression.level, level):
		xp += Progression.xp_to_next(lvl)
	if xp > 0:
		hero.progression.add_xp(xp)
	for slot in ItemData.SLOT_COUNT:
		var item := ItemGenerator.generate(rarity_bias, hero.class_data.id)
		for tries in 200:  # the generator rolls the slot: keep rolling until it fits
			if int(item.slot) == slot:
				break
			item = ItemGenerator.generate(rarity_bias, hero.class_data.id)
		ItemGenerator.apply_item_level(item, level)
		if hero.equipment.add_item(item):  # equip() takes from the bag
			hero.equipment.equip(item)
	hero.health.heal_full()


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
	_duty_left -= dt
	if _duty_left <= 0.0:
		_duty_left = DUTY_EVERY
		duty = _find_duty(player)
	if leader != null and is_instance_valid(leader) and leader != player \
			and leader.global_position.distance_to(player.global_position) > LEADER_LEASH:
		target = null  # too far from the leader: catch up first
	if player.class_data.role == "Healer":
		_heal_party(intent, player)
	_pull_left -= dt
	var fighting := target != null and target.global_position.distance_to(player.global_position) < 14.0
	if not duty.is_empty() and (not fighting or String(duty["kind"]) == "revive") and _do_duty(intent, player):
		return
	if target == null:
		_follow(intent, player)
		return
	var to_target := target.global_position - player.global_position
	to_target.y = 0.0
	var dist := to_target.length()
	var dir := to_target / dist if dist > 0.01 else player.facing()
	intent.aim_dir = (target.global_position + Vector3(0, 1.0, 0) - player.muzzle_position()).normalized()
	if player.class_data.preferred_range > MELEE_REACH:
		_ranged(intent, player, _steer(player, target.global_position, dir), dist, player.class_data.preferred_range)
		if player.class_data.role == "Healer":
			_druid_fight(intent, player, dist)
		return
	if dist > STAND_OFF:
		intent.move_dir = _steer(player, target.global_position, dir)
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
		intent.move_dir = _steer(player, leader.global_position, to_leader.normalized())


# ---------------------------------------------------------------------------
# M13b: ways and duties
# ---------------------------------------------------------------------------

## Which way to walk toward `to`: room by room in a dungeon (`fallback` - the
## straight line - elsewhere), with a sidestep when stuck against something.
func _steer(player: Player, to: Vector3, fallback: Vector3) -> Vector3:
	var dt := player.get_physics_process_delta_time()
	if _side_left > 0.0:
		_side_left -= dt
		return _side_step
	var zone := ZoneBase.zone_of(player) as DungeonZone
	var dir := fallback
	if zone != null and zone.layout != null:
		_waypoint_left -= dt
		if _waypoint_left <= 0.0 or _waypoint_to.distance_to(to) > 1.0:
			_waypoint_left = WAYPOINT_EVERY
			_waypoint_to = to
			_waypoint = zone.bot_waypoint(player.global_position, to)
		var d := _waypoint - player.global_position
		d.y = 0.0
		if d.length() > 0.05:
			dir = d.normalized()
	# stuck (a prop, a corner): a short step aside
	if _last_pos != Vector3.INF and player.global_position.distance_to(_last_pos) < 0.02:
		_stuck_for += dt
		if _stuck_for >= STUCK_AFTER:
			_stuck_for = 0.0
			_side_step = Vector3(-dir.z, 0.0, dir.x) * (1.0 if _rng.randf() < 0.5 else -1.0)
			_side_left = 0.6
	else:
		_stuck_for = 0.0
	_last_pos = player.global_position
	return dir


## The duty for now ({} = none): a downed ally first, then a free station of
## the co-op puzzle the leader is at.
func _find_duty(player: Player) -> Dictionary:
	var zone := ZoneBase.zone_of(player) as DungeonZone
	if zone == null or player.health.is_dead:
		return {}
	if zone.revive_system != null:
		var best: Player = null
		var best_d := REVIVE_SEEK
		for h in zone.party():
			if h == player or not h.health.is_dead:
				continue
			var d := h.global_position.distance_to(player.global_position)
			if d < best_d and _enemies_within(h.global_position, REVIVE_SAFE) == 0:
				best_d = d
				best = h
		if best != null:
			return {"kind": "revive", "hero": best}
	if leader == null or not is_instance_valid(leader) or leader == player or leader.health.is_dead:
		return {}
	var pick: Node3D = null
	var stations: Array[Dictionary] = []
	var pick_d := INF
	for id: String in zone.puzzles:
		var p := zone.puzzles[id] as Node3D
		if p == null or not p.has_method(&"bot_stations"):
			continue
		var s: Array[Dictionary] = p.call(&"bot_stations", leader)
		if s.is_empty():
			continue
		var d := p.global_position.distance_to(leader.global_position)
		if d < pick_d:
			pick_d = d
			pick = p
			stations = s
	if pick == null:
		return {}
	# the leader's own place (the one it stands at) is not handed out
	var free: Array[Dictionary] = []
	var leader_at := -1
	var leader_d := 2.5
	for i in stations.size():
		var d := (stations[i]["pos"] as Vector3).distance_to(leader.global_position)
		if d < leader_d:
			leader_d = d
			leader_at = i
	for i in stations.size():
		if i != leader_at:
			free.append(stations[i])
	var helpers: Array[Player] = []
	for h in zone.party():
		if h != leader and not h.health.is_dead:
			helpers.append(h)
	helpers.sort_custom(func(a: Player, b: Player) -> bool: return zone.hero_ref(a) < zone.hero_ref(b))
	var rank := helpers.find(player)
	if rank < 0 or rank >= free.size():
		return {}
	return {"kind": "station", "puzzle": pick, "station": free[rank]}


## Walks to the duty and does it; false when there is nothing to do after all.
func _do_duty(intent: PlayerIntent, player: Player) -> bool:
	if String(duty["kind"]) == "revive":
		var h := duty.get("hero") as Player
		if h == null or not is_instance_valid(h) or not h.health.is_dead:
			duty = {}
			return false
		var to := h.global_position - player.global_position
		to.y = 0.0
		if to.length() > 1.4:
			intent.move_dir = _steer(player, h.global_position, to.normalized())
		else:
			intent.interact_held = true
		return true
	var p := duty.get("puzzle") as Node3D
	if p == null or not is_instance_valid(p):
		duty = {}
		return false
	var st: Dictionary = duty["station"]
	var at := st["pos"] as Vector3
	var off := at - player.global_position
	off.y = 0.0
	if off.length() > STATION_ARRIVE:
		intent.move_dir = _steer(player, at, off.normalized())
		return true
	var pull := int(st.get("pull", -1))
	if pull >= 0 and _pull_left <= 0.0 and p is SyncLevers:
		var sync := p as SyncLevers
		if sync.pulled_count() > 0 and not sync.pulled_now(pull):  # someone struck one: now
			_pull_left = 0.5
			sync.request("pull", pull, player)
	return true


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
	return enemy != null and enemy.ai_state != EnemyBase.AIState.DEAD and enemy.targetable  # M12
