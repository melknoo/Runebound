class_name RunebreakerHero
extends Player
## M10: the Runebreaker, the tank. Melee (Rune Cleave) builds Resonance; heavy
## rune abilities spend it (Earthbreaker, Runic Guard, Resonance Burst). It
## holds the enemies' attention: its damage threatens double (ClassData
## threat_mult), Rune Challenge / Rune Chain / Warden's Leap taunt, Rune Wall
## blocks and parries, Warding Rune shields the party (CLASS_DESIGN "Three
## roles"). The elemental spells went to the Elementalist.

# Ability tuning: derived caches of `abilities` (the tests read them by name).
var cleave: AbilityData
var earthbreaker: AbilityData
var runic_guard: AbilityData        # M07 talent ability
var resonance_burst: AbilityData    # M07 talent ability
var rune_wall: AbilityData          # M10: hold to block, parry in the first moment
var rune_challenge: AbilityData     # M10: taunt shout
var rune_chain: AbilityData         # M10: pull + taunt one enemy
var warden_leap: AbilityData        # M10: leap, the landing taunts
var warding_rune: AbilityData       # M10: ground ward, allies take less damage

var _melee_flip: bool = false
var _melee_did_hit_window: bool = false

## Rune Wall: frontal arc it covers, the parry window, how much a block keeps
## off, how slow the hero walks behind it, the Resonance a blocked hit gives.
const BLOCK_ARC := deg_to_rad(70.0)
const PARRY_WINDOW := 0.3
const BLOCK_REDUCTION := 0.75
const BLOCK_MOVE := 0.4
const PARRY_RESONANCE := 10.0
const RIPOSTE_RADIUS := 2.5
const WARDENS_OATH_BARRIER := 20.0
## Warden's Leap: flight time and apex height.
const LEAP_TIME := 0.5
const LEAP_HEIGHT := 2.2
## Rune Chain lands its catch this far in front of the hero.
const CHAIN_DROP := 2.0
## Aegis of Runes shields allies within this radius (half the guard).
const AEGIS_RADIUS := 6.0
## Unyielding: below this share of health, this much less damage.
const UNYIELDING_BELOW := 0.3
const UNYIELDING_REDUCTION := 0.3

var _block_time: float = 0.0
var _leap_from: Vector3 = Vector3.ZERO
var _leap_to: Vector3 = Vector3.ZERO
var _ward: MeshInstance3D = null


var lodestone_rune: AbilityData   # M12: the tome's rune that drags a pack together
var breakwater: AbilityData       # M13 the Cistern's tome: a shield charge that shoves aside
var forge_brand: AbilityData      # M13 the Warrens' tome: a brand - the target takes more, deals less

## Breakwater: the charge's time over its full reach, the shove to the side,
## the share of damage the raised shield keeps off on the way.
const BREAKWATER_TIME := 0.45
const BREAKWATER_SHOVE := 2.6
const BREAKWATER_REDUCTION := 0.5
var _charge_from: Vector3 = Vector3.ZERO
var _charge_dir: Vector3 = Vector3.FORWARD
var _charge_len: float = 0.0
var _charge_struck: Array[int] = []


func _load_abilities() -> void:
	super()
	lodestone_rune = ability(&"lodestone_rune")
	breakwater = ability(&"breakwater")
	forge_brand = ability(&"forge_brand")
	cleave = ability(&"rune_cleave")
	earthbreaker = ability(&"earthbreaker")
	runic_guard = ability(&"runic_guard")
	resonance_burst = ability(&"resonance_burst")
	rune_wall = ability(&"rune_wall")
	rune_challenge = ability(&"rune_challenge")
	rune_chain = ability(&"rune_chain")
	warden_leap = ability(&"warden_leap")
	warding_rune = ability(&"warding_rune")


func _register_actions() -> void:
	super()
	_actions.merge({
		&"rune_cleave": try_melee,
		&"earthbreaker": try_earthbreaker,
		&"runic_guard": try_runic_guard,
		&"resonance_burst": try_resonance_burst,
		&"rune_wall": try_rune_wall,
		&"rune_challenge": try_rune_challenge,
		&"rune_chain": try_rune_chain,
		&"warden_leap": try_warden_leap,
		&"warding_rune": try_warding_rune,
		&"lodestone_rune": try_lodestone_rune,
		&"breakwater": try_breakwater,
		&"forge_brand": try_forge_brand,
	})


