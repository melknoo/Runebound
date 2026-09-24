class_name MeleeRusher
extends EnemyBase
## Squat, axe-carrying rusher: closes distance fast, telegraphed overhead chop.

const ATTACK_RANGE := 1.9
const WINDUP_TIME := 0.55
const ATTACK_TIME := 0.15
const RECOVER_TIME := 0.7
const ATTACK_DAMAGE := 12.0

var _axe_pivot: Node3D
var _axe_glow: StandardMaterial3D
var _telegraph_disc: MeshInstance3D


func _init() -> void:
	xp_value = 20
	display_name = "Cinder Marauder"
	max_health = 55.0
	move_speed = 4.3
	body_color = Color(0.72, 0.32, 0.22)


const RIG_PATH := "res://assets/models/chars/cinder_marauder.glb"


func _build_body() -> void:
	var rig_mesh := _setup_rigged_visual(RIG_PATH, "cinder_marauder", {
		"idle": &"idle", "run": &"run", "run_speed": move_speed,
		"states": {AIState.WINDUP: &"attack", AIState.STAGGER: &"stagger", AIState.CHASE: &"@loco",
			AIState.IDLE: &"@loco", AIState.DEAD: &"@dead"},
	}, ArtKit.color("palettes.cinder_marauder.eyes"))
	if rig_mesh != null:
		# The axe blade (surface 2) keeps the telegraph ramp: code-owned material,
		# never in the hit-flash list. The pivot is an invisible stand-in so the
		# existing windup/strike tweens stay untouched (the clip animates the arm).
		_axe_glow = flat_material(Color(0.62, 0.6, 0.66))
		# emission stays on at energy 0: the windup ramps energy only, so the
		# first telegraph never compiles a new shader variant mid-fight
		_axe_glow.emission_enabled = true
		_axe_glow.emission = Color(1.0, 0.4, 0.2)
		_axe_glow.emission_energy_multiplier = 0.0
		_axe_glow.set_meta(ArtKit.KEEP_EMISSION, true)
		rig_mesh.set_surface_override_material(2, _axe_glow)
		_axe_pivot = Node3D.new()
		_axe_pivot.name = "AxePivotStandIn"
		visual.add_child(_axe_pivot)
		return
	if _setup_model_visual("res://assets/models/enemy_rusher.glb"):
		_build_axe()
		return
	# Fallback primitives: wide, low silhouette that reads as "will run at you".
	var torso := MeshInstance3D.new()
	var torso_mesh := BoxMesh.new()
	torso_mesh.size = Vector3(0.85, 0.7, 0.5)
	torso_mesh.material = flat_material(body_color)
	torso.mesh = torso_mesh
	torso.position = Vector3(0, 0.75, 0)
	visual.add_child(torso)

	var head := MeshInstance3D.new()
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.35, 0.3, 0.35)
	head_mesh.material = flat_material(body_color.darkened(0.25))
	head.mesh = head_mesh
	head.position = Vector3(0, 1.28, -0.05)
	visual.add_child(head)

	var eyes := MeshInstance3D.new()
	var eyes_mesh := BoxMesh.new()
	eyes_mesh.size = Vector3(0.26, 0.06, 0.06)
	eyes_mesh.material = flat_material(Color(1.0, 0.85, 0.3), true, 2.0)
	eyes.mesh = eyes_mesh
	eyes.position = Vector3(0, 1.3, -0.22)
	visual.add_child(eyes)
	_build_axe()


func _build_axe() -> void:
	_axe_pivot = Node3D.new()
	_axe_pivot.position = Vector3(0.5, 1.0, 0)
	visual.add_child(_axe_pivot)
	var handle := MeshInstance3D.new()
	var handle_mesh := BoxMesh.new()
	handle_mesh.size = Vector3(0.08, 0.08, 0.8)
	handle_mesh.material = flat_material(Color(0.4, 0.3, 0.22))
	handle.mesh = handle_mesh
	handle.position = Vector3(0, 0, -0.4)
	_axe_pivot.add_child(handle)
	var blade := MeshInstance3D.new()
	var blade_mesh := BoxMesh.new()
	blade_mesh.size = Vector3(0.06, 0.4, 0.3)
	_axe_glow = flat_material(Color(0.75, 0.75, 0.8))
	blade_mesh.material = _axe_glow
	blade.mesh = blade_mesh
	blade.position = Vector3(0, 0.1, -0.75)
	_axe_pivot.add_child(blade)
	_axe_pivot.rotation_degrees = Vector3(-20, 10, 0)


