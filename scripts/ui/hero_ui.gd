class_name HeroUI
extends CanvasLayer
## M07b hero window: one framed panel with the tabs Inventory (I), Character
## (C) and Talents (N). Each key opens its tab, the same key or Esc closes;
## while open, combat input is locked and the mouse is free. The tabs are the
## former InventoryUI / TalentUI panels plus the new CharacterTab; ZoneBase
## keeps `inventory_ui` / `talent_ui` pointing at them.

enum Tab { INVENTORY, CHARACTER, TALENTS }

const TAB_ACTIONS: Array[StringName] = [&"inventory_toggle", &"hero_character", &"talents_toggle"]
const TAB_TITLES: Array[String] = ["INVENTORY", "CHARACTER", "TALENTS"]

var player: Player
var inventory_tab: InventoryUI
var character_tab: CharacterTab
var talent_tab: TalentUI
var current: Tab = Tab.INVENTORY

var _root: Control
var _buttons: Array[Button] = []
var _pages: Array[Control] = []


func setup(p: Player) -> void:
	player = p
	layer = 8
	_build()
	visible = false
	_show_pages()


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
	panel.custom_minimum_size = Vector2(1120, 640)
	panel.position = Vector2(-560, -320)
	panel.add_theme_stylebox_override("panel", UiTheme.nine("frame.png", 16, 18))
	_root.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	panel.add_child(body)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	body.add_child(bar)
	var group := ButtonGroup.new()
	for i in TAB_TITLES.size():
		var btn := Button.new()
		btn.toggle_mode = true
		btn.button_group = group
		btn.text = "%s   %s" % [TAB_TITLES[i], InputSetup.key_label(TAB_ACTIONS[i])]
		btn.custom_minimum_size = Vector2(220, 0)
		btn.add_theme_font_override("font", UiTheme.font(true))
		btn.add_theme_font_size_override("font_size", UiTheme.TITLE)
		btn.pressed.connect(open_tab.bind(i as Tab))
		bar.add_child(btn)
		_buttons.append(btn)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	var hint := Label.new()
	hint.text = "[Esc]"
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", UiTheme.MUTED)
	bar.add_child(hint)
	bar.add_child(UiTheme.close_button(close))

	var content := MarginContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("margin_top", 4)
	body.add_child(content)

	inventory_tab = InventoryUI.new()
	inventory_tab.setup(player, self)
	content.add_child(inventory_tab)
	character_tab = CharacterTab.new()
	character_tab.setup(player)
	content.add_child(character_tab)
	talent_tab = TalentUI.new()
	talent_tab.setup(player, self)
	content.add_child(talent_tab)
	_pages = [inventory_tab, character_tab, talent_tab]


func is_open() -> bool:
	return visible


func open_tab(tab: Tab) -> void:
	current = tab
	visible = true
	player.input_locked = true
	var zone := get_parent() as ZoneBase
	if zone != null and zone.trainer_ui != null and zone.trainer_ui.visible:
		zone.trainer_ui.close()
		player.input_locked = true
	if zone != null and zone.map_ui != null and zone.map_ui.visible:  # M08
		zone.map_ui.close()
		player.input_locked = true
	if zone != null and zone.waypoint_ui != null and zone.waypoint_ui.visible:
		zone.waypoint_ui.close()
		player.input_locked = true
	_show_pages()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## The tab's key: opens it, switches to it, or closes the window when it is
## already the one showing.
func toggle_tab(tab: Tab) -> void:
	if visible and current == tab:
		close()
	else:
		open_tab(tab)


func close() -> void:
	if not visible:
		return
	visible = false
	player.input_locked = false
	_show_pages()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Page visibility is set explicitly (not inherited), so `zone.talent_ui.visible`
## keeps meaning "the talent panel is showing".
func _show_pages() -> void:
	for i in _pages.size():
		var showing := visible and i == int(current)
		_pages[i].visible = showing
		_buttons[i].set_pressed_no_signal(showing)
		if showing:
			_pages[i].call(&"refresh")


func _unhandled_input(event: InputEvent) -> void:
	var zone := get_parent() as ZoneBase
	if zone != null and zone.debug_overlay != null and zone.debug_overlay._visible:
		return  # the F1 overlay owns the letter keys while it shows
	if visible and event.is_action_pressed(&"toggle_cursor"):
		close()
		get_viewport().set_input_as_handled()
		return
	for i in TAB_ACTIONS.size():
		if InputMap.has_action(TAB_ACTIONS[i]) and event.is_action_pressed(TAB_ACTIONS[i]):
			toggle_tab(i as Tab)
			get_viewport().set_input_as_handled()
			return