func _anim_profile() -> Dictionary:
	var profile := super()
	(profile["actions"] as Dictionary).merge({&"cleave_l": &"cleave_l", &"cleave_r": &"cleave_r",
		&"earthbreaker": &"earthbreaker_rise", &"earthbreaker_impact": &"earthbreaker_impact",
		&"resonance_burst": &"resonance_burst", &"rune_challenge": &"challenge",
		&"warden_leap": &"earthbreaker_rise", &"warden_leap_land": &"earthbreaker_impact", &"rune_chain": &"ember",
		&"lodestone_rune": &"ember", &"breakwater": &"block", &"forge_brand": &"ember"})
	# instant casts keep the legs running: upper-body layer only
	(profile["upper"] as Dictionary).merge({&"runic_guard": &"runic_guard", &"rune_wall": &"block",
		&"warding_rune": &"fracture_rune"})
	# M10: the block is held for as long as the key stays down
	profile["hold"] = {&"rune_wall": &"rune_wall_end"}
	return profile


func _process_class_state(delta: float) -> void:
	match state:
		State.MELEE:
			_process_melee(delta)
		State.SLAM:
			_process_slam(delta)
		State.BLOCK:
			_process_block(delta)
		State.LEAP:
			_process_leap(delta)
		State.CHARGE:
			_process_breakwater(delta)
		_:
			state = State.MOVE


## Earthbreaker is committed once the hero leaves the ground; so is a leap.
func _dodge_allowed() -> bool:
	if state == State.LEAP or state == State.CHARGE:
		return false
	return not (state == State.SLAM and _state_timer < earthbreaker.startup + earthbreaker.active)


## A dodge out of Rune Wall lowers the ward (its cooldown starts).
func _on_dodge_cancel() -> void:
	if state == State.BLOCK:
		_lower_ward()


func resource_cost(id: StringName) -> float:
	if id == &"earthbreaker":
		return earthbreaker_cost()
	return super(id)


func earthbreaker_cost() -> float:
	return maxf(earthbreaker.resonance_cost - stat(&"eb_cost_reduce"), 10.0)


## Earthbreaker's shockwave radius (M10 Aftershock).
func earthbreaker_radius() -> float:
	return earthbreaker.aoe_radius + stat(&"eb_radius")


## Runic Guard's barrier (+1 per level, M10 Warding Runes).
func guard_amount() -> float:
	return runic_guard.damage + float(progression.level) + stat(&"guard_amount")


# ---------------------------------------------------------------------------
# Rune Cleave (melee)
# ---------------------------------------------------------------------------

func try_melee() -> bool:
	if state != State.MOVE:
		return false
	state = State.MELEE
	_state_timer = 0.0
	_melee_did_hit_window = false
	_melee_flip = not _melee_flip
	_face_melee_target()
	_animate_cleave()
	hero_fx(&"sfx", ["swing", global_position, -2.0])
	action_started.emit(&"cleave_l" if _melee_flip else &"cleave_r")
	return true


## Melee snaps to the soft target when one is in reach — swinging at the
## marker the player can see beats swinging at the camera ray.
func _face_melee_target() -> void:
	var t: EnemyBase = targeting.current if targeting != null else null
	if t != null and is_instance_valid(t) \
			and t.global_position.distance_to(global_position) <= 4.0:
		var dir := t.global_position - global_position
		dir.y = 0.0
		if dir.length() > 0.05:
			dir = dir.normalized()
			_visual.rotation.y = atan2(-dir.x, -dir.z)
			return
	_face_aim_instant()


func _animate_cleave() -> void:
	var side := 1.0 if _melee_flip else -1.0
	_weapon_pivot.rotation_degrees = Vector3(-10, side * 70.0, 0)
	var tw := _weapon_pivot.create_tween()
	tw.tween_property(_weapon_pivot, "rotation_degrees:y", -side * 80.0, cleave.startup + cleave.active) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	tw.tween_property(_weapon_pivot, "rotation_degrees", Vector3(-25, 15, 0), cleave.recovery) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _process_melee(delta: float) -> void:
	_state_timer += delta
	# Slight forward drift keeps swings aggressive without lunging.
	var fwd := facing()
	velocity.x = fwd.x * 1.6
	velocity.z = fwd.z * 1.6
	if not _melee_did_hit_window and _state_timer >= cleave.startup:
		_melee_did_hit_window = true
		_do_cleave_hit()
	if _state_timer >= cleave.startup + cleave.active + cleave.recovery:
		state = State.MOVE
		_consume_buffer()


