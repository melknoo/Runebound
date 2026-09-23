class_name Player
extends CharacterBody3D
## The Runebreaker. Movement, dodge, Rune Cleave (melee), Ember Lance
## (fire projectile), Earthbreaker (Resonance-fueled slam).

signal health_changed(current: float, maximum: float)
signal resonance_changed(current: float, maximum: float)
signal cooldowns_changed
signal player_died

enum State { MOVE, DODGE, MELEE, CAST, SLAM, STORM_STEP }

const MAX_SPEED := 6.8
const ACCEL := 60.0
const DECEL := 55.0
const ROTATION_SPEED := 14.0
const GRAVITY := 24.0

const DODGE_SPEED := 15.0
const DODGE_DURATION := 0.24
const DODGE_RECOVERY := 0.08
const DODGE_COOLDOWN := 0.55
const DODGE_IFRAMES := 0.26  # user-tuned: a touch past the dash itself

const MAX_RESONANCE := 100.0
const INPUT_BUFFER := 0.22

const EmberProjectile := preload("res://scripts/projectiles/ember_lance_projectile.gd")

var state: State = State.MOVE
var resonance: float = 0.0
var god_mode: bool = false
## Set by InventoryUI while its panel is open: combat input ignored.
var input_locked: bool = false

var camera_rig: CameraRig = null
var targeting: TargetingSystem = null
var health: HealthComponent
var equipment: Equipment

# Ability tuning (assigned in _ready from resources, overridable in tests).
var cleave: AbilityData
var ember: AbilityData
var earthbreaker: AbilityData
var storm_step: AbilityData
var chain_spark: AbilityData
var fracture_rune: AbilityData

var _cooldowns: Dictionary = {}  # id -> seconds remaining
var _state_timer: float = 0.0
var _dodge_dir: Vector3 = Vector3.ZERO
var _melee_flip: bool = false
var _melee_did_hit_window: bool = false
var _buffered_action: StringName = &""
var _buffer_timer: float = 0.0
var _footstep_accum: float = 0.0
var _knockback_velocity: Vector3 = Vector3.ZERO
var _hitstop_left: float = 0.0

var _visual: Node3D
var _weapon_pivot: Node3D


func _ready() -> void:
	collision_layer = 0b10
	collision_mask = 0b101
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.42
	capsule.height = 1.7
	col.shape = capsule
	col.position = Vector3(0, 0.85, 0)
	add_child(col)

	health = HealthComponent.new()
	health.max_health = 100.0
	add_child(health)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	health.health_changed.connect(func(c: float, m: float) -> void: health_changed.emit(c, m))

	equipment = Equipment.new()
	equipment.name = "Equipment"
	equipment.player = self
	add_child(equipment)

	Hurtbox.create(self, 0b1000, 0.5, 1.75, 0.85)

	_build_visual()
	_load_abilities()
	floor_snap_length = 0.4


func _load_abilities() -> void:
	cleave = load("res://resources/abilities/rune_cleave.tres")
	ember = load("res://resources/abilities/ember_lance.tres")
	earthbreaker = load("res://resources/abilities/earthbreaker.tres")
	storm_step = load("res://resources/abilities/storm_step.tres")
	chain_spark = load("res://resources/abilities/chain_spark.tres")
	fracture_rune = load("res://resources/abilities/fracture_rune.tres")


