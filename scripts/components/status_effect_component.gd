class_name StatusEffectComponent
extends Node
## Elemental statuses on one entity: Burn (fire DoT), Chill (slow),
## Shock (increased damage taken). Applied from HitInfo flags by the owner,
## queried by movement/damage code. Reapplying refreshes duration.

const BURN_DPS := 4.0
const BURN_DURATION := 3.0
const CHILL_DURATION := 3.0
const CHILL_SPEED_MULT := 0.55
const SHOCK_DURATION := 4.0
const SHOCK_DAMAGE_MULT := 1.2

var health: HealthComponent = null  # wired by the owner

var _burn_left: float = 0.0
var _burn_dps: float = 0.0
var _burn_accum: float = 0.0
var _chill_left: float = 0.0
var _shock_left: float = 0.0
var _conductor_left: float = 0.0
var _tick_vfx_accum: float = 0.0


func is_conductor() -> bool:
	return _conductor_left > 0.0


func apply_conductor(duration: float = 6.0) -> void:
	_conductor_left = maxf(_conductor_left, duration)


func has_burn() -> bool:
	return _burn_left > 0.0


func has_chill() -> bool:
	return _chill_left > 0.0


func has_shock() -> bool:
	return _shock_left > 0.0


func speed_multiplier() -> float:
	return CHILL_SPEED_MULT if has_chill() else 1.0


func damage_taken_multiplier() -> float:
	return SHOCK_DAMAGE_MULT if has_shock() else 1.0


func apply_from_hit(hit: HitInfo) -> void:
	if hit.applies_burn:
		apply_burn(BURN_DPS * hit.burn_mult)
	if hit.applies_chill:
		apply_chill()
	if hit.applies_shock:
		apply_shock()


func apply_burn(dps: float = BURN_DPS, duration: float = BURN_DURATION) -> void:
	_burn_dps = maxf(_burn_dps, dps)
	_burn_left = maxf(_burn_left, duration)


func apply_chill(duration: float = CHILL_DURATION) -> void:
	_chill_left = maxf(_chill_left, duration)


func apply_shock(duration: float = SHOCK_DURATION) -> void:
	_shock_left = maxf(_shock_left, duration)


func clear_all() -> void:
	_burn_left = 0.0
	_chill_left = 0.0
	_shock_left = 0.0
	_burn_dps = 0.0


func _process(delta: float) -> void:
	if health == null or health.is_dead:
		return
	_chill_left = maxf(_chill_left - delta, 0.0)
	_shock_left = maxf(_shock_left - delta, 0.0)
	_conductor_left = maxf(_conductor_left - delta, 0.0)

	var owner_3d := get_parent() as Node3D
	if _burn_left > 0.0:
		_burn_left -= delta
		_burn_accum += delta
		if _burn_accum >= 0.5:
			_burn_accum -= 0.5
			health.apply_dot(_burn_dps * 0.5, HitInfo.DamageType.FIRE)
			if owner_3d != null:
				VFX.burn_tick(owner_3d.get_tree().current_scene, owner_3d.global_position + Vector3(0, 0.8, 0))
	else:
		_burn_dps = 0.0

	# Occasional ambient ticks so active statuses stay visible.
	_tick_vfx_accum += delta
	if _tick_vfx_accum >= 0.7 and owner_3d != null:
		_tick_vfx_accum = 0.0
		var scene := owner_3d.get_tree().current_scene
		if has_chill():
			VFX.chill_tick(scene, owner_3d.global_position + Vector3(0, 0.5, 0))
		if has_shock():
			VFX.shock_tick(scene, owner_3d.global_position + Vector3(0, 1.0, 0))
		if is_conductor():
			var top := owner_3d.global_position + Vector3(0, 1.9, 0)
			VFX.lightning_arc(scene, top, top + Vector3(randf_range(-0.4, 0.4), 0.5, randf_range(-0.4, 0.4)))
