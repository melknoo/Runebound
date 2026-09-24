class_name AbilityData
extends Resource
## Tuning data for one ability. Behavior lives in code; numbers live here.

@export var id: StringName = &""
@export var display_name: String = ""
## One-line player-facing summary, shown in the HUD tooltip (inventory open).
@export var description: String = ""
@export var cooldown: float = 1.0
@export var resonance_cost: float = 0.0
@export var resonance_gain_per_hit: float = 0.0
@export var startup: float = 0.1        # anticipation before the active moment
@export var active: float = 0.1         # active hit window / release moment
@export var recovery: float = 0.2
@export var damage: float = 10.0
@export var damage_type: HitInfo.DamageType = HitInfo.DamageType.PHYSICAL
@export var weight: HitInfo.Weight = HitInfo.Weight.LIGHT
@export var knockback: float = 0.0
@export var projectile_speed: float = 0.0
@export var aoe_radius: float = 0.0
@export var applies_burn: bool = false
@export var applies_chill: bool = false
@export var applies_shock: bool = false
@export var crit_chance: float = 0.08
@export var crit_multiplier: float = 1.6


func roll_hit(source_pos: Vector3, damage_mult: float = 1.0, bonus_crit: float = 0.0) -> HitInfo:
	var hit := HitInfo.create(damage * damage_mult, damage_type, weight, source_pos)
	hit.knockback = knockback
	hit.applies_burn = applies_burn
	hit.applies_chill = applies_chill
	hit.applies_shock = applies_shock
	if randf() < crit_chance + bonus_crit:
		hit.is_crit = true
		hit.damage *= crit_multiplier
	return hit
