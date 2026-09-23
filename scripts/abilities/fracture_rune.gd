class_name FractureRune
extends Node3D
## Ground rune placed at the aim point; arms for ARM_TIME while brightening,
## then detonates: Frost damage + Chill in an AoE. The rune itself is the
## telegraph -- enemies (and the player) can read the timing.

const ARM_TIME := 1.2

var arm_time: float = ARM_TIME  # equipment can shorten this
var _data: AbilityData
var _source: Player


func setup(data: AbilityData, source: Player) -> void:
	_data = data
	_source = source


func _ready() -> void:
	# Glyph plane, teal to white-hot fill while arming.
	var glyph := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.4, 1.4)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.3
	if ResourceLoader.exists("res://assets/vfx/glyph.png"):
		mat.albedo_texture = load("res://assets/vfx/glyph.png")
	mat.albedo_color = Color(0.45, 0.95, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.85, 1.0)
	mat.emission_energy_multiplier = 0.6
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.disable_receive_shadows = true
	plane.material = mat
	glyph.mesh = plane
	add_child(glyph)
	glyph.position.y = 0.05

	# Radius outline so the blast area is readable before it pops.
	# (Player positions the rune before add_child, so global_position is valid.)
	VFX.telegraph_disc(self, global_position, _data.aoe_radius, arm_time, Color(0.5, 0.85, 1.0, 0.18))

	var light := OmniLight3D.new()
	light.light_color = Color(0.5, 0.85, 1.0)
	light.light_energy = 0.8
	light.omni_range = 3.0
	light.shadow_enabled = false
	add_child(light)

	Sfx.play("rune_place", global_position, -4.0)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mat, "emission_energy_multiplier", 3.5, arm_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(light, "light_energy", 2.5, arm_time)
	tw.tween_property(glyph, "rotation:y", TAU * 0.75, arm_time)
	tw.chain().tween_callback(_detonate)


func _detonate() -> void:
	var scene := get_tree().current_scene
	VFX.frost_burst(scene, global_position, _data.aoe_radius)
	Sfx.play("rune_detonate", global_position, 0.0, 0.08)
	GameFeel.camera_shake(0.2)

	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = _data.aoe_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), global_position + Vector3(0, 0.5, 0))
	query.collision_mask = 0b10000
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit_any := false
	for result: Dictionary in space.intersect_shape(query, 16):
		var hb := result["collider"] as Hurtbox
		if hb != null and hb.owner_entity != null and hb.owner_entity.has_method(&"take_hit"):
			var hit := _data.roll_hit(global_position)
			if bool(hb.owner_entity.call(&"take_hit", hit)):
				hit_any = true
				if _source != null and is_instance_valid(_source):
					_source.gain_resonance(6.0)
	if hit_any:
		GameFeel.camera_impulse(Vector3.UP, 0.04)
	queue_free()
