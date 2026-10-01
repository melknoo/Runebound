class_name SettingsUI
extends Control
## M17a: the settings window, the same on the title screen and in the Esc
## menu. Tabs Audio / Video / Controls / Gameplay; every change applies and
## saves at once (GameSettings). "Reset tab" puts one tab back to the
## defaults. Back, the X or Esc (the owner calls `cancel()`) emit `closed`.

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
		var page := VBoxContainer.new()
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.add_theme_constant_override("separation", 14)
		scroll.add_child(page)
		build.call(page)
		_pages.append(scroll)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	body.add_child(bottom)
	var reset := UiTheme.menu_button("Reset tab", func() -> void: GameSettings.reset_section(TAB_SECTIONS[current]))
	reset.custom_minimum_size = Vector2(200, 44)
	bottom.add_child(reset)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer)
	var back := UiTheme.menu_button("Back", cancel)
	back.custom_minimum_size = Vector2(200, 44)
	bottom.add_child(back)


func _show_tab(tab: Tab) -> void:
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


func _refresh_window_size() -> void:
	if _window_size_pick != null:
		_window_size_pick.disabled = str(GameSettings.value("video/window_mode")) != "windowed"


func _percent(v: float) -> String:
	return "%d %%" % roundi(v * 100.0)


func _on_setting_changed(_key: String) -> void:
	for refresh: Callable in _refreshers:
		refresh.call()
