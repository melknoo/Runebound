class_name Hud
extends CanvasLayer
## Combat HUD (M06 v2, ART_BIBLE section 11): framed health + Resonance bars,
## pixel ability icons with a radial cooldown sweep and key labels, themed
## tooltip, boss bar, toasts. Pixel fonts and frames come from UiTheme.

var player: Player

var _health_fill: ColorRect
var _resonance_fill: ColorRect
var _xp_fill: ColorRect
var _level_label: Label
var _cost_tick: ColorRect
var _hurt_flash: ColorRect
var _slots: Dictionary = {}  # id -> {overlay, slot, icon, key, name, desc, type, data}
var _toast_box: VBoxContainer
var _slot_row: HBoxContainer
const TALENT_SLOTS: Array[StringName] = [&"runic_guard", &"resonance_burst"]

# Ability tooltip: names stay off the combat screen and only appear while the
# inventory is open (cursor free) and the mouse hovers a slot.
var _tooltip: PanelContainer
var _tooltip_title: Label
var _tooltip_meta: Label
var _tooltip_desc: Label
var _tooltip_stats: Label
var _tooltip_id: StringName = &""

const BAR_WIDTH := 360.0
const HEALTH_HEIGHT := 26.0
const RESONANCE_HEIGHT := 20.0
const XP_HEIGHT := 14.0
## Inner inset of the 2x pixel bar frame (bar.png margin).
const BAR_INSET := 6.0
const SLOT_SIZE := 44.0
const SLOT_GAP := 10.0
const TOOLTIP_WIDTH := 300.0
## Above the inventory (8), below the debug overlay (10) and travel fade (20).
const TOOLTIP_LAYER := 9
const ICON_DIR := "res://assets/ui/icons/"


func ability_names() -> Array[String]:
	var out: Array[String] = []
	for id: StringName in _slots:
		if (_slots[id]["slot"] as Control).visible:  # talent abilities only once learned
			out.append(_slots[id]["name"] as String)
	return out


## Screen rect of an ability slot (tests use it to simulate hovering).
func slot_rect(id: StringName) -> Rect2:
	return (_slots[id]["slot"] as Control).get_global_rect()


func tooltip_visible() -> bool:
	return _tooltip != null and _tooltip.visible


func tooltip_title() -> String:
	return _tooltip_title.text if _tooltip_title != null else ""


