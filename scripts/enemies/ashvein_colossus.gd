class_name AshveinColossus
extends EnemyBase
## Mini-boss of the Ashen Highlands: a towering ember-veined brute.
## Slam (close) + telegraphed line charge (mid-range). Enrages below 50%:
## faster, quicker slams, leaves fire patches.

signal boss_health_changed(current: float, maximum: float)

const SLAM_RANGE := 3.2
const SLAM_RADIUS := 3.2
const SLAM_DAMAGE := 28.0
const CHARGE_MIN := 6.0
const CHARGE_MAX := 18.0
const CHARGE_SPEED := 14.0
const CHARGE_DAMAGE := 30.0
const CHARGE_COOLDOWN := 7.0

var enraged: bool = false

var _attack_kind: String = "slam"
var _slam_windup: float = 0.9
var _charge_cd: float = 3.0
var _charge_dir: Vector3 = Vector3.FORWARD
var _charge_hit_done: bool = false
var _arms_pivot: Node3D
var _veins: StandardMaterial3D
var _telegraph: MeshInstance3D
var _fire_timer: float = 0.0


func _init() -> void:
	xp_value = 600
	display_name = "Ashvein Colossus"
	max_health = 600.0
	move_speed = 2.6
	body_color = Color(0.55, 0.3, 0.2)
	stagger_resist = true


func _ready() -> void:
	super()
	# Boss-sized collision + hurtbox (base builds man-sized ones).
	for child in get_children():
		if child is CollisionShape3D:
			var capsule := (child as CollisionShape3D).shape as CapsuleShape3D
			capsule.radius = 0.85
			capsule.height = 2.8
			(child as CollisionShape3D).position.y = 1.4
		elif child is Hurtbox:
			var hb_col := (child as Hurtbox).get_child(0) as CollisionShape3D
			var hb_capsule := hb_col.shape as CapsuleShape3D
			hb_capsule.radius = 1.0
			hb_capsule.height = 3.0
			hb_col.position.y = 1.5
	health.health_changed.connect(func(c: float, m: float) -> void:
		boss_health_changed.emit(c, m)
		if not enraged and not net_puppet and c <= m * 0.5:  # a puppet learns it from the server
			_enrage()
	)


const RIG_PATH := "res://assets/models/chars/ashvein_colossus.glb"
const VEIN_ENERGY := 0.6
const VEIN_ENRAGED := 2.4


func _build_body() -> void:
	var rig_mesh := _setup_rigged_visual(RIG_PATH, "ashvein_colossus", {
		"idle": &"idle", "run": &"run", "run_speed": move_speed,
		"states": {
			AIState.WINDUP: func() -> StringName: return &"slam" if _attack_kind == "slam" else &"charge_windup",
			AIState.ATTACK: &"~charge",
			AIState.RECOVER: func() -> StringName: return &"~stun" if _attack_kind == "charge" else &"",
			AIState.STAGGER: &"stagger", AIState.CHASE: &"@loco", AIState.IDLE: &"@loco", AIState.DEAD: &"@dead"},
		# enraged slams wind up faster (0.65 s): the clip follows the timing
		"rate": func(clip: StringName) -> float: return 0.9 / _slam_windup if clip == &"slam" else 1.0,
	}, ArtKit.color("palettes.ashvein.eyes"))
	if rig_mesh != null:
		visual.scale = Vector3.ONE * 1.7
		base_visual_scale = visual.scale
		# Veins + back crystals (surface 2): code-owned, never hit-flashed,
		# emission always on (the enrage ramps energy only).
		_veins = flat_material(ArtKit.color("palettes.ashvein.vein"))
		_veins.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_veins.emission_enabled = true
		_veins.emission = ArtKit.color("palettes.ashvein.vein")
		_veins.emission_energy_multiplier = VEIN_ENERGY
		_veins.disable_fog = true
		_veins.set_meta(ArtKit.KEEP_EMISSION, true)
		rig_mesh.set_surface_override_material(2, _veins)
		_arms_pivot = Node3D.new()
		_arms_pivot.name = "ArmsPivotStandIn"
		visual.add_child(_arms_pivot)
		return
	if not _setup_model_visual("res://assets/models/enemy_brute.glb"):
		var torso := MeshInstance3D.new()
		var torso_mesh := BoxMesh.new()
		torso_mesh.size = Vector3(1.2, 1.3, 0.75)
		torso_mesh.material = flat_material(body_color)
		torso.mesh = torso_mesh
		torso.position = Vector3(0, 0.95, 0)
		visual.add_child(torso)
	visual.scale = Vector3.ONE * 1.7
	base_visual_scale = visual.scale
	# Ember crystal spikes: boss silhouette + element identity.
	for spike in [
		[Vector3(-0.55, 1.7, 0), Vector3(0.4, 0, -0.3)],
		[Vector3(0.6, 1.75, 0.1), Vector3(0.35, 0, 0.4)],
		[Vector3(0, 1.9, 0.25), Vector3(-0.5, 0, 0)],
	]:
		var crystal := MeshInstance3D.new()
		var mesh := PrismMesh.new()
		mesh.size = Vector3(0.28, 0.8, 0.28)
		mesh.material = flat_material(Color(1.0, 0.5, 0.15), true, 1.8)
		crystal.mesh = mesh
		crystal.position = spike[0]
		crystal.rotation = spike[1]
		visual.add_child(crystal)
	_arms_pivot = Node3D.new()
	_arms_pivot.position = Vector3(0, 1.35, 0)
	visual.add_child(_arms_pivot)
	for side: float in [-1.0, 1.0]:
		var fist := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.5, 0.5, 0.5)
		mesh.material = flat_material(body_color.darkened(0.2))
		fist.mesh = mesh
		fist.position = Vector3(side * 0.85, -0.45, -0.2)
		_arms_pivot.add_child(fist)