func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)

	const MODEL_PATH := "res://assets/models/player_runebreaker.glb"
	if ResourceLoader.exists(MODEL_PATH):
		var model := (load(MODEL_PATH) as PackedScene).instantiate() as Node3D
		model.rotation.y = PI  # Blender -Y front → Godot +Z; we face -Z
		_visual.add_child(model)
		_build_weapon()
		return

	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.32, 0.34, 0.44)
	iron.roughness = 0.7
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(0.16, 0.55, 0.55)
	accent.roughness = 0.5
	var rune_glow := StandardMaterial3D.new()
	rune_glow.albedo_color = Color(1.0, 0.6, 0.25)
	rune_glow.emission_enabled = true
	rune_glow.emission = Color(1.0, 0.55, 0.2)
	rune_glow.emission_energy_multiplier = 1.6
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.85, 0.68, 0.55)

	# Chunky armored silhouette: wide torso, big pauldrons, small head.
	var torso := MeshInstance3D.new()
	var torso_mesh := BoxMesh.new()
	torso_mesh.size = Vector3(0.72, 0.62, 0.44)
	torso_mesh.material = iron
	torso.mesh = torso_mesh
	torso.position = Vector3(0, 1.05, 0)
	_visual.add_child(torso)

	var belt := MeshInstance3D.new()
	var belt_mesh := BoxMesh.new()
	belt_mesh.size = Vector3(0.5, 0.28, 0.36)
	belt_mesh.material = accent
	belt.mesh = belt_mesh
	belt.position = Vector3(0, 0.68, 0)
	_visual.add_child(belt)

	var legs := MeshInstance3D.new()
	var legs_mesh := BoxMesh.new()
	legs_mesh.size = Vector3(0.44, 0.55, 0.3)
	legs_mesh.material = iron
	legs.mesh = legs_mesh
	legs.position = Vector3(0, 0.3, 0)
	_visual.add_child(legs)

	for side: float in [-1.0, 1.0]:
		var pauldron := MeshInstance3D.new()
		var pmesh := BoxMesh.new()
		pmesh.size = Vector3(0.28, 0.24, 0.34)
		pmesh.material = accent
		pauldron.mesh = pmesh
		pauldron.position = Vector3(side * 0.48, 1.32, 0)
		_visual.add_child(pauldron)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.17
	head_mesh.height = 0.34
	head_mesh.material = skin
	head.mesh = head_mesh
	head.position = Vector3(0, 1.56, 0)
	_visual.add_child(head)

	# Rune sigil on the chest — the class identity glow.
	var sigil := MeshInstance3D.new()
	var sigil_mesh := BoxMesh.new()
	sigil_mesh.size = Vector3(0.16, 0.22, 0.05)
	sigil_mesh.material = rune_glow
	sigil.mesh = sigil_mesh
	sigil.position = Vector3(0, 1.08, -0.23)
	_visual.add_child(sigil)
	_build_weapon()