func setup(p: Player) -> void:
	player = p
	player.health_changed.connect(_on_health_changed)
	player.resonance_changed.connect(_on_resonance_changed)
	player.progression.xp_changed.connect(_on_xp_changed)
	player.progression.leveled_up.connect(_on_level_up)
	_build()
	_on_health_changed(player.health.current_health, player.health.max_health)
	_on_resonance_changed(player.resonance, Player.MAX_RESONANCE)
	var prog := player.progression
	_on_xp_changed(prog.xp, Progression.xp_to_next(prog.level), prog.level)


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.apply(root)
	add_child(root)

	_hurt_flash = ColorRect.new()
	_hurt_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hurt_flash.color = Color(0.8, 0.1, 0.1, 0.0)
	_hurt_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hurt_flash)

	# Bottom-center cluster: bars above the ability slots.
	var cluster := VBoxContainer.new()
	cluster.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	cluster.position = Vector2(-BAR_WIDTH * 0.5, -176)
	cluster.custom_minimum_size = Vector2(BAR_WIDTH, 0)
	cluster.add_theme_constant_override("separation", 4)
	cluster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cluster)

	_health_fill = _bar(cluster, HEALTH_HEIGHT, Color("#D8404A"), Color("#5A1A22"))
	var resonance := ArtKit.color("color_roles.resonance.body", Color("#FFC34D"))
	_resonance_fill = _bar(cluster, RESONANCE_HEIGHT, resonance, resonance.darkened(0.7))
	# Earthbreaker's cost marked on the Resonance bar: affordable = past the tick.
	_cost_tick = ColorRect.new()
	_cost_tick.color = ArtKit.color("color_roles.resonance.hot", Color("#FFF0B8"))
	_cost_tick.size = Vector2(2, RESONANCE_HEIGHT - BAR_INSET * 2.0 + 4.0)
	_cost_tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_resonance_fill.get_parent().add_child(_cost_tick)
	# M07: thin experience bar under Resonance, level badge left of the bars.
	var xp_color := ArtKit.color("color_roles.experience.body", Color("#9FB4FF"))
	_xp_fill = _bar(cluster, XP_HEIGHT, xp_color, xp_color.darkened(0.75))
	_level_label = Label.new()
	_level_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_level_label.position = Vector2(-BAR_WIDTH * 0.5 - 70, -150)
	_level_label.custom_minimum_size = Vector2(62, 0)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_level_label.add_theme_color_override("font_color", xp_color.lightened(0.3))
	_level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_level_label)

	# Ability row: icon + key only. Names live in the hover tooltip.
	var slot_row := HBoxContainer.new()
	slot_row.add_theme_constant_override("separation", SLOT_GAP)
	slot_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	var row_width := SLOT_SIZE * 7 + SLOT_GAP * 6
	slot_row.position = Vector2(-row_width * 0.5, -98)
	root.add_child(slot_row)

	_add_slot(slot_row, &"melee", "LMB", player.cleave)
	_add_slot(slot_row, &"ember", "RMB", player.ember)
	_add_slot(slot_row, &"earthbreaker", InputSetup.key_label(&"ability_q"), player.earthbreaker)
	_add_slot(slot_row, &"storm_step", InputSetup.key_label(&"ability_e"), player.storm_step)
	_add_slot(slot_row, &"chain_spark", InputSetup.key_label(&"ability_r"), player.chain_spark)
	_add_slot(slot_row, &"fracture_rune", InputSetup.key_label(&"ability_f"), player.fracture_rune)
	_add_slot(slot_row, &"dodge", "SPC", null)
	# M07 talent abilities: slots appear once their talent is learned.
	_add_slot(slot_row, &"runic_guard", InputSetup.key_label(&"ability_runic_guard"), player.runic_guard)
	_add_slot(slot_row, &"resonance_burst", InputSetup.key_label(&"ability_resonance_burst"), player.resonance_burst)
	_slot_row = slot_row
	player.progression.talents_changed.connect(_refresh_talent_slots)
	_refresh_talent_slots()

	# Pickup toasts, top-center.
	_toast_box = VBoxContainer.new()
	_toast_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_box.position = Vector2(-240, 64)
	_toast_box.custom_minimum_size = Vector2(480, 0)
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toast_box)

	# Added last: the root Control must stay child 0 (show_boss_bar relies on it).
	_build_tooltip()


var _boss_root: VBoxContainer
var _boss_name: Label
var _boss_fill: ColorRect

const BOSS_BAR_WIDTH := 600.0


func show_boss_bar(boss_name: String) -> void:
	if _boss_root == null:
		_boss_root = VBoxContainer.new()
		_boss_root.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_boss_root.position = Vector2(-BOSS_BAR_WIDTH * 0.5, 12)
		_boss_root.custom_minimum_size = Vector2(BOSS_BAR_WIDTH, 0)
		_boss_root.add_theme_constant_override("separation", 0)
		_boss_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		(get_child(0) as Control).add_child(_boss_root)
		_boss_name = Label.new()
		_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_boss_name.add_theme_font_override("font", UiTheme.font(true))
		_boss_name.add_theme_font_size_override("font_size", UiTheme.TITLE)
		_boss_name.add_theme_color_override("font_color", Color("#F2B27A"))
		_boss_root.add_child(_boss_name)
		# Enemy health = the threat colour (a bar: a shape no telegraph shares).
		_boss_fill = _bar(_boss_root, 26.0, ArtKit.color("color_roles.threat.body", Color("#E8283C")), Color("#3A0E16"),
			BOSS_BAR_WIDTH)
	_boss_name.text = boss_name
	_boss_fill.size.x = BOSS_BAR_WIDTH - BAR_INSET * 2.0
	_boss_root.visible = true


