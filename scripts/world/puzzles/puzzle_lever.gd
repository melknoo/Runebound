class_name PuzzleLever
extends PoiPuzzle
## M13: a lever (or a sluice valve, the same thing with a wheel) used with
## [E]. One-way by default: pulled once, it stays (`solved`), which is what
## gates, water and shortcuts wait on; a toggle lever flips each time. The
## pull is a request, the authority keeps the state for the party.

var one_way: bool = true
## "lever" (a handle) or "valve" (a wheel).
var look: String = "lever"
var _handle: Node3D
var _switch: PuzzleSwitch
var _loaded: bool = false


static func build(zone: ZoneBase, poi: Dictionary) -> PuzzleLever:
	var l := PuzzleLever.new()
	l.id = String(poi.get("id", ""))
	l.name = "Lever_" + l.id
	l.one_way = not bool(poi.get("toggle", false))
	l.look = String(poi.get("look", "lever"))
	l.act_range = 4.0
	l.state = {"on": false, "solved": false}
	l.set_meta(&"poi_id", l.id)
	l.position = ZoneLayout.pos_of(poi)
	l.rotation.y = float(poi.get("yaw", 0.0))
	l._build()
	zone.world.add_child(l)
	return l


func is_on() -> bool:
	return bool(state.get("on", false))


func is_active() -> bool:
	return is_on()


func _build() -> void:
	var post := StaticBody3D.new()
	post.collision_layer = Grove.FOLIAGE_LAYER
	post.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.7, 1.2, 0.5)
	col.shape = shape
	col.position = Vector3(0, 0.6, 0)
	post.add_child(col)
	add_child(post)
	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(0.7, 1.0, 0.5)
	base_mesh.material = EnemyBase.flat_material(Color(0.3, 0.32, 0.34))
	base.mesh = base_mesh
	base.position = Vector3(0, 0.5, 0)
	add_child(base)
	_handle = Node3D.new()
	_handle.position = Vector3(0, 1.0, 0.28)
	add_child(_handle)
	var part := MeshInstance3D.new()
	if look == "valve":
		var wheel := CylinderMesh.new()
		wheel.top_radius = 0.42
		wheel.bottom_radius = 0.42
		wheel.height = 0.08
		wheel.material = EnemyBase.flat_material(Color(0.55, 0.4, 0.22))
		part.mesh = wheel
		part.rotation_degrees = Vector3(90, 0, 0)
	else:
		var bar := BoxMesh.new()
		bar.size = Vector3(0.1, 0.9, 0.1)
		bar.material = EnemyBase.flat_material(Color(0.55, 0.4, 0.22))
		part.mesh = bar
		part.position = Vector3(0, 0.4, 0)
	_handle.add_child(part)
	_switch = PuzzleSwitch.new()
	_switch.text_key = "ui.prompt.valve" if look == "valve" else "ui.prompt.pull"
	_switch.reach = 2.2
	_switch.on_use = func(hero: Player) -> void: request("pull", 0, hero)
	_switch.usable = func(_hero: Player) -> bool: return not (one_way and is_on())
	add_child(_switch)
	_switch.position = Vector3(0, 0.2, 0.6)


func _ready() -> void:
	super()
	_loaded = true


func act(action: String, _arg: Variant, _hero: Player) -> void:
	if action != "pull" or (one_way and is_on()):
		return
	state["on"] = not is_on()
	state["solved"] = is_on() if one_way else false
	commit()


func _present() -> void:
	if _handle == null:
		return
	var want := Vector3(0, 0, -150) if look == "valve" and is_on() else (Vector3(-70, 0, 0) if is_on() else Vector3(35, 0, 0))
	if look == "valve" and not is_on():
		want = Vector3.ZERO
	if not _loaded:
		_handle.rotation_degrees = want
		return
	var tw := _handle.create_tween()
	tw.tween_property(_handle, "rotation_degrees", want, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play("block_clang", global_position, -8.0, 0.1, 0.8 if look == "valve" else 1.1)
