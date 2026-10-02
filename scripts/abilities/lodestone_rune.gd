class_name LodestoneRune
extends Node3D
## M12 tome (Runebreaker): a gold rune on the ground at the aim. It arms for
## `arm_time` (its ring fills - the heroes' marker, never the enemies' red
## disc), then drags every enemy within `radius` PULL metres toward its
## middle (the heavy ones keep their footing: stagger_resist), strikes them
## and taunts them onto the Runebreaker. Gathers a scattered pack for the
## party's area spells.

const PULL := 3.0
## Nobody is dragged closer to the middle than this.
const MIN_GAP := 0.9

var arm_time: float = 0.5
var radius: float = 6.0
## M09: another player's rune on a co-op client (the look only).
var visual_only: bool = false
var _data: AbilityData
var _source: Player


func setup(data: AbilityData, source: Player) -> void:
	_data = data
	_source = source
	radius = data.aoe_radius
	arm_time = data.startup


func _ready() -> void:
	var gold := ArtKit.color("color_roles.resonance.body", Color("#FFC34D"))
	var glyph := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.8, 1.8)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.3
	if ResourceLoader.exists("res://assets/vfx/glyph.png"):
		mat.albedo_texture = load("res://assets/vfx/glyph.png")
	mat.albedo_color = gold
	mat.emission_enabled = true
	mat.emission = gold
	mat.emission_energy_multiplier = 0.8
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.disable_receive_shadows = true
	plane.material = mat
	glyph.mesh = plane
	add_child(glyph)
	glyph.position.y = 0.05
	VFX.player_ring(self, global_position, radius, arm_time, gold)
	Sfx.play("rune_place", global_position, -3.0, 0.05, 0.8)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mat, "emission_energy_multiplier", 3.5, arm_time)
	tw.tween_property(glyph, "rotation:y", -TAU * 0.5, arm_time)
	tw.chain().tween_callback(_pull)


func _pull() -> void:
	var scene := get_tree().current_scene
	var gold := ArtKit.color("color_roles.resonance.body", Color("#FFC34D"))
	VFX.ground_ring(scene, global_position, gold, radius, 0.3)
	VFX.flash(scene, global_position + Vector3(0, 0.6, 0), ArtKit.color("color_roles.resonance.hot", Color("#FFF0B8")), 1.6, 0.15)
	Sfx.play("chain_pull", global_position, -1.0, 0.05, 0.8)
	if visual_only or _source == null or not is_instance_valid(_source):
		queue_free()
		return
	var rb := _source as RunebreakerHero
	var struck := 0
	for e in EnemyBase.all_enemies:
		if not is_instance_valid(e) or e.ai_state == EnemyBase.AIState.DEAD or not e.targetable:
			continue
		var to := e.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d > radius:
			continue
		var hit := _source.roll_ability_hit(_data)
		hit.source_position = global_position
		hit.taunt = rb.taunt_seconds(_data.active) if rb != null else _data.active
		hit.threat_mult = _data.threat_mult
		if d > MIN_GAP + 0.1:
			hit.pull_to = global_position + to / d * maxf(d - PULL, MIN_GAP)
		if e.take_hit(hit):
			struck += 1
	if struck > 0:
		_source.feel_shake(0.25)
	queue_free()
