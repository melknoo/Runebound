extends Control
## M09 title screen (the main scene): Continue (singleplayer, straight into
## the save), Join co-op (name + server address + invite code, remembered in
## user://settings.cfg, never a fixed server) and Quit. After a co-op session
## ends it shows why. `-- --connect=host:port [--name=N] [--invite=CODE]` joins
## right away (tools/run_godot coop).

const ACCENT_FALLBACK := Color(0.37, 0.88, 0.91)
const WARN := Color("#E08A7A")
const DEFAULT_SERVER := ""

var _main_page: VBoxContainer
var _join_page: VBoxContainer
var _continue_btn: Button
var _name_edit: LineEdit
var _address_edit: LineEdit
var _invite_edit: LineEdit
var _invite_show: Button
var _connect_btn: Button
var _back_btn: Button
var _status: Label
var _main_status: Label
## `--connect=` joins (run_godot coop) keep the player's saved name and server.
var _auto: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	UiTheme.apply(self)
	_build()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Net.session_failed.connect(_on_failed)
	if Net.last_reason != "":
		_say(_main_status, Net.last_reason, WARN)
	var broken := Net.broken_scripts()
	if not broken.is_empty():
		_continue_btn.disabled = true
		_connect_btn.disabled = true
		_say(_main_status, "This game's scripts failed to compile (%s). Run tools\\run_godot.cmd import or open the project in the Godot editor once, then start again." % [
			broken[0].get_file()], WARN)
		return
	var auto_connect := ""
	var auto_name := ""
	var auto_invite := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--connect="):
			auto_connect = arg.trim_prefix("--connect=")
		elif arg.begins_with("--name="):
			auto_name = arg.trim_prefix("--name=")
		elif arg.begins_with("--invite="):
			auto_invite = arg.trim_prefix("--invite=")
	if auto_connect != "" and Net.last_reason == "":
		_auto = true
		_show_join()
		_address_edit.text = auto_connect
		_invite_edit.text = auto_invite
		if auto_name != "":
			_name_edit.text = auto_name
		_connect()


func _exit_tree() -> void:
	if Net.session_failed.is_connected(_on_failed):
		Net.session_failed.disconnect(_on_failed)


func _process(_delta: float) -> void:
	if not Net.is_joining():
		return
	var stage := Net.join_stage()
	var target := _address_edit.text.strip_edges()
	match stage:
		"resolve":
			_say(_status, "Looking up %s ..." % target)
		"connect":
			_say(_status, "Connecting to %s ..." % target)
		"handshake":
			_say(_status, "Joining ...")


func _unhandled_input(event: InputEvent) -> void:
	if _join_page.visible and event.is_action_pressed(&"toggle_cursor") and not Net.is_joining():
		_show_main()
		get_viewport().set_input_as_handled()


func _build() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color("#120D18")
	add_child(bg)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.custom_minimum_size = Vector2(560, 0)
	column.position = Vector2(-280, -250)
	column.add_theme_constant_override("separation", 18)
	add_child(column)

	var title := Label.new()
	title.text = "RUNEBOUND"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UiTheme.font(true))
	title.add_theme_font_size_override("font_size", UiTheme.HUGE)
	title.add_theme_color_override("font_color", ArtKit.color("color_roles.player_accent.body", ACCENT_FALLBACK))
	column.add_child(title)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.nine("frame.png", 16, 22))
	column.add_child(panel)
	var pages := VBoxContainer.new()
	panel.add_child(pages)

	_main_page = VBoxContainer.new()
	_main_page.add_theme_constant_override("separation", 12)
	pages.add_child(_main_page)
	_continue_btn = _button(_continue_label(), _continue)
	_main_page.add_child(_continue_btn)
	_main_page.add_child(_button("Join co-op", _show_join))
	_main_page.add_child(_button("Quit", func() -> void: get_tree().quit()))
	_main_status = _status_label()
	_main_page.add_child(_main_status)

	_join_page = VBoxContainer.new()
	_join_page.add_theme_constant_override("separation", 10)
	_join_page.visible = false
	pages.add_child(_join_page)
	_join_page.add_child(_caption("Your name"))
	_name_edit = _line_edit(ClientSettings.get_value("name", ""), "Hero")
	_name_edit.max_length = Net.NAME_MAX
	_join_page.add_child(_name_edit)
	_join_page.add_child(_caption("Server  (the host's address; host:port for a LAN server)"))
	_address_edit = _line_edit(ClientSettings.get_value("last_server", DEFAULT_SERVER), "server-name:7777")
	_address_edit.text_submitted.connect(func(_t: String) -> void: _connect())
	_join_page.add_child(_address_edit)
	# M09b: the host's server lets in invited friends only; each server keeps
	# its own remembered code.
	_join_page.add_child(_caption("Invite code  (the host gives you one)"))
	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 12)
	_join_page.add_child(code_row)
	_invite_edit = _line_edit(ClientSettings.get_invite(_address_edit.text), "XXXX-XXXX-XXXX-XXXX")
	_invite_edit.secret = true
	_invite_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_invite_edit.text_submitted.connect(func(_t: String) -> void: _connect())
	code_row.add_child(_invite_edit)
	_invite_show = _button("Show", _toggle_invite)
	_invite_show.custom_minimum_size = Vector2(150, 44)
	code_row.add_child(_invite_show)
	_address_edit.text_changed.connect(func(text: String) -> void:
		var known := ClientSettings.get_invite(text)
		if known != "":
			_invite_edit.text = known
	)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_join_page.add_child(row)
	_connect_btn = _button("Connect", _connect)
	_connect_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_connect_btn)
	_back_btn = _button("Back", _show_main)
	_back_btn.custom_minimum_size = Vector2(150, 44)
	row.add_child(_back_btn)
	_status = _status_label()
	_join_page.add_child(_status)


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.pressed.connect(on_press)
	return b


