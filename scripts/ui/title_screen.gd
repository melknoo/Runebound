extends Control
## M09 title screen (the main scene): Continue (singleplayer, straight into
## the save), Join co-op (name + server + invite code, remembered in
## user://settings.cfg) and Quit. The server comes from a dropdown of
## ServerList names (2026-10-01: the address never shows) or "Other address"
## for one typed in (LAN, a local test server). After a co-op session ends it
## shows why. `-- --connect=host:port [--name=N] [--invite=CODE]` joins right
## away (tools/run_godot coop). M10: Characters (pick, create - class + name -
## or delete one; several per save, each with its own world); Continue and
## Join co-op play the active character.

const ACCENT_FALLBACK := Color(0.37, 0.88, 0.91)
const WARN := Color("#E08A7A")
const DEFAULT_SERVER := ""
const OTHER_SERVER := "Other address ..."
## ClientSettings "server_pick" for a typed address (else a ServerList id).
const OTHER_ID := "other"

var _main_page: VBoxContainer
var _join_page: VBoxContainer
var _chars_page: VBoxContainer
var _create_page: VBoxContainer
var _chars_list: VBoxContainer
var _class_buttons: Array[Button] = []
var _class_desc: Label
var _char_name_edit: LineEdit
var _create_status: Label
var _join_as: Label
## Index of the character whose Delete was clicked once (-1 = none).
var _delete_armed: int = -1
var _continue_btn: Button
var _name_edit: LineEdit
var _server_pick: OptionButton
## The ServerList entry behind each dropdown item ({} = "Other address").
var _server_items: Array[Dictionary] = []
var _address_caption: Label
var _address_edit: LineEdit
var _invite_edit: LineEdit
var _invite_show: Button
var _connect_btn: Button
var _back_btn: Button
var _status: Label
var _main_status: Label
var _column: VBoxContainer
## M17a: the settings window while it is open (null otherwise).
var _settings: SettingsUI
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
	var snap := ""
	var snap_page := "main"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snap="):
			snap = arg.trim_prefix("--snap=")
		elif arg.begins_with("--snap-page="):
			snap_page = arg.trim_prefix("--snap-page=")
		elif arg.begins_with("--connect="):
			auto_connect = arg.trim_prefix("--connect=")
		elif arg.begins_with("--name="):
			auto_name = arg.trim_prefix("--name=")
		elif arg.begins_with("--invite="):
			auto_invite = arg.trim_prefix("--invite=")
	if snap != "":
		_snap.call_deferred(snap, snap_page)
		return
	if auto_connect != "" and Net.last_reason == "":
		_auto = true
		_show_join()
		_select_server(_server_items.size() - 1)  # "Other address"
		_address_edit.text = auto_connect
		_invite_edit.text = auto_invite
		if auto_name != "":
			_name_edit.text = auto_name
		_connect()


## Look review (M17a): `-- --snap=<png> [--snap-page=main|characters|create|join|settings[_<tab>]]`
## shows that page, saves a screenshot and quits. A test-run flag: the
## capture save and the default settings, never the player's own.
func _snap(file: String, page: String) -> void:
	match page:
		"characters": _show_characters()
		"create": _show_create()
		"join": _show_join()
		"settings": show_settings()
		_:
			if page.begins_with("settings_"):  # settings_video, settings_controls, ...
				show_settings()
				_settings.open_tab(maxi(SettingsUI.TAB_SECTIONS.find(page.trim_prefix("settings_")), 0) as SettingsUI.Tab)
			else:
				_show_main()
	for i in 45:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var out := file if file.is_absolute_path() else ProjectSettings.globalize_path(file)
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	img.save_png(out)
	print("snap: ", out)
	get_tree().quit()


func _exit_tree() -> void:
	if Net.session_failed.is_connected(_on_failed):
		Net.session_failed.disconnect(_on_failed)