## Broad rune blade on the right hand, swung via pivot tweens. Always
## code-built: abilities animate this pivot directly.
func _build_weapon() -> void:
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.32, 0.34, 0.44)
	iron.roughness = 0.7
	var rune_glow := StandardMaterial3D.new()
	rune_glow.albedo_color = Color(1.0, 0.6, 0.25)
	rune_glow.emission_enabled = true
	rune_glow.emission = Color(1.0, 0.55, 0.2)
	rune_glow.emission_energy_multiplier = 1.6

	_weapon_pivot = Node3D.new()
	_weapon_pivot.name = "WeaponPivot"
	_weapon_pivot.position = Vector3(0.45, 1.15, 0)
	_visual.add_child(_weapon_pivot)

	var blade := MeshInstance3D.new()
	var blade_mesh := BoxMesh.new()
	blade_mesh.size = Vector3(0.1, 0.05, 1.15)
	blade_mesh.material = iron
	blade.mesh = blade_mesh
	blade.position = Vector3(0, 0, -0.65)
	_weapon_pivot.add_child(blade)
	var edge := MeshInstance3D.new()
	var edge_mesh := BoxMesh.new()
	edge_mesh.size = Vector3(0.04, 0.06, 0.9)
	edge_mesh.material = rune_glow
	edge.mesh = edge_mesh
	edge.position = Vector3(0, 0, -0.7)
	_weapon_pivot.add_child(edge)
	_weapon_pivot.rotation_degrees = Vector3(-25, 15, 0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_cursor"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func apply_hitstop(duration: float) -> void:
	_hitstop_left = maxf(_hitstop_left, duration)


func _physics_process(delta: float) -> void:
	if _hitstop_left > 0.0:
		_hitstop_left -= delta
		return
	for key: StringName in _cooldowns.keys():
		_cooldowns[key] = maxf(_cooldowns[key] - delta, 0.0)
	if _buffer_timer > 0.0:
		_buffer_timer -= delta
		if _buffer_timer <= 0.0:
			_buffered_action = &""

	_read_action_input()

	match state:
		State.MOVE:
			_process_move(delta)
		State.DODGE:
			_process_dodge(delta)
		State.MELEE:
			_process_melee(delta)
		State.CAST:
			_process_cast(delta)
		State.SLAM:
			_process_slam(delta)
		State.STORM_STEP:
			_process_storm_step(delta)

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	velocity += _knockback_velocity
	move_and_slide()
	velocity -= _knockback_velocity
	_knockback_velocity = _knockback_velocity.lerp(Vector3.ZERO, minf(8.0 * delta, 1.0))


## Central ability hit roll: applies equipment damage and crit bonuses.
func roll_ability_hit(data: AbilityData) -> HitInfo:
	var damage_mult := 1.0 + equipment.stat(&"damage_pct") / 100.0
	var bonus_crit := equipment.stat(&"crit_pct") / 100.0
	return data.roll_hit(global_position, damage_mult, bonus_crit)


## Central cooldown setter: applies global (and dodge-specific) reduction.
func _set_cooldown(id: StringName, base: float) -> void:
	var mult := 1.0 - equipment.stat(&"cooldown_pct") / 100.0
	if id == &"dodge":
		mult *= 1.0 - equipment.stat(&"dodge_cd_pct") / 100.0
	_cooldowns[id] = base * clampf(mult, 0.35, 1.0)


func earthbreaker_cost() -> float:
	return maxf(earthbreaker.resonance_cost - equipment.stat(&"eb_cost_reduce"), 10.0)


func _read_action_input() -> void:
	if input_locked:
		return
	if Input.is_action_just_pressed(&"dodge"):
		_try_or_buffer(&"dodge")
	if Input.is_action_just_pressed(&"primary_attack"):
		_try_or_buffer(&"melee")
	if Input.is_action_just_pressed(&"secondary_ability"):
		_try_or_buffer(&"ember")
	if Input.is_action_just_pressed(&"ability_q"):
		_try_or_buffer(&"earthbreaker")
	if Input.is_action_just_pressed(&"ability_e"):
		_try_or_buffer(&"storm_step")
	if Input.is_action_just_pressed(&"ability_r"):
		_try_or_buffer(&"chain_spark")
	if Input.is_action_just_pressed(&"ability_f"):
		_try_or_buffer(&"fracture_rune")


func _try_or_buffer(action: StringName) -> void:
	if not _try_action(action):
		_buffered_action = action
		_buffer_timer = INPUT_BUFFER


func _consume_buffer() -> void:
	if _buffered_action != &"":
		var action := _buffered_action
		_buffered_action = &""
		_buffer_timer = 0.0
		_try_action(action)


func _try_action(action: StringName) -> bool:
	match action:
		&"dodge":
			return try_dodge()
		&"melee":
			return try_melee()
		&"ember":
			return try_ember()
		&"earthbreaker":
			return try_earthbreaker()
		&"storm_step":
			return try_storm_step()
		&"chain_spark":
			return try_chain_spark()
		&"fracture_rune":
			return try_fracture_rune()
	return false


# ---------------------------------------------------------------------------
# Movement
# ---------------------------------------------------------------------------

func _move_input_dir() -> Vector3:
	var raw := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	if raw == Vector2.ZERO or camera_rig == null:
		return Vector3.ZERO
	var flat := camera_rig.get_flat_basis()
	return (flat * Vector3(raw.x, 0, raw.y)).normalized()


func _process_move(delta: float) -> void:
	var dir := _move_input_dir()
	var target_vel := dir * MAX_SPEED * (1.0 + equipment.stat(&"move_pct") / 100.0)
	var rate := ACCEL if dir != Vector3.ZERO else DECEL
	velocity.x = move_toward(velocity.x, target_vel.x, rate * delta)
	velocity.z = move_toward(velocity.z, target_vel.z, rate * delta)
	if dir != Vector3.ZERO:
		_face_direction(dir, delta)
		_footsteps(delta)


func _face_direction(dir: Vector3, delta: float) -> void:
	var target_yaw := atan2(-dir.x, -dir.z)
	_visual.rotation.y = lerp_angle(_visual.rotation.y, target_yaw, minf(ROTATION_SPEED * delta, 1.0))


func _face_aim_instant() -> void:
	var aim := aim_direction()
	_visual.rotation.y = atan2(-aim.x, -aim.z)


## Melee snaps to the soft target when one is in reach — swinging at the
## marker the player can see beats swinging at the camera ray.
func _face_melee_target() -> void:
	var t: EnemyBase = targeting.current if targeting != null else null
	if t != null and is_instance_valid(t) \
			and t.global_position.distance_to(global_position) <= 4.0:
		var dir := t.global_position - global_position
		dir.y = 0.0
		if dir.length() > 0.05:
			dir = dir.normalized()
			_visual.rotation.y = atan2(-dir.x, -dir.z)
			return
	_face_aim_instant()


func facing() -> Vector3:
	return -_visual.global_transform.basis.z


func aim_direction() -> Vector3:
	if camera_rig == null:
		return facing()
	var exclude: Array[RID] = [get_rid()]
	var aim_point := camera_rig.get_aim_point(exclude)
	var from := muzzle_position()
	var dir := aim_point - from
	if dir.length() < 1.0:
		dir = -camera_rig.camera.global_transform.basis.z
	dir.y = clampf(dir.y / maxf(dir.length(), 0.01), -0.6, 0.6) * dir.length()
	return dir.normalized()


func muzzle_position() -> Vector3:
	return global_position + Vector3(0, 1.2, 0) + facing() * 0.5


func _footsteps(delta: float) -> void:
	_footstep_accum += delta * velocity.length()
	if _footstep_accum >= 2.6:
		_footstep_accum = 0.0
		Sfx.play("footstep", global_position, -12.0, 0.15)


# ---------------------------------------------------------------------------
# Dodge
# ---------------------------------------------------------------------------

func try_dodge() -> bool:
	if state == State.DODGE or _cooldowns.get(&"dodge", 0.0) > 0.0:
		return false
	# Dodge cancels melee recovery and cast startup — the trust rule.
	if state == State.SLAM and _state_timer < earthbreaker.startup + earthbreaker.active:
		return false
	var dir := _move_input_dir()
	if dir == Vector3.ZERO:
		dir = facing()
	_dodge_dir = dir
	state = State.DODGE
	_state_timer = 0.0
	_set_cooldown(&"dodge", DODGE_COOLDOWN)
	health.invulnerable = true
	_visual.rotation.y = atan2(-dir.x, -dir.z)
	VFX.dodge_dust(get_tree().current_scene, global_position, dir)
	Sfx.play("dodge", global_position, -4.0)
	cooldowns_changed.emit()
	return true


func _process_dodge(delta: float) -> void:
	_state_timer += delta
	if _state_timer >= DODGE_IFRAMES:
		health.invulnerable = god_mode
	if _state_timer < DODGE_DURATION:
		# Ease-out dash: strong start, soft landing.
		var t := _state_timer / DODGE_DURATION
		var speed := DODGE_SPEED * (1.0 - t * t * 0.7)
		velocity.x = _dodge_dir.x * speed
		velocity.z = _dodge_dir.z * speed
	elif _state_timer < DODGE_DURATION + DODGE_RECOVERY:
		velocity.x = move_toward(velocity.x, 0, DECEL * delta)
		velocity.z = move_toward(velocity.z, 0, DECEL * delta)
	else:
		state = State.MOVE
		_consume_buffer()


# ---------------------------------------------------------------------------
# Rune Cleave (melee)
# ---------------------------------------------------------------------------

func try_melee() -> bool:
	if state != State.MOVE:
		return false
	state = State.MELEE
	_state_timer = 0.0
	_melee_did_hit_window = false
	_melee_flip = not _melee_flip
	_face_melee_target()
	_animate_cleave()
	Sfx.play("swing", global_position, -2.0, 0.1)
	return true


func _animate_cleave() -> void:
	var side := 1.0 if _melee_flip else -1.0
	_weapon_pivot.rotation_degrees = Vector3(-10, side * 70.0, 0)
	var tw := _weapon_pivot.create_tween()
	tw.tween_property(_weapon_pivot, "rotation_degrees:y", -side * 80.0, cleave.startup + cleave.active) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	tw.tween_property(_weapon_pivot, "rotation_degrees", Vector3(-25, 15, 0), cleave.recovery) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _process_melee(delta: float) -> void:
	_state_timer += delta
	# Slight forward drift keeps swings aggressive without lunging.
	var fwd := facing()
	velocity.x = fwd.x * 1.6
	velocity.z = fwd.z * 1.6
	if not _melee_did_hit_window and _state_timer >= cleave.startup:
		_melee_did_hit_window = true
		_do_cleave_hit()
	if _state_timer >= cleave.startup + cleave.active + cleave.recovery:
		state = State.MOVE
		_consume_buffer()


func _do_cleave_hit() -> void:
	var fwd := facing()
	var center := global_position + Vector3(0, 1.0, 0) + fwd * 1.2
	var radius := 1.5 * (1.0 + equipment.stat(&"cleave_radius_pct") / 100.0)
	var hits := _query_hurtboxes(center, radius)
	var scene := get_tree().current_scene
	# Slash arc regardless of contact — the swing itself must read.
	VFX.melee_slash(scene, global_position + Vector3(0, 1.1, 0) + fwd * 0.9, fwd, _melee_flip)
	var any_hit := false
	for enemy: Node in hits:
		var hit := roll_ability_hit(cleave)
		if enemy.has_method(&"take_hit") and enemy.call(&"take_hit", hit):
			any_hit = true
			gain_resonance(cleave.resonance_gain_per_hit)
			VFX.melee_impact(scene, (enemy as Node3D).global_position + Vector3(0, 1.0, 0), fwd)
	if any_hit:
		Sfx.play("impact_flesh", center, 0.0, 0.12)
		var stop_targets: Array = [self]
		stop_targets.append_array(hits)
		GameFeel.hitstop(stop_targets, 0.045)
		GameFeel.camera_impulse(fwd, 0.08)
	cooldowns_changed.emit()


func _query_hurtboxes(center: Vector3, radius: float) -> Array[Node]:
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), center)
	query.collision_mask = 0b10000  # enemy hurtboxes
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var found: Array[Node] = []
	for result: Dictionary in space.intersect_shape(query, 16):
		var hb := result["collider"] as Hurtbox
		if hb != null and hb.owner_entity != null and not found.has(hb.owner_entity):
			found.append(hb.owner_entity)
	return found