func _caption(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", UiTheme.MUTED)
	return l


func _line_edit(text: String, placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	e.custom_minimum_size = Vector2(0, 44)
	e.add_theme_stylebox_override("normal", UiTheme.nine("slot.png", 12, 10))
	e.add_theme_stylebox_override("focus", UiTheme.nine("button_hover.png", 16, 10))
	e.add_theme_color_override("font_placeholder_color", UiTheme.MUTED)
	e.add_theme_color_override("caret_color", UiTheme.TEXT)
	return e


func _status_label() -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(500, 0)
	l.visible = false
	return l


## "Continue - Runebreaker, level 7" (or "New game" without a save).
func _continue_label() -> String:
	var ch := SaveGame.active_character()
	if ch.is_empty():
		return "New game"
	var cls := ClassData.load_by_id(SaveGame.active_class_id())
	var level := int((ch.get("progression", {}) as Dictionary).get("level", 1))
	return "Continue  -  %s, level %d" % [cls.display_name if cls != null else "Hero", level]


func _continue() -> void:
	Net.last_reason = ""
	var zone := SaveGame.current_zone
	if not ResourceLoader.exists(zone):
		zone = "res://scenes/hub.tscn"
	get_tree().change_scene_to_file(zone)


func _show_join() -> void:
	_main_page.visible = false
	_join_page.visible = true
	_say(_status, "")
	(_address_edit if _name_edit.text != "" else _name_edit).grab_focus()


func _show_main() -> void:
	_join_page.visible = false
	_main_page.visible = true
	_say(_main_status, "")
	_continue_btn.grab_focus()


func _toggle_invite() -> void:
	_invite_edit.secret = not _invite_edit.secret
	_invite_show.text = "Show" if _invite_edit.secret else "Hide"


func _connect() -> void:
	if Net.is_joining():
		return
	var address := _address_edit.text.strip_edges()
	var parsed := NetAddress.parse(address, Net.DEFAULT_PORT)
	if String(parsed["error"]) != "":
		_say(_status, String(parsed["error"]), WARN)
		return
	var code := _invite_edit.text.strip_edges()
	if code != "" and not NetAuth.is_valid_code(code):
		_say(_status, "An invite code has 16 letters and digits, like K7QM-2XRP-VB4T-5NHL. Check it for typos.", WARN)
		return
	var player_name := Net.clean_name(_name_edit.text)
	if not _auto:
		ClientSettings.set_value("name", player_name)
		ClientSettings.set_value("last_server", address)
		ClientSettings.set_invite(address, NetAuth.pretty_code(code) if code != "" else "")
	var ch := SaveGame.active_character()
	var level := int((ch.get("progression", {}) as Dictionary).get("level", 1))
	_set_busy(true)
	Net.join(address, player_name, SaveGame.active_class_id(), level, code)


func _on_failed(reason: String) -> void:
	_set_busy(false)
	_say(_status, reason, WARN)


## Progress in the muted tone, problems in `color`; an empty line takes no
## room in the panel.
func _say(label: Label, text: String, color: Color = UiTheme.MUTED) -> void:
	label.text = text
	label.visible = text != ""
	label.add_theme_color_override("font_color", color)


func _set_busy(busy: bool) -> void:
	_connect_btn.disabled = busy
	_back_btn.disabled = busy
	_name_edit.editable = not busy
	_address_edit.editable = not busy
	_invite_edit.editable = not busy
