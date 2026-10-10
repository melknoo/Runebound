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
## M11 support abilities: the health a heal restores (a zone or a heal over
## time: per second / in total, see its description) or the barrier a shield
## grants. The healer's `heal_pct` scales it.
@export var heal: float = 0.0

## M07b: how a character comes to know this ability (docs/PROGRESSION_DESIGN.md).
## START: known from creation. TRAINER: bought at the hub trainer (level +
## gold). TALENT: granted while the talent `unlock_power` is learned. M12 TOME:
## taught by a tome (one per class and tome; `tome_id` names which).
enum Unlock { START, TRAINER, TALENT, TOME }
## M10: holding its key keeps firing it (the Elementalist's Rune Bolt).
@export var repeat_while_held: bool = false
## M10 threat: enemies take this ability's damage x this as threat (tank
## abilities threaten more; a taunt pulls regardless).
@export var threat_mult: float = 1.0
@export_group("Learning")
## M10: keys belong to loadout slots (InputSetup.SLOT_ACTIONS), not abilities.
@export var unlock: Unlock = Unlock.TRAINER
@export var learn_level: int = 1
@export var learn_price: int = 0
## TALENT unlocks: the power id Player.has_power() must report.
@export var unlock_power: StringName = &""
## M13 TOME unlocks: the tome that teaches it ("" = the Charwood grotto's,
## "cistern" / "warrens" = the dungeons' big secrets).
@export var tome_id: StringName = &""


## M12: the name players read - the text table's "ability.<id>" (DE/EN) where
## there is one (the abilities from M12 on), else display_name.
func title() -> String:
	var key := "ability.%s" % id
	var text := Texts.t(key)
	return display_name if text == key else text


func summary() -> String:
	var key := "ability.%s.desc" % id
	var text := Texts.t(key)
	return description if text == key else text


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
