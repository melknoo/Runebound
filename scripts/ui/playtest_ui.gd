class_name PlaytestUI
extends CanvasLayer
## The PLAYTEST log (key J, user 2026-09-28): every open playtest point from
## docs/KNOWN_ISSUES.md as a checklist (PlaytestLog). Per point a status
## button (offen -> passt -> Problem -> offen) and, for a problem, a note.
## Saves at once to user://playtest.json. Locks combat input like the other
## windows; one window at a time.

const PANEL := Vector2(1040, 680)
const OK_COLOR := Color("#8FD694")
const PROBLEM_COLOR := Color("#E08A7A")

var player: Player
var zone: ZoneBase

var _root: Control
var _summary: Label
var _only_open: CheckButton
var _list: VBoxContainer


func setup(p: Player, z: ZoneBase) -> void:
	player = p
	zone = z
	layer = 8
	_build()
	visible = false


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	if zone != null:
		for other: Variant in [zone.hero_ui, zone.trainer_ui, zone.waypoint_ui, zone.map_ui]:
			if other != null:
				other.call(&"close")
	visible = true
	player.input_locked = true
	_refresh()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	if not visible:
		return
	visible = false
	player.input_locked = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if zone != null and zone.debug_overlay != null and zone.debug_overlay._visible:
		return  # the F1 overlay owns the letter keys while it shows
	if visible and (event.is_action_pressed(&"toggle_cursor") or event.is_action_pressed(&"playtest_toggle")):
		close()
		get_viewport().set_input_as_handled()
	elif not visible and event.is_action_pressed(&"playtest_toggle"):
		if player != null and not player.input_locked and GameSettings.dev_tools():
			open()
			get_viewport().set_input_as_handled()


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
	panel.custom_minimum_size = PANEL
	panel.position = -PANEL * 0.5
	panel.add_theme_stylebox_override("panel", UiTheme.nine("frame.png", 16, 18))
	_root.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	panel.add_child(body)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 20)
	body.add_child(top)
	var title := Label.new()
	title.text = "PLAYTEST"
	title.add_theme_font_override("font", UiTheme.font(true))
	title.add_theme_font_size_override("font_size", UiTheme.TITLE)
	title.add_theme_color_override("font_color", ArtKit.color("color_roles.player_accent.body", Color(0.37, 0.88, 0.91)))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(UiTheme.close_button(close))

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 20)
	body.add_child(bar)
	_summary = Label.new()
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_summary)
	_only_open = CheckButton.new()
	_only_open.text = "nur offene"
	_only_open.toggled.connect(func(_on: bool) -> void: _refresh())
	bar.add_child(_only_open)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(PANEL.x - 40, PANEL.y - 150)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)


func _refresh() -> void:
	var c := PlaytestLog.counts()
	_summary.text = "%d / %d geprüft  ·  %d passt  ·  %d Problem%s  ·  %d offen" % [
		int(c["ok"]) + int(c["problem"]), int(c["total"]), int(c["ok"]), int(c["problem"]),
		"e" if int(c["problem"]) != 1 else "", int(c["open"])]
	for child in _list.get_children():
		_list.remove_child(child)  # out of the list now, not after the frame
		child.queue_free()
	for g: Dictionary in PlaytestLog.groups():
		var gc := PlaytestLog.counts(str(g.get("id", "")))
		var items: Array = g.get("items", [])
		if _only_open.button_pressed and int(gc["open"]) == 0:
			continue
		var header := Label.new()
		header.text = "%s   %d / %d" % [str(g.get("title", "")).to_upper(), int(gc["ok"]) + int(gc["problem"]), int(gc["total"])]
		header.add_theme_color_override("font_color", ArtKit.color("color_roles.resonance.body", Color("#FFC34D")))
		_list.add_child(header)
		for it: Dictionary in items:
			var id := str(it.get("id", ""))
			if _only_open.button_pressed and PlaytestLog.state_of(id) != PlaytestLog.OPEN:
				continue
			_list.add_child(_row(it))


func _row(it: Dictionary) -> Control:
	var id := str(it.get("id", ""))
	var state := PlaytestLog.state_of(id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var status := Button.new()
	status.custom_minimum_size = Vector2(130, 36)
	status.text = {PlaytestLog.OPEN: "offen", PlaytestLog.OK: "passt", PlaytestLog.PROBLEM: "Problem"}[state]
	if state == PlaytestLog.OK:
		status.add_theme_color_override("font_color", OK_COLOR)
	elif state == PlaytestLog.PROBLEM:
		status.add_theme_color_override("font_color", PROBLEM_COLOR)
	else:
		status.add_theme_color_override("font_color", UiTheme.MUTED)
	status.tooltip_text = "Klick: offen -> passt -> Problem -> offen"
	status.pressed.connect(func() -> void:
		PlaytestLog.set_state(id, PlaytestLog.next_state(PlaytestLog.state_of(id)), PlaytestLog.note_of(id))
		Sfx.play_ui("equip", -10.0)
		_refresh())
	status.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(status)

	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var title := Label.new()
	title.text = "%s   (%s)" % [str(it.get("title", "")), str(it.get("src", ""))]
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if state == PlaytestLog.OK:
		title.add_theme_color_override("font_color", UiTheme.MUTED)
	text.add_child(title)
	var hint := Label.new()
	hint.text = str(it.get("hint", ""))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", UiTheme.MUTED)
	text.add_child(hint)
	if state == PlaytestLog.PROBLEM:
		var note := LineEdit.new()
		note.text = PlaytestLog.note_of(id)
		note.placeholder_text = "Was stimmt nicht? (Enter speichert)"
		note.custom_minimum_size = Vector2(0, 36)
		note.text_submitted.connect(func(t: String) -> void:
			PlaytestLog.set_note(id, t)
			note.release_focus())
		note.focus_exited.connect(func() -> void: PlaytestLog.set_note(id, note.text))
		text.add_child(note)
	return row


## Tests: the rows shown right now.
func row_count() -> int:
	var n := 0
	for child in _list.get_children():
		if child is HBoxContainer:
			n += 1
	return n