# ---------------------------------------------------------------------------
# Ember Lance
# ---------------------------------------------------------------------------

func try_ember() -> bool:
	if state != State.MOVE or _cooldowns.get(&"ember", 0.0) > 0.0:
		return false
	state = State.CAST
	_state_timer = 0.0
	_set_cooldown(&"ember", ember.cooldown)
	_face_aim_instant()
	VFX.ember_cast(get_tree().current_scene, muzzle_position())
	Sfx.play("ember_cast", global_position, -3.0)
	cooldowns_changed.emit()
	return true


func _process_cast(delta: float) -> void:
	_state_timer += delta
	velocity.x = move_toward(velocity.x, 0, DECEL * 2.0 * delta)
	velocity.z = move_toward(velocity.z, 0, DECEL * 2.0 * delta)
	_face_aim_instant()
	if _state_timer >= ember.startup:
		_fire_ember()
		state = State.MOVE
		_consume_buffer()


func _fire_ember() -> void:
	var proj := EmberProjectile.new()
	proj.setup(ember, aim_direction(), self)
	# Position before add_child: spawning at the scene origin for even one
	# frame overlaps the floor and detonates the projectile instantly.
	proj.position = muzzle_position()
	get_tree().current_scene.add_child(proj)
	GameFeel.camera_impulse(-aim_direction(), 0.05)
	Sfx.play("ember_fire", muzzle_position(), -2.0, 0.1)


