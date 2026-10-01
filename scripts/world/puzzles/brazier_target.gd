class_name BrazierTarget
extends Node3D
## M12: the hittable part of a brazier - a hurtbox on the enemy-hurtbox layer,
## so every hit path finds it (melee shape queries, bolts, thorns). Not an
## enemy: no health, never in EnemyBase.all_enemies, never a target, and
## `take_hit` answers false (no Resonance or Aether from striking it).

var puzzle: BrazierPuzzle
var index: int = 0


func setup() -> void:
	Hurtbox.create(self, 0b10000, 0.45, 0.9, 1.0)


func take_hit(hit: HitInfo) -> bool:
	if puzzle == null:
		return false
	var zone := ZoneBase.zone_of(self)
	var hero := zone.player if zone != null else null
	if hero != null and hit != null:
		puzzle.strike(index, hero)
	return false
