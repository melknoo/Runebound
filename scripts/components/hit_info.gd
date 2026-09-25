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
## M07: player hits carry their ability so talents can modify them on impact.
var from_player: bool = false
var ability: StringName = &""
var burn_mult: float = 1.0  # Kindling: scales the Burn this hit applies
## M07b: who dealt it, as an instance id (0 = nobody / the world). An id, not
## a reference: statuses and Wildfire resolve seconds later, possibly after
## the attacker is gone, and an int travels over the wire unchanged.
var attacker_id: int = 0
## M09: the volume an enemy attack struck (sphere centre + radius; INF / 0 =
## unknown). A co-op client only takes a forwarded hit when its own hero is
## still inside it: dodging out on your own screen counts.
var area_center: Vector3 = Vector3.INF
var area_radius: float = 0.0


## The attacker node, or null when it is gone or unknown.
func attacker() -> Node:
	if attacker_id == 0:
		return null
	var obj := instance_from_id(attacker_id)
	return obj as Node if obj != null and is_instance_valid(obj) else null


func attacker_player() -> Player:
	return attacker() as Player


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
