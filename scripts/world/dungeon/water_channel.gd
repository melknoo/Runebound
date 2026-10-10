class_name WaterChannel
extends Node3D
## M13: the water in a sunken channel across a room. Full, it stands level
## with the floor and is deep: an invisible fence along it (foliage layer:
## heroes and enemies stop, the camera passes) keeps everyone out. Its
## valves (`inputs`, like a gate's: puzzle ids or `flag:<name>`) drain it:
## the water sinks and the causeways (`walkways`) laid in it show and carry
## heroes across; the fence then stands only where there is no causeway.
## Derived on every machine from the shared states, never refilled over a
## hero. Phase 3 lays temporary ice on a full channel (`freeze`). Phase 6: a
## channel of kind "lava" glows instead (the zone's lava colours) and, with
## no inputs, never drains - a fenced runnel of fire.

const FENCE_HEIGHT := 5.0
const DRAIN_TIME := 1.6
const WATER_SHADER := preload("res://shaders/water_pixel.gdshader")
const LAVA_SHADER := preload("res://shaders/lava_pixel.gdshader")

var channel_id: String = ""
var rect: Rect2 = Rect2()
var floor_y: float = 0.0
var depth: float = 2.0
var lava: bool = false
var inputs: Array[String] = []
var walkways: Array[Rect2] = []
var drained: bool = false
var _wants_drained: bool = false
var _water: MeshInstance3D
var _walkway_bodies: Array[StaticBody3D] = []
var _fence: StaticBody3D
var _built: bool = false
## Phase 3: ice anchors in this channel (IceBridge) and their floes.
var ice_bridges: Array[IceBridge] = []
var _ice_bodies: Array[StaticBody3D] = []
var _ice_on: Array[bool] = []


static func build(zone: ZoneBase, layout: DungeonLayout, poi: Dictionary) -> WaterChannel:
	var w := WaterChannel.new()
	var ch := layout.channel(String(poi.get("channel", "")))
	w.channel_id = String(poi.get("id", ""))
	w.name = "Water_" + w.channel_id
	w.rect = DungeonLayout.rect_of(ch)
	w.floor_y = float(ch.get("floor", 0.0))
	w.depth = float(ch.get("depth", 2.0))
	w.lava = String(ch.get("kind", "water")) == "lava"
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
	plane.material = lava_material() if lava else _water_material()
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


## Opaque pixel ripples in the zone's water colours.
static func _water_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	var deep := ArtKit.color("palettes.cistern.water", Color(0.07, 0.2, 0.24))
	mat.set_shader_parameter(&"deep", deep)
	mat.set_shader_parameter(&"shallow", deep.lerp(ArtKit.color("palettes.cistern.water_hi", Color(0.18, 0.4, 0.44)), 0.45))
	mat.set_shader_parameter(&"glint", ArtKit.color("palettes.cistern.water_hi", Color(0.36, 0.62, 0.64)).lightened(0.15))
	return mat


static var _lava_mat: ShaderMaterial


## Phase 6: crust plates and glowing cracks in the Warrens' lava colours
## (shared: every lava surface pulses alike).
static func lava_material() -> ShaderMaterial:
	if _lava_mat == null:
		_lava_mat = ShaderMaterial.new()
		_lava_mat.shader = LAVA_SHADER
		_lava_mat.set_shader_parameter(&"crust", ArtKit.color("palettes.warrens.lava_crust", Color(0.16, 0.07, 0.05)))
		_lava_mat.set_shader_parameter(&"hot", ArtKit.color("palettes.warrens.lava", Color(0.72, 0.25, 0.1)))
		_lava_mat.set_shader_parameter(&"glow", ArtKit.color("palettes.warrens.lava_hi", Color(1.0, 0.69, 0.25)))
	return _lava_mat


## The water's surface: level with the floor when full, low when drained.
func _level_y(low: bool) -> float:
	if lava and not low:
		return -0.35  # lava sits a little under the floor's lip (it reads as a runnel)
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
	var changed := false
	for i in ice_bridges.size():
		var want := not drained and is_instance_valid(ice_bridges[i]) and ice_bridges[i].is_active()
		if not want and _ice_on[i] and _someone_on(ice_bridges[i].strip):
			want = true  # never melts under a hero: it holds until the strip is clear
		if want != _ice_on[i]:
			_ice_on[i] = want
			_set_floe(i, want)
			changed = true
	if changed:
		_rebuild_fence()


## Phase 3: a frozen strip for this anchor - a floe level with the floor.
func link_ice(bridge: IceBridge) -> void:
	ice_bridges.append(bridge)
	_ice_on.append(false)
	var body := StaticBody3D.new()
	body.name = "Floe"
	body.collision_layer = 0
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(bridge.strip.size.x, 0.5, bridge.strip.size.y)
	col.shape = shape
	body.add_child(col)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = shape.size + Vector3(0.0, 0.06, 0.0)
	box.material = EnemyBase.flat_material(Color(0.78, 0.92, 1.0), true, 0.35)
	mesh.mesh = box
	mesh.position = Vector3(0, 0.06, 0)  # its face just over the water's
	body.add_child(mesh)
	body.visible = false
	add_child(body)
	body.global_position = Vector3(bridge.strip.get_center().x, floor_y - 0.25, bridge.strip.get_center().y)
	_ice_bodies.append(body)


func _set_floe(i: int, on: bool) -> void:
	var body := _ice_bodies[i]
	body.collision_layer = 1 if on else 0  # a floor while it holds
	body.visible = on


func ice_active(i: int) -> bool:
	return i < _ice_on.size() and _ice_on[i]


func _someone_on(strip: Rect2) -> bool:
	var zone := ZoneBase.zone_of(self)
	if zone == null:
		return false
	for p in zone.players:
		if p != null and is_instance_valid(p) and strip.grow(0.3).has_point(Vector2(p.global_position.x, p.global_position.z)):
			return true
	return false


## The fence covers the channel except where a causeway carries heroes.
func _rebuild_fence() -> void:
	for child in _fence.get_children():
		child.queue_free()
	var holes: Array[Rect2] = []
	if drained:
		holes.append_array(walkways)
	for i in ice_bridges.size():
		if _ice_on[i]:
			holes.append(ice_bridges[i].strip)
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
