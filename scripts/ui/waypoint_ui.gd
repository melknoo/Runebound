class_name WaypointUI
extends CanvasLayer
## M08 travel panel: opened at an attuned waypoint shrine, lists every shrine
## this character knows (Runehold first, then each zone), the current one
## greyed. Picking one fast-travels (a fade within the zone, a zone change
## across zones). Esc / the X close it; combat input is locked while open.
## M08 notes (user 2026-09-28): the zone map sits next to the list (ZoneMapView):
## the known shrines on it, the hovered one lit up, a click on an icon travels
## too. Zones without a map (Runehold) show only the list.

const MAP_PX := 400.0
const PANEL := Vector2(1000, 540)

var player: Player

var _root: Control
var _title: Label
var _sub: Label
var _list: VBoxContainer
var _map_frame: PanelContainer
var _map: ZoneMapView
var _map_title: Label
var _map_scene := ""  # the zone whose map shows
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
	panel.custom_minimum_size = PANEL
	panel.position = -PANEL * 0.5
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

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(columns)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, MAP_PX)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var map_side := VBoxContainer.new()
	map_side.add_theme_constant_override("separation", 4)
	columns.add_child(map_side)
	_map_title = Label.new()
	_map_title.add_theme_color_override("font_color", UiTheme.MUTED)
	map_side.add_child(_map_title)
	_map_frame = PanelContainer.new()
	_map_frame.add_theme_stylebox_override("panel", UiTheme.nine("slot.png", 6, 6))
	map_side.add_child(_map_frame)
	_map = ZoneMapView.new()
	_map.setup(null, Rect2(-50, -50, 100, 100), MAP_PX)
	_map.marker_pressed.connect(func(key: String) -> void:
		if _from == null or _from.id != key:
			_travel(key))
	_map_frame.add_child(_map)


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
		var scene := String(entry["scene"])
		button.mouse_entered.connect(func() -> void: _hover(scene, key))
		button.focus_entered.connect(func() -> void: _hover(scene, key))
		_list.add_child(button)
	_show_map(_default_map_scene(), _from.id if _from != null else "")


## The map to show first: this zone's, else the first listed zone that has one.
func _default_map_scene() -> String:
	var zone := get_parent() as ZoneBase
	if zone != null and not WaypointRegistry.zone_map(zone.scene_file_path).is_empty():
		return zone.scene_file_path
	for key in _listed:
		var scene := String(WaypointRegistry.find(key).get("scene", ""))
		if not WaypointRegistry.zone_map(scene).is_empty():
			return scene
	return ""


func _hover(scene: String, key: String) -> void:
	if WaypointRegistry.zone_map(scene).is_empty():
		return  # Runehold: keep the map that shows
	if scene != _map_scene:
		_show_map(scene, key)
	else:
		_map.highlight(key)


## The zone's map with the shrines this hero knows there (the hero's arrow
## when it is this zone). No map: the column hides.
func _show_map(scene: String, lit_key: String) -> void:
	var info := WaypointRegistry.zone_map(scene)
	_map_frame.get_parent().visible = not info.is_empty()
	_map_scene = scene
	if info.is_empty():
		return
	_map.setup(info["texture"] as Texture2D, info["bounds"] as Rect2, MAP_PX)
	var markers: Array[Dictionary] = []
	for key in _listed:
		var entry := WaypointRegistry.find(key)
		if String(entry.get("scene", "")) == scene and entry.has("pos"):
			markers.append({"key": key, "pos": entry["pos"], "icon": "waypoint",
				"label": String(entry["name"]) + ("  (here)" if _from != null and _from.id == key else "")})
	_map.set_markers(markers)
	_map.highlight(lit_key)
	var zone := get_parent() as ZoneBase
	var here := zone != null and zone.scene_file_path == scene and player != null
	_map.set_player(player.global_position if here else Vector3.INF, player.facing() if here else Vector3.FORWARD)
	_map_title.text = String(WaypointRegistry.find(markers[0]["key"]).get("zone", "")) if not markers.is_empty() else ""


## The map column in the last build (tests): the zone scene shown and its shrines.
func map_scene() -> String:
	return _map_scene if _map_frame.get_parent().visible else ""


func map_has_shrine(key: String) -> bool:
	return _map.has_marker(key)


func _travel(key: String) -> void:
	var zone := get_parent() as ZoneBase
	close()
	if zone != null:
		zone.fast_travel(key)