# ---------------------------------------------------------------------------
# Earthbreaker
# ---------------------------------------------------------------------------

func try_earthbreaker() -> bool:
	if state != State.MOVE or _cooldowns.get(&"earthbreaker", 0.0) > 0.0:
		return false
	if resonance < earthbreaker_cost():
		Sfx.play_ui("ui_denied", -8.0)
		return false
	state = State.SLAM
	_state_timer = 0.0
	_set_cooldown(&"earthbreaker", earthbreaker.cooldown)
	spend_resonance(earthbreaker_cost())
	# Anticipation: rise + weapon raised overhead.
	var tw := _weapon_pivot.create_tween()
	tw.tween_property(_weapon_pivot, "rotation_degrees", Vector3(-120, 0, 0), earthbreaker.startup) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	velocity.y = 7.0
	Sfx.play("earthbreaker_windup", global_position, -3.0)
	cooldowns_changed.emit()
	return true


func _process_slam(delta: float) -> void:
	_state_timer += delta
	velocity.x = move_toward(velocity.x, 0, DECEL * delta)
	velocity.z = move_toward(velocity.z, 0, DECEL * delta)
	if _state_timer >= earthbreaker.startup and _state_timer - delta < earthbreaker.startup:
		velocity.y = -22.0  # slam down hard
		var tw := _weapon_pivot.create_tween()
		tw.tween_property(_weapon_pivot, "rotation_degrees", Vector3(30, 0, 0), 0.08)
		tw.tween_property(_weapon_pivot, "rotation_degrees", Vector3(-25, 15, 0), 0.4) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if _state_timer >= earthbreaker.startup + earthbreaker.active:
		if is_on_floor() or _state_timer > earthbreaker.startup + 0.5:
			_do_slam_hit()
			state = State.MOVE
			_consume_buffer()