func _do_cleave_hit() -> void:
	var fwd := facing()
	var center := global_position + Vector3(0, 1.0, 0) + fwd * 1.2
	var radius := 1.5 * (1.0 + stat(&"cleave_radius_pct") / 100.0)
	var hits := _query_hurtboxes(center, radius)
	var scene := get_tree().current_scene
	# Slash arc regardless of contact — the swing itself must read.
	hero_fx(&"slash", [global_position + Vector3(0, 1.1, 0) + fwd * 0.9, fwd, _melee_flip])
	var any_hit := false
	for enemy: Node in hits:
		var hit := roll_ability_hit(cleave)
		if enemy.has_method(&"take_hit") and enemy.call(&"take_hit", hit):
			any_hit = true
			gain_resonance(cleave.resonance_gain_per_hit)
			VFX.melee_impact(scene, (enemy as Node3D).global_position + Vector3(0, 1.0, 0), fwd)
	if any_hit:
		Sfx.play("impact_flesh", center, 0.0, 0.12)
		var stop_targets: Array = [self]
		stop_targets.append_array(hits)
		GameFeel.hitstop(stop_targets, 0.045)
		feel_impulse(fwd, 0.08)
	cooldowns_changed.emit()


# ---------------------------------------------------------------------------
# Earthbreaker
# ---------------------------------------------------------------------------

func try_earthbreaker() -> bool:
	if not knows(&"earthbreaker") or state != State.MOVE or _on_cooldown(&"earthbreaker"):
		return false
	if resonance < earthbreaker_cost():
		ui_denied()
		return false
	state = State.SLAM
	_state_timer = 0.0
	_set_cooldown(&"earthbreaker", earthbreaker.cooldown)
	spend_resonance(earthbreaker_cost())
	# Anticipation: rise + weapon raised overhead.
	var tw := _weapon_pivot.create_tween()
	tw.tween_property(_weapon_pivot, "rotation_degrees", Vector3(-120, 0, 0), earthbreaker.startup) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	velocity.y = 7.0
	hero_fx(&"sfx", ["earthbreaker_windup", global_position, -3.0])
	cooldowns_changed.emit()
	action_started.emit(&"earthbreaker")
	return true


func _process_slam(delta: float) -> void:
	_state_timer += delta
	velocity.x = move_toward(velocity.x, 0, DECEL * delta)
	velocity.z = move_toward(velocity.z, 0, DECEL * delta)
	if _state_timer >= earthbreaker.startup and _state_timer - delta < earthbreaker.startup:
		velocity.y = -22.0  # slam down hard
		var tw := _weapon_pivot.create_tween()
		tw.tween_property(_weapon_pivot, "rotation_degrees", Vector3(30, 0, 0), 0.08)
		tw.tween_property(_weapon_pivot, "rotation_degrees", Vector3(-25, 15, 0), 0.4) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if _state_timer >= earthbreaker.startup + earthbreaker.active:
		if is_on_floor() or _state_timer > earthbreaker.startup + 0.5:
			_do_slam_hit()
			state = State.MOVE
			_consume_buffer()


func _do_slam_hit() -> void:
	action_started.emit(&"earthbreaker_impact")  # presentation: landing clip
	var scene := get_tree().current_scene
	var pos := global_position
	var radius := earthbreaker_radius()
	hero_fx(&"slam", [pos, radius])
	feel_shake(0.55)
	var hits := _query_hurtboxes(pos + Vector3(0, 0.5, 0), radius)
	for enemy: Node in hits:
		var hit := roll_ability_hit(earthbreaker)
		hit.source_position = pos
		hit.threat_mult = earthbreaker.threat_mult
		if has_power(&"molten_core"):
			hit.applies_burn = true  # M07 Molten Core
		if has_power(&"tectonic"):
			hit.taunt = taunt_seconds(3.0)  # M10 Tectonic
		enemy.call(&"take_hit", hit)
	if not hits.is_empty():
		GameFeel.hitstop(hits, 0.07)
	# Glacier Heart: the slam leaves a chilling frost field.
	if has_power(&"glacier_heart"):
		var field := FrostField.new()
		field.position = ZoneBase.ground_under(self, pos, 0.02)
		scene.add_child(field)


