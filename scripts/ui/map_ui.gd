class_name MapUI
extends CanvasLayer
## M08 zone map (key M): the baked map image with the points of interest
## this character has seen, the hero's arrow, a legend and a list of what is
## known. Zones without a map (hub, Spire) just say so. Locks combat input
## like the other windows; one window at a time.

const MAP_PX := 600.0
const PANEL := Vector2(1120, 660)

var player: Player
var zone: ZoneBase

var _root: Control
var _title: Label
var _sub: Label
var _view: ZoneMapView
var _legend: VBoxContainer
var _list: VBoxContainer
var _marker_count: int = 0
var _refresh_left: float = 0.0


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
	if zone == null or zone.map_texture() == null:
		if zone != null and zone.hud != null:
			zone.hud.toast("No map of this place", UiTheme.MUTED)
		return
	if zone.hero_ui != null:
		zone.hero_ui.close()
	if zone.trainer_ui != null:
		zone.trainer_ui.close()
	if zone.lore_ui != null:
		zone.lore_ui.close()
	if zone.waypoint_ui != null:
		zone.waypoint_ui.close()
	if zone.playtest_ui != null:
		zone.playtest_ui.close()
	visible = true
	player.input_locked = true
	_view.setup(zone.map_texture(), zone.map_bounds(), MAP_PX)
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


## Map pixel (inside the MAP_PX square) of a world position.
func world_to_map(pos: Vector3) -> Vector2:
	_view.bounds = zone.map_bounds()
	return _view.world_to_map(pos)


func marker_count() -> int:
	return _marker_count


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"toggle_cursor"):
		close()
		get_viewport().set_input_as_handled()
		return
	if zone != null and zone.debug_overlay != null and zone.debug_overlay._visible:
		return  # the F1 overlay owns the letter keys while it shows
	if PauseMenu.showing:
		return  # M17a: nothing opens under the Esc menu
	if visible and event.is_action_pressed(&"map_toggle"):
		close()
		get_viewport().set_input_as_handled()
	elif not visible and event.is_action_pressed(&"map_toggle"):
		if player != null and not player.input_locked:
			open()
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	if player != null and is_instance_valid(player):
		_view.set_player(player.global_position, player.facing())
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = 1.0
		_refresh()


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
	_title = Label.new()
	_title.add_theme_font_override("font", UiTheme.font(true))
	_title.add_theme_font_size_override("font_size", UiTheme.TITLE)
	_title.add_theme_color_override("font_color", ArtKit.color("color_roles.player_accent.body", Color(0.37, 0.88, 0.91)))
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	top.add_child(UiTheme.close_button(close))

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	body.add_child(columns)

	var map_frame := PanelContainer.new()
	map_frame.custom_minimum_size = Vector2(MAP_PX + 12, MAP_PX + 12)
	map_frame.add_theme_stylebox_override("panel", UiTheme.nine("slot.png", 6, 6))
	columns.add_child(map_frame)
	_view = ZoneMapView.new()
	_view.setup(null, Rect2(-50, -50, 100, 100), MAP_PX)
	map_frame.add_child(_view)

	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 8)
	side.custom_minimum_size = Vector2(440, 0)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(side)
	_sub = Label.new()
	_sub.add_theme_color_override("font_color", UiTheme.MUTED)
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub.custom_minimum_size = Vector2(420, 0)
	side.add_child(_sub)
	var legend_title := Label.new()
	legend_title.text = "LEGEND"
	legend_title.add_theme_color_override("font_color", ArtKit.color("color_roles.resonance.body", Color("#FFC34D")))
	side.add_child(legend_title)
	_legend = VBoxContainer.new()
	_legend.add_theme_constant_override("separation", 2)
	side.add_child(_legend)
	for entry: Array in [["waypoint", "Waypoint shrine"], ["portal", "Gate"], ["camp", "Raider camp"],
			["camp_cleared", "Camp cleared"], ["chest", "Treasure"], ["ruin", "Ruin"], ["landmark", "Landmark"],
			["boss", "Colossus arena"], ["dungeon", "Sealed gate"]]:
		_legend.add_child(_legend_row(String(entry[0]), String(entry[1])))
	var known_title := Label.new()
	known_title.text = "KNOWN PLACES"
	known_title.add_theme_color_override("font_color", ArtKit.color("color_roles.resonance.body", Color("#FFC34D")))
	side.add_child(known_title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 220)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_list)


func _legend_row(icon_name: String, text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var ic := TextureRect.new()
	ic.texture = Compass.icon(icon_name)
	ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	ic.custom_minimum_size = Vector2(24, 24)
	row.add_child(ic)
	var label := Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	return row


func _refresh() -> void:
	_title.text = zone.zone_title() if zone.zone_title() != "" else "MAP"
	for child in _list.get_children():
		child.queue_free()
	var markers := zone.map_markers()
	_marker_count = markers.size()
	_sub.text = "%d places known. Walk the trails to reveal more." % markers.size()
	_view.set_markers(markers)
	for m in markers:
		_list.add_child(_legend_row(String(m.get("icon", "landmark")), String(m.get("label", ""))))