func _process(_delta: float) -> void:
	if not Net.is_joining():
		return
	var stage := Net.join_stage()
	var target := _join_label()
	match stage:
		"resolve":
			_say(_status, "Looking up %s ..." % target)
		"connect":
			_say(_status, "Connecting to %s ..." % target)
		"handshake":
			_say(_status, "Joining ...")


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"toggle_cursor") or Net.is_joining():
		return
	if _settings != null:
		_settings.cancel()
		get_viewport().set_input_as_handled()
	elif _create_page.visible:
		_show_characters()
		get_viewport().set_input_as_handled()
	elif _join_page.visible or _chars_page.visible:
		_show_main()
		get_viewport().set_input_as_handled()


func _build() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color("#120D18")
	add_child(bg)

	var column := VBoxContainer.new()
	_column = column
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
	_main_page.add_child(_button("Characters", _show_characters))
	_main_page.add_child(_button("Join co-op", _show_join))
	_main_page.add_child(_button("Settings", show_settings))
	_main_page.add_child(_button("Quit", func() -> void: get_tree().quit()))
	_main_status = _status_label()
	_main_page.add_child(_main_status)
	# The playtest checklist (PlaytestLog): how much is left to try.
	var todo := PlaytestLog.counts()
	if int(todo["total"]) > 0 and GameSettings.dev_tools():  # M17a: a developer tool
		var hint := Label.new()
		hint.text = "Playtest: %d offen, %d Probleme  (J im Spiel)" % [int(todo["open"]), int(todo["problem"])]
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.add_theme_color_override("font_color", UiTheme.MUTED)
		_main_page.add_child(hint)

	_build_character_pages(pages)

	_join_page = VBoxContainer.new()
	_join_page.add_theme_constant_override("separation", 10)
	_join_page.visible = false
	pages.add_child(_join_page)
	_join_as = _caption("")
	_join_page.add_child(_join_as)
	_join_page.add_child(_caption("Your name"))
	_name_edit = _line_edit(ClientSettings.get_value("name", ""), "Hero")
	_name_edit.max_length = Net.NAME_MAX
	_join_page.add_child(_name_edit)
	_join_page.add_child(_caption("Server"))
	_server_pick = OptionButton.new()
	_server_pick.custom_minimum_size = Vector2(0, 44)
	_server_pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_server_items.clear()
	for server: Dictionary in ServerList.all():
		_server_pick.add_item(str(server["name"]))
		_server_items.append(server)
	_server_pick.add_item(OTHER_SERVER)
	_server_items.append({})
	_server_pick.item_selected.connect(_on_server_picked)
	_join_page.add_child(_server_pick)
	_address_caption = _caption("Address  (or host:port for a LAN server)")
	_join_page.add_child(_address_caption)
	_address_edit = _line_edit(ClientSettings.get_value("last_server", DEFAULT_SERVER), "server-name:7777")
	_address_edit.text_submitted.connect(func(_t: String) -> void: _connect())
	_join_page.add_child(_address_edit)
	# M09b: the host's server lets in invited friends only; each server keeps
	# its own remembered code.
	_join_page.add_child(_caption("Invite code  (the host gives you one)"))
	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 12)
	_join_page.add_child(code_row)
	_invite_edit = _line_edit("", "XXXX-XXXX-XXXX-XXXX")
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
	_select_server(_initial_server())


## The dropdown item to start on: the remembered pick, else the listed server
## whose address was typed last (settings from before the list), else the
## typed address, else the first server.
func _initial_server() -> int:
	var other := _server_items.size() - 1
	var pick := ClientSettings.get_value("server_pick", "")
	if pick == OTHER_ID:
		return other
	var last := ClientSettings.get_value("last_server", DEFAULT_SERVER)
	var by_address := str(ServerList.by_address(last).get("id", "")) if last.strip_edges() != "" else ""
	for i in other:
		var id := str(_server_items[i]["id"])
		if id == pick or (pick == "" and id == by_address):
			return i
	return other if last.strip_edges() != "" else 0


func _select_server(index: int) -> void:
	_server_pick.select(index)
	_on_server_picked(index)


func _on_server_picked(_index: int) -> void:
	var typed := _picked_server().is_empty()
	_address_caption.visible = typed
	_address_edit.visible = typed
	_invite_edit.text = ClientSettings.get_invite(_join_address())


## The picked ServerList entry ({} = "Other address").
func _picked_server() -> Dictionary:
	var i := _server_pick.selected
	return _server_items[i] if i >= 0 and i < _server_items.size() else {}