# ---------------------------------------------------------------------------
# M07 talent abilities
# ---------------------------------------------------------------------------

func try_runic_guard() -> bool:
	if not knows(&"runic_guard") or state != State.MOVE or _on_cooldown(&"runic_guard"):
		return false
	if resonance < runic_guard.resonance_cost:
		ui_denied()
		return false
	spend_resonance(runic_guard.resonance_cost)
	_set_cooldown(&"runic_guard", runic_guard.cooldown)
	grant_barrier(guard_amount(), runic_guard.active)
	if has_power(&"aegis_of_runes"):  # M10: half the guard for every ally near
		hero_fx(&"ally_barrier", [global_position, guard_amount() * 0.5, runic_guard.active, AEGIS_RADIUS])
	hero_fx(&"sfx", ["runic_guard", global_position, -2.0])
	cooldowns_changed.emit()
	action_started.emit(&"runic_guard")
	return true


func try_resonance_burst() -> bool:
	if not knows(&"resonance_burst") or state != State.MOVE or _on_cooldown(&"resonance_burst"):
		return false
	if resonance < resonance_burst.resonance_cost:
		ui_denied()
		return false
	var spent := resonance
	spend_resonance(spent)
	_set_cooldown(&"resonance_burst", resonance_burst.cooldown)
	var pos := global_position
	hero_fx(&"res_burst", [pos, resonance_burst.aoe_radius])
	feel_shake(0.45)
	var hits := _query_hurtboxes(pos + Vector3(0, 0.8, 0), resonance_burst.aoe_radius)
	for enemy: Node in hits:
		var hit := roll_ability_hit(resonance_burst)
		hit.damage *= spent  # 0.7 per point of Resonance spent
		hit.source_position = pos
		enemy.call(&"take_hit", hit)
	if not hits.is_empty():
		GameFeel.hitstop(hits, 0.08)
	cooldowns_changed.emit()
	action_started.emit(&"resonance_burst")
	return true


# ---------------------------------------------------------------------------
# M10: threat and taunts
# ---------------------------------------------------------------------------

## A taunt's hold with the Provoker talent on top.
func taunt_seconds(base: float) -> float:
	return base + stat(&"taunt_duration")


## M10 Unyielding: badly hurt, the tank takes less. M13 Breakwater: behind
## the raised shield of the charge, half.
func _class_damage_reduction() -> float:
	if state == State.CHARGE:
		return BREAKWATER_REDUCTION
	if has_power(&"unyielding") and health != null and health.max_health > 0.0 \
			and health.current_health / health.max_health < UNYIELDING_BELOW:
		return UNYIELDING_REDUCTION
	return 0.0


## Living enemies within `radius` of `center`, flat (the registry, not the
## hurtbox query: a shout reaches every one of them).
func _enemies_near(center: Vector3, radius: float) -> Array[EnemyBase]:
	var out: Array[EnemyBase] = []
	for e in EnemyBase.all_enemies:
		if not is_instance_valid(e) or e.ai_state == EnemyBase.AIState.DEAD:
			continue
		var d := e.global_position - center
		d.y = 0.0
		if d.length() <= radius:
			out.append(e)
	return out


func try_rune_challenge() -> bool:
	if not knows(&"rune_challenge") or state != State.MOVE or _on_cooldown(&"rune_challenge"):
		return false
	_set_cooldown(&"rune_challenge", rune_challenge.cooldown)
	var hold := taunt_seconds(rune_challenge.active)
	var taunted := 0
	for e in _enemies_near(global_position, rune_challenge.aoe_radius):
		var hit := roll_ability_hit(rune_challenge)  # no damage: the shout only taunts
		hit.damage = 0.0
		hit.taunt = hold
		if e.take_hit(hit):
			taunted += 1
	gain_resonance(rune_challenge.resonance_gain_per_hit * taunted)
	hero_fx(&"challenge", [global_position, rune_challenge.aoe_radius])
	feel_shake(0.2)
	cooldowns_changed.emit()
	action_started.emit(&"rune_challenge")
	return true