func _do_slam_hit() -> void:
	var scene := get_tree().current_scene
	var pos := global_position
	VFX.earthbreaker_slam(scene, pos, earthbreaker.aoe_radius)
	Sfx.play("earthbreaker_impact", pos, 2.0, 0.06)
	GameFeel.camera_shake(0.55)
	var hits := _query_hurtboxes(pos + Vector3(0, 0.5, 0), earthbreaker.aoe_radius)
	for enemy: Node in hits:
		var hit := roll_ability_hit(earthbreaker)
		hit.source_position = pos
		enemy.call(&"take_hit", hit)
	if not hits.is_empty():
		GameFeel.hitstop(hits, 0.07)
	# Glacier Heart: the slam leaves a chilling frost field.
	if equipment.has_power(&"glacier_heart"):
		var field := FrostField.new()
		field.position = Vector3(pos.x, 0.02, pos.z)
		scene.add_child(field)


# ---------------------------------------------------------------------------
# Storm Step
# ---------------------------------------------------------------------------

const STORM_STEP_SPEED := 50.0  # ~6m over the 0.12s active window

var _dash_dir: Vector3 = Vector3.ZERO
var _dash_start: Vector3 = Vector3.ZERO
var _dash_time: float = 0.12  # active window; shorter for close gap-closes


func try_storm_step() -> bool:
	if state != State.MOVE or _cooldowns.get(&"storm_step", 0.0) > 0.0:
		return false
	# Direction priority (user-tuned):
	# 1. Held movement input — steering wins ("I'm dashing where I'm running").
	# 2. Tab target the camera is looking at — gap-closer that lands in melee
	#    range instead of overshooting through the enemy.
	# 3. Camera aim direction.
	var dash_dist := storm_step.active * STORM_STEP_SPEED
	var dir := _move_input_dir()
	if dir == Vector3.ZERO:
		var target: EnemyBase = targeting.current if targeting != null else null
		if target != null and is_instance_valid(target) and target.ai_state != EnemyBase.AIState.DEAD:
			var to_target := target.global_position - global_position
			to_target.y = 0.0
			var cam_fwd := -(camera_rig.get_flat_basis().z) if camera_rig != null else facing()
			if to_target.length() > 0.5 and cam_fwd.dot(to_target.normalized()) > 0.4:
				dir = to_target.normalized()
				dash_dist = clampf(to_target.length() - 1.3, 1.5, dash_dist)
	if dir == Vector3.ZERO:
		var aim := aim_direction()
		dir = Vector3(aim.x, 0, aim.z).normalized()
	if dir == Vector3.ZERO and camera_rig != null:
		dir = -(camera_rig.get_flat_basis().z)
	if dir == Vector3.ZERO:
		dir = facing()
	_dash_dir = dir
	_dash_time = dash_dist / STORM_STEP_SPEED
	_dash_start = global_position
	state = State.STORM_STEP
	_state_timer = 0.0
	_set_cooldown(&"storm_step", storm_step.cooldown)
	collision_mask = 0b001  # phase through enemies during the dash
	_visual.rotation.y = atan2(-dir.x, -dir.z)
	VFX.flash(get_tree().current_scene, global_position + Vector3(0, 1.0, 0), Color(0.8, 0.9, 1.0), 1.0, 0.1)
	Sfx.play("storm_step", global_position, -1.0, 0.08)
	cooldowns_changed.emit()
	return true


