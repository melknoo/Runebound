class_name WaterChannel
extends Node3D
## M13: the water in a sunken channel across a room. Full, it stands level
## with the floor and is deep: an invisible fence along it (foliage layer:
## heroes and enemies stop, the camera passes) keeps everyone out. Its
## valves (`inputs`, like a gate's: puzzle ids or `flag:<name>`) drain it:
## the water sinks and the causeways (`walkways`) laid in it show and carry
## heroes across; the fence then stands only where there is no causeway.
## Derived on every machine from the shared states, never refilled over a
## hero. Phase 3 lays temporary ice on a full channel (`freeze`).

const FENCE_HEIGHT := 5.0
const DRAIN_TIME := 1.6

var channel_id: String = ""
var rect: Rect2 = Rect2()
var floor_y: float = 0.0
var depth: float = 2.0
var inputs: Array[String] = []
var walkways: Array[Rect2] = []
var drained: bool = false
var _wants_drained: bool = false
var _water: MeshInstance3D
var _walkway_bodies: Array[StaticBody3D] = []
var _fence: StaticBody3D
var _built: bool = false


static func build(zone: ZoneBase, layout: DungeonLayout, poi: Dictionary) -> WaterChannel:
	var w := WaterChannel.new()
	var ch := layout.channel(String(poi.get("channel", "")))
	w.channel_id = String(poi.get("id", ""))
	w.name = "Water_" + w.channel_id
	w.rect = DungeonLayout.rect_of(ch)
	w.floor_y = float(ch.get("floor", 0.0))
	w.depth = float(ch.get("depth", 2.0))
	for i in poi.get("inputs", []):
		w.inputs.append(String(i))
	for r: Array in poi.get("walkways", []):
		w.walkways.append(Rect2(float(r[0]), float(r[1]), float(r[2]) - float(r[0]), float(r[3]) - float(r[1])))
	w.set_meta(&"poi_id", w.channel_id)
	w.position = Vector3(w.rect.get_center().x, w.floor_y, w.rect.get_center().y)  # before add_child: _ready places in world space
	zone.world.add_child(w)
	return w


func _ready() -> void:
	_water = MeshInstance3D.new()
	_water.name = "Water"
	var plane := BoxMesh.new()
	plane.size = Vector3(rect.size.x, 0.1, rect.size.y)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.09, 0.27, 0.31)
	mat.roughness = 0.15
	mat.metallic_specular = 0.8
	mat.emission_enabled = true
	mat.emission = Color(0.05, 0.2, 0.22)
	plane.material = mat
	_water.mesh = plane
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_water)
	_water.position.y = _level_y(false)
	for wr in walkways:
		var body := StaticBody3D.new()
		body.name = "Causeway"
		body.collision_layer = 0
		body.collision_mask = 0
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(wr.size.x, depth, wr.size.y)
		col.shape = shape
		body.add_child(col)
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = shape.size
		box.material = EnemyBase.flat_material(Color(0.32, 0.34, 0.35))
		mesh.mesh = box
		body.add_child(mesh)
		add_child(body)
		body.global_position = Vector3(wr.get_center().x, floor_y - depth * 0.5, wr.get_center().y)
		_walkway_bodies.append(body)
	_fence = StaticBody3D.new()
	_fence.name = "Fence"
	_fence.collision_layer = Grove.FOLIAGE_LAYER
	_fence.collision_mask = 0
	add_child(_fence)
	_built = true
	_rebuild_fence()


## The water's surface: level with the floor when full, low when drained.
func _level_y(low: bool) -> float:
	return -depth + 0.35 if low else 0.02  # full: just over the causeway


## Every input holds? (the same rules as DungeonGate)
func evaluate(puzzles: Dictionary) -> bool:
	if inputs.is_empty():
		return false
	for input in inputs:
		if input.begins_with("flag:"):
			if not SaveGame.has_flag(StringName(input.trim_prefix("flag:"))):
				return false
		else:
			var p := puzzles.get(input) as PoiPuzzle
			if p == null or not p.is_active():
				return false
	return true


func refresh(puzzles: Dictionary, instant: bool = false) -> void:
	_wants_drained = evaluate(puzzles)
	_apply(instant)


func _apply(instant: bool) -> void:
	if _wants_drained == drained or not _built:
		return
	if not _wants_drained and _someone_in_channel():
		return  # refills once nobody stands in it (_process retries)
	drained = _wants_drained
	for body in _walkway_bodies:
		body.collision_layer = 1 if drained else 0  # a floor: the ground seam and the camera see it
	_rebuild_fence()
	var y := _level_y(drained)
	if instant:
		_water.position.y = y
		return
	var tw := _water.create_tween()
	tw.tween_property(_water, "position:y", y, DRAIN_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	Sfx.play("frost_nova", global_position, -10.0, 0.1, 0.5)


func _process(_delta: float) -> void:
	if _wants_drained != drained:
		_apply(false)


## The fence covers the channel except where a causeway carries heroes.
func _rebuild_fence() -> void:
	for child in _fence.get_children():
		child.queue_free()
	var holes: Array[Rect2] = []
	if drained:
		holes.append_array(walkways)
	for part in DungeonBuilder.subtract(rect, holes):
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(part.size.x, FENCE_HEIGHT + depth, part.size.y)
		col.shape = shape
		_fence.add_child(col)
		col.global_position = Vector3(part.get_center().x, floor_y + (FENCE_HEIGHT - depth) * 0.5, part.get_center().y)


func _someone_in_channel() -> bool:
	var zone := ZoneBase.zone_of(self)
	if zone == null:
		return false
	for p in zone.players:
		if p != null and is_instance_valid(p) and rect.grow(0.4).has_point(Vector2(p.global_position.x, p.global_position.z)):
			return true
	return false


## Can a hero cross here right now (tests): drained and on a causeway.
func crossable_at(x: float, z: float) -> bool:
	if not drained:
		return false
	for wr in walkways:
		if wr.has_point(Vector2(x, z)):
			return true
	return false