func _ai_process(delta: float) -> void:
	_charge_cd = maxf(_charge_cd - delta, 0.0)
	if enraged:
		_fire_timer += delta
		if _fire_timer >= 3.0:
			_fire_timer = 0.0
			var patch := FirePatch.new()
			patch.position = ZoneBase.ground_under(self, global_position, 0.02)
			get_tree().current_scene.add_child(patch)
	match ai_state:
		AIState.IDLE:
			brake(delta)
			if distance_to_player() < 22.0:
				_enter_state(AIState.CHASE)
				play_fx(&"roar")
		AIState.CHASE:
			face_player(delta, 4.0)
			var dist := distance_to_player()
			if dist <= SLAM_RANGE:
				_start_slam()
			elif _charge_cd <= 0.0 and dist >= CHARGE_MIN and dist <= CHARGE_MAX:
				_start_charge()
			else:
				move_towards(dir_to_player(), move_speed, delta)
		AIState.WINDUP:
			brake(delta)
			if _attack_kind == "slam":
				face_player(delta, 1.5)
				if _state_timer >= _slam_windup:
					_do_slam()
			else:
				# Charge windup: direction is committed, only slight tracking.
				if _state_timer >= 0.8:
					_begin_charge_run()
		AIState.ATTACK:
			# Charging run.
			velocity.x = _charge_dir.x * CHARGE_SPEED
			velocity.z = _charge_dir.z * CHARGE_SPEED
			_charge_contact_check()
			if is_on_wall() or _state_timer > 1.6:
				_end_charge(is_on_wall())
		AIState.RECOVER:
			brake(delta)
			if _state_timer >= (2.0 if _attack_kind == "charge" else 1.2):
				_enter_state(AIState.CHASE)
		AIState.STAGGER:
			brake(delta)
			if _state_timer >= 0.0:
				_enter_state(AIState.CHASE)


func _start_slam() -> void:
	_attack_kind = "slam"
	_enter_state(AIState.WINDUP)
	play_fx(&"slam_windup")


func _do_slam() -> void:
	_enter_state(AIState.RECOVER)
	play_fx(&"slam")
	var fwd := -visual.global_transform.basis.z
	var center := global_position + fwd * 1.8
	_hit_player_in_radius(center, SLAM_RADIUS, SLAM_DAMAGE, 9.0, HitInfo.Weight.HEAVY)


func _start_charge() -> void:
	_attack_kind = "charge"
	_charge_cd = CHARGE_COOLDOWN
	_charge_hit_done = false
	_enter_state(AIState.WINDUP)
	_charge_dir = dir_to_player()
	visual.rotation.y = atan2(-_charge_dir.x, -_charge_dir.z)
	play_fx(&"charge_windup")


func _begin_charge_run() -> void:
	_enter_state(AIState.ATTACK)
	play_fx(&"charge_run")


