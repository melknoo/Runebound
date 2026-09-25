extends Node
## Autoload "GameFeel": localized hitstop, camera feedback routing, damage numbers.
## Hitstop pauses individual nodes instead of the global timescale so the rest
## of combat keeps flowing (see docs/COMBAT_DESIGN.md).

var camera_rig: Node3D = null

var damage_numbers_enabled: bool = true


## Autoloads leave the tree before engine teardown: release static look caches
## (materials, look-dev lambdas) while the rendering server still exists —
## otherwise the process crashes on quit (0xC0000005).
func _exit_tree() -> void:
	LookDev.clear()
	ArtKit.clear_caches()
	VFX.clear_caches()
	UiTheme.clear()


func hitstop(targets: Array, duration: float = 0.05) -> void:
	# Duck-typed: entities implement apply_hitstop() and freeze themselves
	# without leaving the physics space (process_mode tricks break SpringArm
	# raycasts and area overlaps).
	for t: Variant in targets:
		var node := t as Node
		if node == null or not is_instance_valid(node):
			continue
		if node.has_method(&"apply_hitstop"):
			node.call(&"apply_hitstop", duration)


func camera_impulse(dir: Vector3, strength: float) -> void:
	if camera_rig != null and camera_rig.has_method(&"add_impulse"):
		camera_rig.call(&"add_impulse", dir, strength)


func camera_shake(amount: float) -> void:
	if camera_rig != null and camera_rig.has_method(&"add_trauma"):
		camera_rig.call(&"add_trauma", amount)


## M07: small rising text (XP on kills). Same fixed-size pixel label as the
## damage numbers, slower and quieter.
func float_text(pos: Vector3, text: String, color: Color) -> void:
	if not Net.has_view():
		return  # M09: the dedicated server draws nothing
	if not damage_numbers_enabled:
		return
	var root := get_tree().current_scene
	if root == null:
		return
	var label := Label3D.new()
	label.text = text
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	UiTheme.label3d(label, UiTheme.BODY)
	root.add_child(label)
	label.global_position = pos
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position", pos + Vector3(0, 0.9, 0), 1.1) 		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(label, "modulate:a", 0.0, 0.4).set_delay(0.7)
	tween.chain().tween_callback(label.queue_free)


func damage_number(pos: Vector3, amount: float, color: Color = Color.WHITE, crit: bool = false) -> void:
	if not Net.has_view():
		return  # M09: the dedicated server draws nothing
	if not damage_numbers_enabled:
		return
	var root := get_tree().current_scene
	if root == null:
		return
	var label := Label3D.new()
	label.text = str(int(round(amount)))
	label.font_size = 88 if crit else 52
	label.pixel_size = 0.004
	label.modulate = Color(1.0, 0.9, 0.3) if crit else color
	label.outline_size = 18
	label.outline_modulate = Color(0.08, 0.05, 0.1, 1.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = false
	UiTheme.label3d(label, UiTheme.BIG if crit else UiTheme.BODY)
	root.add_child(label)
	# Slight horizontal scatter keeps rapid hits readable instead of stacking.
	var scatter := Vector3(randf_range(-0.35, 0.35), randf_range(0.0, 0.2), randf_range(-0.2, 0.2))
	label.global_position = pos + Vector3(0, 0.15, 0) + scatter
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position", label.global_position + Vector3(0, 0.8, 0), 0.55) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(label, "modulate:a", 0.0, 0.25).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)
