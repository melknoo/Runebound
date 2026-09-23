class_name HealthComponent
extends Node
## Owns hit points and i-frames for one entity. Status effects live in
## StatusEffectComponent; the owner reacts to consequences via signals.

signal damaged(hit: HitInfo)
signal died
signal health_changed(current: float, maximum: float)

@export var max_health: float = 100.0

var current_health: float
var invulnerable: bool = false
var is_dead: bool = false


func _ready() -> void:
	current_health = max_health


func apply_hit(hit: HitInfo) -> bool:
	if is_dead or invulnerable:
		return false
	current_health = maxf(current_health - hit.damage, 0.0)
	health_changed.emit(current_health, max_health)
	damaged.emit(hit)
	_check_death()
	return true


## Damage over time: no hit reaction, own damage number.
func apply_dot(amount: float, type: HitInfo.DamageType) -> void:
	if is_dead:
		return
	current_health = maxf(current_health - amount, 0.0)
	health_changed.emit(current_health, max_health)
	var parent_3d := get_parent() as Node3D
	if parent_3d != null:
		GameFeel.damage_number(parent_3d.global_position + Vector3(0, 1.2, 0), amount, HitInfo.type_color(type))
	_check_death()


func _check_death() -> void:
	if current_health <= 0.0 and not is_dead:
		is_dead = true
		died.emit()


func heal_full() -> void:
	current_health = max_health
	is_dead = false
	health_changed.emit(current_health, max_health)
