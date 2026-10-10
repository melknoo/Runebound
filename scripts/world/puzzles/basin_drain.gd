class_name BasinDrain
extends PoiPuzzle
## M13: the settling basin's sluices. The basin stands under shallow water,
## and the Bloated Keeper is tough in it. Two levers, one at each wall: pull
## both within `window` seconds of each other and the basin runs dry for
## `seconds` (the keeper is laid bare); then the water comes back and the
## levers want pulling again. One hero runs from lever to lever; two pull at
## once. The pulls are requests; the authority keeps the times on the
## server's clock, every machine shows the water from them.

var seconds: float = 15.0
var window: float = 8.0
var levers: Array[Vector3] = []
var room_rect: Rect2 = Rect2()
var floor_y: float = 0.0
var _water: MeshInstance3D
var _handles: Array[Node3D] = []
var _shown_dry: bool = false
var _loaded: bool = false


static func build(zone: ZoneBase, layout: DungeonLayout, poi: Dictionary) -> BasinDrain:
	var d := BasinDrain.new()
	d.id = String(poi.get("id", ""))
	d.name = "Drain_" + d.id
	d.seconds = float(poi.get("seconds", 15.0))
	d.window = float(poi.get("window", 8.0))
	var room := layout.room(String(poi.get("room", "")))
	d.room_rect = DungeonLayout.rect_of(room)
	d.floor_y = float(room.get("floor", 0.0))
	var pulled: Array = []
	for l: Array in poi.get("levers", []):
		d.levers.append(Vector3(float(l[0]), d.floor_y, float(l[1])))
		pulled.append(0)
	d.act_range = maxf(d.room_rect.size.x, d.room_rect.size.y)
	d.state = {"pulled": pulled, "until": 0}
	d.set_meta(&"poi_id", d.id)
	d.position = ZoneLayout.pos_of(poi)
	d._build(poi.get("levers", []) as Array)
	zone.world.add_child(d)
	d._loaded = true
	return d


func now_msec() -> int:
	return IceBridge.now_msec(self)


## Dry right now (the keeper is laid bare).
func is_active() -> bool:
	return now_msec() < int(state.get("until", 0))


func is_dry() -> bool:
	return is_active()


func _build(lever_data: Array) -> void:
	_water = MeshInstance3D.new()
	_water.name = "BasinWater"
	var plane := BoxMesh.new()
	plane.size = Vector3(room_rect.size.x - 0.2, 0.06, room_rect.size.y - 0.2)
	var mat := ShaderMaterial.new()
	mat.shader = WaterChannel.WATER_SHADER
	var deep := ArtKit.color("palettes.cistern.water", Color(0.07, 0.2, 0.24))
	mat.set_shader_parameter(&"deep", deep.lightened(0.05))
	mat.set_shader_parameter(&"shallow", deep.lerp(ArtKit.color("palettes.cistern.water_hi", Color(0.18, 0.4, 0.44)), 0.5))
	plane.material = mat
	_water.mesh = plane
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_water)
	_water.position = Vector3(room_rect.get_center().x - position.x, 0.07, room_rect.get_center().y - position.z)
	for i in levers.size():
		var holder := Node3D.new()
		add_child(holder)
		holder.position = levers[i] - position
		holder.rotation.y = float((lever_data[i] as Array)[2]) if (lever_data[i] as Array).size() > 2 else 0.0
		var body := StaticBody3D.new()
		body.collision_layer = Grove.FOLIAGE_LAYER
		body.collision_mask = 0
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.8, 1.3, 0.5)
		col.shape = shape
		col.position = Vector3(0, 0.65, 0)
		body.add_child(col)
		holder.add_child(body)
		var base := MeshInstance3D.new()
		var base_mesh := BoxMesh.new()
		base_mesh.size = Vector3(0.8, 1.1, 0.5)
		base_mesh.material = EnemyBase.flat_material(Color(0.25, 0.29, 0.3))
		base.mesh = base_mesh
		base.position = Vector3(0, 0.55, 0)
		holder.add_child(base)
		var handle := Node3D.new()
		handle.position = Vector3(0, 1.1, 0.28)
		holder.add_child(handle)
		var bar := MeshInstance3D.new()
		var bar_mesh := BoxMesh.new()
		bar_mesh.size = Vector3(0.12, 1.0, 0.12)
		bar_mesh.material = EnemyBase.flat_material(Color(0.55, 0.4, 0.22))
		bar.mesh = bar_mesh
		bar.position = Vector3(0, 0.45, 0)
		handle.add_child(bar)
		_handles.append(handle)
		var sw := PuzzleSwitch.new()
		sw.text_key = "ui.prompt.pull"
		sw.reach = 2.2
		var index := i
		sw.on_use = func(hero: Player) -> void: request("pull", index, hero)
		sw.usable = func(_hero: Player) -> bool: return not is_dry() and not _pulled_now(index)
		holder.add_child(sw)
		sw.position = Vector3(0, 0.2, 0.7)


func _ready() -> void:
	super()
	if not Net.is_client() and int(state.get("until", 0)) != 0:
		state["until"] = 0  # a clock of an earlier session means nothing now
		(state["pulled"] as Array).fill(0)
		commit()


## Is lever i down (pulled within the window, waiting for the other)?
func _pulled_now(i: int) -> bool:
	var pulled: Array = state.get("pulled", [])
	return i < pulled.size() and int(pulled[i]) > 0 and now_msec() - int(pulled[i]) < int(window * 1000.0)


func act(action: String, arg: Variant, _hero: Player) -> void:
	if action != "pull" or is_dry():
		return
	var i := int(arg)
	var pulled: Array = state["pulled"]
	if i < 0 or i >= pulled.size():
		return
	var now := now_msec()
	pulled[i] = now
	var all := true
	for t in pulled:
		if int(t) <= 0 or now - int(t) > int(window * 1000.0):
			all = false
	if all:
		state["until"] = now + int(seconds * 1000.0)
		pulled.fill(0)
	commit()


func _process(_delta: float) -> void:
	var dry := is_dry()
	if dry != _shown_dry:
		_shown_dry = dry
		_present_water(true)
	if Engine.get_process_frames() % 10 == 0:
		_present_handles()


func _present() -> void:
	_present_handles()
	_present_water(_loaded)


func _present_handles() -> void:
	for i in _handles.size():
		_handles[i].rotation_degrees = Vector3(-70, 0, 0) if _pulled_now(i) or is_dry() else Vector3(35, 0, 0)


func _present_water(animate: bool) -> void:
	if _water == null:
		return
	var y := -0.5 if is_dry() else 0.07
	if not animate:
		_water.position.y = y
		return
	var tw := _water.create_tween()
	tw.tween_property(_water, "position:y", y, 1.2).set_trans(Tween.TRANS_SINE)
	Sfx.play("wave_surge", global_position, -6.0, 0.1, 0.8 if is_dry() else 1.0)