func update_boss_bar(current: float, maximum: float) -> void:
	if _boss_fill != null:
		_boss_fill.size.x = (BOSS_BAR_WIDTH - BAR_INSET * 2.0) * clampf(current / maximum, 0.0, 1.0)


func hide_boss_bar() -> void:
	if _boss_root != null:
		_boss_root.visible = false


func toast(text: String, color: Color = Color.WHITE) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", color)
	_toast_box.add_child(label)
	if _toast_box.get_child_count() > 4:
		_toast_box.get_child(0).queue_free()
	var tw := label.create_tween()
	tw.tween_property(label, "modulate:a", 0.0, 0.5).set_delay(2.2)
	tw.tween_callback(label.queue_free)


## Framed pixel bar: returns the fill rect (its width is set by callers).
func _bar(parent: Control, height: float, fill_color: Color, back_color: Color, width: float = BAR_WIDTH) -> ColorRect:
	var frame := NinePatchRect.new()
	frame.texture = load(UiTheme.UI_DIR + "bar.png")
	frame.patch_margin_left = int(BAR_INSET)
	frame.patch_margin_top = int(BAR_INSET)
	frame.patch_margin_right = int(BAR_INSET)
	frame.patch_margin_bottom = int(BAR_INSET)
	frame.custom_minimum_size = Vector2(width, height)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(frame)
	var back := ColorRect.new()
	back.color = back_color
	back.position = Vector2(BAR_INSET, BAR_INSET)
	back.size = Vector2(width - BAR_INSET * 2.0, height - BAR_INSET * 2.0)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(back)
	var fill := ColorRect.new()
	fill.color = fill_color
	fill.position = back.position
	fill.size = back.size
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(fill)
	# 1-px highlight along the top of the fill: pixel-art bar, not a flat block
	var shine := ColorRect.new()
	shine.color = Color(1, 1, 1, 0.22)
	shine.size = Vector2(back.size.x, 2)
	shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.add_child(shine)
	fill.resized.connect(func() -> void: shine.size.x = fill.size.x)
	return fill


func _add_slot(parent: Control, id: StringName, key_label: String, data: AbilityData) -> void:
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(slot)

	var frame := TextureRect.new()
	frame.texture = load(UiTheme.UI_DIR + "slot.png")
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(frame)

	var icon := TextureRect.new()
	var icon_path := ICON_DIR + String(id) + ".png"
	if ResourceLoader.exists(icon_path):
		icon.texture = load(icon_path)
	icon.position = Vector2(2, 2)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(icon)

	# Radial sweep over the icon: the dark wedge is the cooldown still left.
	var sweep := TextureProgressBar.new()
	sweep.fill_mode = TextureProgressBar.FILL_COUNTER_CLOCKWISE
	sweep.texture_progress = load(UiTheme.UI_DIR + "cooldown.png")
	sweep.position = Vector2(2, 2)
	sweep.max_value = 100.0
	sweep.value = 0.0
	sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(sweep)

	var label := Label.new()
	label.text = key_label
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.offset_right = 1
	label.offset_bottom = 5
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(label)

	var entry := {"overlay": sweep, "slot": slot, "icon": icon, "key": key_label, "data": data}
	if data != null:
		entry["name"] = data.display_name
		entry["desc"] = data.description
		entry["type"] = data.damage_type
	else:  # Dodge has no AbilityData.
		entry["name"] = "Dodge"
		entry["desc"] = "Quick evasive dash with brief invulnerability. Cancels attack recovery."
		entry["type"] = -1
	_slots[id] = entry


func _build_tooltip() -> void:
	var layer := CanvasLayer.new()
	layer.layer = TOOLTIP_LAYER
	add_child(layer)
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.apply(holder)
	layer.add_child(holder)

	_tooltip = PanelContainer.new()
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.custom_minimum_size = Vector2(TOOLTIP_WIDTH, 0)
	_tooltip.visible = false
	holder.add_child(_tooltip)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.add_child(box)

	_tooltip_title = _tooltip_label(box, UiTheme.TEXT)
	_tooltip_meta = _tooltip_label(box, UiTheme.MUTED)
	_tooltip_desc = _tooltip_label(box, Color("#D8D2E0"))
	_tooltip_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tooltip_desc.custom_minimum_size = Vector2(TOOLTIP_WIDTH - 24, 0)
	_tooltip_stats = _tooltip_label(box, ArtKit.color("color_roles.player_accent.hot", Color("#9FF2E6")))


