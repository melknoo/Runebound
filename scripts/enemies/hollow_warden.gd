class_name HollowWarden
extends EnemyBase
## Construct guardian that teaches flanking: damage from the front is halved
## (grey "blocked" feedback), its exposed rune core on the back takes full
## damage. Slow, wide telegraphed spin attack.

const FRONT_BLOCK_ANGLE := 1.05  # ~60° to each side counts as "front"
const FRONT_DAMAGE_MULT := 0.5
const ATTACK_RANGE := 2.2
const SPIN_RADIUS := 2.4
const WINDUP_TIME := 0.7
const RECOVER_TIME := 1.1
const SPIN_DAMAGE := 16.0

var _telegraph_disc: MeshInstance3D


func _init() -> void:
	display_name = "Hollow Warden"
	max_health = 90.0
	move_speed = 2.8
	body_color = Color(0.36, 0.34, 0.44)
	stagger_resist = true


func _build_body() -> void:
	if _setup_model_visual("res://assets/models/enemy_warden.glb"):
		return
	var torso := MeshInstance3D.new()
	var torso_mesh := BoxMesh.new()
	torso_mesh.size = Vector3(0.9, 1.1, 0.7)
	torso_mesh.material = flat_material(body_color)
	torso.mesh = torso_mesh
	torso.position = Vector3(0, 0.8, 0)
	visual.add_child(torso)
	var core := MeshInstance3D.new()
	var core_mesh := BoxMesh.new()
	core_mesh.size = Vector3(0.3, 0.3, 0.12)
	core_mesh.material = flat_material(Color(0.4, 1.0, 0.9), true, 3.0)
	core.mesh = core_mesh
	core.position = Vector3(0, 0.9, 0.4)  # back side
	visual.add_child(core)


## Frontal hits are blocked to half damage; flanking bypasses it entirely.
func take_hit(hit: HitInfo) -> bool:
	if ai_state != AIState.DEAD:
		var to_source := hit.source_position - global_position
		to_source.y = 0.0
		var fwd := -visual.global_transform.basis.z
		if to_source.length() > 0.05 and fwd.angle_to(to_source.normalized()) <= FRONT_BLOCK_ANGLE:
			hit.damage *= FRONT_DAMAGE_MULT
			# Feedback: metallic sparks + clink so the halving reads as a block.
			VFX.burst(get_tree().current_scene, global_position + Vector3(0, 1.0, 0) + fwd * 0.6, {
				"tex": "spark", "amount": 5, "lifetime": 0.2, "size": 0.14,
				"direction": fwd, "spread": 60.0, "vel_min": 2.0, "vel_max": 4.0,
				"colors": [Color(0.8, 0.85, 0.9), Color(0.5, 0.55, 0.6, 0.0)] as Array[Color],
			})
			Sfx.play("bolt_impact", global_position, -8.0, 0.1, 0.7)
	return super(hit)


func _ai_process(delta: float) -> void:
	match ai_state:
		AIState.IDLE:
			brake(delta)
			if distance_to_player() < AGGRO_RANGE:
				_enter_state(AIState.CHASE)
		AIState.CHASE:
			face_player(delta, 3.0)  # slow turner: flanking window is real
			move_towards(dir_to_player(), move_speed, delta)
			if distance_to_player() <= ATTACK_RANGE:
				_start_windup()
		AIState.WINDUP:
			brake(delta)
			if _state_timer >= WINDUP_TIME:
				_spin()
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
	_telegraph_disc = VFX.telegraph_disc(get_tree().current_scene,
		Vector3(global_position.x, 0.0, global_position.z), SPIN_RADIUS, WINDUP_TIME)
	Sfx.play("telegraph", global_position, -6.0, 0.1, 0.8)
	var tw := visual.create_tween()
	tw.tween_property(visual, "rotation:y", visual.rotation.y - 0.7, WINDUP_TIME * 0.85)


func _spin() -> void:
	_enter_state(AIState.RECOVER)
	var tw := visual.create_tween()
	tw.tween_property(visual, "rotation:y", visual.rotation.y + TAU + 0.7, 0.3) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	VFX.ground_ring(get_tree().current_scene, global_position, Color(0.5, 0.95, 0.85, 0.9), SPIN_RADIUS, 0.3)
	Sfx.play("swing", global_position, -4.0, 0.1, 0.7)
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = SPIN_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), global_position + Vector3(0, 0.9, 0))
	query.collision_mask = 0b1000
	query.collide_with_areas = true
	query.collide_with_bodies = false
	for result: Dictionary in space.intersect_shape(query, 4):
		var hb := result["collider"] as Hurtbox
		if hb != null and hb.owner_entity is Player:
			var hit := HitInfo.create(SPIN_DAMAGE, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.MEDIUM, global_position)
			hit.knockback = 5.0
			(hb.owner_entity as Player).take_hit(hit)
			break


func _on_interrupted() -> void:
	if _telegraph_disc != null and is_instance_valid(_telegraph_disc):
		_telegraph_disc.queue_free()
