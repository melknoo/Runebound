class_name TalentUI
extends CanvasLayer
## M07 talent panel (`N`): three branch columns of tiered nodes. Left click
## learns a rank, right click removes one, Respec returns every point.
## Locks combat input and frees the mouse while open (like the inventory).

const ACTION := &"talents_toggle"
const BRANCH_COLORS := ["color_roles.lightning.body", "color_roles.fire.body", "color_roles.frost.body"]

var player: Player

var _root: Control
var _header: Label
var _detail_title: Label
var _detail_text: Label
var _columns: Array[VBoxContainer] = []
var _buttons: Dictionary = {}  # talent id -> Button
var _hovered: TalentData = null


func setup(p: Player) -> void:
	player = p
	layer = 8
	player.progression.talents_changed.connect(_refresh)
	_build()
	visible = false


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	UiTheme.apply(_root)
	add_child(_root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.01, 0.04, 0.6)
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(1120, 620)
	panel.position = Vector2(-560, -310)
	panel.add_theme_stylebox_override("panel", UiTheme.nine("frame.png", 16, 18))
	_root.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	panel.add_child(body)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 24)
	body.add_child(top)
	var title := Label.new()
	title.text = "TALENTS"
	title.add_theme_font_override("font", UiTheme.font(true))
	title.add_theme_font_size_override("font_size", UiTheme.TITLE)
	title.add_theme_color_override("font_color", ArtKit.color("color_roles.player_accent.body"))
	top.add_child(title)
	_header = Label.new()
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(_header)
	var respec := Button.new()
	respec.text = "Respec"
	respec.pressed.connect(func() -> void:
		player.progression.respec()
		Sfx.play_ui("equip", -6.0)
	)
	top.add_child(respec)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 20)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(cols)
	for b in 3:
		var col := VBoxContainer.new()
		col.custom_minimum_size = Vector2(350, 0)
		col.add_theme_constant_override("separation", 6)
		cols.add_child(col)
		var name_label := Label.new()
		name_label.text = TalentData.branch_name(b).to_upper()
		name_label.add_theme_font_override("font", UiTheme.font(true))
		name_label.add_theme_font_size_override("font_size", UiTheme.TITLE)
		name_label.add_theme_color_override("font_color", ArtKit.color(BRANCH_COLORS[b]))
		col.add_child(name_label)
		_columns.append(col)

	_detail_title = Label.new()
	_detail_title.add_theme_color_override("font_color", ArtKit.color("color_roles.resonance.hot"))
	body.add_child(_detail_title)
	_detail_text = Label.new()
	_detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_text.custom_minimum_size = Vector2(1080, 44)
	body.add_child(_detail_text)

	for t in Progression.tree():
		var col := _columns[t.branch]
		var btn := Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(350, 0)
		btn.mouse_entered.connect(func() -> void:
			_hovered = t
			_render_detail()
		)
		btn.gui_input.connect(func(event: InputEvent) -> void:
			var mb := event as InputEventMouseButton
			if mb == null or not mb.pressed:
				return
			if mb.button_index == MOUSE_BUTTON_LEFT:
				try_learn(t)
			elif mb.button_index == MOUSE_BUTTON_RIGHT:
				try_unlearn(t)
		)
		col.add_child(btn)
		_buttons[t.id] = btn
	_refresh()


func try_learn(t: TalentData) -> bool:
	var ok := player.progression.learn(t)
	Sfx.play_ui("equip" if ok else "ui_denied", -6.0)
	return ok


func try_unlearn(t: TalentData) -> bool:
	var ok := player.progression.unlearn(t)
	Sfx.play_ui("pickup" if ok else "ui_denied", -8.0)
	return ok


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION):
		toggle()


func toggle() -> void:
	visible = not visible
	player.input_locked = visible
	if visible:
		var zone := get_parent() as ZoneBase
		if zone != null and zone.inventory_ui != null and zone.inventory_ui.visible:
			zone.inventory_ui.toggle()  # one panel at a time
			player.input_locked = true
		_refresh()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED


func _refresh() -> void:
	if player == null:
		return
	var prog := player.progression
	_header.text = "Level %d    %d point%s free    (left click: learn, right click: remove)" % [
		prog.level, prog.points_free(), "" if prog.points_free() == 1 else "s"]
	for t in Progression.tree():
		var btn := _buttons[t.id] as Button
		var r := prog.rank(t.id)
		var tier_label := "" if t.tier == 0 else ("%d+ " % TalentData.TIER_POINTS[t.tier])
		btn.text = "%s%s   %d/%d" % [tier_label, t.display_name, r, t.max_rank]
		var open := prog.tier_open(t)
		var learnable := prog.can_learn(t)
		var color := ArtKit.color(BRANCH_COLORS[t.branch])
		if r >= t.max_rank:
			btn.add_theme_color_override("font_color", color)
		elif learnable:
			btn.add_theme_color_override("font_color", Color(0.93, 0.9, 0.84))
		elif open:
			btn.add_theme_color_override("font_color", Color(0.7, 0.68, 0.74))
		else:
			btn.add_theme_color_override("font_color", Color(0.42, 0.4, 0.48))
	_render_detail()


func _render_detail() -> void:
	if _hovered == null:
		_detail_title.text = ""
		_detail_text.text = "Hover a talent for details. The number before a name is the points its tier needs."
		return
	var t := _hovered
	var r := player.progression.rank(t.id)
	_detail_title.text = "%s  -  %s, rank %d/%d" % [t.display_name, TalentData.branch_name(t.branch), r, t.max_rank]
	var now := t.describe(r) if r > 0 else ""
	var next := t.describe(r + 1) if r < t.max_rank else ""
	var lines: Array[String] = []
	if now != "":
		lines.append("Now: " + now)
	if next != "":
		lines.append(("Next: " if r > 0 else "") + next)
	if not player.progression.tier_open(t):
		lines.append("Needs %d points in %s below this tier." % [TalentData.TIER_POINTS[t.tier], TalentData.branch_name(t.branch)])
	_detail_text.text = "   ".join(lines)
