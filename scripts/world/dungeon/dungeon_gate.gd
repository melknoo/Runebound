class_name DungeonGate
extends Node3D
## M13: bars across a dungeon doorway that open when everything they wait on
## holds: world flags ("flag:<name>", a boss's fall) and puzzles by POI id
## (PoiPuzzle.is_active: solved, or a plate weighed down right now). The gate
## keeps no state of its own - every machine derives it from the replicated
## flags and puzzle states, so a late joiner sees it right. The bars stand on
## the foliage layer: heroes and enemies bump them, the camera passes, and a
## gate that closes again never shuts while a hero stands in its doorway.

const SINK_TIME := 0.9
const BAR_SPACING := 0.55

var door_id: String = ""
var inputs: Array[String] = []
## The doorway on XZ and its floor (DungeonLayout door entry).
var rect: Rect2 = Rect2()
var floor_y: float = 0.0
var height: float = 4.5
var is_open: bool = false
var _body: StaticBody3D
var _bars: MeshInstance3D
var _built: bool = false
var _wants_open: bool = false


static func build(zone: ZoneBase, door: Dictionary) -> DungeonGate:
	var g := DungeonGate.new()
	g.door_id = String(door.get("id", ""))
	g.name = "Gate_" + g.door_id
	for i in door.get("inputs", []):
		g.inputs.append(String(i))
	g.rect = DungeonLayout.rect_of(door)
	g.floor_y = float(door.get("floor", 0.0))
	g.height = minf(float(door.get("wall_h", 6.0)), 4.5)
	zone.world.add_child(g)
	g.global_position = Vector3(g.rect.get_center().x, g.floor_y, g.rect.get_center().y)
	return g


func _ready() -> void:
	_build_bars()


## Bars along the doorway's width, in its middle (across the walking axis).
func _build_bars() -> void:
	var across_x := rect.size.x >= rect.size.y  # the bars span the longer side (the door's width)
	var width := rect.size.x if across_x else rect.size.y
	var st := SurfaceTool.new()
	var count := maxi(int(width / BAR_SPACING), 2)
	for i in count + 1:
		var t := -width * 0.5 + width * float(i) / float(count)
		var bar := BoxMesh.new()
		bar.size = Vector3(0.12, height, 0.12)
		st.append_from(bar, 0, Transform3D(Basis(), Vector3(t, height * 0.5, 0) if across_x else Vector3(0, height * 0.5, t)))
	for y: float in [0.6, height * 0.55, height - 0.2]:
		var rail := BoxMesh.new()
		rail.size = Vector3(width, 0.14, 0.16) if across_x else Vector3(0.16, 0.14, width)
		st.append_from(rail, 0, Transform3D(Basis(), Vector3(0, y, 0)))
	_bars = MeshInstance3D.new()
	_bars.name = "Bars"
	_bars.mesh = st.commit()
	_bars.material_override = EnemyBase.flat_material(Color(0.2, 0.22, 0.24))
	add_child(_bars)
	_body = StaticBody3D.new()
	_body.collision_layer = Grove.FOLIAGE_LAYER
	_body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, height, 0.4) if across_x else Vector3(0.4, height, width)
	col.shape = shape
	col.position = Vector3(0, height * 0.5, 0)
	_body.add_child(col)
	add_child(_body)
	_built = true


## Every input holds? `puzzles`: the zone's PoiPuzzles by id.
func evaluate(puzzles: Dictionary) -> bool:
	for input in inputs:
		if input.begins_with("flag:"):
			if not SaveGame.has_flag(StringName(input.trim_prefix("flag:"))):
				return false
		else:
			var p := puzzles.get(input) as PoiPuzzle
			if p == null or not p.is_active():
				return false
	return true


## Opens or closes to match its inputs; `instant` on load (no animation).
func refresh(puzzles: Dictionary, instant: bool = false) -> void:
	_wants_open = evaluate(puzzles)
	_apply(instant)


func _apply(instant: bool) -> void:
	if _wants_open == is_open or not _built:
		return
	if not _wants_open and _someone_in_doorway():
		return  # closes once the doorway is clear (_process retries)
	is_open = _wants_open
	_body.collision_layer = 0 if is_open else Grove.FOLIAGE_LAYER
	var y := -height - 0.2 if is_open else 0.0
	if instant:
		_bars.position.y = y
		return
	var tw := _bars.create_tween()
	tw.tween_property(_bars, "position:y", y, SINK_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	Sfx.play("block_clang", global_position, -6.0, 0.1, 0.6)


func _process(_delta: float) -> void:
	if _wants_open != is_open:
		_apply(false)


func _someone_in_doorway() -> bool:
	var zone := ZoneBase.zone_of(self)
	if zone == null:
		return false
	var grown := rect.grow(0.6)
	for p in zone.players:
		if p != null and is_instance_valid(p) and grown.has_point(Vector2(p.global_position.x, p.global_position.z)):
			return true
	return false
