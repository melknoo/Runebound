class_name SettingsUI
extends Control
## M17a: the settings window, the same on the title screen and in the Esc
## menu. Tabs Audio / Video / Controls / Gameplay; every change applies and
## saves at once (GameSettings). "Reset tab" puts one tab back to the
## defaults. Back, the X or Esc (the owner calls `cancel()`) emit `closed`.
## Controls also lists the key bindings (KeyBindings): click one, then press
## the new key or mouse button; Esc cancels, Delete clears. While it waits
## for a key it takes every key and click (so Esc never closes the window).

signal closed

enum Tab { AUDIO, VIDEO, CONTROLS, GAMEPLAY }

const TAB_TITLES: Array[String] = ["AUDIO", "VIDEO", "CONTROLS", "GAMEPLAY"]
const TAB_SECTIONS: Array[String] = ["audio", "video", "controls", "gameplay"]
const PANEL := Vector2(920, 620)
const LABEL_WIDTH := 330.0

var current: Tab = Tab.AUDIO

var _tab_buttons: Array[Button] = []
var _pages: Array[Control] = []
## Callables that re-read GameSettings into the widgets (after a reset).
var _refreshers: Array[Callable] = []
var _window_size_pick: OptionButton
## action -> [slot 0 button, slot 1 button]
var _bind_buttons: Dictionary = {}
## {"action", "slot"} while a binding waits for its key ({} otherwise).
var _capture: Dictionary = {}
var _bind_status: Label
const WARN := Color("#E08A7A")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	UiTheme.apply(self)
	_build()
	_show_tab(Tab.AUDIO)
	GameSettings.changed.connect(_on_setting_changed)


func _exit_tree() -> void:
	if GameSettings.changed.is_connected(_on_setting_changed):
		GameSettings.changed.disconnect(_on_setting_changed)


## Esc from the owner: closes the window.
func cancel() -> void:
	closed.emit()


func open_tab(tab: Tab) -> void:
	_show_tab(tab)


func _build() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -PANEL.x * 0.5
	panel.offset_top = -PANEL.y * 0.5
	panel.offset_right = PANEL.x * 0.5
	panel.offset_bottom = PANEL.y * 0.5
	panel.add_theme_stylebox_override("panel", UiTheme.nine("frame.png", 16, 18))
	add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	panel.add_child(body)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	body.add_child(top)
	var title := UiTheme.title_label("SETTINGS")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var hint := UiTheme.caption("[Esc]")
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(hint)
	top.add_child(UiTheme.close_button(cancel))

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	body.add_child(tabs)
	var group := ButtonGroup.new()
	for i in TAB_TITLES.size():
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.text = TAB_TITLES[i]
		b.custom_minimum_size = Vector2(180, 44)
		b.pressed.connect(_show_tab.bind(i as Tab))
		tabs.add_child(b)
		_tab_buttons.append(b)

	var pages := MarginContainer.new()
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(pages)
	for build: Callable in [_build_audio, _build_video, _build_controls, _build_gameplay]:
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		pages.add_child(scroll)
		var gutter := MarginContainer.new()  # keeps the values clear of the scroll bar
		gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gutter.add_theme_constant_override("margin_right", 22)
		scroll.add_child(gutter)
		var page := VBoxContainer.new()
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.add_theme_constant_override("separation", 14)
		gutter.add_child(page)
		build.call(page)
		_pages.append(scroll)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	body.add_child(bottom)
	var reset := UiTheme.menu_button("Reset tab", _reset_tab)
	reset.custom_minimum_size = Vector2(200, 44)
	bottom.add_child(reset)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer)
	var back := UiTheme.menu_button("Back", cancel)
	back.custom_minimum_size = Vector2(200, 44)
	bottom.add_child(back)


func _reset_tab() -> void:
	_capture = {}
	GameSettings.reset_section(TAB_SECTIONS[current])
	if current == Tab.CONTROLS:
		GameSettings.reset_bindings()
		_say_bind("Every key is back to its default.")


func _show_tab(tab: Tab) -> void:
	_capture = {}
	current = tab
	for i in _pages.size():
		_pages[i].visible = i == int(tab)
		_tab_buttons[i].set_pressed_no_signal(i == int(tab))


# --- pages -------------------------------------------------------------------

func _build_audio(page: VBoxContainer) -> void:
	page.add_child(_slider_row("Master volume", "audio/master", 0.0, 1.0, 0.05, _percent))
	page.add_child(_slider_row("Music", "audio/music", 0.0, 1.0, 0.05, _percent))
	page.add_child(_slider_row("Effects", "audio/effects", 0.0, 1.0, 0.05, _percent))
	page.add_child(_slider_row("Ambience", "audio/ambience", 0.0, 1.0, 0.05, _percent))
	page.add_child(_slider_row("Interface", "audio/interface", 0.0, 1.0, 0.05, _percent))


