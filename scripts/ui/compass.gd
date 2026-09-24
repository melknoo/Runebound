class_name Compass
extends Control
## M08 compass strip at the top of the HUD: headings from the camera's view
## direction (N = -Z, E = +X), cardinal letters, ticks every 15 degrees and
## the zone's compass markers (attuned shrines, gates, the arena, armed camps
## nearby) as pixel icons that fade with distance. Hidden while a boss bar
## shows; zones without a map show none.

const WIDTH := 520.0
const HEIGHT := 34.0
const HALF_FOV := deg_to_rad(70.0)
const ICON_DIR := "res://assets/ui/map/"
const LETTERS := {0: "N", 6: "E", 12: "S", 18: "W"}

var zone: ZoneBase
var _font: Font
static var _icons: Dictionary = {}


## Map / compass pixel icon by name (assets/ui/map/<name>.png); null when missing.
static func icon(icon_name: String) -> Texture2D:
	if _icons.has(icon_name):
		return _icons[icon_name]
	var path := ICON_DIR + icon_name + ".png"
	var tex: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_icons[icon_name] = tex
	return tex


static func clear_cache() -> void:
	_icons.clear()


func setup(z: ZoneBase) -> void:
	zone = z
	_font = UiTheme.font()
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	position = Vector2(-WIDTH * 0.5, 8)
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	size = Vector2(WIDTH, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame := NinePatchRect.new()
	frame.texture = load(UiTheme.UI_DIR + "bar.png")
	for side in ["left", "top", "right", "bottom"]:
		frame.set("patch_margin_" + side, 6)
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.modulate = Color(1, 1, 1, 0.9)
	add_child(frame)


## Bearing the camera looks along (0 = north, +90 deg = east), radians.
func heading() -> float:
	if zone == null or zone.camera_rig == null:
		return 0.0
	var f := -zone.camera_rig.camera.global_transform.basis.z
	f.y = 0.0
	if f.length() < 0.01:
		return wrapf(-zone.camera_rig._yaw, -PI, PI)
	return atan2(f.x, -f.z)


func markers() -> Array[Dictionary]:
	return zone.compass_markers() if zone != null else []


## Bearing from `from` to `to` (radians, 0 = north).
static func bearing(from: Vector3, to: Vector3) -> float:
	return atan2(to.x - from.x, -(to.z - from.z))


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if zone == null or zone.player == null or not is_instance_valid(zone.player):
		return
	var h := heading()
	var cx := WIDTH * 0.5
	var mid := HEIGHT * 0.5
	var span := cx - 16.0
	var muted := UiTheme.MUTED
	var text := UiTheme.TEXT
	for i in 24:
		var b := TAU * float(i) / 24.0
		var d := wrapf(b - h, -PI, PI)
		if absf(d) > HALF_FOV:
			continue
		var x := cx + d / HALF_FOV * span
		var edge := 1.0 - clampf((absf(d) - HALF_FOV * 0.75) / (HALF_FOV * 0.25), 0.0, 1.0)
		if LETTERS.has(i):
			var letter: String = LETTERS[i]
			var col := (ArtKit.color("color_roles.player_accent.hot", Color("#9FF2E6")) if i == 0 else text)
			col.a = edge
			draw_string(_font, Vector2(x - 6.0, mid + 7.0), letter, HORIZONTAL_ALIGNMENT_CENTER, 12.0, UiTheme.BODY, col)
		else:
			var tick := Color(muted, 0.7 * edge)
			draw_line(Vector2(x, mid - 3.0), Vector2(x, mid + 3.0), tick, 2.0)
	# Marker icons, faded with distance; the nearest draws last (on top).
	var origin := zone.player.global_position
	var visible_markers: Array[Dictionary] = []
	for m in markers():
		var pos: Vector3 = m["pos"]
		var d := wrapf(bearing(origin, pos) - h, -PI, PI)
		if absf(d) > HALF_FOV:
			continue
		var dist := Vector2(pos.x - origin.x, pos.z - origin.z).length()
		visible_markers.append({"x": cx + d / HALF_FOV * span, "dist": dist, "icon": m.get("icon", "landmark"),
			"max": float(m.get("max_dist", 260.0))})
	visible_markers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["dist"]) > float(b["dist"]))
	for vm in visible_markers:
		var tex := icon(String(vm["icon"]))
		if tex == null:
			continue
		var alpha := clampf(1.15 - float(vm["dist"]) / float(vm["max"]), 0.3, 1.0)
		draw_texture(tex, Vector2(float(vm["x"]) - 12.0, mid - 12.0), Color(1, 1, 1, alpha))
	# Centre pointer.
	var accent := ArtKit.color("color_roles.player_accent.body", Color(0.37, 0.88, 0.91))
	draw_line(Vector2(cx, 2.0), Vector2(cx, 8.0), accent, 2.0)
	draw_line(Vector2(cx, HEIGHT - 8.0), Vector2(cx, HEIGHT - 2.0), accent, 2.0)