func _tooltip_label(parent: Control, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


## Shows the tooltip for the slot under `mouse_pos` — only while the inventory
## has the cursor (player.input_locked). The inventory's full-rect root blocks
## mouse events from reaching this layer, so hovering is a manual rect test.
func _update_tooltip(mouse_pos: Vector2) -> void:
	var hovered: StringName = &""
	if player.input_locked:
		for id: StringName in _slots:
			if slot_rect(id).has_point(mouse_pos):
				hovered = id
				break
	if hovered == &"":
		_tooltip.visible = false
		_tooltip_id = &""
		return
	if hovered != _tooltip_id:
		_tooltip_id = hovered
		_fill_tooltip(hovered)
	_tooltip.visible = true
	# Shrink to content every frame: the autowrapped description reports a tall
	# minimum height until it has been laid out at its final width once.
	_tooltip.size = Vector2.ZERO
	_tooltip.position = tooltip_position(slot_rect(hovered), _tooltip.size,
		get_viewport().get_visible_rect().size)


## Centered above the slot, kept inside the screen with an 8 px margin.
static func tooltip_position(slot: Rect2, tip_size: Vector2, view: Vector2) -> Vector2:
	var pos := Vector2(slot.get_center().x - tip_size.x * 0.5, slot.position.y - tip_size.y - 10.0)
	pos.x = clampf(pos.x, 8.0, maxf(view.x - tip_size.x - 8.0, 8.0))
	pos.y = maxf(pos.y, 8.0)
	return pos


func _fill_tooltip(id: StringName) -> void:
	var entry: Dictionary = _slots[id]
	_tooltip_title.text = entry["name"]
	var type: int = entry["type"]
	if type < 0:
		_tooltip_meta.text = "%s  ·  Evasion" % entry["key"]
		_tooltip_meta.add_theme_color_override("font_color", ArtKit.color("color_roles.player_accent.body", Color(0.55, 0.8, 0.8)))
	else:
		var element: String = (HitInfo.DamageType.keys()[type] as String).capitalize()
		_tooltip_meta.text = "%s  ·  %s" % [entry["key"], element]
		_tooltip_meta.add_theme_color_override("font_color", HitInfo.type_color(type as HitInfo.DamageType))
	_tooltip_desc.text = entry["desc"]
	_tooltip_stats.text = _stats_line(id, entry["data"] as AbilityData)
	_tooltip.reset_size()


func _stats_line(id: StringName, data: AbilityData) -> String:
	var parts: PackedStringArray = []
	if data == null:
		parts.append("Cooldown %ss" % String.num(Player.DODGE_COOLDOWN, 2))
		return "  ·  ".join(parts)
	var cost := player.earthbreaker_cost() if id == &"earthbreaker" else data.resonance_cost
	if cost > 0.0:
		parts.append("Costs %s Resonance" % String.num(cost, 0))
	if data.cooldown > 0.0:
		parts.append("Cooldown %ss" % String.num(data.cooldown, 2))
	if data.resonance_gain_per_hit > 0.0:
		parts.append("+%s Resonance per hit" % String.num(data.resonance_gain_per_hit, 0))
	return "  ·  ".join(parts)


func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	for id: StringName in _slots.keys():
		var sweep := _slots[id]["overlay"] as TextureProgressBar
		var icon := _slots[id]["icon"] as TextureRect
		sweep.value = player.cooldown_fraction(id) * 100.0
		# Earthbreaker also dims fully while Resonance is below its cost.
		if id == &"earthbreaker":
			var starved := player.resonance < player.earthbreaker_cost()
			if starved:
				sweep.value = 100.0
			icon.modulate = Color(0.6, 0.6, 0.65) if starved else Color.WHITE
	if _hurt_flash.color.a > 0.0:
		_hurt_flash.color.a = maxf(_hurt_flash.color.a - _delta * 1.4, 0.0)
	_update_tooltip(get_viewport().get_mouse_position())


func _on_health_changed(current: float, maximum: float) -> void:
	var frac := clampf(current / maximum, 0.0, 1.0)
	_health_fill.size.x = (BAR_WIDTH - BAR_INSET * 2.0) * frac
	if frac < 1.0:
		_hurt_flash.color.a = maxf(_hurt_flash.color.a, 0.22)


## Talent abilities show only once learned; the row stays centred.
func _refresh_talent_slots() -> void:
	var shown := 7
	for id in TALENT_SLOTS:
		var visible_now := player.has_power(id)
		(_slots[id]["slot"] as Control).visible = visible_now
		if visible_now:
			shown += 1
	var row_width := SLOT_SIZE * shown + SLOT_GAP * (shown - 1)
	# offsets, not position: once laid out, position is in parent space
	_slot_row.offset_left = -row_width * 0.5
	_slot_row.offset_right = row_width * 0.5


func _on_xp_changed(xp: int, needed: int, level: int) -> void:
	var at_cap := level >= Progression.LEVEL_CAP
	_xp_fill.size.x = (BAR_WIDTH - BAR_INSET * 2.0) * (1.0 if at_cap else clampf(float(xp) / maxf(float(needed), 1.0), 0.0, 1.0))
	_level_label.text = "LV %d" % level


func _on_level_up(level: int) -> void:
	var free := player.progression.points_free()
	toast("LEVEL %d" % level, ArtKit.color("color_roles.resonance.hot", Color("#FFF0B8")))
	if free > 0:
		toast("Talent point%s ready (%d)  -  N" % ["s" if free > 1 else "", free],
			ArtKit.color("color_roles.experience.body", Color("#9FB4FF")))
	Sfx.play_ui("level_up", -4.0)
	var scene := get_tree().current_scene
	var at := player.global_position
	VFX.flash(scene, at + Vector3(0, 1.2, 0), ArtKit.color("color_roles.resonance.hot"), 1.6, 0.25)
	VFX.ground_ring(scene, at, ArtKit.color("color_roles.resonance.body"), 3.2, 0.45)


## Place name on arrival (Jacquard), optional subtitle (discovery XP).
func title_card(title: String, subtitle: String = "") -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	box.position = Vector2(-400, 120)
	box.custom_minimum_size = Vector2(800, 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.modulate.a = 0.0
	get_child(0).add_child(box)
	var label := Label.new()
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", UiTheme.HUGE)  # Pixelify: blackletter read badly
	label.add_theme_constant_override("outline_size", UiTheme.OUTLINE * 2)
	label.add_theme_color_override("font_outline_color", UiTheme.INK)
	label.add_theme_color_override("font_color", ArtKit.color("color_roles.player_accent.hot", Color("#9FF2E6")))
	box.add_child(label)
	if subtitle != "":
		var sub := Label.new()
		sub.text = subtitle
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.add_theme_color_override("font_color", ArtKit.color("color_roles.experience.body", Color("#9FB4FF")))
		box.add_child(sub)
	var tw := box.create_tween()
	tw.tween_property(box, "modulate:a", 1.0, 0.6).set_delay(0.3)
	tw.tween_interval(2.2)
	tw.tween_property(box, "modulate:a", 0.0, 0.9)
	tw.tween_callback(box.queue_free)


func _on_resonance_changed(current: float, maximum: float) -> void:
	var inner := BAR_WIDTH - BAR_INSET * 2.0
	_resonance_fill.size.x = inner * clampf(current / maximum, 0.0, 1.0)
	if _cost_tick != null:
		_cost_tick.position = Vector2(BAR_INSET + inner * clampf(player.earthbreaker_cost() / maximum, 0.0, 1.0) - 1.0,
			BAR_INSET - 2.0)