# ---------------------------------------------------------------------------
# M10: Rune Wall (hold to block; the first moment parries)
# ---------------------------------------------------------------------------

func try_rune_wall() -> bool:
	if not knows(&"rune_wall") or state != State.MOVE or _on_cooldown(&"rune_wall"):
		return false
	state = State.BLOCK
	_state_timer = 0.0
	_block_time = 0.0
	_hold_aim()
	hero_fx(&"sfx", ["equip", global_position, -8.0])
	action_started.emit(&"rune_wall")
	return true


func is_blocking() -> bool:
	return state == State.BLOCK


func _process_block(delta: float) -> void:
	_block_time += delta
	if input_locked or not intent.held.has(&"rune_wall"):
		_lower_ward()
		state = State.MOVE
		_consume_buffer()
		return
	# a slow walk behind the ward, always facing the aim
	var dir := _move_input_dir()
	var target_vel := dir * MAX_SPEED * BLOCK_MOVE
	velocity.x = move_toward(velocity.x, target_vel.x, ACCEL * delta)
	velocity.z = move_toward(velocity.z, target_vel.z, ACCEL * delta)
	_face_aim_instant()


func _lower_ward() -> void:
	_set_cooldown(&"rune_wall", rune_wall.cooldown)
	cooldowns_changed.emit()
	action_started.emit(&"rune_wall_end")


## A hit from the front while Rune Wall is up: a parry in the first
## PARRY_WINDOW (no damage, a rune counter on the striker), a block after
## (BLOCK_REDUCTION + Shield Wall off). Both give Resonance. Hits from above
## or behind get through.
func _guard_hit(hit: HitInfo) -> bool:
	if state != State.BLOCK:
		return false
	var from := hit.source_position - global_position
	from.y = 0.0
	if from.length() < 0.3 or facing().angle_to(from.normalized()) > BLOCK_ARC:
		return false
	var gain := rune_wall.resonance_gain_per_hit + stat(&"block_res")
	var at := global_position + Vector3(0, 1.2, 0) + facing() * 0.7
	if _block_time <= PARRY_WINDOW:
		gain_resonance(gain + PARRY_RESONANCE)
		_parry(hit, at)
		return true
	hit.damage *= 1.0 - clampf(BLOCK_REDUCTION + stat(&"block_pct") / 100.0, 0.0, 0.95)
	hit.knockback *= 0.3
	gain_resonance(gain)
	hero_fx(&"block", [at])
	return false


func _parry(hit: HitInfo, at: Vector3) -> void:
	hero_fx(&"parry", [at])
	feel_shake(0.15)
	var foes: Array[EnemyBase] = []
	if has_power(&"riposte"):  # M10 Riposte: the counter hits everything close
		foes = _enemies_near(global_position, RIPOSTE_RADIUS)
		gain_resonance(15.0)
	else:
		var striker := instance_from_id(hit.source_id) as EnemyBase if hit.source_id != 0 else null
		if striker != null and is_instance_valid(striker) and striker.ai_state != EnemyBase.AIState.DEAD:
			foes.append(striker)
	for foe in foes:
		var counter := roll_ability_hit(rune_wall)
		counter.weight = HitInfo.Weight.HEAVY  # the counter staggers
		counter.threat_mult = rune_wall.threat_mult
		counter.source_position = global_position
		foe.take_hit(counter)
	if has_power(&"wardens_oath"):  # M10 legendary: a parry leaves a barrier
		grant_barrier(WARDENS_OATH_BARRIER, 3.0)


# ---------------------------------------------------------------------------
# M10: Rune Chain (pull one enemy in and taunt it)
# ---------------------------------------------------------------------------

