class_name HitInfo
extends RefCounted
## Everything a hit needs to communicate, passed to HealthComponent.apply_hit().

enum DamageType { PHYSICAL, FIRE, FROST, LIGHTNING }
enum Weight { LIGHT, MEDIUM, HEAVY }

var damage: float = 0.0
var type: DamageType = DamageType.PHYSICAL
var weight: Weight = Weight.LIGHT
var is_crit: bool = false
var knockback: float = 0.0
var source_position: Vector3 = Vector3.ZERO
var applies_burn: bool = false
var applies_chill: bool = false
var applies_shock: bool = false
## Set on Conductor splash hits so they never chain into further splashes.
var is_conductor_arc: bool = false


static func create(dmg: float, dmg_type: DamageType, hit_weight: Weight, source_pos: Vector3) -> HitInfo:
	var h := HitInfo.new()
	h.damage = dmg
	h.type = dmg_type
	h.weight = hit_weight
	h.source_position = source_pos
	return h


static func type_color(dmg_type: DamageType) -> Color:
	match dmg_type:
		DamageType.FIRE:
			return Color(1.0, 0.55, 0.2)
		DamageType.FROST:
			return Color(0.5, 0.85, 1.0)
		DamageType.LIGHTNING:
			return Color(1.0, 0.95, 0.4)
		_:
			return Color(0.95, 0.95, 0.9)