func _build_video(page: VBoxContainer) -> void:
	page.add_child(_option_row("Window", "video/window_mode",
		[["Windowed", "windowed"], ["Borderless fullscreen", "borderless"], ["Fullscreen", "fullscreen"]]))
	var sizes: Array = []
	for size: String in GameSettings.WINDOW_SIZES:
		sizes.append([size.replace("x", " x "), size])
	var size_row := _option_row("Window size", "video/window_size", sizes)
	_window_size_pick = size_row.get_child(1) as OptionButton
	page.add_child(size_row)
	page.add_child(_check_row("Vertical sync", "video/vsync"))
	var limits: Array = []
	for fps: int in GameSettings.FPS_LIMITS:
		limits.append(["No limit" if fps == 0 else "%d" % fps, fps])
	page.add_child(_option_row("Frame rate limit", "video/max_fps", limits))
	page.add_child(_check_row("Show FPS", "video/show_fps"))
	_refreshers.append(_refresh_window_size)
	_refresh_window_size()


func _build_controls(page: VBoxContainer) -> void:
	page.add_child(_slider_row("Mouse sensitivity", "controls/sensitivity", 0.25, 3.0, 0.05, _percent))
	page.add_child(_check_row("Invert mouse Y", "controls/invert_y"))
	page.add_child(_slider_row("Zoom speed", "controls/zoom_speed", 0.5, 2.0, 0.1, _percent))
	var heading := UiTheme.title_label("KEYS")
	heading.add_theme_font_size_override("font_size", UiTheme.BODY)
	page.add_child(heading)
	page.add_child(UiTheme.caption("Click a key, then press the new key or mouse button.  Esc cancels, Delete clears."))
	_bind_status = UiTheme.caption("")
	_bind_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bind_status.visible = false
	page.add_child(_bind_status)
	for group: Array in KeyBindings.GROUPS:
		var group_label := UiTheme.caption(str(group[0]))
		group_label.add_theme_color_override("font_color", ArtKit.color("color_roles.resonance.body", Color("#E8B23A")))
		page.add_child(group_label)
		for entry: Array in group[1]:
			var action: StringName = entry[0]
			if action == &"playtest_toggle" and not GameSettings.dev_tools():
				continue  # a developer tool
			page.add_child(_bind_row(action, str(entry[1])))
	_refreshers.append(_refresh_bindings)
	_refresh_bindings()


func _build_gameplay(page: VBoxContainer) -> void:
	page.add_child(_slider_row("Screen shake", "gameplay/shake", 0.0, 1.0, 0.1, _percent))
	page.add_child(_check_row("Red flash when hit", "gameplay/hurt_flash"))
	page.add_child(_check_row("Damage numbers", "gameplay/damage_numbers"))
	page.add_child(_check_row("Pause when the window loses focus (solo)", "gameplay/pause_on_focus_loss"))
	page.add_child(_check_row("Developer tools (F1 debug panel, J playtest list)", "gameplay/dev_tools"))


# --- rows --------------------------------------------------------------------

