class_name ElementalistHero
extends Player
## M10: the Elementalist, the ranged damage dealer. Rune Bolt (LMB, held for
## auto-fire) and spell hits build Aether; Frost Nova and Ember Fall spend it.
## The inherited spells (Ember Lance, Storm Step, Chain Spark, Fracture Rune)
## came over from the Runebreaker with their statuses and talents; Flame Wall,
## Ball Lightning, Frost Nova and Ember Fall are its own (CLASS_DESIGN "Three
## roles").

const STORM_STEP_SPEED := 50.0  # ~6m over the 0.12s active window
const FRACTURE_RUNE_MAX_RANGE := 12.0
const OVERLOAD_RADIUS := 2.5
const THUNDERCLAP_RADIUS := 2.0
## Deep Freeze roots what Frost Nova chills this long.
const DEEP_FREEZE_ROOT := 1.0
## M12 Hoarfrost Fan: half its spread (degrees); what it finds Chilled takes
## this much more and freezes in place this long.
const FAN_HALF_ANGLE := 30.0
const FAN_CHILLED_MULT := 1.5
const FAN_ROOT := 1.0

# Ability tuning: derived caches of `abilities` (the tests read them by name).
var rune_bolt: AbilityData
var ember: AbilityData
var storm_step: AbilityData
var chain_spark: AbilityData
var fracture_rune: AbilityData
var frost_nova: AbilityData       # M10: ring of ice, spends Aether
var flame_wall: AbilityData       # M10: burning line at the aim
var ball_lightning: AbilityData   # M10: a slow zapping orb
var ember_fall: AbilityData       # M10: the meteor, spends Aether
var hoarfrost_fan: AbilityData    # M12 tome: a cone of rime, spends Aether
var rime_ward: AbilityData        # M13 the Cistern's tome: a barrier that chills melee strikers

## Rime Ward: the barrier grows this much per level; until when it holds.
const RIME_PER_LEVEL := 3.0
var _rime_until: int = 0

## The spell State.CAST is winding up (Ember Lance, Ember Fall).
var _cast_id: StringName = &""
var _cast_at: Vector3 = Vector3.ZERO

var _dash_dir: Vector3 = Vector3.ZERO
var _dash_start: Vector3 = Vector3.ZERO
var _dash_time: float = 0.12  # active window; shorter for close gap-closes


func _load_abilities() -> void:
	super()
	rune_bolt = ability(&"rune_bolt")
	ember = ability(&"ember_lance")
	storm_step = ability(&"storm_step")
	chain_spark = ability(&"chain_spark")
	fracture_rune = ability(&"fracture_rune")
	frost_nova = ability(&"frost_nova")
	flame_wall = ability(&"flame_wall")
	ball_lightning = ability(&"ball_lightning")
	ember_fall = ability(&"ember_fall")
	hoarfrost_fan = ability(&"hoarfrost_fan")
	rime_ward = ability(&"rime_ward")


func _register_actions() -> void:
	super()
	_actions.merge({
		&"rune_bolt": try_rune_bolt,
		&"ember_lance": try_ember,
		&"storm_step": try_storm_step,
		&"chain_spark": try_chain_spark,
		&"fracture_rune": try_fracture_rune,
		&"frost_nova": try_frost_nova,
		&"flame_wall": try_flame_wall,
		&"ball_lightning": try_ball_lightning,
		&"ember_fall": try_ember_fall,
		&"hoarfrost_fan": try_hoarfrost_fan,
		&"rime_ward": try_rime_ward,
	})


## The Elementalist rig's clips (tools/modelgen: elementalist_clips). Quick
## casts are upper-body gestures, so the legs keep running.
func _anim_profile() -> Dictionary:
	var profile := super()
	(profile["actions"] as Dictionary).merge({&"ember": &"ember", &"storm_step": &"storm_step",
		&"frost_nova": &"frost_nova", &"ember_fall": &"ember_fall"})
	(profile["upper"] as Dictionary).merge({&"rune_bolt": &"bolt", &"chain_spark": &"chain_spark",
		&"fracture_rune": &"fracture_rune", &"flame_wall": &"flame_wall", &"ball_lightning": &"ball_lightning",
		&"hoarfrost_fan": &"flame_wall", &"rime_ward": &"chain_spark"})
	return profile


func _process_class_state(delta: float) -> void:
	match state:
		State.CAST:
			_process_cast(delta)
		State.STORM_STEP:
			_process_storm_step(delta)
		_:
			state = State.MOVE


