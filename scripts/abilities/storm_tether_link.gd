class_name StormTetherLink
extends Node3D
## M13b the Stormwatch's tome (Runebreaker): the look of a Storm Tether - a
## crackling line of lightning between the tank and the ally it bound, drawn
## on every machine (HeroFx "ally_tether") while both stand and keep within
## Player.TETHER_SNAP of each other. The tether's work (the share of each
## blow, the lash) lives on the heroes' owners (Player.bind_tether,
## carry_for_ally); this only shows it.

const ARC_EVERY := 0.16
const LIFT := Vector3(0, 1.2, 0)

var tank: Player = null
var ally: Player = null
var duration: float = 8.0
var _age: float = 0.0
var _arc_left: float = 0.0


func _process(delta: float) -> void:
	_age += delta
	if _age >= duration or not _holds():
		queue_free()
		return
	_arc_left -= delta
	if _arc_left > 0.0 or not Net.has_view():
		return
	_arc_left = ARC_EVERY
	VFX.lightning_arc(get_tree().current_scene, tank.global_position + LIFT, ally.global_position + LIFT,
		ArtKit.color("palettes.stormwatch.lightning", Color("#B9A8FF")))


func _holds() -> bool:
	return tank != null and is_instance_valid(tank) and ally != null and is_instance_valid(ally) \
		and not tank.health.is_dead and not ally.health.is_dead \
		and tank.global_position.distance_to(ally.global_position) <= Player.TETHER_SNAP