func try_rune_chain() -> bool:
	if not knows(&"rune_chain") or state != State.MOVE or _on_cooldown(&"rune_chain"):
		return false
	var catch := _chain_target(rune_chain.aoe_radius)
	if catch == null:
		ui_denied()
		return false
	_set_cooldown(&"rune_chain", rune_chain.cooldown)
	var to_catch := catch.global_position - global_position
	to_catch.y = 0.0
	var dir := to_catch.normalized() if to_catch.length() > 0.05 else facing()
	_visual.rotation.y = atan2(-dir.x, -dir.z)
	_aim_hold_until = Time.get_ticks_msec() + AIM_HOLD_MSEC
	hero_fx(&"rune_chain", [muzzle_position(), catch.global_position + Vector3(0, 1.0, 0)])
	var hit := roll_ability_hit(rune_chain)
	hit.taunt = taunt_seconds(rune_chain.active)
	hit.threat_mult = rune_chain.threat_mult
	if to_catch.length() > CHAIN_DROP + 0.5:
		hit.pull_to = global_position + dir * CHAIN_DROP
		hero_fx(&"sfx", ["chain_pull", catch.global_position, -1.0])
	if catch.take_hit(hit):
		gain_resonance(rune_chain.resonance_gain_per_hit)
	cooldowns_changed.emit()
	action_started.emit(&"rune_chain")
	return true


## The held Tab target if it is in range, else the best candidate in view,
## else (bots, no targeting) the nearest enemy along the aim.
func _chain_target(reach: float) -> EnemyBase:
	if targeting != null:
		var held := targeting.current
		if held != null and is_instance_valid(held) and held.ai_state != EnemyBase.AIState.DEAD \
				and held.global_position.distance_to(global_position) <= reach:
			return held
		var best := targeting.best_candidate()
		if best != null and best.global_position.distance_to(global_position) <= reach:
			return best
		return null
	var aim := aim_direction()
	aim.y = 0.0
	var pick: EnemyBase = null
	var pick_d := reach
	for e in _enemies_near(global_position, reach):
		var to_e := e.global_position - global_position
		to_e.y = 0.0
		if to_e.length() < pick_d and (aim.length() < 0.01 or aim.normalized().dot(to_e.normalized()) > 0.5):
			pick_d = to_e.length()
			pick = e
	return pick


# ---------------------------------------------------------------------------
# M10: Warden's Leap (a leap to the aim point; the landing taunts)
# ---------------------------------------------------------------------------

func try_warden_leap() -> bool:
	if not knows(&"warden_leap") or state != State.MOVE or _on_cooldown(&"warden_leap"):
		return false
	var reach := warden_leap.projectile_speed  # data: the leap's range in metres
	var exclude: Array[RID] = [get_rid()]
	var aim_point := camera_rig.get_aim_point(exclude) if camera_rig != null else global_position + aim_direction() * reach
	var offset := Vector3(aim_point.x - global_position.x, 0.0, aim_point.z - global_position.z)
	if offset.length() > reach:
		offset = offset.normalized() * reach
	_leap_from = global_position
	_leap_to = ZoneBase.ground_under(self, global_position + offset, 0.0)
	_set_cooldown(&"warden_leap", warden_leap.cooldown)
	state = State.LEAP
	_state_timer = 0.0
	collision_mask = 0b1000001  # over the enemies, not into them (world + foliage)
	if offset.length() > 0.2:
		_visual.rotation.y = atan2(-offset.x, -offset.z)
	hero_fx(&"sfx", ["earthbreaker_windup", global_position, -4.0])
	cooldowns_changed.emit()
	action_started.emit(&"warden_leap")
	return true


func _process_leap(delta: float) -> void:
	_state_timer += delta
	var k := clampf(_state_timer / LEAP_TIME, 0.0, 1.0)
	var want := _leap_from.lerp(_leap_to, k) + Vector3.UP * LEAP_HEIGHT * 4.0 * k * (1.0 - k)
	velocity = (want - global_position) / maxf(delta, 0.001)
	velocity.y += GRAVITY * delta  # the chassis adds gravity after this
	if k >= 1.0:
		velocity = Vector3.ZERO
		collision_mask = 0b1000101
		_land_leap()
		state = State.MOVE
		_consume_buffer()


func _land_leap() -> void:
	action_started.emit(&"warden_leap_land")
	var pos := global_position
	var radius := warden_leap.aoe_radius
	hero_fx(&"slam", [pos, radius])
	feel_shake(0.4)
	var hits := _query_hurtboxes(pos + Vector3(0, 0.5, 0), radius)
	for enemy: Node in hits:
		var hit := roll_ability_hit(warden_leap)
		hit.source_position = pos
		hit.taunt = taunt_seconds(warden_leap.active)
		hit.threat_mult = warden_leap.threat_mult
		if has_power(&"quake_leap"):
			hit.weight = HitInfo.Weight.HEAVY  # M10 Quake Leap
		if enemy.call(&"take_hit", hit):
			gain_resonance(warden_leap.resonance_gain_per_hit)
	if not hits.is_empty():
		GameFeel.hitstop(hits, 0.05)


