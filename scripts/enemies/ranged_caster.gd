class_name RangedCaster
extends EnemyBase
## Tall hooded caster: keeps its distance and lobs slow, readable bolts.
## Its purpose in the lab is to punish standing still.

const PREFERRED_MIN := 7.0
const PREFERRED_MAX := 12.0
const WINDUP_TIME := 0.9
const RECOVER_TIME := 1.4
const BOLT_SPEED := 9.0
const BOLT_DAMAGE := 12.0

var _staff_orb: StandardMaterial3D
var _orb_mesh: MeshInstance3D


func _init() -> void:
	xp_value = 22
	display_name = "Duskweaver"
	max_health = 40.0
	move_speed = 3.2
	body_color = Color(0.45, 0.3, 0.65)


const RIG_PATH := "res://assets/models/chars/duskweaver.glb"


func _build_body() -> void:
	# M06 rig: the floating staff is part of the model (root bone, never
	# animated); the orb stays code-built — telegraph glow + bolt origin.
	if _setup_rigged_visual(RIG_PATH, "duskweaver", {
		"idle": &"idle", "run": &"glide", "run_speed": move_speed,
		"states": {AIState.WINDUP: &"charge", AIState.RECOVER: &"cast", AIState.STAGGER: &"stagger",
			AIState.CHASE: &"@loco", AIState.IDLE: &"@loco", AIState.DEAD: &"@dead"},
	}, ArtKit.color("palettes.duskweaver.eyes")) != null:
		_build_orb()
		return
	if _setup_model_visual("res://assets/models/enemy_caster.glb"):
		_build_staff()
		return
	# Fallback primitives: tall, thin silhouette — "caster, kill first".
	var robe := MeshInstance3D.new()
	var robe_mesh := CylinderMesh.new()
	robe_mesh.top_radius = 0.22
	robe_mesh.bottom_radius = 0.45
	robe_mesh.height = 1.3
	robe_mesh.material = flat_material(body_color)
	robe.mesh = robe_mesh
	robe.position = Vector3(0, 0.65, 0)
	visual.add_child(robe)

	var hood := MeshInstance3D.new()
	var hood_mesh := CylinderMesh.new()
	hood_mesh.top_radius = 0.02
	hood_mesh.bottom_radius = 0.28
	hood_mesh.height = 0.5
	hood_mesh.material = flat_material(body_color.darkened(0.3))
	hood.mesh = hood_mesh
	hood.position = Vector3(0, 1.55, 0)
	visual.add_child(hood)

	var eyes := MeshInstance3D.new()
	var eyes_mesh := BoxMesh.new()
	eyes_mesh.size = Vector3(0.18, 0.05, 0.05)
	eyes_mesh.material = flat_material(Color(0.8, 0.5, 1.0), true, 2.2)
	eyes.mesh = eyes_mesh
	eyes.position = Vector3(0, 1.42, -0.2)
	visual.add_child(eyes)
	_build_staff()


func _build_staff() -> void:
	var staff := MeshInstance3D.new()
	var staff_mesh := CylinderMesh.new()
	staff_mesh.top_radius = 0.04
	staff_mesh.bottom_radius = 0.04
	staff_mesh.height = 1.6
	staff_mesh.material = flat_material(Color(0.35, 0.28, 0.2))
	staff.mesh = staff_mesh
	staff.position = Vector3(0.42, 0.8, 0)
	visual.add_child(staff)
	_build_orb()


## Staff orb: charges during the windup and is where the bolt spawns.
func _build_orb() -> void:
	_orb_mesh = MeshInstance3D.new()
	var orb := SphereMesh.new()
	orb.radius = 0.14
	orb.height = 0.28
	_staff_orb = flat_material(Color(0.7, 0.35, 1.0), true, 0.4)
	_staff_orb.disable_fog = true  # the charge is the telegraph: readable in haze
	orb.material = _staff_orb
	_orb_mesh.mesh = orb
	_orb_mesh.position = Vector3(0.42, 1.7, 0)
	visual.add_child(_orb_mesh)


func _ai_process(delta: float) -> void:
	match ai_state:
		AIState.IDLE:
			brake(delta)
			if distance_to_player() < AGGRO_RANGE:
				_enter_state(AIState.CHASE)
		AIState.CHASE:
			face_player(delta)
			var dist := distance_to_player()
			if dist < PREFERRED_MIN:
				move_towards(-dir_to_player(), move_speed, delta)  # back away
			elif dist > PREFERRED_MAX:
				move_towards(dir_to_player(), move_speed, delta)
			else:
				brake(delta)
				if _state_timer > 0.4:
					_start_windup()
		AIState.WINDUP:
			face_player(delta, 3.0)
			brake(delta)
			if _state_timer >= WINDUP_TIME:
				_fire()
		AIState.RECOVER:
			brake(delta)
			# Strafe sideways a little while recovering: less of a turret.
			var side := dir_to_player().cross(Vector3.UP)
			move_towards(side * (1.0 if (get_instance_id() % 2 == 0) else -1.0), move_speed * 0.5, delta)
			if _state_timer >= RECOVER_TIME:
				_enter_state(AIState.CHASE)
		AIState.STAGGER:
			brake(delta)
			if _state_timer >= 0.0:
				_enter_state(AIState.CHASE)


func _start_windup() -> void:
	_enter_state(AIState.WINDUP)
	_present_windup()


func _present_state(s: AIState) -> void:
	super(s)
	match s:
		AIState.WINDUP:
			_present_windup()
		AIState.RECOVER:
			_present_fire()


func _present_windup() -> void:
	# Telegraph: orb charges up bright with sound; scales with time.
	var tw := create_tween()
	tw.tween_property(_staff_orb, "emission_energy_multiplier", 3.5, WINDUP_TIME * 0.9)
	var scale_tw := _orb_mesh.create_tween()
	scale_tw.tween_property(_orb_mesh, "scale", Vector3.ONE * 1.8, WINDUP_TIME * 0.9)
	Sfx.play("caster_charge", global_position, -5.0)


func _fire() -> void:
	_enter_state(AIState.RECOVER)
	_present_fire()
	if player == null or not is_instance_valid(player):
		return
	var origin := _orb_mesh.global_position
	var target := player.global_position + Vector3(0, 1.0, 0)
	var bolt := EnemyBolt.new()
	bolt.setup((target - origin).normalized(), BOLT_SPEED, BOLT_DAMAGE)
	bolt.position = origin  # position before add_child: no origin-frame overlap
	get_tree().current_scene.add_child(bolt)


## The orb lets go (the bolt itself is simulation; a co-op client gets its
## own copy from the server).
func _present_fire() -> void:
	_reset_orb()
	Sfx.play("bolt_fire", global_position, -4.0)


func _reset_orb() -> void:
	if _staff_orb != null:
		_staff_orb.emission_energy_multiplier = 0.4
	if _orb_mesh != null:
		_orb_mesh.scale = Vector3.ONE


func _on_interrupted() -> void:
	_reset_orb()
