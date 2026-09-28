class_name ZoneMapView
extends Control
## A zone's baked map at any size: the image, icons at world positions, an
## optional hero arrow. The full map (MapUI, key M) and the waypoint travel
## panel (M08 notes, user 2026-09-28: "show the map at the shrines so you see
## where you go") both draw with it. Markers are {pos, icon, label} plus an
## optional "key": keyed icons are buttons (marker_pressed) and can be
## highlighted.

signal marker_pressed(key: String)

const ICON := 24.0
const ICON_BIG := 34.0

var bounds := Rect2(-50, -50, 100, 100)
var _map_rect: TextureRect
var _marker_layer: Control
var _player_icon: TextureRect
var _icons: Dictionary = {}  # key -> TextureRect
var _highlighted := ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_map_rect = TextureRect.new()
	_map_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_map_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_map_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_map_rect)
	_marker_layer = Control.new()
	_marker_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_marker_layer)
	_player_icon = TextureRect.new()
	_player_icon.texture = Compass.icon("player")
	_player_icon.size = Vector2(ICON, ICON)
	_player_icon.pivot_offset = Vector2(ICON, ICON) * 0.5
	_player_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_icon.visible = false
	add_child(_player_icon)


## The map image and the world rectangle it covers (x/z), drawn `px` square.
func setup(texture: Texture2D, world_bounds: Rect2, px: float) -> void:
	bounds = world_bounds
	custom_minimum_size = Vector2(px, px)
	size = Vector2(px, px)
	_map_rect.texture = texture
	_map_rect.size = size
	_marker_layer.size = size


## Pixel inside the view of a world position.
func world_to_map(pos: Vector3) -> Vector2:
	return Vector2((pos.x - bounds.position.x) / maxf(bounds.size.x, 0.001),
		(pos.z - bounds.position.y) / maxf(bounds.size.y, 0.001)) * size


func set_markers(markers: Array[Dictionary]) -> void:
	for child in _marker_layer.get_children():
		child.queue_free()
	_icons.clear()
	for m in markers:
		var tex := Compass.icon(String(m.get("icon", "landmark")))
		if tex == null:
			continue
		var ic := TextureRect.new()
		ic.texture = tex
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ic.tooltip_text = String(m.get("label", ""))
		ic.set_meta(&"pos", m["pos"])
		var key := String(m.get("key", ""))
		if key != "":
			_icons[key] = ic
			ic.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			ic.gui_input.connect(func(event: InputEvent) -> void:
				var mb := event as InputEventMouseButton
				if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
					marker_pressed.emit(key))
		ic.mouse_filter = Control.MOUSE_FILTER_STOP if key != "" else Control.MOUSE_FILTER_PASS
		_marker_layer.add_child(ic)
		_place(ic, ICON)
	highlight(_highlighted)


## Draw the keyed marker big and bright ("" = none).
func highlight(key: String) -> void:
	_highlighted = key
	for k: String in _icons:
		var ic := _icons[k] as TextureRect
		var on := k == key
		_place(ic, ICON_BIG if on else ICON)
		ic.modulate = Color(1.4, 1.25, 0.8) if on else Color.WHITE


func has_marker(key: String) -> bool:
	return _icons.has(key)


## The hero arrow (hidden when `pos` is INF).
func set_player(pos: Vector3, facing: Vector3) -> void:
	_player_icon.visible = pos != Vector3.INF
	if not _player_icon.visible:
		return
	_player_icon.position = world_to_map(pos) - _player_icon.size * 0.5
	_player_icon.rotation = atan2(facing.x, -facing.z)


func _place(ic: TextureRect, px: float) -> void:
	ic.size = Vector2(px, px)
	ic.position = world_to_map(ic.get_meta(&"pos") as Vector3) - ic.size * 0.5
