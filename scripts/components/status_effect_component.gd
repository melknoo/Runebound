class_name StatusEffectComponent
extends Node
## Elemental statuses on one entity: Burn (fire DoT), Chill (slow),
## Shock (increased damage taken), M10 Root (frozen in place: no movement),
## M13 Brand (the Warrens' tome: takes more from every hero, deals less).
## Applied from HitInfo flags by the owner, queried by movement/damage code.
## Reapplying refreshes duration.

const BURN_DPS := 4.0
const BURN_DURATION := 3.0
const CHILL_DURATION := 3.0
const CHILL_SPEED_MULT := 0.55
const SHOCK_DURATION := 4.0
const SHOCK_DAMAGE_MULT := 1.2
## M13 Forge Brand: the branded take this much more and deal this much less.
const BRAND_DAMAGE_MULT := 1.2
const BRAND_WEAKEN := 0.75
const BRAND_DURATION := 8.0
## The hit that brands (its ability id travels with a forwarded hit).
const BRAND_ABILITY := &"forge_brand"

var health: HealthComponent = null  # wired by the owner
## M09: set on an enemy puppet (co-op client). Its statuses mirror the
## server's snapshot bits (set_net_bits), never tick damage here, and
## applying one is forwarded to the server (Overload, Glacial Bulwark,
## FrostField, Conductor's Oath touch statuses without a hit).
var puppet_of: Node = null

var _burn_left: float = 0.0
var _burn_dps: float = 0.0
var _burn_accum: float = 0.0
var _chill_left: float = 0.0
var _shock_left: float = 0.0
var _conductor_left: float = 0.0
var _root_left: float = 0.0
var _brand_left: float = 0.0
## M10 Absolute Zero: when the last chills landed (seconds, engine time).
var _chill_times: Array[float] = []
var _tick_vfx_accum: float = 0.0


func is_conductor() -> bool:
	return _conductor_left > 0.0


func apply_conductor(duration: float = 6.0) -> void:
	if puppet_of != null:
		puppet_of.call(&"forward_status", &"conductor", duration, 0.0)
		return
	_conductor_left = maxf(_conductor_left, duration)


func has_burn() -> bool:
	return _burn_left > 0.0


func has_chill() -> bool:
	return _chill_left > 0.0


func has_shock() -> bool:
	return _shock_left > 0.0


func is_rooted() -> bool:
	return _root_left > 0.0


func speed_multiplier() -> float:
	if is_rooted():
		return 0.0
	return CHILL_SPEED_MULT if has_chill() else 1.0


## M10 Deep Freeze / Absolute Zero: frozen in place (it can still strike what
## is in reach).
func apply_root(duration: float) -> void:
	if puppet_of != null:
		puppet_of.call(&"forward_status", &"root", duration, 0.0)
		return
	_root_left = maxf(_root_left, duration)


## Chills that landed within the last `window` seconds (Absolute Zero).
func chills_within(window: float) -> int:
	var now := Time.get_ticks_msec() / 1000.0
	var n := 0
	for at in _chill_times:
		if now - at <= window:
			n += 1
	return n


func clear_chill_count() -> void:
	_chill_times.clear()


func is_branded() -> bool:
	return _brand_left > 0.0


func apply_brand(duration: float = BRAND_DURATION) -> void:
	if puppet_of != null:
		puppet_of.call(&"forward_status", &"brand", duration, 0.0)
		return
	_brand_left = maxf(_brand_left, duration)


func damage_taken_multiplier() -> float:
	return (SHOCK_DAMAGE_MULT if has_shock() else 1.0) * (BRAND_DAMAGE_MULT if is_branded() else 1.0)


## M07b: instance id of whoever applied the current Burn (Wildfire credit).
var burn_source_id: int = 0


func burn_source() -> Node:
	if burn_source_id == 0:
		return null
	var obj := instance_from_id(burn_source_id)
	return obj as Node if obj != null and is_instance_valid(obj) else null


