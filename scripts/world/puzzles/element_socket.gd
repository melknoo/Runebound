class_name ElementSocket
extends Node3D
## M13: the hittable part of an element target (a kiln, a copper post, an
## ice anchor) - a hurtbox on the enemy-hurtbox layer like a brazier's. A
## strike brings its own element or the striking hero's carried one
## (ElementCharge); the right one is reported to the owner puzzle (`struck`).
## Never an enemy, never a target; `take_hit` answers false.

## The puzzle (ElementPuzzle / IceBridge) with `struck(index, element, hero)`.
var puzzle: Node = null
var index: int = 0


func setup(radius: float = 0.5, height: float = 1.4, y: float = 0.9) -> void:
	Hurtbox.create(self, 0b10000, radius, height, y)


func take_hit(hit: HitInfo) -> bool:
	if puzzle == null or hit == null:
		return false
	var zone := ZoneBase.zone_of(self)
	var hero := zone.player if zone != null else null
	if hero == null or not is_instance_valid(hero):
		return false
	var element := ElementCharge.of_strike(hit, hero)
	if element != ElementCharge.NONE:
		puzzle.call(&"struck", index, element, hero)
	return false