## Dodging out of a Storm Step still ends the dash properly (collision mask,
## path zap) — otherwise the hero kept phasing through enemies.
func _on_dodge_cancel() -> void:
	if state == State.STORM_STEP:
		_resolve_storm_step()


# ---------------------------------------------------------------------------
# Rune Bolt (basic attack, auto-fire while held)
# ---------------------------------------------------------------------------

func try_rune_bolt() -> bool:
	if not knows(&"rune_bolt") or state != State.MOVE or _on_cooldown(&"rune_bolt"):
		return false
	_set_cooldown(&"rune_bolt", rune_bolt.cooldown)
	_hold_aim()
	var bolt := SpellBolt.new()
	bolt.setup(rune_bolt, aim_direction(), self)
	bolt.position = muzzle_position()  # before add_child, like every projectile
	get_tree().current_scene.add_child(bolt)
	mark_combat()
	hero_fx(&"rune_bolt", [muzzle_position(), aim_direction()])  # puppets fly a visual copy
	cooldowns_changed.emit()
	action_started.emit(&"rune_bolt")
	return true


# ---------------------------------------------------------------------------
# Ember Lance
# ---------------------------------------------------------------------------

func try_ember() -> bool:
	if not knows(&"ember_lance") or state != State.MOVE or _on_cooldown(&"ember_lance"):
		return false
	state = State.CAST
	_state_timer = 0.0
	_cast_id = &"ember_lance"
	_set_cooldown(&"ember_lance", ember.cooldown)
	_face_aim_instant()
	hero_fx(&"ember_cast", [muzzle_position()])
	cooldowns_changed.emit()
	action_started.emit(&"ember")
	return true


## A short wind-up that roots the hero, then the spell lets go (Ember Lance,
## Ember Fall: `startup` of the spell's data).
func _process_cast(delta: float) -> void:
	_state_timer += delta
	velocity.x = move_toward(velocity.x, 0, DECEL * 2.0 * delta)
	velocity.z = move_toward(velocity.z, 0, DECEL * 2.0 * delta)
	var data := ability(_cast_id)
	if _cast_id == &"ember_lance":
		_face_aim_instant()
	if data == null or _state_timer >= data.startup:
		match _cast_id:
			&"ember_fall":
				_call_ember_fall()
			_:
				_fire_ember()
		_cast_id = &""
		state = State.MOVE
		_consume_buffer()


func _fire_ember() -> void:
	var proj := EmberLanceProjectile.new()
	proj.setup(ember, aim_direction(), self)
	# Position before add_child: spawning at the scene origin for even one
	# frame overlaps the floor and detonates the projectile instantly.
	proj.position = muzzle_position()
	get_tree().current_scene.add_child(proj)
	feel_impulse(-aim_direction(), 0.05)
	hero_fx(&"ember_fire", [muzzle_position(), aim_direction()])  # puppets fly a visual copy


# ---------------------------------------------------------------------------
# Storm Step
# ---------------------------------------------------------------------------

func try_storm_step() -> bool:
	if not knows(&"storm_step") or state != State.MOVE or _on_cooldown(&"storm_step"):
		return false
	# Direction priority (user-tuned):
	# 1. Held movement input — steering wins ("I'm dashing where I'm running").
	# 2. Tab target the camera is looking at — gap-closer that lands in melee
	#    range instead of overshooting through the enemy.
	# 3. Camera aim direction.
	var dash_dist := storm_step.active * STORM_STEP_SPEED
	var dir := _move_input_dir()
	if dir == Vector3.ZERO:
		var target: EnemyBase = targeting.current if targeting != null else null
		if target != null and is_instance_valid(target) and target.ai_state != EnemyBase.AIState.DEAD:
			var to_target := target.global_position - global_position
			to_target.y = 0.0
			var cam_fwd := -(camera_rig.get_flat_basis().z) if camera_rig != null else facing()
			if to_target.length() > 0.5 and cam_fwd.dot(to_target.normalized()) > 0.4:
				dir = to_target.normalized()
				dash_dist = clampf(to_target.length() - 1.3, 1.5, dash_dist)
	if dir == Vector3.ZERO:
		var aim := aim_direction()
		dir = Vector3(aim.x, 0, aim.z).normalized()
	if dir == Vector3.ZERO and camera_rig != null:
		dir = -(camera_rig.get_flat_basis().z)
	if dir == Vector3.ZERO:
		dir = facing()
	_dash_dir = dir
	_dash_time = dash_dist / STORM_STEP_SPEED
	_dash_start = global_position
	state = State.STORM_STEP
	_state_timer = 0.0
	_set_cooldown(&"storm_step", storm_step.cooldown)
	collision_mask = 0b1000001  # phase through enemies during the dash (world + foliage)
	_visual.rotation.y = atan2(-dir.x, -dir.z)
	hero_fx(&"storm_step", [global_position])
	cooldowns_changed.emit()
	action_started.emit(&"storm_step")
	return true