## Where Connect goes: the picked server's address, or the one typed.
func _join_address() -> String:
	var server := _picked_server()
	return str(server["address"]) if not server.is_empty() else _address_edit.text.strip_edges()


## The server as the messages name it (its name from the list, else the address).
func _join_label() -> String:
	var server := _picked_server()
	return str(server["name"]) if not server.is_empty() else _address_edit.text.strip_edges()


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


## "Continue - Brynja, Runebreaker level 7" (or "New game" without a character).
func _continue_label() -> String:
	var ch := SaveGame.active_character()
	if ch.is_empty():
		return "New game"
	return "Continue  -  %s" % _character_line(ch)


## "Brynja, Runebreaker level 7" for a saved character dict.
static func _character_line(ch: Dictionary) -> String:
	var cls := ClassData.load_by_id(StringName(str(ch.get("class_id", ClassData.DEFAULT_ID))))
	var level := int((ch.get("progression", {}) as Dictionary).get("level", 1))
	var cls_name := cls.display_name if cls != null else "Hero"
	var char_name := str(ch.get("name", "")).strip_edges()
	if char_name == "":
		return "%s, level %d" % [cls_name, level]
	return "%s, %s level %d" % [char_name, cls_name, level]


func _continue() -> void:
	if SaveGame.active_character().is_empty():
		_show_create()  # M10: a new game starts with choosing a class
		return
	Net.last_reason = ""
	var zone := SaveGame.current_zone
	if not ResourceLoader.exists(zone):
		zone = "res://scenes/hub.tscn"
	get_tree().change_scene_to_file(zone)


func _show_join() -> void:
	_hide_pages()
	_join_page.visible = true
	var ch := SaveGame.active_character()
	_join_as.text = "Playing as %s" % (_character_line(ch) if not ch.is_empty() else "a new Runebreaker (make one under Characters)")
	_say(_status, "")
	var focus: Control = _name_edit
	if _name_edit.text != "":
		focus = _address_edit if _picked_server().is_empty() else _server_pick
	focus.grab_focus()


## M17a: the settings window over the title (Esc / Back closes it).
func show_settings() -> void:
	if _settings != null:
		return
	_settings = SettingsUI.new()
	add_child(_settings)
	_column.visible = false
	_settings.closed.connect(_close_settings)


func _close_settings() -> void:
	if _settings == null:
		return
	_settings.queue_free()
	_settings = null
	_column.visible = true
	_continue_btn.grab_focus()


func _show_main() -> void:
	_hide_pages()
	_main_page.visible = true
	_continue_btn.text = _continue_label()
	_say(_main_status, "")
	_continue_btn.grab_focus()


func _hide_pages() -> void:
	for page: Control in [_main_page, _join_page, _chars_page, _create_page]:
		page.visible = false


# ---------------------------------------------------------------------------
# M10: characters (several per save, one class each)
# ---------------------------------------------------------------------------

func _build_character_pages(pages: Control) -> void:
	_chars_page = VBoxContainer.new()
	_chars_page.add_theme_constant_override("separation", 10)
	_chars_page.visible = false
	pages.add_child(_chars_page)
	_chars_page.add_child(_caption("Characters  (each has its own world)"))
	_chars_list = VBoxContainer.new()
	_chars_list.add_theme_constant_override("separation", 8)
	_chars_page.add_child(_chars_list)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_chars_page.add_child(row)
	var new_btn := _button("New character", _show_create)
	new_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(new_btn)
	var back := _button("Back", _show_main)
	back.custom_minimum_size = Vector2(150, 44)
	row.add_child(back)

	_create_page = VBoxContainer.new()
	_create_page.add_theme_constant_override("separation", 10)
	_create_page.visible = false
	pages.add_child(_create_page)
	_create_page.add_child(_caption("Choose a class"))
	var group := ButtonGroup.new()
	for cls in ClassData.all():
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.text = "%s  -  %s" % [cls.display_name, cls.role] if cls.role != "" else cls.display_name
		b.custom_minimum_size = Vector2(0, 44)
		b.set_meta(&"class_id", cls.id)
		b.pressed.connect(_on_class_picked.bind(cls))
		_create_page.add_child(b)
		_class_buttons.append(b)
	_class_desc = Label.new()
	_class_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_class_desc.custom_minimum_size = Vector2(500, 0)
	_class_desc.add_theme_color_override("font_color", UiTheme.MUTED)
	_create_page.add_child(_class_desc)
	_create_page.add_child(_caption("Name"))
	_char_name_edit = _line_edit("", "Hero")
	_char_name_edit.max_length = Net.NAME_MAX
	_char_name_edit.text_submitted.connect(func(_t: String) -> void: _create())
	_create_page.add_child(_char_name_edit)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 12)
	_create_page.add_child(row2)
	var create_btn := _button("Create and play", _create)
	create_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(create_btn)
	var back2 := _button("Back", _show_characters)
	back2.custom_minimum_size = Vector2(150, 44)
	row2.add_child(back2)
	_create_status = _status_label()
	_create_page.add_child(_create_status)


