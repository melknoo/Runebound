class_name BeamPuzzle
extends PoiPuzzle
## M13: a light beam and turnable crystals. The source shines one way; a
## crystal the beam meets sends it on in the direction it faces (eight
## steps of 45 degrees, [E] turns it one step); walls stop it. When the beam
## reaches the receiver the puzzle is solved for good (gates wait on it).
## Every machine traces the beam from the shared state for its look; the
## authority traces it to judge a turn.

const BEAM_Y := 1.25
const HIT_TOL := 0.6
const MAX_LEGS := 8
const FREE_RANGE := 40.0
const SOLVE_XP := 60

var source: Vector3 = Vector3.ZERO
var source_dir: int = 0
var mirrors: Array[Vector3] = []
var receiver: Vector3 = Vector3.ZERO
var _mirror_nodes: Array[Node3D] = []
var _segments: Array[MeshInstance3D] = []
var _receiver_mat: StandardMaterial3D
var _loaded: bool = false


static func dir_vec(k: int) -> Vector3:
	var a := float(posmod(k, 8)) * PI * 0.25
	return Vector3(sin(a), 0.0, cos(a))


static func build(zone: ZoneBase, poi: Dictionary) -> BeamPuzzle:
	var b := BeamPuzzle.new()
	b.id = String(poi.get("id", ""))
	b.name = "Beam_" + b.id
	b.source = ZoneLayout.pos_of(poi)
	b.source_dir = int(poi.get("dir", 0))
	var rot: Array = []
	for m: Array in poi.get("mirrors", []):
		var p := Vector3(float(m[0]), zone.ground_y(Vector3(float(m[0]), 0, float(m[1]))), float(m[1]))
		b.mirrors.append(p)
		rot.append(int(m[2]) if m.size() > 2 else 0)
	var r: Array = poi.get("receiver", [0, 0])
	b.receiver = Vector3(float(r[0]), zone.ground_y(Vector3(float(r[0]), 0, float(r[1]))), float(r[1]))
	var reach := 6.0
	for m in b.mirrors:
		reach = maxf(reach, m.distance_to(b.source) + 4.0)
	b.act_range = reach
	b.state = {"rot": rot, "solved": false}
	b.set_meta(&"poi_id", b.id)
	b.position = b.source
	zone.world.add_child(b)  # loads a saved state
	b._build()
	b._present()  # still without animation
	b._loaded = true
	return b


func is_active() -> bool:
	return is_solved()


func _build() -> void:
	# the source: a lamp on a pedestal
	_pedestal(Vector3.ZERO, Color(0.95, 0.9, 0.6))
	for i in mirrors.size():
		var holder := _pedestal(mirrors[i] - source, Color(0.6, 0.9, 1.0))
		var crystal := MeshInstance3D.new()
		var plate := BoxMesh.new()
		plate.size = Vector3(0.9, 1.0, 0.12)
		plate.material = EnemyBase.flat_material(Color(0.55, 0.85, 0.95), true, 0.6)
		crystal.mesh = plate
		crystal.position = Vector3(0, BEAM_Y, 0)
		holder.add_child(crystal)
		_mirror_nodes.append(holder)
		var sw := PuzzleSwitch.new()
		sw.text_key = "ui.prompt.turn"
		sw.reach = 2.4
		var index := i
		sw.on_use = func(hero: Player) -> void: request("turn", index, hero)
		sw.usable = func(_hero: Player) -> bool: return not is_solved()
		add_child(sw)
		sw.position = mirrors[i] - source + Vector3(0, 0.2, 0)
	var socket := _pedestal(receiver - source, Color(0.3, 0.3, 0.32))
	_receiver_mat = EnemyBase.flat_material(Color(0.95, 0.85, 0.5), true, 0.2)
	var ring := MeshInstance3D.new()
	var orb := SphereMesh.new()
	orb.radius = 0.3
	orb.height = 0.6
	orb.material = _receiver_mat
	ring.mesh = orb
	ring.position = Vector3(0, BEAM_Y, 0)
	socket.add_child(ring)
	var glow := EnemyBase.flat_material(Color(1.0, 0.92, 0.6), true, 3.0)
	for k in MAX_LEGS + 1:
		var seg := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.09, 0.09, 1.0)
		box.material = glow
		seg.mesh = box
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		seg.visible = false
		add_child(seg)
		_segments.append(seg)


