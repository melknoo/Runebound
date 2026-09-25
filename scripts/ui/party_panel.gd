class_name PartyPanel
extends Control
## M09 party frames (HUD, left edge): every other hero in the zone with name,
## level and a health bar, plus the ping to the server. Only shown in co-op.

const WIDTH := 240.0
const BAR_H := 8.0
const ROW_H := 44.0

var zone: ZoneBase
var _title: Label
var _rows: VBoxContainer
var _row_of: Dictionary = {}  # peer -> {box, label, fill}
var _refresh_left: float = 0.0


func setup(z: ZoneBase) -> void:
	zone = z
	# Offsets, not `position`: added after the HUD into a sized viewport,
	# `position` would be absolute (the panel landed above the screen).
	set_anchors_preset(Control.PRESET_CENTER_LEFT)
	offset_left = 16.0
	offset_top = -120.0
	custom_minimum_size = Vector2(WIDTH, 0)
	UiTheme.apply(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame := PanelContainer.new()  # the HUD's pixel frame keeps it readable on bright ground
	frame.add_theme_stylebox_override("panel", UiTheme.nine("frame.png", 16, 10))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(col)
	_title = Label.new()
	_title.add_theme_color_override("font_color", UiTheme.MUTED)
	col.add_child(_title)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	col.add_child(_rows)


func _process(delta: float) -> void:
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = 0.1
	var ping := Net.ping_ms()
	_title.text = "Party  %s" % ("%d ms" % ping if ping >= 0 else "")
	var seen: Array[int] = []
	for p in zone.players:
		if p == null or not is_instance_valid(p) or p.is_local:
			continue
		seen.append(p.peer_id)
		var row: Dictionary = _row_of.get(p.peer_id, {})
		if row.is_empty():
			row = _make_row()
			_row_of[p.peer_id] = row
		var entry: Dictionary = Net.roster.get(p.peer_id, {})
		(row["label"] as Label).text = "%s  Lv%d" % [str(entry.get("name", "Hero")), int(entry.get("level", 1))]
		var frac := clampf(p.health.current_health / maxf(p.health.max_health, 1.0), 0.0, 1.0)
		(row["fill"] as ColorRect).size.x = (WIDTH - 4.0) * frac
		(row["label"] as Label).modulate = Color(1, 1, 1, 0.5) if p.health.is_dead else Color.WHITE
	for peer: int in _row_of.keys():
		if not seen.has(peer):
			((_row_of[peer] as Dictionary)["box"] as Control).queue_free()
			_row_of.erase(peer)
	visible = not _row_of.is_empty() or Net.is_client()


func _make_row() -> Dictionary:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(WIDTH, ROW_H)
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.add_child(box)
	var label := Label.new()
	box.add_child(label)
	var back := ColorRect.new()
	back.custom_minimum_size = Vector2(WIDTH, BAR_H + 4.0)
	back.color = UiTheme.INK
	box.add_child(back)
	var fill := ColorRect.new()
	fill.position = Vector2(2, 2)
	fill.size = Vector2(WIDTH - 4.0, BAR_H)
	fill.color = ArtKit.color("color_roles.health.body", Color("#D9423A"))
	back.add_child(fill)
	return {"box": box, "label": label, "fill": fill}