func _show_characters() -> void:
	_hide_pages()
	_delete_armed = -1
	_chars_page.visible = true
	_fill_characters()


func _fill_characters() -> void:
	for child in _chars_list.get_children():
		child.queue_free()
	var chars := SaveGame.characters()
	if chars.is_empty():
		_chars_list.add_child(_caption("No characters yet."))
	for i in chars.size():
		var ch: Dictionary = chars[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_chars_list.add_child(row)
		var play := _button(("> " if i == SaveGame.active else "") + _character_line(ch), _play_character.bind(i))
		play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		play.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_child(play)
		var del := _button("Really delete?" if _delete_armed == i else "Delete", _delete_character.bind(i))
		del.custom_minimum_size = Vector2(170, 44)
		if _delete_armed == i:
			del.add_theme_color_override("font_color", WARN)
		row.add_child(del)


func _play_character(i: int) -> void:
	SaveGame.select_character(i)
	_continue()


## First click arms the button, the second deletes (the viewer has no dialogs).
func _delete_character(i: int) -> void:
	if _delete_armed != i:
		_delete_armed = i
	else:
		SaveGame.delete_character(i)
		_delete_armed = -1
	_fill_characters()


func _show_create() -> void:
	_hide_pages()
	_create_page.visible = true
	_say(_create_status, "")
	if not _class_buttons.is_empty() and _picked_class() == null:
		_class_buttons[0].button_pressed = true
		_on_class_picked(ClassData.load_by_id(_class_buttons[0].get_meta(&"class_id")))
	_char_name_edit.grab_focus()


func _on_class_picked(cls: ClassData) -> void:
	_class_desc.text = cls.description
	_char_name_edit.placeholder_text = cls.display_name


func _picked_class() -> ClassData:
	for b in _class_buttons:
		if b.button_pressed:
			return ClassData.load_by_id(b.get_meta(&"class_id"))
	return null


func _create() -> void:
	var cls := _picked_class()
	if cls == null:
		_say(_create_status, "Pick a class first.", WARN)
		return
	SaveGame.create_character(cls.id, Net.clean_name(_char_name_edit.text) if _char_name_edit.text.strip_edges() != "" else "")
	_char_name_edit.text = ""
	_continue()


func _toggle_invite() -> void:
	_invite_edit.secret = not _invite_edit.secret
	_invite_show.text = "Show" if _invite_edit.secret else "Hide"


func _connect() -> void:
	if Net.is_joining():
		return
	var address := _join_address()
	var server := _picked_server()
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
		ClientSettings.set_value("server_pick", str(server["id"]) if not server.is_empty() else OTHER_ID)
		if server.is_empty():
			ClientSettings.set_value("last_server", address)
		ClientSettings.set_invite(address, NetAuth.pretty_code(code) if code != "" else "")
	var ch := SaveGame.active_character()
	var level := int((ch.get("progression", {}) as Dictionary).get("level", 1))
	_set_busy(true)
	Net.join(address, player_name, SaveGame.active_class_id(), level, code,
		str(server["name"]) if not server.is_empty() else "")


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
	_server_pick.disabled = busy
	_address_edit.editable = not busy
	_invite_edit.editable = not busy