func _process_storm_step(delta: float) -> void:
	_state_timer += delta
	if _state_timer < _dash_time:
		velocity.x = _dash_dir.x * STORM_STEP_SPEED
		velocity.z = _dash_dir.z * STORM_STEP_SPEED
		velocity.y = 0.0
	elif _state_timer < _dash_time + storm_step.recovery:
		if _state_timer - delta < _dash_time:
			# Hard stop at the end of the active window: letting 50 m/s decay
			# through normal deceleration added ~11m of ice-skating overshoot.
			velocity.x = _dash_dir.x * 4.0
			velocity.z = _dash_dir.z * 4.0
		velocity.x = move_toward(velocity.x, 0, DECEL * 2.0 * delta)
		velocity.z = move_toward(velocity.z, 0, DECEL * 2.0 * delta)
	else:
		_finish_storm_step()


func _finish_storm_step() -> void:
	state = State.MOVE
	_resolve_storm_step()
	_consume_buffer()


## Ends the dash itself: restores collision and zaps everything on the path.
## Shared by the normal finish and a dodge cancel (which must not consume the
## input buffer mid-dodge).
func _resolve_storm_step() -> void:
	collision_mask = 0b1000101
	hero_fx(&"storm_trail", [_dash_start, global_position])
	# Everything the dash passed through gets zapped and shocked.
	var path := global_position - _dash_start
	var center := _dash_start + path * 0.5 + Vector3(0, 1.0, 0)
	var hits := _query_hurtboxes(center, maxf(path.length() * 0.5 + 0.5, 1.0))
	var zapped := 0
	for enemy: Node in hits:
		var enemy_3d := enemy as Node3D
		# Radius covers a sphere; keep only enemies near the actual dash line.
		var to_enemy := enemy_3d.global_position - _dash_start
		var along := clampf(to_enemy.dot(path.normalized()), 0.0, path.length())
		var closest := _dash_start + path.normalized() * along
		if enemy_3d.global_position.distance_to(closest) > 1.4:
			continue
		var hit := roll_ability_hit(storm_step)
		hit.source_position = _dash_start
		if enemy.has_method(&"take_hit") and enemy.call(&"take_hit", hit):
			zapped += 1
			gain_resonance(storm_step.resonance_gain_per_hit, true)
			hero_fx(&"arc", [global_position + Vector3(0, 1.0, 0), enemy_3d.global_position + Vector3(0, 1.0, 0),
				Color(0.8, 0.9, 1.0), false])
	# M07 Overload: the landing point Shocks everything around it.
	if has_power(&"overload"):
		hero_fx(&"ring", [global_position, ArtKit.color("color_roles.lightning.body"), OVERLOAD_RADIUS, 0.25])
		for other in EnemyBase.all_enemies:
			if is_instance_valid(other) and other.ai_state != EnemyBase.AIState.DEAD \
					and other.global_position.distance_to(global_position) <= OVERLOAD_RADIUS:
				other.status.apply_shock()
	# M07 Eye of the Storm: every enemy on the path refunds 20 % of the cooldown.
	if has_power(&"eye_of_the_storm") and zapped > 0:
		_cooldowns[&"storm_step"] = maxf(float(_cooldowns.get(&"storm_step", 0.0)) - storm_step.cooldown * 0.2 * zapped, 0.0)
		cooldowns_changed.emit()


# ---------------------------------------------------------------------------
# Chain Spark
# ---------------------------------------------------------------------------