func _ai_process(delta: float) -> void:
	match ai_state:
		AIState.IDLE:
			brake(delta)
			if distance_to_player() < AGGRO_RANGE:
				_enter_state(AIState.CHASE)
		AIState.CHASE:
			face_player(delta)
			move_towards(dir_to_player(), move_speed, delta)
			if distance_to_player() <= ATTACK_RANGE:
				_start_windup()
		AIState.WINDUP:
			face_player(delta, 4.0)  # slow tracking: dodging sideways works
			brake(delta)
			if _state_timer >= WINDUP_TIME:
				_do_attack()
		AIState.ATTACK:
			brake(delta)
			if _state_timer >= ATTACK_TIME:
				_enter_state(AIState.RECOVER)
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
	# Ground disc marks the strike zone; fills in over the wind-up.
	var fwd := -visual.global_transform.basis.z
	_telegraph_disc = VFX.telegraph_disc(get_tree().current_scene,
		global_position + fwd * 1.1,
		1.4, WINDUP_TIME)
	# Telegraph: axe raised, blade glows hot, warning sound.
	var tw := _axe_pivot.create_tween()
	tw.tween_property(_axe_pivot, "rotation_degrees", Vector3(-110, 0, 0), WINDUP_TIME * 0.8) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_axe_glow.emission_enabled = true
	_axe_glow.emission = Color(1.0, 0.4, 0.2)
	_axe_glow.emission_energy_multiplier = 0.2
	var glow_tw := create_tween()
	glow_tw.tween_property(_axe_glow, "emission_energy_multiplier", 2.5, WINDUP_TIME * 0.85)
	Sfx.play("telegraph", global_position, -4.0)


func _do_attack() -> void:
	_enter_state(AIState.ATTACK)
	var tw := _axe_pivot.create_tween()
	tw.tween_property(_axe_pivot, "rotation_degrees", Vector3(35, 0, 0), 0.09) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	tw.tween_property(_axe_pivot, "rotation_degrees", Vector3(-20, 10, 0), 0.4) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_reset_glow()
	Sfx.play("swing", global_position, -6.0, 0.12, 0.8)

	# Hit check: sphere in front, against the player hurtbox layer.
	var fwd := -visual.global_transform.basis.z
	var center := global_position + Vector3(0, 0.9, 0) + fwd * 1.2
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 1.1
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), center)
	query.collision_mask = 0b1000
	query.collide_with_areas = true
	query.collide_with_bodies = false
	for result: Dictionary in space.intersect_shape(query, 4):
		var hb := result["collider"] as Hurtbox
		if hb != null and hb.owner_entity is Player:
			var hit := HitInfo.create(ATTACK_DAMAGE, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.MEDIUM, global_position)
			hit.knockback = 4.0
			(hb.owner_entity as Player).take_hit(hit)
			VFX.melee_impact(get_tree().current_scene, hb.owner_entity.global_position + Vector3(0, 1.0, 0), fwd)
			break


func _reset_glow() -> void:
	if _axe_glow != null:
		_axe_glow.emission_energy_multiplier = 0.0
		if not _axe_glow.has_meta(ArtKit.KEEP_EMISSION):
			_axe_glow.emission_enabled = false


func _on_interrupted() -> void:
	_reset_glow()
	if _telegraph_disc != null and is_instance_valid(_telegraph_disc):
		_telegraph_disc.queue_free()
	if _axe_pivot != null:
		var tw := _axe_pivot.create_tween()
		tw.tween_property(_axe_pivot, "rotation_degrees", Vector3(-20, 10, 0), 0.15)