# ---------------------------------------------------------------------------
# M12 tome: Lodestone Rune (a rune at the aim drags a pack together, taunts it)
# ---------------------------------------------------------------------------

func try_lodestone_rune() -> bool:
	if not knows(&"lodestone_rune") or state != State.MOVE or _on_cooldown(&"lodestone_rune"):
		return false
	var cost := resource_cost(&"lodestone_rune")
	if resonance < cost:
		ui_denied()
		return false
	spend_resonance(cost)
	_set_cooldown(&"lodestone_rune", lodestone_rune.cooldown)
	var at := _rune_aim(lodestone_rune.projectile_speed)
	var rune := LodestoneRune.new()
	rune.setup(lodestone_rune, self)
	rune.position = at  # before add_child: the ring is drawn from there
	get_tree().current_scene.add_child(rune)
	hero_fx(&"lodestone_rune", [at, rune.radius, rune.arm_time])  # puppets lay a visual copy
	var to := at - global_position
	to.y = 0.0
	if to.length() > 0.2:
		_visual.rotation.y = atan2(-to.x, -to.z)
		_aim_hold_until = Time.get_ticks_msec() + AIM_HOLD_MSEC
	cooldowns_changed.emit()
	action_started.emit(&"lodestone_rune")
	return true


## The ground under the aim, at most `reach` away; without a camera (a bot)
## the middle of the enemies along the aim, else `reach` ahead.
func _rune_aim(reach: float) -> Vector3:
	var offset := Vector3.ZERO
	if camera_rig != null:
		var exclude: Array[RID] = [get_rid()]
		var aim_point := camera_rig.get_aim_point(exclude)
		offset = Vector3(aim_point.x - global_position.x, 0.0, aim_point.z - global_position.z)
	else:
		var near := _enemies_near(global_position, reach)
		if near.is_empty():
			offset = aim_direction() * reach
		else:
			for e in near:
				offset += e.global_position - global_position
			offset /= float(near.size())
		offset.y = 0.0
	if offset.length() > reach:
		offset = offset.normalized() * reach
	return ZoneBase.ground_under(self, global_position + offset, 0.02)


# ---------------------------------------------------------------------------
# M13 tome (the Cistern): Breakwater (a shield charge that shoves aside)
# ---------------------------------------------------------------------------

func try_breakwater() -> bool:
	if not knows(&"breakwater") or state != State.MOVE or _on_cooldown(&"breakwater"):
		return false
	var cost := resource_cost(&"breakwater")
	if resonance < cost:
		ui_denied()
		return false
	spend_resonance(cost)
	_set_cooldown(&"breakwater", breakwater.cooldown)
	var dir := aim_direction()
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else facing()
	_charge_dir = dir
	_charge_from = global_position
	_charge_len = breakwater.projectile_speed  # data: the charge's reach in metres
	_charge_struck.clear()
	state = State.CHARGE
	_state_timer = 0.0
	collision_mask = 0b1000001  # through the enemies (they are shoved), not through walls
	_visual.rotation.y = atan2(-dir.x, -dir.z)
	hero_fx(&"breakwater", [global_position, dir, _charge_len])
	feel_impulse(dir, 0.1)
	cooldowns_changed.emit()
	action_started.emit(&"breakwater")
	return true


func _process_breakwater(delta: float) -> void:
	_state_timer += delta
	var speed := _charge_len / BREAKWATER_TIME
	velocity.x = _charge_dir.x * speed
	velocity.z = _charge_dir.z * speed
	_breakwater_contact()
	var run := (global_position - _charge_from).dot(_charge_dir)
	if run >= _charge_len or _state_timer >= BREAKWATER_TIME + 0.1 or (is_on_wall() and _state_timer > 0.05):
		velocity.x = 0.0
		velocity.z = 0.0
		collision_mask = 0b1000101
		state = State.MOVE
		_consume_buffer()