func try_chain_spark() -> bool:
	if not knows(&"chain_spark") or state != State.MOVE or _on_cooldown(&"chain_spark"):
		return false
	var first: EnemyBase = null
	if targeting != null:
		var held := targeting.current
		if held != null and is_instance_valid(held) and held.ai_state != EnemyBase.AIState.DEAD \
				and held.global_position.distance_to(global_position) <= 14.0:
			first = held
		else:
			first = targeting.best_candidate()
	if first == null:
		ui_denied()
		return false
	_set_cooldown(&"chain_spark", chain_spark.cooldown)
	_hold_aim()
	var from := muzzle_position()
	var hit_enemies: Array[EnemyBase] = []
	var next: EnemyBase = first
	var bonus_jump := false
	while next != null:
		if next.status.has_shock():
			bonus_jump = true
		var chest := next.global_position + Vector3(0, 1.0, 0)
		hero_fx(&"arc", [from, chest, Color(1.0, 0.95, 0.5), true])
		var hit := roll_ability_hit(chain_spark)
		if next.take_hit(hit):
			gain_resonance(chain_spark.resonance_gain_per_hit, true)
			# Conductor's Oath: struck enemies stay charged; later lightning
			# damage on any Conductor arcs to all others (see EnemyBase).
			if has_power(&"conductors_oath"):
				next.status.apply_conductor()
		hit_enemies.append(next)
		from = chest
		var max_targets := 3 + int(stat(&"chain_jumps")) + (1 if bonus_jump else 0)
		next = null
		if hit_enemies.size() < max_targets:
			next = _nearest_chain_candidate(from, hit_enemies)
	# M07 Thunderclap: the last target bursts onto its neighbours.
	if has_power(&"thunderclap") and not hit_enemies.is_empty() and is_instance_valid(hit_enemies[-1]):
		var last := hit_enemies[-1]
		hero_fx(&"ring", [last.global_position, ArtKit.color("color_roles.lightning.body"), THUNDERCLAP_RADIUS, 0.25])
		for other in EnemyBase.all_enemies.duplicate():
			if other == last or not is_instance_valid(other) or other.ai_state == EnemyBase.AIState.DEAD:
				continue
			if other.global_position.distance_to(last.global_position) <= THUNDERCLAP_RADIUS:
				var splash := roll_ability_hit(chain_spark)
				splash.damage *= 0.6
				splash.source_position = last.global_position
				other.take_hit(splash)
	hero_fx(&"sfx", ["chain_spark", global_position, -1.0])
	feel_impulse(aim_direction(), 0.04)
	_flourish(Vector3(-70, 20, 0), 0.07, 0.25)
	cooldowns_changed.emit()
	action_started.emit(&"chain_spark")
	return true


func _nearest_chain_candidate(from: Vector3, exclude: Array[EnemyBase]) -> EnemyBase:
	var best: EnemyBase = null
	var best_dist := chain_spark.aoe_radius  # jump range
	for enemy in EnemyBase.all_enemies:
		if not is_instance_valid(enemy) or enemy.ai_state == EnemyBase.AIState.DEAD or exclude.has(enemy):
			continue
		var d := enemy.global_position.distance_to(from)
		if d < best_dist:
			best_dist = d
			best = enemy
	return best


# ---------------------------------------------------------------------------
# Fracture Rune
# ---------------------------------------------------------------------------

func try_fracture_rune() -> bool:
	if not knows(&"fracture_rune") or state != State.MOVE or _on_cooldown(&"fracture_rune"):
		return false
	_set_cooldown(&"fracture_rune", fracture_rune.cooldown)
	var exclude: Array[RID] = [get_rid()]
	var aim_point := camera_rig.get_aim_point(exclude) if camera_rig != null else global_position + aim_direction() * 6.0
	var offset := Vector3(aim_point.x - global_position.x, 0.0, aim_point.z - global_position.z)
	if offset.length() > FRACTURE_RUNE_MAX_RANGE:
		offset = offset.normalized() * FRACTURE_RUNE_MAX_RANGE
	var rune := FractureRune.new()
	rune.setup(fracture_rune, self)
	rune.arm_time = maxf(FractureRune.ARM_TIME - stat(&"rune_arm_reduce"), 0.5)
	rune.radius = fracture_rune.aoe_radius + stat(&"rune_radius")  # M10 Rune Mastery
	# M08: on the ground under the aim spot (slopes, ledges), never at y 0
	rune.position = ZoneBase.ground_under(self, global_position + offset, 0.02)
	get_tree().current_scene.add_child(rune)
	hero_fx(&"rune", [rune.position, rune.arm_time, rune.radius])  # puppets arm a visual copy
	_hold_aim()
	_flourish(Vector3(-60, 0, 0), 0.08, 0.3)
	cooldowns_changed.emit()
	action_started.emit(&"fracture_rune")
	return true


