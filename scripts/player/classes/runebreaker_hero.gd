class_name RunebreakerHero
extends Player
## M10: the Runebreaker, the tank. Melee (Rune Cleave) builds Resonance; heavy
## rune abilities spend it (Earthbreaker, Runic Guard, Resonance Burst). The
## elemental spells went to the Elementalist (CLASS_DESIGN "Three roles").

# Ability tuning: derived caches of `abilities` (the tests read them by name).
var cleave: AbilityData
var earthbreaker: AbilityData
var runic_guard: AbilityData        # M07 talent ability
var resonance_burst: AbilityData    # M07 talent ability

var _melee_flip: bool = false
var _melee_did_hit_window: bool = false


func _load_abilities() -> void:
	super()
	cleave = ability(&"rune_cleave")
	earthbreaker = ability(&"earthbreaker")
	runic_guard = ability(&"runic_guard")
	resonance_burst = ability(&"resonance_burst")


func _register_actions() -> void:
	super()
	_actions.merge({
		&"rune_cleave": try_melee,
		&"earthbreaker": try_earthbreaker,
		&"runic_guard": try_runic_guard,
		&"resonance_burst": try_resonance_burst,
	})


func _anim_profile() -> Dictionary:
	var profile := super()
	(profile["actions"] as Dictionary).merge({&"cleave_l": &"cleave_l", &"cleave_r": &"cleave_r",
		&"earthbreaker": &"earthbreaker_rise", &"earthbreaker_impact": &"earthbreaker_impact",
		&"resonance_burst": &"resonance_burst"})
	# instant casts keep the legs running: upper-body layer only
	(profile["upper"] as Dictionary).merge({&"runic_guard": &"runic_guard"})
	return profile


func _process_class_state(delta: float) -> void:
	match state:
		State.MELEE:
			_process_melee(delta)
		State.SLAM:
			_process_slam(delta)
		_:
			state = State.MOVE


## Earthbreaker is committed once the hero leaves the ground.
func _dodge_allowed() -> bool:
	return not (state == State.SLAM and _state_timer < earthbreaker.startup + earthbreaker.active)


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
		if has_power(&"molten_core"):
			hit.applies_burn = true  # M07 Molten Core
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
