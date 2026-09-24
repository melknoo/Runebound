class_name CameraRig
extends Node3D
## Free third-person camera: yaw/pitch from mouse, spring-arm collision,
## wheel zoom, impact impulses and trauma shake. Follows a target's position
## without inheriting its rotation.

const PITCH_MIN := -1.134  # -65 degrees
const PITCH_MAX := 0.96    # +55 degrees
const ZOOM_MIN := 2.2
const ZOOM_MAX := 8.0
const ZOOM_STEP := 0.6
const AIM_RAY_LENGTH := 100.0
## World + enemies are aim-relevant; ignore hurtbox/projectile layers.
const AIM_COLLISION_MASK := 0b101

@export var sensitivity: float = 0.0026
@export var follow_height: float = 1.4

var target: Node3D = null

var _yaw: float = 0.0
var _pitch: float = -0.32
var _zoom: float = 4.6
var _trauma: float = 0.0
var _impulse: Vector3 = Vector3.ZERO
var _shake_time: float = 0.0

var yaw_node: Node3D
var pitch_node: Node3D
var spring: SpringArm3D
var camera: Camera3D
var _shake_node: Node3D


func _ready() -> void:
	yaw_node = Node3D.new()
	yaw_node.name = "Yaw"
	add_child(yaw_node)
	pitch_node = Node3D.new()
	pitch_node.name = "Pitch"
	yaw_node.add_child(pitch_node)
	spring = SpringArm3D.new()
	spring.spring_length = _zoom
	spring.collision_mask = 1  # world only; enemies never push the camera
	spring.margin = 0.3
	pitch_node.add_child(spring)
	# The spring positions this holder; shake offsets go on the camera below
	# so they never fight the spring's placement.
	_shake_node = Node3D.new()
	spring.add_child(_shake_node)
	camera = Camera3D.new()
	camera.fov = 68.0
	_shake_node.add_child(camera)
	camera.make_current()
	GameFeel.camera_rig = self
	top_level = true


func set_target(t: Node3D) -> void:
	target = t
	if t is CollisionObject3D:
		spring.add_excluded_object((t as CollisionObject3D).get_rid())
	if t != null:
		global_position = t.global_position + Vector3(0, follow_height, 0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * sensitivity
		_pitch = clampf(_pitch - motion.relative.y * sensitivity, PITCH_MIN, PITCH_MAX)
	elif event.is_action_pressed(&"zoom_in"):
		_zoom = maxf(_zoom - ZOOM_STEP, ZOOM_MIN)
	elif event.is_action_pressed(&"zoom_out"):
		_zoom = minf(_zoom + ZOOM_STEP, ZOOM_MAX)


func _process(delta: float) -> void:
	if target != null and is_instance_valid(target):
		# Hard position follow: lag between player and camera reads as mushy controls.
		global_position = target.global_position + Vector3(0, follow_height, 0)
	yaw_node.rotation.y = _yaw
	pitch_node.rotation.x = _pitch
	spring.spring_length = lerpf(spring.spring_length, _zoom, minf(12.0 * delta, 1.0))

	# Shake: trauma decays, offset applied to the camera only (never to aim math).
	var offset := _impulse
	if _trauma > 0.0:
		_shake_time += delta * 30.0
		var t := _trauma * _trauma
		offset += Vector3(
			sin(_shake_time * 2.3) * 0.12 * t,
			cos(_shake_time * 3.1) * 0.10 * t,
			0.0)
		_trauma = maxf(_trauma - delta * 2.2, 0.0)
	camera.position = offset
	_impulse = _impulse.lerp(Vector3.ZERO, minf(14.0 * delta, 1.0))


func add_impulse(dir: Vector3, strength: float) -> void:
	var local_dir := camera.global_transform.basis.inverse() * dir
	_impulse += local_dir.normalized() * strength


func add_trauma(amount: float) -> void:
	_trauma = minf(_trauma + amount, 1.0)


## Camera-forward yaw basis for movement input.
func get_flat_basis() -> Basis:
	return Basis(Vector3.UP, _yaw)


## Where the center-screen ray hits (far point if nothing hit). Enemies close
## to the aim line take priority over terrain: with a shoulder camera the
## crosshair often rests on the ground in front of a distant enemy, and
## projectiles must go where the player *means*, not into the floor.
const AIM_ASSIST_RADIUS := 0.8

## True when the last get_aim_point() landed on walkable ground (not an enemy,
## not a wall): projectiles then aim at chest height above that spot.
var last_aim_on_floor: bool = false


func get_aim_point(exclude: Array[RID] = []) -> Vector3:
	last_aim_on_floor = false
	var from := camera.global_position
	var dir := -camera.global_transform.basis.z
	var to := from + dir * AIM_RAY_LENGTH
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, AIM_COLLISION_MASK, exclude)
	var result := space.intersect_ray(query)
	var hit_pos := to
	if not result.is_empty():
		var collider := result["collider"] as CollisionObject3D
		if collider != null and (collider.collision_layer & 0b100) != 0:
			# Direct enemy hit: aim center mass, not the exact surface point —
			# a ray clipping the feet would send projectiles into the ground
			# right behind the target (kills pierce lines).
			return (collider as Node3D).global_position + Vector3(0, 0.9, 0)
		hit_pos = result["position"]
		last_aim_on_floor = (result["normal"] as Vector3).y > 0.7

	# Soft assist: sweep a capsule along the aim line, enemy layer only.
	# Extend past the terrain hit — the player aiming "at the ground" a few
	# meters short of an enemy almost always means the enemy.
	var seg_len := minf(from.distance_to(hit_pos) + 8.0, AIM_RAY_LENGTH)
	if seg_len < 1.5:
		return hit_pos
	var shape := CapsuleShape3D.new()
	shape.radius = AIM_ASSIST_RADIUS
	shape.height = seg_len
	var mid := from + dir * seg_len * 0.5
	var basis := Basis(Quaternion(Vector3.UP, dir.normalized()))
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = shape
	sq.transform = Transform3D(basis, mid)
	sq.collision_mask = 0b100
	sq.exclude = exclude
	var best: Node3D = null
	var best_along := INF
	for hit: Dictionary in space.intersect_shape(sq, 8):
		var body := hit["collider"] as Node3D
		if body == null:
			continue
		var along := (body.global_position - from).dot(dir)
		if along > 0.5 and along < best_along:
			best_along = along
			best = body
	if best != null:
		last_aim_on_floor = false
		return best.global_position + Vector3(0, 0.9, 0)
	return hit_pos
