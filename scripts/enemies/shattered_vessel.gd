class_name ShatteredVessel
extends EnemyBase
## THE VESSEL OF THE SHATTERED RUNE — major boss of the Shattered Spire.
## Phase 1 (Construct): grounded melee — slams, shadow runes, rusher adds.
## Phase 2 (Shatter, <50%): breaks apart — blinks between arena anchors,
## fires rune fans, more runes, expanding hazard rings from the arena center.

signal boss_health_changed(current: float, maximum: float)
signal summon_requested(pos: Vector3)

const SLAM_RANGE := 3.0
const SLAM_RADIUS := 3.0
const SLAM_DAMAGE := 26.0
const SLAM_WINDUP := 0.8
const FAN_BOLTS := 3
const FAN_SPREAD := 0.35  # radians total
const RING_DAMAGE := 15.0
const RING_MAX_RADIUS := 13.0
const RING_EXPAND_TIME := 2.6

var phase: int = 1
var arena_center: Vector3 = Vector3.ZERO
var blink_anchors: Array[Vector3] = []

var _rune_timer: float = 4.0
var _summon_timer: float = 12.0
var _blink_timer: float = 2.0
var _fan_timer: float = 1.5
var _ring_timer: float = 6.0
var _adds_alive: int = 0
var _shattering: bool = false
var _core_visual: Node3D


func _init() -> void:
	xp_value = 1200
	display_name = "Vessel of the Shattered Rune"
	max_health = 1400.0
	move_speed = 2.4
	body_color = Color(0.5, 0.35, 0.75)
	stagger_resist = true


## Floating crystal body is far taller than its scale suggests.
func nameplate_height() -> float:
	return 4.7


func setup_arena(center: Vector3, anchors: Array[Vector3]) -> void:
	arena_center = center
	blink_anchors = anchors


func _ready() -> void:
	super()
	for child in get_children():
		if child is CollisionShape3D:
			var capsule := (child as CollisionShape3D).shape as CapsuleShape3D
			capsule.radius = 0.9
			capsule.height = 3.0
			(child as CollisionShape3D).position.y = 1.5
		elif child is Hurtbox:
			var hb_col := (child as Hurtbox).get_child(0) as CollisionShape3D
			var hb_capsule := hb_col.shape as CapsuleShape3D
			hb_capsule.radius = 1.1
			hb_capsule.height = 3.2
			hb_col.position.y = 1.6
	health.health_changed.connect(func(c: float, m: float) -> void:
		boss_health_changed.emit(c, m)
		if phase == 1 and not _shattering and c <= m * 0.5:
			_begin_shatter()
	)


const RIG_PATH := "res://assets/models/chars/vessel.glb"