## M09 presentation of the colossus's actions (see EnemyBase.play_fx).
func _present_fx(fx: StringName) -> void:
	var scene := get_tree().current_scene
	var fwd := present_forward()
	match fx:
		&"roar":
			Sfx.play("boss_roar", global_position, 2.0)
		&"slam_windup":
			_telegraph = VFX.telegraph_disc(scene, present_origin() + fwd * 1.8, SLAM_RADIUS, _slam_windup)
			var tw := _arms_pivot.create_tween()
			tw.tween_property(_arms_pivot, "rotation_degrees", Vector3(-130, 0, 0), _slam_windup * 0.85) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			Sfx.play("earthbreaker_windup", global_position, -3.0, 0.1, 0.7)
		&"slam":
			var center := present_origin() + fwd * 1.8
			var tw := _arms_pivot.create_tween()
			tw.tween_property(_arms_pivot, "rotation_degrees", Vector3(40, 0, 0), 0.08)
			tw.tween_property(_arms_pivot, "rotation_degrees", Vector3.ZERO, 0.5)
			VFX.earthbreaker_slam(scene, center, SLAM_RADIUS)
			Sfx.play("earthbreaker_impact", center, 0.0, 0.08, 0.8)
			GameFeel.camera_shake(0.4)
		&"charge_windup":
			# Line telegraph: the shared threat language as a lane, filling from the
			# colossus to the far end over the 0.8 s charge windup.
			_telegraph = VFX.telegraph_lane(scene, present_origin(), fwd, CHARGE_MAX, 3.0, 0.8)
			Sfx.play("charge_horn", global_position, 0.0)
		&"charge_run":
			if _telegraph != null and is_instance_valid(_telegraph):
				_telegraph.queue_free()
			Sfx.play("boss_roar", global_position, -2.0, 0.1, 1.2)
		&"wall":
			VFX.earthbreaker_slam(scene, present_origin() + fwd * 1.5, 2.0)
			GameFeel.camera_shake(0.35)
		&"enrage":
			_present_enrage()


func _charge_contact_check() -> void:
	if _charge_hit_done:
		return
	# M07b: the charge flattens every hero in its path, not only the target.
	var zone := get_tree().current_scene as ZoneBase
	var victims: Array[Player] = zone.players_within(global_position, 2.0) if zone != null else []
	if victims.is_empty() and zone == null and player != null and is_instance_valid(player) \
			and player.global_position.distance_to(global_position) <= 2.0:
		victims.append(player)
	if not victims.is_empty():
		_charge_hit_done = true
		for victim in victims:
			var hit := HitInfo.create(CHARGE_DAMAGE, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.HEAVY, global_position - _charge_dir)
			hit.knockback = 10.0
			hit.area_center = global_position + Vector3(0, 0.9, 0)
			hit.area_radius = 2.0
			victim.take_hit(hit)
			VFX.melee_impact(get_tree().current_scene, victim.global_position + Vector3(0, 1.0, 0), _charge_dir)


func _end_charge(hit_wall: bool) -> void:
	_enter_state(AIState.RECOVER)
	velocity = Vector3.ZERO
	if hit_wall:
		play_fx(&"wall")
		_state_timer = -0.8  # extra stun for slamming the wall


func _hit_player_in_radius(center: Vector3, radius: float, damage: float, knockback: float, weight: HitInfo.Weight) -> void:
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), center + Vector3(0, 0.5, 0))
	query.collision_mask = 0b1000
	query.collide_with_areas = true
	query.collide_with_bodies = false
	for result: Dictionary in space.intersect_shape(query, 4):
		var hb := result["collider"] as Hurtbox
		if hb != null and hb.owner_entity is Player:
			var hit := HitInfo.create(damage, HitInfo.DamageType.PHYSICAL, weight, global_position)
			hit.knockback = knockback
			hit.area_center = center + Vector3(0, 0.5, 0)
			hit.area_radius = radius
			(hb.owner_entity as Player).take_hit(hit)  # M09: every hero inside


func _enrage() -> void:
	move_speed = 3.4
	play_fx(&"enrage")


## Enraged looks (and the quicker slam windup the telegraphs use).
func _present_enrage() -> void:
	enraged = true
	_slam_windup = 0.65
	if _veins != null:
		create_tween().tween_property(_veins, "emission_energy_multiplier", VEIN_ENRAGED, 0.4)
	if animator != null and ai_state == AIState.CHASE:
		animator.play_one_shot(&"roar")
	var aura := OmniLight3D.new()
	aura.light_color = Color(1.0, 0.3, 0.15)
	aura.light_energy = 2.0
	aura.omni_range = 6.0
	aura.position = Vector3(0, 1.5, 0)
	add_child(aura)
	VFX.flash(get_tree().current_scene, global_position + Vector3(0, 2.0, 0), Color(1.0, 0.3, 0.2), 2.5, 0.25)
	GameFeel.camera_shake(0.4)
	Sfx.play("boss_roar", global_position, 4.0, 0.05, 0.85)


func _on_interrupted() -> void:
	if _telegraph != null and is_instance_valid(_telegraph):
		_telegraph.queue_free()