# ---------------------------------------------------------------------------
# M10: Frost Nova (a ring of ice around the caster, spends Aether)
# ---------------------------------------------------------------------------

func try_frost_nova() -> bool:
	if not knows(&"frost_nova") or state != State.MOVE or _on_cooldown(&"frost_nova"):
		return false
	if resonance < frost_nova.resonance_cost:
		ui_denied()
		return false
	spend_resonance(frost_nova.resonance_cost)
	_set_cooldown(&"frost_nova", frost_nova.cooldown)
	var pos := global_position
	hero_fx(&"frost_nova", [pos, frost_nova.aoe_radius])
	feel_shake(0.25)
	var hits := _query_hurtboxes(pos + Vector3(0, 0.8, 0), frost_nova.aoe_radius)
	for enemy: Node in hits:
		var hit := roll_ability_hit(frost_nova)
		hit.source_position = pos
		if enemy.call(&"take_hit", hit) and has_power(&"deep_freeze") and enemy is EnemyBase:
			(enemy as EnemyBase).status.apply_root(DEEP_FREEZE_ROOT)  # M10 Deep Freeze
	if not hits.is_empty():
		GameFeel.hitstop(hits, 0.05)
	cooldowns_changed.emit()
	action_started.emit(&"frost_nova")
	return true


# ---------------------------------------------------------------------------
# M13 tome (the Cistern): Rime Ward (a barrier; melee strikers are Chilled)
# ---------------------------------------------------------------------------

func rime_amount() -> float:
	var lvl := progression.level if progression != null else 1
	return rime_ward.heal + RIME_PER_LEVEL * lvl


## Does the rime still hold (time left and barrier left)?
func rime_warded() -> bool:
	return rime_ward != null and Time.get_ticks_msec() < _rime_until and barrier > 0.0


func try_rime_ward() -> bool:
	if not knows(&"rime_ward") or state != State.MOVE or _on_cooldown(&"rime_ward"):
		return false
	if resonance < rime_ward.resonance_cost:
		ui_denied()
		return false
	spend_resonance(rime_ward.resonance_cost)
	_set_cooldown(&"rime_ward", rime_ward.cooldown)
	grant_barrier(rime_amount(), rime_ward.active)
	_rime_until = Time.get_ticks_msec() + int(rime_ward.active * 1000.0)
	hero_fx(&"rime_ward", [rime_ward.active])
	cooldowns_changed.emit()
	action_started.emit(&"rime_ward")
	return true


## The rime bites back: an enemy that strikes this hero in melee while the
## ward holds is Chilled (its owner's machine judges, like every hit taken).
func take_hit(hit: HitInfo) -> bool:
	if hit != null and not hit.from_player and net_role == NetRole.OWNER and not god_mode and rime_warded():
		var striker := instance_from_id(hit.source_id) as EnemyBase if hit.source_id != 0 else null
		if striker != null and is_instance_valid(striker) and striker.ai_state != EnemyBase.AIState.DEAD \
				and striker.global_position.distance_to(global_position) <= rime_ward.aoe_radius:
			var bite := roll_ability_hit(rime_ward)
			bite.source_position = global_position
			striker.take_hit(bite)
			VFX.frost_burst(get_tree().current_scene, striker.global_position + Vector3(0, 0.8, 0), 0.9)
	return super(hit)


# ---------------------------------------------------------------------------
# M12 tome: Hoarfrost Fan (a cone of rime; the Chilled freeze in place)
# ---------------------------------------------------------------------------

func try_hoarfrost_fan() -> bool:
	if not knows(&"hoarfrost_fan") or state != State.MOVE or _on_cooldown(&"hoarfrost_fan"):
		return false
	if resonance < hoarfrost_fan.resonance_cost:
		ui_denied()
		return false
	spend_resonance(hoarfrost_fan.resonance_cost)
	_set_cooldown(&"hoarfrost_fan", hoarfrost_fan.cooldown)
	var dir := aim_direction()
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else facing()
	_visual.rotation.y = atan2(-dir.x, -dir.z)
	_aim_hold_until = Time.get_ticks_msec() + AIM_HOLD_MSEC
	var pos := global_position
	hero_fx(&"hoarfrost_fan", [pos, dir, hoarfrost_fan.aoe_radius])
	feel_shake(0.15)
	var struck: Array[Node] = []
	for node: Node in _query_hurtboxes(pos + Vector3(0, 0.8, 0), hoarfrost_fan.aoe_radius):
		var e := node as EnemyBase
		if e == null:
			continue
		var to := e.global_position - pos
		to.y = 0.0
		if to.length() > 0.8 and rad_to_deg(dir.angle_to(to.normalized())) > FAN_HALF_ANGLE:
			continue
		var chilled := e.status.has_chill()
		var hit := roll_ability_hit(hoarfrost_fan)
		hit.source_position = pos
		if chilled:
			hit.damage *= FAN_CHILLED_MULT
		if e.take_hit(hit):
			struck.append(e)
			if chilled:
				e.status.apply_root(FAN_ROOT)
	if not struck.is_empty():
		GameFeel.hitstop(struck, 0.04)
	cooldowns_changed.emit()
	action_started.emit(&"hoarfrost_fan")
	return true


