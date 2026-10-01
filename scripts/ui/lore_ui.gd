class_name LoreUI
extends CanvasLayer
## M12: the reading window for lore - a grave's inscription, a note, a
## ghost's words. Shows `<id>.title` and `<id>.body` from the text table
## (Texts) in the current language and re-renders when the language changes.
## Opened by a lore object, closed with Esc, the interact key or the X; one
## window at a time like the others. Locks the hero while it is open.
## The chronicle (key L, `open_chronicle`): the same window with a list of
## everything this character has read and the rune shards found; a click on
## an entry reads it again.

const PANEL := Vector2(980, 560)

var player: Player
## The lore id on show ("" when closed).
var shown_id: String = ""

var _root: Control
var _title: Label
var _kind: Label
var _body: Label
var _footer: Label
var _kind_key: String = ""
## True while the window shows the chronicle (the list beside the text).
var chronicle: bool = false
var _list_box: VBoxContainer
var _list_scroll: ScrollContainer


func setup(p: Player) -> void:
	player = p
	layer = 8
	_build()
	visible = false
	GameSettings.changed.connect(_on_setting_changed)


func _exit_tree() -> void:
	if GameSettings.changed.is_connected(_on_setting_changed):
		GameSettings.changed.disconnect(_on_setting_changed)


## Shows lore `id` (its `.title` and `.body` keys); `kind_key` is an
## optional key for the line above the title ("Grave", "Note").
func open(id: String, kind_key: String = "", p: Player = null) -> void:
	if p != null:
		player = p
	var zone := get_parent() as ZoneBase
	if zone != null:
		zone.close_windows()  # one window at a time
	chronicle = false
	shown_id = id
	_kind_key = kind_key
	_render()
	visible = true
	player.input_locked = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## The chronicle: every lore text this character has read (newest first) and
## the shards found; shows the newest entry, or a hint when there is none.
func open_chronicle(p: Player = null) -> void:
	if p != null:
		player = p
	var zone := get_parent() as ZoneBase
	if zone != null:
		zone.close_windows()
	chronicle = true
	var read := player.lore_read
	shown_id = read[read.size() - 1] if not read.is_empty() else ""
	_kind_key = ""
	_render()
	visible = true
	player.input_locked = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func toggle_chronicle() -> void:
	if visible and chronicle:
		close()
	else:
		open_chronicle()


func close() -> void:
	if not visible:
		return
	visible = false
	chronicle = false
	shown_id = ""
	player.input_locked = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		var zone := get_parent() as ZoneBase
		if zone != null and zone.debug_overlay != null and zone.debug_overlay._visible:
			return  # the F1 overlay owns the letter keys while it shows
		if not PauseMenu.showing and player != null and InputMap.has_action(&"chronicle_toggle") \
				and event.is_action_pressed(&"chronicle_toggle"):
			open_chronicle()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"toggle_cursor") or event.is_action_pressed(&"interact") \
			or (chronicle and event.is_action_pressed(&"chronicle_toggle")):
		close()
		get_viewport().set_input_as_handled()


func _on_setting_changed(key: String) -> void:
	if (key == "general/language" or key == "keys") and visible:
		_render()


func _render() -> void:
	_list_scroll.visible = chronicle
	if chronicle:
		_fill_list()
	if chronicle and shown_id == "":
		_kind.text = Texts.t("ui.chronicle.title").to_upper()
		_kind.visible = true
		_title.text = Texts.t("ui.chronicle.empty_title")
		_body.text = Texts.t("ui.chronicle.empty")
	else:
		_kind.text = Texts.t(_kind_key).to_upper() if _kind_key != "" else (Texts.t("ui.chronicle.title").to_upper() if chronicle else "")
		_kind.visible = _kind.text != ""
		_title.text = Texts.t(shown_id + ".title")
		_body.text = Texts.t(shown_id + ".body")
	_footer.text = Texts.t("ui.lore.close", [InputSetup.key_label(&"interact")])


func _fill_list() -> void:
	for child in _list_box.get_children():
		child.queue_free()
	var found := 0
	for c in player.collected:
		if String(c).begins_with("shard_"):
			found += 1
	var shards := UiTheme.caption(Texts.t("ui.chronicle.shards", [found, RuneShard.TOTAL]))
	shards.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	shards.add_theme_color_override("font_color", ArtKit.color("color_roles.player_accent.hot", Color("#9FF2E6")))
	_list_box.add_child(shards)
	var read := player.lore_read
	for i in range(read.size() - 1, -1, -1):
		var lid := String(read[i])
		var b := Button.new()
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.text = Texts.t(lid + ".title")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_pressed = lid == shown_id
		b.clip_text = true
		b.custom_minimum_size = Vector2(250, 36)
		b.pressed.connect(func() -> void:
			shown_id = lid
			_render()
		)
		_list_box.add_child(b)


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiTheme.apply(_root)
	add_child(_root)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.01, 0.04, 0.6)
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -PANEL.x * 0.5
	panel.offset_top = -PANEL.y * 0.5
	panel.offset_right = PANEL.x * 0.5
	panel.offset_bottom = PANEL.y * 0.5
	panel.add_theme_stylebox_override("panel", UiTheme.nine("frame.png", 16, 18))
	_root.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	panel.add_child(body)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	body.add_child(top)
	var heads := VBoxContainer.new()
	heads.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heads.add_theme_constant_override("separation", 2)
	top.add_child(heads)
	_kind = UiTheme.caption("")
	_kind.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # already translated
	heads.add_child(_kind)
	_title = Label.new()
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_title.add_theme_font_override("font", UiTheme.font(true))
	_title.add_theme_font_size_override("font_size", UiTheme.TITLE)
	_title.add_theme_color_override("font_color", ArtKit.color("palettes.highlands.bone.3", UiTheme.TEXT))
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heads.add_child(_title)
	top.add_child(UiTheme.close_button(close))

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(columns)
	_list_scroll = ScrollContainer.new()  # the chronicle's list (hidden while reading one text)
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_scroll.custom_minimum_size = Vector2(270, 0)
	_list_scroll.visible = false
	columns.add_child(_list_scroll)
	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 4)
	_list_scroll.add_child(_list_box)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(scroll)
	var gutter := MarginContainer.new()
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_theme_constant_override("margin_right", 22)
	scroll.add_child(gutter)
	_body = Label.new()
	_body.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_color_override("font_color", UiTheme.TEXT)
	_body.add_theme_constant_override("line_spacing", 6)
	gutter.add_child(_body)

	_footer = UiTheme.caption("")
	_footer.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	body.add_child(_footer)
