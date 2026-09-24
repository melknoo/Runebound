class_name Brute
extends EnemyBase
## Slow, stagger-resistant wall of stone. Long telegraphed overhead slam with
## a big ground disc — the enemy that teaches dodging on reaction.

const ATTACK_RANGE := 2.4
const SLAM_RADIUS := 2.5
const WINDUP_TIME := 0.9
const RECOVER_TIME := 1.3
const SLAM_DAMAGE := 25.0

var _arms_pivot: Node3D
var _telegraph_disc: MeshInstance3D


func _init() -> void:
	xp_value = 45
	display_name = "Stonehulk"
	max_health = 140.0
	move_speed = 2.2
	body_color = Color(0.45, 0.48, 0.42)
	stagger_resist = true


const RIG_PATH := "res://assets/models/chars/stonehulk.glb"


func _build_body() -> void:
	var rig_mesh := _setup_rigged_visual(RIG_PATH, "stonehulk", {
		"idle": &"idle", "run": &"run", "run_speed": move_speed,
		"states": {AIState.WINDUP: &"slam", AIState.STAGGER: &"stagger", AIState.CHASE: &"@loco",
			AIState.IDLE: &"@loco", AIState.DEAD: &"@dead"},
	}, ArtKit.color("palettes.stonehulk.eyes"))
	if rig_mesh != null:
		# The slam clip animates the arms; the old pivot tweens run on an
		# invisible stand-in (gameplay timing untouched).
		_arms_pivot = Node3D.new()
		_arms_pivot.name = "ArmsPivotStandIn"
		visual.add_child(_arms_pivot)
		return
	if _setup_model_visual("res://assets/models/enemy_brute.glb"):
		_build_arms()
		return
	# Fallback primitives: a walking boulder.
	var torso := MeshInstance3D.new()
	var torso_mesh := BoxMesh.new()
	torso_mesh.size = Vector3(1.1, 1.2, 0.7)
	torso_mesh.material = flat_material(body_color)
	torso.mesh = torso_mesh
	torso.position = Vector3(0, 0.9, 0)
	visual.add_child(torso)
	var head := MeshInstance3D.new()
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.45, 0.35, 0.4)
	head_mesh.material = flat_material(body_color.darkened(0.3))
	head.mesh = head_mesh
	head.position = Vector3(0, 1.65, -0.1)
	visual.add_child(head)
	var eyes := MeshInstance3D.new()
	var eyes_mesh := BoxMesh.new()
	eyes_mesh.size = Vector3(0.3, 0.06, 0.06)
	eyes_mesh.material = flat_material(Color(1.0, 0.5, 0.2), true, 2.0)
	eyes.mesh = eyes_mesh
	eyes.position = Vector3(0, 1.68, -0.31)
	visual.add_child(eyes)
	_build_arms()


func _build_arms() -> void:
	_arms_pivot = Node3D.new()
	_arms_pivot.position = Vector3(0, 1.35, 0)
	visual.add_child(_arms_pivot)
	for side: float in [-1.0, 1.0]:
		var fist := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.42, 0.42, 0.42)
		mesh.material = flat_material(body_color.darkened(0.15))
		fist.mesh = mesh
		fist.position = Vector3(side * 0.75, -0.4, -0.15)
		_arms_pivot.add_child(fist)


func _ai_process(delta: float) -> void:
	match ai_state:
		AIState.IDLE:
			brake(delta)
			if distance_to_player() < AGGRO_RANGE:
				_enter_state(AIState.CHASE)
		AIState.CHASE:
			face_player(delta, 5.0)
			move_towards(dir_to_player(), move_speed, delta)
			if distance_to_player() <= ATTACK_RANGE:
				_start_windup()
		AIState.WINDUP:
			brake(delta)
			face_player(delta, 1.5)  # barely tracks: walk out of the disc
			if _state_timer >= WINDUP_TIME:
				_slam()
		AIState.RECOVER:
			brake(delta)
			if _state_timer >= RECOVER_TIME:
				_enter_state(AIState.CHASE)
		AIState.STAGGER:
			brake(delta)
			if _state_timer >= 0.0:
				_enter_state(AIState.CHASE)


func _start_windup() -> void:
	_enter_state(AIState.WINDUP)
	var fwd := -visual.global_transform.basis.z
	_telegraph_disc = VFX.telegraph_disc(get_tree().current_scene,
		Vector3(global_position.x, 0.0, global_position.z) + fwd * 1.4,
		SLAM_RADIUS, WINDUP_TIME)
	var tw := _arms_pivot.create_tween()
	tw.tween_property(_arms_pivot, "rotation_degrees", Vector3(-130, 0, 0), WINDUP_TIME * 0.85) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	Sfx.play("earthbreaker_windup", global_position, -6.0, 0.1, 0.85)


func _slam() -> void:
	_enter_state(AIState.RECOVER)
	var fwd := -visual.global_transform.basis.z
	var impact_center := global_position + fwd * 1.4
	var tw := _arms_pivot.create_tween()
	tw.tween_property(_arms_pivot, "rotation_degrees", Vector3(40, 0, 0), 0.08) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	tw.tween_property(_arms_pivot, "rotation_degrees", Vector3.ZERO, 0.5) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	VFX.earthbreaker_slam(get_tree().current_scene, impact_center, SLAM_RADIUS)
	Sfx.play("earthbreaker_impact", impact_center, -4.0, 0.1, 0.9)
	GameFeel.camera_shake(0.25)

	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = SLAM_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), impact_center + Vector3(0, 0.5, 0))
	query.collision_mask = 0b1000
	query.collide_with_areas = true
	query.collide_with_bodies = false
	for result: Dictionary in space.intersect_shape(query, 4):
		var hb := result["collider"] as Hurtbox
		if hb != null and hb.owner_entity is Player:
			var hit := HitInfo.create(SLAM_DAMAGE, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.HEAVY, global_position)
			hit.knockback = 8.0
			(hb.owner_entity as Player).take_hit(hit)
			break


func _on_interrupted() -> void:
	if _telegraph_disc != null and is_instance_valid(_telegraph_disc):
		_telegraph_disc.queue_free()
	if _arms_pivot != null:
		var tw := _arms_pivot.create_tween()
		tw.tween_property(_arms_pivot, "rotation_degrees", Vector3.ZERO, 0.2)
