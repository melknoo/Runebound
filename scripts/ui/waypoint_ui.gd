class_name WaypointUI
extends CanvasLayer
## M08 travel panel: opened at an attuned waypoint shrine, lists every shrine
## this character knows (Runehold first, then each zone), the current one
## greyed. Picking one fast-travels (a fade within the zone, a zone change
## across zones). Esc / the X close it; combat input is locked while open.

var player: Player

var _root: Control
var _title: Label
var _sub: Label
var _list: VBoxContainer
var _from: Waypoint = null
var _listed: PackedStringArray = PackedStringArray()


func setup(p: Player) -> void:
	player = p
	layer = 8
	_build()
	visible = false


func open(from: Waypoint, p: Player = null) -> void:
	if p != null:
		player = p
	_from = from
	var zone := get_parent() as ZoneBase
	if zone != null:
		if zone.hero_ui != null:
			zone.hero_ui.close()
		if zone.trainer_ui != null:
			zone.trainer_ui.close()
		if zone.map_ui != null:
			zone.map_ui.close()
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


## Keys shown the last time the list was built (tests).
func listed_keys() -> PackedStringArray:
	return _listed


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"toggle_cursor"):
		close()
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
	panel.custom_minimum_size = Vector2(560, 460)
	panel.position = Vector2(-280, -230)
	panel.add_theme_stylebox_override("panel", UiTheme.nine("frame.png", 16, 18))
	_root.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	panel.add_child(body)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 20)
	body.add_child(top)
	_title = Label.new()
	_title.text = "WAYPOINTS"
	_title.add_theme_font_override("font", UiTheme.font(true))
	_title.add_theme_font_size_override("font_size", UiTheme.TITLE)
	_title.add_theme_color_override("font_color", ArtKit.color("color_roles.player_accent.body", Color(0.37, 0.88, 0.91)))
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	top.add_child(UiTheme.close_button(close))

	_sub = Label.new()
	_sub.add_theme_color_override("font_color", UiTheme.MUTED)
	body.add_child(_sub)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 330)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)


func _refresh() -> void:
	for child in _list.get_children():
		child.queue_free()
	_listed.clear()
	_sub.text = "At %s. Attuned shrines answer the call." % (_from.display_name if _from != null else "a shrine")
	var last_zone := ""
	for entry in WaypointRegistry.all():
		var key := String(entry["key"])
		if key != WaypointRegistry.HUB_KEY and not player.knows_waypoint(key):
			continue
		_listed.append(key)
		var zone_name := String(entry["zone"])
		if zone_name != last_zone:
			last_zone = zone_name
			var header := Label.new()
			header.text = zone_name
			header.add_theme_color_override("font_color", ArtKit.color("color_roles.resonance.body", Color("#FFC34D")))
			_list.add_child(header)
		var button := Button.new()
		var here := _from != null and _from.id == key
		button.text = ("   %s  (here)" if here else "   %s") % String(entry["name"])
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.disabled = here
		button.custom_minimum_size = Vector2(500, 36)
		button.pressed.connect(_travel.bind(key))
		_list.add_child(button)


func _travel(key: String) -> void:
	var zone := get_parent() as ZoneBase
	close()
	if zone != null:
		zone.fast_travel(key)