func _row_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(LABEL_WIDTH, 44)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _slider_row(text: String, key: String, lo: float, hi: float, step: float, fmt: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.add_child(_row_label(text))
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(0, 28)
	slider.name = key.replace("/", "_")
	row.add_child(slider)
	var shown := Label.new()
	shown.custom_minimum_size = Vector2(90, 0)
	shown.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(shown)
	var refresh := func() -> void:
		slider.set_value_no_signal(float(GameSettings.value(key)))
		shown.text = fmt.call(float(GameSettings.value(key)))
	slider.value_changed.connect(func(v: float) -> void:
		GameSettings.set_value(key, v)
		shown.text = fmt.call(v)
	)
	_refreshers.append(refresh)
	refresh.call()
	return row


func _check_row(text: String, key: String) -> CheckBox:
	var box := CheckBox.new()
	box.text = text
	box.custom_minimum_size = Vector2(0, 44)
	box.name = key.replace("/", "_")
	var refresh := func() -> void: box.set_pressed_no_signal(bool(GameSettings.value(key)))
	box.toggled.connect(func(on: bool) -> void: GameSettings.set_value(key, on))
	_refreshers.append(refresh)
	refresh.call()
	return box


## `items` = [[shown text, stored value], ...].
func _option_row(text: String, key: String, items: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.add_child(_row_label(text))
	var pick := OptionButton.new()
	pick.custom_minimum_size = Vector2(360, 44)
	pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
	pick.name = key.replace("/", "_")
	for item: Array in items:
		pick.add_item(str(item[0]))
	row.add_child(pick)
	var refresh := func() -> void:
		var current_value: Variant = GameSettings.value(key)
		for i in items.size():
			if (items[i] as Array)[1] == current_value:
				pick.select(i)
	pick.item_selected.connect(func(i: int) -> void: GameSettings.set_value(key, (items[i] as Array)[1]))
	_refreshers.append(refresh)
	refresh.call()
	return row


func _bind_row(action: StringName, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.add_child(_row_label(text))
	var buttons: Array[Button] = []
	for slot in KeyBindings.SLOTS:
		var b := UiTheme.menu_button("", _start_capture.bind(action, slot))
		b.custom_minimum_size = Vector2(220, 40)
		b.name = "bind_%s_%d" % [action, slot]
		row.add_child(b)
		buttons.append(b)
	_bind_buttons[action] = buttons
	return row


func _refresh_bindings() -> void:
	for action: StringName in _bind_buttons:
		var codes := KeyBindings.codes(action)
		var buttons: Array = _bind_buttons[action]
		for slot in buttons.size():
			var b := buttons[slot] as Button
			if not _capture.is_empty() and _capture["action"] == action and int(_capture["slot"]) == slot:
				b.text = "Press a key ..."
				b.add_theme_color_override("font_color", ArtKit.color("color_roles.player_accent.hot", Color("#9FF2E6")))
			elif slot < codes.size():
				b.text = KeyBindings.label(codes[slot])
				b.remove_theme_color_override("font_color")
			elif slot == 0:
				b.text = "Not bound"
				b.add_theme_color_override("font_color", WARN)
			else:
				b.text = "-"
				b.remove_theme_color_override("font_color")


func _start_capture(action: StringName, slot: int) -> void:
	_capture = {"action": action, "slot": slot}
	_say_bind("Press the new key or mouse button for %s." % KeyBindings.display_name(action))
	_refresh_bindings()


## While a binding waits: the next key or mouse button is its new key.
func _input(event: InputEvent) -> void:
	if _capture.is_empty() or not is_visible_in_tree():
		return
	var key := event as InputEventKey
	var mouse := event as InputEventMouseButton
	var cancel_action := event is InputEventAction and event.is_action_pressed(&"toggle_cursor")
	if (key == null or not key.pressed or key.echo) and (mouse == null or not mouse.pressed) and not cancel_action:
		return
	get_viewport().set_input_as_handled()
	var action: StringName = _capture["action"]
	var slot := int(_capture["slot"])
	_capture = {}
	if cancel_action or (key != null and (key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE)):
		_say_bind("")
		_refresh_bindings()
		return
	if key != null and (key.physical_keycode in [KEY_DELETE, KEY_BACKSPACE]):
		KeyBindings.clear(action, slot)
		GameSettings.save_bindings()
		_say_bind("%s: binding cleared." % KeyBindings.display_name(action))
		return
	var code := KeyBindings.code_of(event)
	if KeyBindings.RESERVED.has(code):
		_say_bind("Esc and F1 stay with the menu and the debug panel.", WARN)
		_refresh_bindings()
		return
	var taken := KeyBindings.bind(action, slot, code)
	GameSettings.save_bindings()
	if taken != &"" and KeyBindings.is_unbound(taken):
		_say_bind("%s is now %s. %s has no key any more." % [KeyBindings.label(code), KeyBindings.display_name(action),
			KeyBindings.display_name(taken)], WARN)
	elif taken != &"":
		_say_bind("%s is now %s (taken from %s)." % [KeyBindings.label(code), KeyBindings.display_name(action),
			KeyBindings.display_name(taken)])
	else:
		_say_bind("%s is now %s." % [KeyBindings.label(code), KeyBindings.display_name(action)])


func _say_bind(text: String, color: Color = UiTheme.MUTED) -> void:
	if _bind_status == null:
		return
	_bind_status.text = text
	_bind_status.visible = text != ""
	_bind_status.add_theme_color_override("font_color", color)


## True while a binding waits for its key (the owner leaves Esc alone then).
func is_capturing() -> bool:
	return not _capture.is_empty()


func _refresh_window_size() -> void:
	if _window_size_pick != null:
		_window_size_pick.disabled = str(GameSettings.value("video/window_mode")) != "windowed"


func _percent(v: float) -> String:
	return "%d %%" % roundi(v * 100.0)


func _on_setting_changed(_key: String) -> void:
	for refresh: Callable in _refreshers:
		refresh.call()