## A pedestal (on the foliage layer: heroes bump it, the camera passes).
func _pedestal(local: Vector3, top: Color) -> Node3D:
	var holder := Node3D.new()
	add_child(holder)
	holder.position = local
	var body := StaticBody3D.new()
	body.collision_layer = Grove.FOLIAGE_LAYER
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.7, 0.9, 0.7)
	col.shape = shape
	col.position = Vector3(0, 0.45, 0)
	body.add_child(col)
	holder.add_child(body)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.7, 0.9, 0.7)
	box.material = EnemyBase.flat_material(Color(0.3, 0.32, 0.34))
	mesh.mesh = box
	mesh.position = col.position
	holder.add_child(mesh)
	var cap := MeshInstance3D.new()
	var cap_mesh := BoxMesh.new()
	cap_mesh.size = Vector3(0.3, 0.12, 0.3)
	cap_mesh.material = EnemyBase.flat_material(top, true, 1.0)
	cap.mesh = cap_mesh
	cap.position = Vector3(0, 0.96, 0)
	holder.add_child(cap)
	return holder


## The beam's path for the current state: {points, reached}.
func trace() -> Dictionary:
	var rot: Array = state.get("rot", [])
	var lift := Vector3(0, BEAM_Y, 0)
	var cur := source + lift
	var dir := dir_vec(source_dir)
	var points: Array[Vector3] = [cur]
	var at := -1  # the crystal the beam leaves (-1: the source)
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	for leg in MAX_LEGS:
		var best_t := INF
		var best := -2
		for i in mirrors.size() + 1:
			if i == at:
				continue
			var p := (mirrors[i] if i < mirrors.size() else receiver) + lift
			var v := p - cur
			var t := v.dot(dir)
			if t < 0.5 or (v - dir * t).length() > HIT_TOL:
				continue
			if t < best_t:
				best_t = t
				best = i
		var end := cur + dir * (best_t if best >= 0 else FREE_RANGE)
		if space != null:
			var q := PhysicsRayQueryParameters3D.create(cur, end, 1)
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				points.append(hit["position"] as Vector3)
				return {"points": points, "reached": false}
		points.append(end)
		if best < 0:
			return {"points": points, "reached": false}
		if best == mirrors.size():
			return {"points": points, "reached": true}
		at = best
		cur = end
		dir = dir_vec(int(rot[best]) if best < rot.size() else 0)
	return {"points": points, "reached": false}


func act(action: String, arg: Variant, _hero: Player) -> void:
	if action != "turn" or is_solved():
		return
	var i := int(arg)
	var rot: Array = state["rot"]
	if i < 0 or i >= rot.size():
		return
	rot[i] = (int(rot[i]) + 1) % 8
	if bool(trace()["reached"]):
		state["solved"] = true
		reward_party(SOLVE_XP, "ui.puzzle.solved")
	commit()


func _present() -> void:
	if _segments.is_empty():
		return
	var rot: Array = state.get("rot", [])
	for i in _mirror_nodes.size():
		var yaw := float(int(rot[i]) if i < rot.size() else 0) * PI * 0.25
		if _loaded:
			var tw := _mirror_nodes[i].create_tween()
			var cur := _mirror_nodes[i].rotation.y
			tw.tween_property(_mirror_nodes[i], "rotation:y", cur + wrapf(yaw - cur, -PI, PI), 0.25)
		else:
			_mirror_nodes[i].rotation.y = yaw
	var path := trace()
	var points: Array = path["points"]
	for k in _segments.size():
		var on := k < points.size() - 1
		_segments[k].visible = on
		if on:
			var a: Vector3 = points[k]
			var b: Vector3 = points[k + 1]
			if a.distance_to(b) < 0.05:
				_segments[k].visible = false
				continue
			_segments[k].global_position = (a + b) * 0.5
			_segments[k].look_at(b, Vector3.UP)
			_segments[k].scale = Vector3(1.0, 1.0, a.distance_to(b))
	_receiver_mat.emission_energy_multiplier = 3.0 if bool(path["reached"]) or is_solved() else 0.2
