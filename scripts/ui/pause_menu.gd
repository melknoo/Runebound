class_name PauseMenu
extends CanvasLayer
## M17a: the Esc menu in a zone. Solo it pauses the world; online the world
## keeps moving and the hero only stands still (input locked), which the menu
## says. Resume, Settings, Back to title (solo: save first; online: leave the
## server) and Quit. Esc reaches it only when no window took the key first
## (ZoneBase adds it before the windows: later siblings see input first);
## while it shows it owns Esc (back out of the settings, then close).
## Solo it also opens when the window loses focus (GameSettings).

## True while a menu shows: window hotkeys (I, C, N, K, M, J, F1, Tab, the
## zoom) stay quiet under it, also online where nothing is paused.
static var showing: bool = false

var zone: ZoneBase

var _root: Control
var _panel: PanelContainer
var _title: Label
var _who: Label
var _note: Label
var _resume_btn: Button
var _back_btn: Button
var _quit_btn: Button
var _settings: SettingsUI
## Online the hero was already locked by something else (keep it so on close).
var _was_locked: bool = false


func setup(z: ZoneBase) -> void:
	zone = z
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS  # it runs the paused world's menu
	_build()
	visible = false


func _exit_tree() -> void:
	if visible:
		showing = false
		if get_tree() != null and get_tree().paused:
			get_tree().paused = false


func is_open() -> bool:
	return visible


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	UiTheme.apply(_root)
	add_child(_root)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.01, 0.04, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(580, 0)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH  # sized by its content, around the centre
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.add_theme_stylebox_override("panel", UiTheme.nine("frame.png", 16, 22))
	_root.add_child(_panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	_panel.add_child(body)
	var top := HBoxContainer.new()
	body.add_child(top)
	_title = UiTheme.title_label("PAUSED")
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	var hint := UiTheme.caption("[Esc]")
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(hint)
	_who = UiTheme.caption("")
	body.add_child(_who)
	_note = UiTheme.caption("")
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(520, 0)
	body.add_child(_note)
	_resume_btn = UiTheme.menu_button("Resume", close)
	body.add_child(_resume_btn)
	body.add_child(UiTheme.menu_button("Settings", open_settings))
	_back_btn = UiTheme.menu_button("Save and return to title", _back_to_title)
	body.add_child(_back_btn)
	_quit_btn = UiTheme.menu_button("Quit game", _quit)
	body.add_child(_quit_btn)


func open() -> void:
	if visible or zone == null:
		return
	zone.close_windows()
	var online := Net.is_online()
	visible = true
	showing = true
	_title.text = "MENU" if online else "PAUSED"
	_who.text = _who_line()
	if online:
		var server := Net.server_name if Net.server_name != "" else "the server"
		_note.text = "Online on %s - the world keeps moving, your hero stands still." % server
		_back_btn.text = "Leave the server"
		_quit_btn.text = "Leave and quit"
		var hero := zone.player
		if hero != null and is_instance_valid(hero):
			_was_locked = hero.input_locked
			hero.input_locked = true
	else:
		_note.text = "The world waits."
		_back_btn.text = "Save and return to title"
		_quit_btn.text = "Save and quit"
		get_tree().paused = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_resume_btn.grab_focus()


func close() -> void:
	if not visible:
		return
	_close_settings()
	visible = false
	showing = false
	if Net.is_online():
		var hero := zone.player if zone != null else null
		if hero != null and is_instance_valid(hero):
			hero.input_locked = _was_locked
	get_tree().paused = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func open_settings() -> void:
	if _settings != null:
		return
	_settings = SettingsUI.new()
	_root.add_child(_settings)
	_panel.visible = false
	_settings.closed.connect(_close_settings)


func _close_settings() -> void:
	if _settings == null:
		return
	_settings.queue_free()
	_settings = null
	_panel.visible = true
	_resume_btn.grab_focus()


## "Brynja  -  Druid level 7  -  Runehold"
func _who_line() -> String:
	var hero := zone.player
	if hero == null or not is_instance_valid(hero):
		return ""
	var ch := SaveGame.active_character()
	var who := str(ch.get("name", "")).strip_edges()
	var cls := hero.class_data.display_name if hero.class_data != null else "Hero"
	var line := "%s level %d" % [cls, hero.progression.level]
	if who != "":
		line = "%s  -  %s" % [who, line]
	return "%s  -  %s" % [line, ZoneBase.zone_label(zone.scene_file_path).trim_prefix("the ")]


func _back_to_title() -> void:
	close()
	zone.return_to_title()


func _quit() -> void:
	close()
	zone.quit_game()


func _input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed(&"toggle_cursor"):
		return
	if _settings != null:
		_settings.cancel()
	else:
		close()
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if visible or not event.is_action_pressed(&"toggle_cursor"):
		return
	if zone == null or zone.player == null or not is_instance_valid(zone.player):
		return
	get_viewport().set_input_as_handled()
	if zone.close_windows():
		return  # a window that missed the key (e.g. under the F1 panel) closes first
	open()


func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_FOCUS_OUT or visible or zone == null:
		return
	if Net.is_online() or GameSettings.test_run or not GameSettings.pause_on_focus_loss():
		return
	if DisplayServer.get_name() == "headless" or zone.player == null:
		return
	open()