func _process_storm_step(delta: float) -> void:
	_state_timer += delta
	if _state_timer < _dash_time:
		velocity.x = _dash_dir.x * STORM_STEP_SPEED
		velocity.z = _dash_dir.z * STORM_STEP_SPEED
		velocity.y = 0.0
	elif _state_timer < _dash_time + storm_step.recovery:
		if _state_timer - delta < _dash_time:
			# Hard stop at the end of the active window: letting 50 m/s decay
			# through normal deceleration added ~11m of ice-skating overshoot.
			velocity.x = _dash_dir.x * 4.0
			velocity.z = _dash_dir.z * 4.0
		velocity.x = move_toward(velocity.x, 0, DECEL * 2.0 * delta)
		velocity.z = move_toward(velocity.z, 0, DECEL * 2.0 * delta)
	else:
		_finish_storm_step()


func _finish_storm_step() -> void:
	collision_mask = 0b101
	state = State.MOVE
	var scene := get_tree().current_scene
	VFX.storm_trail(scene, _dash_start, global_position)
	# Everything the dash passed through gets zapped and shocked.
	var path := global_position - _dash_start
	var center := _dash_start + path * 0.5 + Vector3(0, 1.0, 0)
	var hits := _query_hurtboxes(center, maxf(path.length() * 0.5 + 0.5, 1.0))
	for enemy: Node in hits:
		var enemy_3d := enemy as Node3D
		# Radius covers a sphere; keep only enemies near the actual dash line.
		var to_enemy := enemy_3d.global_position - _dash_start
		var along := clampf(to_enemy.dot(path.normalized()), 0.0, path.length())
		var closest := _dash_start + path.normalized() * along
		if enemy_3d.global_position.distance_to(closest) > 1.4:
			continue
		var hit := roll_ability_hit(storm_step)
		hit.source_position = _dash_start
		if enemy.has_method(&"take_hit") and enemy.call(&"take_hit", hit):
			gain_resonance(storm_step.resonance_gain_per_hit)
			VFX.lightning_arc(scene, global_position + Vector3(0, 1.0, 0),
				enemy_3d.global_position + Vector3(0, 1.0, 0), Color(0.8, 0.9, 1.0))
	_consume_buffer()


# ---------------------------------------------------------------------------
# Chain Spark
# ---------------------------------------------------------------------------

func try_chain_spark() -> bool:
	if state != State.MOVE or _cooldowns.get(&"chain_spark", 0.0) > 0.0:
		return false
	var first: EnemyBase = null
	if targeting != null:
		var held := targeting.current
		if held != null and is_instance_valid(held) and held.ai_state != EnemyBase.AIState.DEAD \
				and held.global_position.distance_to(global_position) <= 14.0:
			first = held
		else:
			first = targeting.best_candidate()
	if first == null:
		Sfx.play_ui("ui_denied", -8.0)
		return false
	_set_cooldown(&"chain_spark", chain_spark.cooldown)
	_face_aim_instant()
	var scene := get_tree().current_scene
	var from := muzzle_position()
	var hit_enemies: Array[EnemyBase] = []
	var next: EnemyBase = first
	var bonus_jump := false
	while next != null:
		if next.status.has_shock():
			bonus_jump = true
		var chest := next.global_position + Vector3(0, 1.0, 0)
		VFX.lightning_arc(scene, from, chest)
		VFX.flash(scene, chest, Color(1.0, 1.0, 0.75), 0.6, 0.1)
		var hit := roll_ability_hit(chain_spark)
		if next.take_hit(hit):
			gain_resonance(chain_spark.resonance_gain_per_hit)
			# Conductor's Oath: struck enemies stay charged; later lightning
			# damage on any Conductor arcs to all others (see EnemyBase).
			if equipment.has_power(&"conductors_oath"):
				next.status.apply_conductor()
		hit_enemies.append(next)
		from = chest
		var max_targets := 3 + int(equipment.stat(&"chain_jumps")) + (1 if bonus_jump else 0)
		next = null
		if hit_enemies.size() < max_targets:
			next = _nearest_chain_candidate(from, hit_enemies)
	Sfx.play("chain_spark", global_position, -1.0, 0.1)
	GameFeel.camera_impulse(aim_direction(), 0.04)
	# Weapon flourish: quick raise, snap back.
	var tw := _weapon_pivot.create_tween()
	tw.tween_property(_weapon_pivot, "rotation_degrees", Vector3(-70, 20, 0), 0.07)
	tw.tween_property(_weapon_pivot, "rotation_degrees", Vector3(-25, 15, 0), 0.25) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	cooldowns_changed.emit()
	return true