func _build_body() -> void:
	var rigged := _setup_rigged_visual(RIG_PATH, "vessel", {
		"idle": &"idle", "run": &"run", "run_speed": maxf(move_speed, 0.1),
		"states": {AIState.WINDUP: &"slam", AIState.STAGGER: &"stagger", AIState.CIRCLE: &"~p2_idle",
			AIState.CHASE: &"@loco", AIState.IDLE: &"@loco", AIState.DEAD: &"@dead"},
	}, ArtKit.color("palettes.vessel.heart")) != null
	if not rigged and not _setup_model_visual("res://assets/models/boss_vessel.glb"):
		var body := MeshInstance3D.new()
		var mesh := PrismMesh.new()
		mesh.size = Vector3(1.2, 2.4, 1.2)
		mesh.material = flat_material(body_color, true, 1.2)
		body.mesh = mesh
		body.position = Vector3(0, 1.5, 0)
		visual.add_child(body)
	visual.scale = Vector3.ONE * 1.4
	base_visual_scale = visual.scale
	# Idle float: the vessel never touches the ground with its body.
	var bob := visual.create_tween().set_loops()
	bob.tween_property(visual, "position:y", 0.35, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(visual, "position:y", 0.0, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var aura := OmniLight3D.new()
	aura.light_color = Color(0.7, 0.4, 1.0)
	aura.light_energy = 1.8
	aura.omni_range = 7.0
	aura.position = Vector3(0, 1.8, 0)
	add_child(aura)


func _ai_process(delta: float) -> void:
	if _shattering:
		brake(delta)
		return
	if phase == 1:
		_phase1(delta)
	else:
		_phase2(delta)


# --- Phase 1: grounded construct ------------------------------------------

func _phase1(delta: float) -> void:
	_rune_timer -= delta
	_summon_timer -= delta
	if _rune_timer <= 0.0 and player != null:
		_rune_timer = 8.0
		_place_runes(3)
	if _summon_timer <= 0.0 and _adds_alive < 3:
		_summon_timer = 20.0
		_summon_adds()
	match ai_state:
		AIState.IDLE:
			brake(delta)
			if distance_to_player() < 26.0:
				_enter_state(AIState.CHASE)
				Sfx.play("vessel_roar", global_position, 4.0)
				GameFeel.camera_shake(0.35)
		AIState.CHASE:
			face_player(delta, 4.0)
			move_towards(dir_to_player(), move_speed, delta)
			if distance_to_player() <= SLAM_RANGE:
				_start_slam()
		AIState.WINDUP:
			brake(delta)
			face_player(delta, 1.5)
			if _state_timer >= SLAM_WINDUP:
				_do_slam()
		AIState.RECOVER:
			brake(delta)
			if _state_timer >= 1.1:
				_enter_state(AIState.CHASE)
		AIState.STAGGER:
			brake(delta)
			if _state_timer >= 0.0:
				_enter_state(AIState.CHASE)


func _start_slam() -> void:
	_enter_state(AIState.WINDUP)
	var fwd := -visual.global_transform.basis.z
	VFX.telegraph_disc(get_tree().current_scene,
		global_position + fwd * 1.6, SLAM_RADIUS, SLAM_WINDUP)
	Sfx.play("earthbreaker_windup", global_position, -4.0, 0.1, 0.75)


func _do_slam() -> void:
	_enter_state(AIState.RECOVER)
	var fwd := -visual.global_transform.basis.z
	var center := global_position + fwd * 1.6
	VFX.earthbreaker_slam(get_tree().current_scene, center, SLAM_RADIUS)
	VFX.light_pop(get_tree().current_scene, center, Color(0.7, 0.4, 1.0), 4.0, 6.0, 0.25)
	Sfx.play("earthbreaker_impact", center, -2.0, 0.1, 0.85)
	GameFeel.camera_shake(0.3)
	_hit_player_in_radius(center, SLAM_RADIUS, SLAM_DAMAGE, 8.0)


func _summon_adds() -> void:
	Sfx.play("vessel_roar", global_position, -4.0, 0.1, 1.3)
	for i in 2:
		var offset := Vector3(randf_range(-4.0, 4.0), 0, randf_range(-4.0, 4.0))
		summon_requested.emit(global_position + offset)
		_adds_alive += 1


func notify_add_died() -> void:
	_adds_alive = maxi(_adds_alive - 1, 0)


# --- Phase transition -------------------------------------------------------

func _begin_shatter() -> void:
	_shattering = true
	health.invulnerable = true
	_enter_state(AIState.RECOVER)
	var scene := get_tree().current_scene
	VFX.flash(scene, global_position + Vector3(0, 2.0, 0), Color(0.85, 0.6, 1.0), 3.0, 0.3)
	VFX.burst(scene, global_position + Vector3(0, 1.8, 0), {
		"tex": "shard", "amount": 30, "lifetime": 0.8, "size": 0.28,
		"spread": 90.0, "vel_min": 5.0, "vel_max": 10.0, "gravity": Vector3(0, -10, 0),
		"emission_radius": 0.8,
		"colors": [Color(0.95, 0.8, 1.0), Color(0.65, 0.35, 1.0), Color(0.3, 0.15, 0.55, 0.0)] as Array[Color],
	})
	Sfx.play("shatter_burst", global_position, 4.0)
	GameFeel.camera_shake(0.6)
	if animator != null:
		animator.play_one_shot(&"shatter")
	await get_tree().create_timer(1.0).timeout
	if not is_instance_valid(self) or health.is_dead:
		return
	health.invulnerable = false
	_shattering = false
	phase = 2
	move_speed = 0.0
	_enter_state(AIState.CIRCLE)
	Sfx.play("vessel_roar", global_position, 2.0, 0.05, 1.2)


# --- Phase 2: shattered — blinks and barrages ------------------------------

func _phase2(delta: float) -> void:
	brake(delta)
	face_player(delta, 6.0)
	_blink_timer -= delta
	_fan_timer -= delta
	_rune_timer -= delta
	_ring_timer -= delta
	if _blink_timer <= 0.0 and not blink_anchors.is_empty():
		_blink_timer = 5.0
		_blink()
	if _fan_timer <= 0.0 and player != null and is_instance_valid(player):
		_fan_timer = 2.5
		_fire_fan()
	if _rune_timer <= 0.0:
		_rune_timer = 7.0
		_place_runes(4)
	if _ring_timer <= 0.0:
		_ring_timer = 10.0
		_expanding_ring()


func _blink() -> void:
	var scene := get_tree().current_scene
	var from := global_position
	var anchor: Vector3 = blink_anchors.pick_random()
	if anchor.distance_to(from) < 2.0 and blink_anchors.size() > 1:
		anchor = blink_anchors[(blink_anchors.find(anchor) + 1) % blink_anchors.size()]
	VFX.flash(scene, from + Vector3(0, 1.5, 0), Color(0.7, 0.4, 1.0), 1.6, 0.2)
	VFX.burst(scene, from + Vector3(0, 1.2, 0), {
		"tex": "spark", "amount": 10, "lifetime": 0.3, "size": 0.16,
		"spread": 90.0, "vel_min": 2.0, "vel_max": 4.0,
		"colors": [Color(0.9, 0.7, 1.0), Color(0.5, 0.25, 0.8, 0.0)] as Array[Color],
	})
	global_position = anchor
	VFX.flash(scene, anchor + Vector3(0, 1.5, 0), Color(0.85, 0.6, 1.0), 2.0, 0.2)
	VFX.light_pop(scene, anchor + Vector3(0, 1.5, 0), Color(0.7, 0.4, 1.0), 3.0, 6.0, 0.2)
	Sfx.play("boss_blink", anchor, 0.0, 0.08)


func _fire_fan() -> void:
	var origin := global_position + Vector3(0, 1.8, 0)
	var base_dir := (player.global_position + Vector3(0, 1.0, 0) - origin).normalized()
	for i in FAN_BOLTS:
		var angle := (float(i) - float(FAN_BOLTS - 1) * 0.5) * (FAN_SPREAD / maxf(FAN_BOLTS - 1, 1))
		var dir := base_dir.rotated(Vector3.UP, angle)
		var bolt := EnemyBolt.new()
		bolt.setup(dir, 12.0, 10.0)
		bolt.position = origin + dir * 1.2
		get_tree().current_scene.add_child(bolt)
	Sfx.play("bolt_fire", global_position, -2.0, 0.1, 0.85)
	if animator != null:
		animator.play_one_shot(&"fan")


func _place_runes(count: int) -> void:
	if player == null or not is_instance_valid(player):
		return
	var scene := get_tree().current_scene
	for i in count:
		var rune := ShadowRune.new()
		var offset := Vector3.ZERO if i == 0 else Vector3(randf_range(-4.0, 4.0), 0, randf_range(-4.0, 4.0))
		var pos := player.global_position + offset
		rune.position = ZoneBase.ground_under(self, pos, 0.02)
		scene.add_child(rune)


func _expanding_ring() -> void:
	var scene := get_tree().current_scene
	Sfx.play("caster_charge", arena_center, -2.0, 0.05, 0.7)
	# Shared threat language (crimson band + bright rims), exactly the band
	# the hit test below uses (+- 0.8 m around the growing radius).
	var ring := VFX.threat_ring(scene, arena_center, RING_MAX_RADIUS, 0.8)
	var hit_done: Array[Player] = []  # M07b: the ring checks every hero, each once
	var zone := get_tree().current_scene as ZoneBase
	var tw := ring.create_tween()
	tw.tween_method(func(r: float) -> void:
		VFX.set_threat_ring(ring, r)
		var heroes: Array[Player] = zone.players if zone != null else ([player] as Array[Player])
		for hero in heroes:
			if hero == null or not is_instance_valid(hero) or hit_done.has(hero):
				continue
			var dist := Vector2(hero.global_position.x - arena_center.x,
				hero.global_position.z - arena_center.z).length()
			# The ring edge is ~1m thick; crossing it while not dodging hurts.
			if absf(dist - r) < 0.8:
				hit_done.append(hero)
				var hit := HitInfo.create(RING_DAMAGE, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.MEDIUM, arena_center)
				hit.knockback = 5.0
				hero.take_hit(hit)
	, 0.5, RING_MAX_RADIUS, RING_EXPAND_TIME)
	tw.tween_callback(ring.queue_free)


func _hit_player_in_radius(center: Vector3, radius: float, damage: float, knockback: float) -> void:
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
			var hit := HitInfo.create(damage, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.HEAVY, global_position)
			hit.knockback = knockback
			(hb.owner_entity as Player).take_hit(hit)
			break