func apply_from_hit(hit: HitInfo) -> void:
	if hit.applies_burn:
		apply_burn(BURN_DPS * hit.burn_mult, BURN_DURATION, hit.attacker_id)
	if hit.applies_chill:
		apply_chill(CHILL_DURATION + hit.chill_bonus)  # M10 Cold Snap
	if hit.applies_shock:
		apply_shock()
	if hit.ability == BRAND_ABILITY:
		apply_brand()


func apply_burn(dps: float = BURN_DPS, duration: float = BURN_DURATION, source_id: int = 0) -> void:
	if puppet_of != null:
		puppet_of.call(&"forward_status", &"burn", duration, dps)
		return
	_burn_dps = maxf(_burn_dps, dps)
	_burn_left = maxf(_burn_left, duration)
	if source_id != 0:
		burn_source_id = source_id


func apply_chill(duration: float = CHILL_DURATION) -> void:
	if puppet_of != null:
		puppet_of.call(&"forward_status", &"chill", duration, 0.0)
		return
	_chill_left = maxf(_chill_left, duration)
	_chill_times.append(Time.get_ticks_msec() / 1000.0)
	if _chill_times.size() > 6:
		_chill_times.remove_at(0)


func apply_shock(duration: float = SHOCK_DURATION) -> void:
	if puppet_of != null:
		puppet_of.call(&"forward_status", &"shock", duration, 0.0)
		return
	_shock_left = maxf(_shock_left, duration)


## M09 puppet: the server's statuses (NetCodec.ST_* bits). They last until the
## next snapshot says otherwise; a puppet shows them but deals no damage.
const NET_HOLD := 0.6


func set_net_bits(bits: int) -> void:
	_burn_left = NET_HOLD if bits & NetCodec.ST_BURN else 0.0
	_chill_left = NET_HOLD if bits & NetCodec.ST_CHILL else 0.0
	_shock_left = NET_HOLD if bits & NetCodec.ST_SHOCK else 0.0
	_conductor_left = NET_HOLD if bits & NetCodec.ST_CONDUCTOR else 0.0
	_root_left = NET_HOLD if bits & NetCodec.ST_ROOT else 0.0
	_brand_left = NET_HOLD if bits & NetCodec.ST_BRAND else 0.0


## The snapshot bits for this component (server side).
func net_bits() -> int:
	var bits := 0
	if has_burn():
		bits |= NetCodec.ST_BURN
	if has_chill():
		bits |= NetCodec.ST_CHILL
	if has_shock():
		bits |= NetCodec.ST_SHOCK
	if is_conductor():
		bits |= NetCodec.ST_CONDUCTOR
	if is_rooted():
		bits |= NetCodec.ST_ROOT
	if is_branded():
		bits |= NetCodec.ST_BRAND
	return bits


func clear_all() -> void:
	_burn_left = 0.0
	_chill_left = 0.0
	_shock_left = 0.0
	_root_left = 0.0
	_brand_left = 0.0
	_chill_times.clear()
	_burn_dps = 0.0


func _process(delta: float) -> void:
	if health == null or health.is_dead:
		return
	_chill_left = maxf(_chill_left - delta, 0.0)
	_shock_left = maxf(_shock_left - delta, 0.0)
	_conductor_left = maxf(_conductor_left - delta, 0.0)
	_root_left = maxf(_root_left - delta, 0.0)
	_brand_left = maxf(_brand_left - delta, 0.0)

	var owner_3d := get_parent() as Node3D
	if _burn_left > 0.0:
		_burn_left -= delta
		_burn_accum += delta
		if _burn_accum >= 0.5:
			_burn_accum -= 0.5
			if puppet_of == null:  # a puppet burns for show; the server deals the damage
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
		if is_branded():
			VFX.flash(scene, owner_3d.global_position + Vector3(0, 2.0, 0), Color(1.0, 0.55, 0.2), 0.45, 0.25)
		if is_conductor():
			var top := owner_3d.global_position + Vector3(0, 1.9, 0)
			VFX.lightning_arc(scene, top, top + Vector3(randf_range(-0.4, 0.4), 0.5, randf_range(-0.4, 0.4)))