func _nearest_chain_candidate(from: Vector3, exclude: Array[EnemyBase]) -> EnemyBase:
	var best: EnemyBase = null
	var best_dist := chain_spark.aoe_radius  # jump range
	for enemy in EnemyBase.all_enemies:
		if not is_instance_valid(enemy) or enemy.ai_state == EnemyBase.AIState.DEAD or exclude.has(enemy):
			continue
		var d := enemy.global_position.distance_to(from)
		if d < best_dist:
			best_dist = d
			best = enemy
	return best


# ---------------------------------------------------------------------------
# Fracture Rune
# ---------------------------------------------------------------------------

const FRACTURE_RUNE_MAX_RANGE := 12.0


func try_fracture_rune() -> bool:
	if state != State.MOVE or _cooldowns.get(&"fracture_rune", 0.0) > 0.0:
		return false
	_set_cooldown(&"fracture_rune", fracture_rune.cooldown)
	var exclude: Array[RID] = [get_rid()]
	var aim_point := camera_rig.get_aim_point(exclude) if camera_rig != null else global_position + facing() * 6.0
	var flat := Vector3(aim_point.x, 0, aim_point.z)
	var origin := Vector3(global_position.x, 0, global_position.z)
	var offset := flat - origin
	if offset.length() > FRACTURE_RUNE_MAX_RANGE:
		offset = offset.normalized() * FRACTURE_RUNE_MAX_RANGE
	var rune := FractureRune.new()
	rune.setup(fracture_rune, self)
	rune.arm_time = maxf(FractureRune.ARM_TIME - equipment.stat(&"rune_arm_reduce"), 0.5)
	rune.position = origin + offset + Vector3(0, 0.02, 0)
	get_tree().current_scene.add_child(rune)
	_face_aim_instant()
	# Casting gesture: brief point with the blade.
	var tw := _weapon_pivot.create_tween()
	tw.tween_property(_weapon_pivot, "rotation_degrees", Vector3(-60, 0, 0), 0.08)
	tw.tween_property(_weapon_pivot, "rotation_degrees", Vector3(-25, 15, 0), 0.3) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	cooldowns_changed.emit()
	return true


# ---------------------------------------------------------------------------
# Resonance / damage intake
# ---------------------------------------------------------------------------

func gain_resonance(amount: float) -> void:
	amount *= 1.0 + equipment.stat(&"resonance_pct") / 100.0
	resonance = minf(resonance + amount, MAX_RESONANCE)
	resonance_changed.emit(resonance, MAX_RESONANCE)


func spend_resonance(amount: float) -> void:
	resonance = maxf(resonance - amount, 0.0)
	resonance_changed.emit(resonance, MAX_RESONANCE)


func take_hit(hit: HitInfo) -> bool:
	if god_mode:
		return false
	if not health.apply_hit(hit):
		return false
	var push := (global_position - hit.source_position)
	push.y = 0
	_knockback_velocity += push.normalized() * hit.knockback
	Sfx.play("player_hurt", global_position, -2.0)
	GameFeel.camera_shake(0.25)
	return true


func _on_damaged(hit: HitInfo) -> void:
	GameFeel.damage_number(global_position + Vector3(0, 1.9, 0), hit.damage, Color(1.0, 0.3, 0.25))


func _on_died() -> void:
	player_died.emit()


func cooldown_fraction(id: StringName) -> float:
	var total: float = 1.0
	match id:
		&"dodge": total = DODGE_COOLDOWN
		&"ember": total = ember.cooldown
		&"earthbreaker": total = earthbreaker.cooldown
		&"storm_step": total = storm_step.cooldown
		&"chain_spark": total = chain_spark.cooldown
		&"fracture_rune": total = fracture_rune.cooldown
	return clampf(_cooldowns.get(id, 0.0) / total, 0.0, 1.0)


func reset_cooldowns() -> void:
	_cooldowns.clear()
	cooldowns_changed.emit()
