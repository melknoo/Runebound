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
	loot_kind = &"boss"  # M13: the drop tables and draughts read the tier
	gold_piles = 3


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


## The slam's disc sits this far ahead (marker and hit alike).
const SLAM_AHEAD := 1.8
## The charge lane: half its drawn width, and how far the colossus's body
## reaches behind / ahead of its centre along the lane.
const CHARGE_HALF_WIDTH := 1.5
const CHARGE_BODY_BACK := 1.0
const CHARGE_BODY_FRONT := 1.8

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
				# Facing locked at wind-up start: the slam lands on its disc.
				if _state_timer >= _slam_windup:
					_do_slam()
			else:
				# Charge windup: direction committed, no tracking.
				if _state_timer >= 0.8:
					_begin_charge_run()
		AIState.ATTACK:
			# Charging run, down the lane it drew and no further.
			velocity.x = _charge_dir.x * CHARGE_SPEED
			velocity.z = _charge_dir.z * CHARGE_SPEED
			_charge_contact_check()
			var run := (global_position - _strike_origin).dot(_charge_dir)
			if is_on_wall() or _state_timer > 1.6 or run >= CHARGE_MAX:
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
	lock_strike()
	_enter_state(AIState.WINDUP)
	play_fx(&"slam_windup")


func _do_slam() -> void:
	_enter_state(AIState.RECOVER)
	play_fx(&"slam")
	_hit_player_in_radius(strike_point(SLAM_AHEAD), SLAM_RADIUS, SLAM_DAMAGE, 9.0, HitInfo.Weight.HEAVY)


func _start_charge() -> void:
	_attack_kind = "charge"
	_charge_cd = CHARGE_COOLDOWN
	_charge_hit_done = false
	_enter_state(AIState.WINDUP)
	_charge_dir = dir_to_player()
	visual.rotation.y = atan2(-_charge_dir.x, -_charge_dir.z)
	lock_strike()  # the lane starts here
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
			_telegraph = VFX.telegraph_disc(scene, present_origin() + fwd * SLAM_AHEAD, SLAM_RADIUS, _slam_windup)
			var tw := _arms_pivot.create_tween()
			tw.tween_property(_arms_pivot, "rotation_degrees", Vector3(-130, 0, 0), _slam_windup * 0.85) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			Sfx.play("earthbreaker_windup", global_position, -3.0, 0.1, 0.7)
		&"slam":
			var center := present_origin() + fwd * SLAM_AHEAD
			var tw := _arms_pivot.create_tween()
			tw.tween_property(_arms_pivot, "rotation_degrees", Vector3(40, 0, 0), 0.08)
			tw.tween_property(_arms_pivot, "rotation_degrees", Vector3.ZERO, 0.5)
			VFX.earthbreaker_slam(scene, center, SLAM_RADIUS)
			Sfx.play("earthbreaker_impact", center, 0.0, 0.08, 0.8)
			GameFeel.camera_shake(0.4)
		&"charge_windup":
			# Line telegraph: the shared threat language as a lane, filling from the
			# colossus to the far end over the 0.8 s charge windup.
			_telegraph = VFX.telegraph_lane(scene, present_origin(), fwd, CHARGE_MAX, CHARGE_HALF_WIDTH * 2.0, 0.8)
			Sfx.play("charge_horn", global_position, 0.0)
		&"charge_run":
			# The lane stays on the ground for the whole run (M08 notes: the
			# charge hit where nothing was drawn anymore).
			if _telegraph != null and is_instance_valid(_telegraph):
				_telegraph.queue_free()
			_telegraph = VFX.telegraph_lane(scene, present_origin(), fwd, CHARGE_MAX, CHARGE_HALF_WIDTH * 2.0,
				CHARGE_MAX / CHARGE_SPEED)
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
	# M08 notes: "in its path" = inside the drawn lane (half width + the rim
	# tolerance), where the colossus is right now.
	var victims := heroes_in_lane()
	if not victims.is_empty():
		_charge_hit_done = true
		for victim in victims:
			var rel := victim.global_position - _strike_origin
			var on_axis := _strike_origin + _charge_dir * rel.dot(_charge_dir)
			var hit := HitInfo.create(CHARGE_DAMAGE, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.HEAVY, global_position - _charge_dir)
			hit.source_id = get_instance_id()  # M10: a parried charge counters the Colossus
			hit.knockback = 10.0
			hit.area_center = on_axis
			hit.area_radius = CHARGE_HALF_WIDTH + STRIKE_TOLERANCE
			victim.take_hit(hit)
			VFX.melee_impact(get_tree().current_scene, victim.global_position + Vector3(0, 1.0, 0), _charge_dir)


## Heroes inside the charge lane next to the colossus: within the half width
## of its axis and from just behind to just ahead of its body.
func heroes_in_lane() -> Array[Player]:
	var out: Array[Player] = []
	var zone := ZoneBase.zone_of(self)
	var candidates: Array[Player] = []
	if zone != null:
		candidates = zone.players
	elif player != null and is_instance_valid(player):
		candidates.append(player)
	var here := (global_position - _strike_origin).dot(_charge_dir)
	for p in candidates:
		if p == null or not is_instance_valid(p) or p.health.is_dead:
			continue
		var rel := p.global_position - _strike_origin
		if absf(rel.y) > STRIKE_HEIGHT:
			continue
		rel.y = 0.0
		var along := rel.dot(_charge_dir)
		var side := (rel - _charge_dir * along).length()
		if side <= CHARGE_HALF_WIDTH + STRIKE_TOLERANCE and along >= here - CHARGE_BODY_BACK \
				and along <= here + CHARGE_BODY_FRONT and along <= CHARGE_MAX + STRIKE_TOLERANCE:
			out.append(p)
	return out


func _end_charge(hit_wall: bool) -> void:
	_enter_state(AIState.RECOVER)
	velocity = Vector3.ZERO
	if hit_wall:
		play_fx(&"wall")
		_state_timer = -0.8  # extra stun for slamming the wall


## M09: every hero inside; exactly the marker's disc (M08 notes).
func _hit_player_in_radius(center: Vector3, radius: float, damage: float, knockback: float, weight: HitInfo.Weight) -> void:
	strike_circle(center, radius, damage, HitInfo.DamageType.PHYSICAL, weight, knockback)


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
