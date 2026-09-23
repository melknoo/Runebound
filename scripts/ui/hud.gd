class_name Hud
extends CanvasLayer
## Minimal combat HUD: health, Resonance, ability cooldowns, hurt flash.

var player: Player

var _health_fill: ColorRect
var _health_back: ColorRect
var _resonance_fill: ColorRect
var _resonance_back: ColorRect
var _hurt_flash: ColorRect
var _slots: Dictionary = {}  # id -> {overlay: ColorRect, label: Label}
var _toast_box: VBoxContainer

const BAR_WIDTH := 340.0
const SLOT_SIZE := 44.0
const SLOT_COLUMN := 84.0  # wide enough for "Fracture Rune" at font 12
const SLOT_GAP := 4.0


func ability_names() -> Array[String]:
	var out: Array[String] = []
	for id: StringName in _slots:
		out.append((_slots[id]["name"] as Label).text)
	return out


func setup(p: Player) -> void:
	player = p
	player.health_changed.connect(_on_health_changed)
	player.resonance_changed.connect(_on_resonance_changed)
	_build()
	_on_health_changed(player.health.current_health, player.health.max_health)
	_on_resonance_changed(player.resonance, Player.MAX_RESONANCE)


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_hurt_flash = ColorRect.new()
	_hurt_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hurt_flash.color = Color(0.8, 0.1, 0.1, 0.0)
	_hurt_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hurt_flash)

	# Bottom-center cluster: bars above ability slots.
	var cluster := VBoxContainer.new()
	cluster.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	cluster.position = Vector2(-BAR_WIDTH * 0.5, -150)
	cluster.custom_minimum_size = Vector2(BAR_WIDTH, 0)
	cluster.add_theme_constant_override("separation", 8)
	cluster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cluster)

	_health_back = _bar(cluster, Color(0.12, 0.08, 0.1, 0.85), 18.0)
	_health_fill = _fill(_health_back, Color(0.85, 0.25, 0.28))
	_resonance_back = _bar(cluster, Color(0.08, 0.09, 0.13, 0.85), 12.0)
	_resonance_fill = _fill(_resonance_back, Color(1.0, 0.62, 0.22))

	# Ability row sits below the bars in its own centered strip: with names
	# under each slot it is wider than the bars.
	var slot_row := HBoxContainer.new()
	slot_row.add_theme_constant_override("separation", SLOT_GAP)
	slot_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	var row_width := SLOT_COLUMN * 7 + SLOT_GAP * 6
	slot_row.position = Vector2(-row_width * 0.5, -96)
	root.add_child(slot_row)

	_add_slot(slot_row, &"melee", "LMB", player.cleave.display_name, Color(0.5, 0.55, 0.65))
	_add_slot(slot_row, &"ember", "RMB", player.ember.display_name, Color(0.9, 0.5, 0.2))
	_add_slot(slot_row, &"earthbreaker", "Q", player.earthbreaker.display_name, Color(0.7, 0.55, 0.35))
	_add_slot(slot_row, &"storm_step", "E", player.storm_step.display_name, Color(0.65, 0.75, 0.95))
	_add_slot(slot_row, &"chain_spark", "R", player.chain_spark.display_name, Color(0.85, 0.85, 0.4))
	_add_slot(slot_row, &"fracture_rune", "F", player.fracture_rune.display_name, Color(0.45, 0.75, 0.9))
	_add_slot(slot_row, &"dodge", "SPC", "Dodge", Color(0.4, 0.7, 0.7))

	# Pickup toasts, top-center.
	_toast_box = VBoxContainer.new()
	_toast_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_box.position = Vector2(-200, 60)
	_toast_box.custom_minimum_size = Vector2(400, 0)
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toast_box)


var _boss_root: VBoxContainer
var _boss_name: Label
var _boss_fill: ColorRect

const BOSS_BAR_WIDTH := 560.0


