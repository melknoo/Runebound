class_name ShadowRune
extends Node3D
## Enemy ground hazard (Vessel boss): violet rune that arms visibly for
## ARM_TIME, then detonates against the player. The mirror of FractureRune.

const ARM_TIME := 1.2
const RADIUS := 2.5
const DAMAGE := 18.0


func _ready() -> void:
	var glyph := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.4, 1.4)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.3
	if ResourceLoader.exists("res://assets/vfx/glyph.png"):
		mat.albedo_texture = load("res://assets/vfx/glyph.png")
	mat.albedo_color = Color(0.75, 0.4, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.7, 0.35, 1.0)
	mat.emission_energy_multiplier = 0.6
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.disable_receive_shadows = true
	plane.material = mat
	glyph.mesh = plane
	glyph.position.y = 0.05
	add_child(glyph)

	VFX.telegraph_disc(self, global_position, RADIUS, ARM_TIME, Color(0.7, 0.35, 1.0, 0.2))
	Sfx.play("rune_place", global_position, -8.0, 0.1, 0.7)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mat, "emission_energy_multiplier", 3.2, ARM_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(glyph, "rotation:y", -TAU * 0.75, ARM_TIME)
	tw.chain().tween_callback(_detonate)


func _detonate() -> void:
	var scene := get_tree().current_scene
	VFX.flash(scene, global_position + Vector3(0, 0.4, 0), Color(0.85, 0.55, 1.0), 1.5, 0.14)
	VFX.light_pop(scene, global_position, Color(0.7, 0.35, 1.0), 4.0, 5.0, 0.25)
	VFX.ground_ring(scene, global_position, Color(0.75, 0.4, 1.0, 0.9), RADIUS, 0.3)
	VFX.burst(scene, global_position + Vector3(0, 0.3, 0), {
		"tex": "shard", "amount": 14, "lifetime": 0.5, "size": 0.2,
		"direction": Vector3.UP, "spread": 70.0,
		"vel_min": 3.0, "vel_max": 7.0, "gravity": Vector3(0, -14, 0),
		"colors": [Color(0.9, 0.7, 1.0), Color(0.6, 0.3, 0.9), Color(0.3, 0.15, 0.5, 0.0)] as Array[Color],
	})
	Sfx.play("rune_detonate", global_position, -4.0, 0.1, 0.8)

	var zone := get_tree().current_scene as ZoneBase
	if zone != null and zone.player != null and is_instance_valid(zone.player) \
			and zone.player.global_position.distance_to(global_position) <= RADIUS:
		var hit := HitInfo.create(DAMAGE, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.MEDIUM, global_position)
		hit.knockback = 4.0
		zone.player.take_hit(hit)
	queue_free()
