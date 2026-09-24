class_name Assassin
extends EnemyBase
## Fast skirmisher: circles the player just out of reach, dashes in with a
## short telegraphed stab, then disengages. Punishes tunnel vision and
## rewards Tab-target switching. Fragile.

const CIRCLE_RADIUS := 5.0
const CIRCLE_TIME := 1.8
const DASH_SPEED := 9.5
const WINDUP_TIME := 0.35
const RETREAT_TIME := 1.6
const STAB_RANGE := 1.5
const STAB_DAMAGE := 9.0

var _circle_dir: float = 1.0
var _blade_pivot: Node3D
var _telegraph_disc: MeshInstance3D


func _init() -> void:
	xp_value = 24
	display_name = "Veilstalker"
	max_health = 30.0
	move_speed = 6.0
	body_color = Color(0.16, 0.45, 0.5)


const RIG_PATH := "res://assets/models/chars/veilstalker.glb"


func _build_body() -> void:
	var rig_mesh := _setup_rigged_visual(RIG_PATH, "veilstalker", {
		"idle": &"idle", "run": &"run", "run_speed": move_speed,
		"states": {AIState.CIRCLE: &"~strafe", AIState.ATTACK: &"~dash", AIState.WINDUP: &"stab",
			AIState.RETREAT: &"~retreat", AIState.STAGGER: &"stagger", AIState.CHASE: &"@loco",
			AIState.IDLE: &"@loco", AIState.DEAD: &"@dead"},
	}, ArtKit.color("palettes.veilstalker.eyes"))
	if rig_mesh != null:
		_blade_pivot = Node3D.new()
		_blade_pivot.name = "BladePivotStandIn"
		visual.add_child(_blade_pivot)
		return
	if _setup_model_visual("res://assets/models/enemy_assassin.glb"):
		_build_blades()
		return
	# Fallback primitives: slim and low, obviously fast.
	var torso := MeshInstance3D.new()
	var torso_mesh := BoxMesh.new()
	torso_mesh.size = Vector3(0.4, 0.75, 0.3)
	torso_mesh.material = flat_material(body_color)
	torso.mesh = torso_mesh
	torso.position = Vector3(0, 0.85, 0)
	visual.add_child(torso)
	var head := MeshInstance3D.new()
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.26, 0.26, 0.3)
	head_mesh.material = flat_material(body_color.darkened(0.35))
	head.mesh = head_mesh
	head.position = Vector3(0, 1.4, 0)
	visual.add_child(head)
	var eyes := MeshInstance3D.new()
	var eyes_mesh := BoxMesh.new()
	eyes_mesh.size = Vector3(0.18, 0.03, 0.05)
	eyes_mesh.material = flat_material(Color(0.5, 1.0, 0.9), true, 2.2)
	eyes.mesh = eyes_mesh
	eyes.position = Vector3(0, 1.42, -0.16)
	visual.add_child(eyes)
	_build_blades()


func _build_blades() -> void:
	_blade_pivot = Node3D.new()
	_blade_pivot.position = Vector3(0, 1.0, 0)
	visual.add_child(_blade_pivot)
	for side: float in [-1.0, 1.0]:
		var blade := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.04, 0.03, 0.55)
		mesh.material = flat_material(Color(0.8, 0.85, 0.9), true, 0.4)
		blade.mesh = mesh
		blade.position = Vector3(side * 0.35, 0, -0.25)
		_blade_pivot.add_child(blade)


func _ai_process(delta: float) -> void:
	match ai_state:
		AIState.IDLE:
			brake(delta)
			if distance_to_player() < AGGRO_RANGE:
				_enter_state(AIState.CHASE)
		AIState.CHASE:
			face_player(delta, 12.0)
			var dist := distance_to_player()
			if dist > CIRCLE_RADIUS + 1.0:
				move_towards(dir_to_player(), move_speed, delta)
			else:
				_enter_state(AIState.CIRCLE)
				_circle_dir = 1.0 if randf() < 0.5 else -1.0
		AIState.CIRCLE:
			face_player(delta, 12.0)
			var to_player := dir_to_player()
			var tangent := to_player.cross(Vector3.UP) * _circle_dir
			# Keep the ring distance while strafing around the player.
			var dist := distance_to_player()
			var radial := to_player * clampf(dist - CIRCLE_RADIUS, -1.0, 1.0)
			move_towards((tangent + radial).normalized(), move_speed * 0.85, delta)
			if _state_timer >= CIRCLE_TIME:
				_enter_state(AIState.ATTACK)  # dash-in phase
		AIState.ATTACK:
			face_player(delta, 14.0)
			move_towards(dir_to_player(), DASH_SPEED, delta)
			if distance_to_player() <= STAB_RANGE:
				_start_windup()
			elif _state_timer > 1.2:
				_enter_state(AIState.CIRCLE)
		AIState.WINDUP:
			brake(delta)
			face_player(delta, 5.0)
			if _state_timer >= WINDUP_TIME:
				_stab()
		AIState.RETREAT:
			face_player(delta, 10.0)
			move_towards(-dir_to_player(), move_speed, delta)
			if _state_timer >= RETREAT_TIME:
				_enter_state(AIState.CIRCLE)
		AIState.STAGGER:
			brake(delta)
			if _state_timer >= 0.0:
				_enter_state(AIState.RETREAT)


func _start_windup() -> void:
	_enter_state(AIState.WINDUP)
	var fwd := -visual.global_transform.basis.z
	_telegraph_disc = VFX.telegraph_disc(get_tree().current_scene,
		Vector3(global_position.x, 0.0, global_position.z) + fwd * 0.9,
		1.0, WINDUP_TIME)
	var tw := _blade_pivot.create_tween()
	tw.tween_property(_blade_pivot, "rotation_degrees", Vector3(0, 0, 90), WINDUP_TIME * 0.8)
	Sfx.play("telegraph", global_position, -8.0, 0.1, 1.4)


func _stab() -> void:
	_enter_state(AIState.RETREAT)
	var fwd := -visual.global_transform.basis.z
	var tw := _blade_pivot.create_tween()
	tw.tween_property(_blade_pivot, "position:z", -0.6, 0.06)
	tw.tween_property(_blade_pivot, "position:z", 0.0, 0.2)
	tw.parallel().tween_property(_blade_pivot, "rotation_degrees", Vector3.ZERO, 0.2)
	Sfx.play("swing", global_position, -8.0, 0.15, 1.5)

	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 0.9
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), global_position + Vector3(0, 0.9, 0) + fwd * 1.0)
	query.collision_mask = 0b1000
	query.collide_with_areas = true
	query.collide_with_bodies = false
	for result: Dictionary in space.intersect_shape(query, 4):
		var hb := result["collider"] as Hurtbox
		if hb != null and hb.owner_entity is Player:
			var hit := HitInfo.create(STAB_DAMAGE, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, global_position)
			hit.knockback = 2.0
			(hb.owner_entity as Player).take_hit(hit)
			VFX.enemy_hit(get_tree().current_scene, hb.owner_entity.global_position + Vector3(0, 1.0, 0))
			break


func _on_interrupted() -> void:
	if _telegraph_disc != null and is_instance_valid(_telegraph_disc):
		_telegraph_disc.queue_free()
	if _blade_pivot != null:
		var tw := _blade_pivot.create_tween()
		tw.tween_property(_blade_pivot, "rotation_degrees", Vector3.ZERO, 0.15)