## Every enemy the shield meets: struck, taunted and shoved to the side it
## stands on (each once a charge).
func _breakwater_contact() -> void:
	var half := breakwater.aoe_radius
	for e in _enemies_near(global_position, half + 1.2):
		if _charge_struck.has(e.get_instance_id()) or not e.targetable:
			continue
		var rel := e.global_position - global_position
		rel.y = 0.0
		var ahead := rel.dot(_charge_dir)
		var side_off := rel - _charge_dir * ahead
		if ahead < -0.8 or ahead > 1.6 or side_off.length() > half + 0.4:
			continue
		_charge_struck.append(e.get_instance_id())
		var side := side_off.normalized() if side_off.length() > 0.05 else Vector3(_charge_dir.z, 0.0, -_charge_dir.x)
		var hit := roll_ability_hit(breakwater)
		hit.source_position = global_position
		hit.taunt = taunt_seconds(breakwater.active)
		hit.threat_mult = breakwater.threat_mult
		hit.pull_to = e.global_position + side * BREAKWATER_SHOVE + _charge_dir * 0.8
		if e.take_hit(hit):
			VFX.melee_impact(get_tree().current_scene, e.global_position + Vector3(0, 1.0, 0), side)


# ---------------------------------------------------------------------------
# M13 tome (the Warrens): Forge Brand (the target takes more, deals less)
# ---------------------------------------------------------------------------

func try_forge_brand() -> bool:
	if not knows(&"forge_brand") or state != State.MOVE or _on_cooldown(&"forge_brand"):
		return false
	var mark := _chain_target(forge_brand.aoe_radius)
	if mark == null:
		ui_denied()
		return false
	var cost := resource_cost(&"forge_brand")
	if resonance < cost:
		ui_denied()
		return false
	spend_resonance(cost)
	_set_cooldown(&"forge_brand", forge_brand.cooldown)
	var to := mark.global_position - global_position
	to.y = 0.0
	if to.length() > 0.1:
		_visual.rotation.y = atan2(-to.x, -to.z)
		_aim_hold_until = Time.get_ticks_msec() + AIM_HOLD_MSEC
	var hit := roll_ability_hit(forge_brand)  # its ability id brands (StatusEffectComponent)
	hit.source_position = global_position
	hit.threat_mult = forge_brand.threat_mult
	mark.take_hit(hit)
	hero_fx(&"forge_brand", [muzzle_position(), mark.global_position + Vector3(0, 1.2, 0)])
	cooldowns_changed.emit()
	action_started.emit(&"forge_brand")
	return true


# ---------------------------------------------------------------------------
# M10: Warding Rune (allies inside take less damage)
# ---------------------------------------------------------------------------

func warding_reduction() -> float:
	return warding_rune.damage / 100.0 + stat(&"aegis_pct") / 100.0


func try_warding_rune() -> bool:
	if not knows(&"warding_rune") or state != State.MOVE or _on_cooldown(&"warding_rune"):
		return false
	if resonance < warding_rune.resonance_cost:
		ui_denied()
		return false
	spend_resonance(warding_rune.resonance_cost)
	_set_cooldown(&"warding_rune", warding_rune.cooldown)
	var at := ZoneBase.ground_under(self, global_position, 0.02)
	hero_fx(&"warding_rune", [at, warding_rune.aoe_radius, warding_rune.active, warding_reduction()])
	cooldowns_changed.emit()
	action_started.emit(&"warding_rune")
	return true


# ---------------------------------------------------------------------------
# M10: the ward's look while Rune Wall is up (every machine: puppets too)
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	var up := state == State.BLOCK
	if up and _ward == null and Net.has_view() and _visual != null:
		_ward = _build_ward()
	if _ward != null:
		_ward.visible = up


func _build_ward() -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.name = "RuneWard"
	var dome := SphereMesh.new()
	dome.radius = 0.8
	dome.height = 1.6
	dome.radial_segments = 16
	dome.rings = 8
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(ArtKit.color("color_roles.player_accent.body", Color(0.24, 0.75, 0.7)), 0.28)
	mat.emission_enabled = true
	mat.emission = ArtKit.color("color_roles.player_accent.hot", Color(0.62, 0.95, 0.9))
	mat.emission_energy_multiplier = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	dome.material = mat
	m.mesh = dome
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.scale = Vector3(1.0, 1.0, 0.22)  # a shallow ward in front of the hero
	m.position = Vector3(0, 1.1, -0.75)
	_visual.add_child(m)
	return m
