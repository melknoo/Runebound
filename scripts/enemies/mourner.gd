class_name Mourner
extends EnemyBase
## M12 the Restless (Ashwick): a drifting, shrouded spirit that keeps its
## distance and screams. The scream is a lane in front of it (the red strip
## fills over the wind-up); whoever is still in it when it lets go takes a
## little damage and is slowed (SLOW for SLOW_TIME; the druid's Rootwalk
## clears it). Pale and solid, with an outline - unlike the see-through
## ghosts that only talk.

const PREFERRED_MIN := 5.0
const PREFERRED_MAX := 9.0
const WINDUP_TIME := 1.0
const RECOVER_TIME := 1.5
const SCREAM_LENGTH := 7.5
const SCREAM_WIDTH := 3.2
const SCREAM_DAMAGE := 8.0
const SLOW := 0.4
const SLOW_TIME := 3.0

const RIG_PATH := "res://assets/models/chars/mourner.glb"

var _lane: MeshInstance3D


func _init() -> void:
	xp_value = 26
	display_name = Texts.t("enemy.mourner")
	max_health = 45.0
	move_speed = 3.0
	body_color = Color(0.56, 0.58, 0.62)


func _build_body() -> void:
	if _setup_rigged_visual(RIG_PATH, "mourner", {
		"idle": &"idle", "run": &"glide", "run_speed": move_speed,
		"states": {AIState.WINDUP: &"charge", AIState.RECOVER: &"cast", AIState.STAGGER: &"stagger",
			AIState.CHASE: &"@loco", AIState.IDLE: &"@loco", AIState.DEAD: &"@dead"},
	}, ArtKit.color("palettes.mourner.eyes")) != null:
		return
	var robe := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.18
	mesh.bottom_radius = 0.38
	mesh.height = 1.5
	mesh.material = flat_material(body_color)
	robe.mesh = mesh
	robe.position = Vector3(0, 0.85, 0)
	visual.add_child(robe)


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
				move_towards(-dir_to_player(), move_speed, delta)
			elif dist > PREFERRED_MAX:
				move_towards(dir_to_player(), move_speed, delta)
			else:
				brake(delta)
				if _state_timer > 0.5:
					lock_strike()
					_enter_state(AIState.WINDUP)
					_present_windup()
		AIState.WINDUP:
			brake(delta)  # facing locked: the scream goes where the strip is
			if _state_timer >= WINDUP_TIME:
				_enter_state(AIState.RECOVER)
				_scream()
				_present_scream()
		AIState.RECOVER:
			brake(delta)
			var side := dir_to_player().cross(Vector3.UP)
			move_towards(side * (1.0 if (get_instance_id() % 2 == 0) else -1.0), move_speed * 0.5, delta)
			if _state_timer >= RECOVER_TIME:
				_enter_state(AIState.CHASE)
		AIState.STAGGER:
			brake(delta)
			if _state_timer >= 0.0:
				_enter_state(AIState.CHASE)


## Every hero inside the strip: a little damage and the slow (a Chill on the
## hit: the owner turns it into the slow, also in co-op).
func _scream() -> void:
	var zone := ZoneBase.zone_of(self)
	if zone == null:
		return
	var start := _strike_origin
	var dir := _strike_forward
	for hero in zone.players:
		if not is_instance_valid(hero) or hero.health.is_dead:
			continue
		var rel := hero.global_position - start
		var along := rel.dot(dir)
		var across := absf(rel.dot(dir.cross(Vector3.UP)))
		if along < 0.0 or along > SCREAM_LENGTH or across > SCREAM_WIDTH * 0.5 + STRIKE_TOLERANCE:
			continue
		var hit := HitInfo.create(SCREAM_DAMAGE, HitInfo.DamageType.ARCANE, HitInfo.Weight.LIGHT, global_position)
		hit.applies_chill = true
		hit.area_center = start + dir * clampf(along, 0.0, SCREAM_LENGTH)
		hit.area_radius = SCREAM_WIDTH * 0.5 + STRIKE_TOLERANCE
		hit.source_id = get_instance_id()
		hero.take_hit(hit)


func _present_state(s: AIState) -> void:
	super(s)
	match s:
		AIState.WINDUP:
			_present_windup()
		AIState.RECOVER:
			_present_scream()


func _present_windup() -> void:
	_lane = VFX.telegraph_lane(get_tree().current_scene, present_origin(), present_forward(), SCREAM_LENGTH,
		SCREAM_WIDTH, WINDUP_TIME)
	Sfx.play("caster_charge", global_position, -4.0, 0.1, 0.6)


func _present_scream() -> void:
	var scene := get_tree().current_scene
	var fwd := present_forward()
	VFX.ground_ring(scene, present_origin() + fwd * 1.5, ArtKit.color("palettes.mourner.eyes", Color("#A8D0F0")), 3.0, 0.45)
	VFX.flash(scene, present_origin() + Vector3(0, 1.5, 0) + fwd * 0.4, ArtKit.color("palettes.mourner.eyes", Color("#A8D0F0")), 1.0, 0.18)
	Sfx.play("vessel_roar", global_position, -10.0, 0.1, 1.8)


func _on_interrupted() -> void:
	if _lane != null and is_instance_valid(_lane):
		_lane.queue_free()