func show_boss_bar(boss_name: String) -> void:
	if _boss_root == null:
		_boss_root = VBoxContainer.new()
		_boss_root.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_boss_root.position = Vector2(-BOSS_BAR_WIDTH * 0.5, 18)
		_boss_root.custom_minimum_size = Vector2(BOSS_BAR_WIDTH, 0)
		_boss_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		(get_child(0) as Control).add_child(_boss_root)
		_boss_name = Label.new()
		_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_boss_name.add_theme_color_override("font_color", Color(1.0, 0.55, 0.25))
		_boss_name.add_theme_font_size_override("font_size", 24)
		_boss_root.add_child(_boss_name)
		var back := ColorRect.new()
		back.color = Color(0.1, 0.05, 0.08, 0.9)
		back.custom_minimum_size = Vector2(BOSS_BAR_WIDTH, 16)
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_boss_root.add_child(back)
		_boss_fill = ColorRect.new()
		_boss_fill.color = Color(0.9, 0.3, 0.15)
		_boss_fill.position = Vector2(2, 2)
		_boss_fill.size = Vector2(BOSS_BAR_WIDTH - 4, 12)
		_boss_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		back.add_child(_boss_fill)
	_boss_name.text = boss_name
	_boss_fill.size.x = BOSS_BAR_WIDTH - 4
	_boss_root.visible = true


func update_boss_bar(current: float, maximum: float) -> void:
	if _boss_fill != null:
		_boss_fill.size.x = (BOSS_BAR_WIDTH - 4) * clampf(current / maximum, 0.0, 1.0)


func hide_boss_bar() -> void:
	if _boss_root != null:
		_boss_root.visible = false


func toast(text: String, color: Color = Color.WHITE) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 20)
	_toast_box.add_child(label)
	if _toast_box.get_child_count() > 4:
		_toast_box.get_child(0).queue_free()
	var tw := label.create_tween()
	tw.tween_property(label, "modulate:a", 0.0, 0.5).set_delay(2.2)
	tw.tween_callback(label.queue_free)


func _bar(parent: Control, back_color: Color, height: float) -> ColorRect:
	var back := ColorRect.new()
	back.color = back_color
	back.custom_minimum_size = Vector2(BAR_WIDTH, height)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(back)
	return back


func _fill(back: ColorRect, color: Color) -> ColorRect:
	var fill := ColorRect.new()
	fill.color = color
	fill.position = Vector2(2, 2)
	fill.size = Vector2(back.custom_minimum_size.x - 4, back.custom_minimum_size.y - 4)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(fill)
	return fill


func _add_slot(parent: Control, id: StringName, key_label: String, ability_name: String, color: Color) -> void:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(SLOT_COLUMN, 0)
	column.add_theme_constant_override("separation", 3)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(column)

	var slot := Panel.new()
	slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = color.darkened(0.35)
	style.border_color = color.lightened(0.2)
	style.set_border_width_all(2)
	slot.add_theme_stylebox_override("panel", style)
	column.add_child(slot)

	var name_label := Label.new()
	name_label.text = ability_name
	name_label.name = "AbilityName"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", color.lightened(0.45))
	name_label.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.06))
	name_label.add_theme_constant_override("outline_size", 4)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(name_label)

	var overlay := ColorRect.new()
	overlay.color = Color(0.05, 0.05, 0.08, 0.75)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(overlay)

	var label := Label.new()
	label.text = key_label
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.position -= Vector2(14, 12)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(label)

	_slots[id] = {"overlay": overlay, "slot": slot, "name": name_label}


func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	for id: StringName in _slots.keys():
		var frac := player.cooldown_fraction(id)
		var overlay := _slots[id]["overlay"] as ColorRect
		overlay.anchor_top = 1.0 - frac
		overlay.offset_top = 0
		# Earthbreaker also greys out when Resonance is too low.
		if id == &"earthbreaker" and player.resonance < player.earthbreaker_cost():
			overlay.anchor_top = 0.0
			overlay.color.a = 0.85
		elif id == &"earthbreaker":
			overlay.color.a = 0.75
	if _hurt_flash.color.a > 0.0:
		_hurt_flash.color.a = maxf(_hurt_flash.color.a - _delta * 1.4, 0.0)


func _on_health_changed(current: float, maximum: float) -> void:
	var frac := clampf(current / maximum, 0.0, 1.0)
	_health_fill.size.x = (BAR_WIDTH - 4) * frac
	if frac < 1.0:
		_hurt_flash.color.a = maxf(_hurt_flash.color.a, 0.22)


func _on_resonance_changed(current: float, maximum: float) -> void:
	_resonance_fill.size.x = (BAR_WIDTH - 4) * clampf(current / maximum, 0.0, 1.0)