# ---------------------------------------------------------------------------
# M10: Flame Wall (a burning line across the aim)
# ---------------------------------------------------------------------------

func try_flame_wall() -> bool:
	if not knows(&"flame_wall") or state != State.MOVE or _on_cooldown(&"flame_wall"):
		return false
	_set_cooldown(&"flame_wall", flame_wall.cooldown)
	var at := _ground_aim(flame_wall.projectile_speed)
	var dir := at - global_position
	dir.y = 0.0
	if dir.length() < 0.1:
		dir = facing()
	var across := Vector3(-dir.z, 0.0, dir.x).normalized()  # the wall stands across the aim line
	var wall := FlameWall.new()
	wall.setup(flame_wall, self)
	wall.length = flame_wall.aoe_radius
	wall.duration = flame_wall.active
	wall.axis = across
	wall.position = at
	get_tree().current_scene.add_child(wall)
	hero_fx(&"flame_wall", [at, across, wall.length, wall.duration])  # puppets raise a visual copy
	_hold_aim()
	cooldowns_changed.emit()
	action_started.emit(&"flame_wall")
	return true


# ---------------------------------------------------------------------------
# M10: Ball Lightning (a slow orb that zaps what it passes)
# ---------------------------------------------------------------------------

func try_ball_lightning() -> bool:
	if not knows(&"ball_lightning") or state != State.MOVE or _on_cooldown(&"ball_lightning"):
		return false
	_set_cooldown(&"ball_lightning", ball_lightning.cooldown)
	_hold_aim()
	var ball := BallLightning.new()
	ball.setup(ball_lightning, aim_direction(), self)
	ball.position = muzzle_position()  # before add_child, like every projectile
	get_tree().current_scene.add_child(ball)
	hero_fx(&"ball_lightning", [muzzle_position(), aim_direction()])  # puppets fly a visual copy
	cooldowns_changed.emit()
	action_started.emit(&"ball_lightning")
	return true


# ---------------------------------------------------------------------------
# M10: Ember Fall (a telegraphed meteor on the aim, spends Aether)
# ---------------------------------------------------------------------------

func try_ember_fall() -> bool:
	if not knows(&"ember_fall") or state != State.MOVE or _on_cooldown(&"ember_fall"):
		return false
	if resonance < ember_fall.resonance_cost:
		ui_denied()
		return false
	spend_resonance(ember_fall.resonance_cost)
	_set_cooldown(&"ember_fall", ember_fall.cooldown)
	_cast_at = _ground_aim(ember_fall.projectile_speed)
	_cast_id = &"ember_fall"
	state = State.CAST
	_state_timer = 0.0
	_hold_aim()
	cooldowns_changed.emit()
	action_started.emit(&"ember_fall")
	return true


func _call_ember_fall() -> void:
	var rock := EmberFall.new()
	rock.setup(ember_fall, self)
	rock.position = _cast_at
	get_tree().current_scene.add_child(rock)
	hero_fx(&"ember_fall", [_cast_at])  # puppets drop a visual copy


## The ground under the aim, at most `reach` away (the camera's aim point;
## a bot's aim direction).
func _ground_aim(reach: float) -> Vector3:
	var exclude: Array[RID] = [get_rid()]
	var aim_point := camera_rig.get_aim_point(exclude) if camera_rig != null else global_position + aim_direction() * reach
	var offset := Vector3(aim_point.x - global_position.x, 0.0, aim_point.z - global_position.z)
	if offset.length() > reach:
		offset = offset.normalized() * reach
	return ZoneBase.ground_under(self, global_position + offset, 0.02)
