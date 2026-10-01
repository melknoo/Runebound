class_name AshJackal
extends EnemyBase
## M12 bone field (the carrion brood): a lean grey jackal that hunts in a
## pack of three. It trots in a ring around a hero, then crouches with its
## jaws open - a disc fills a leap ahead of it, where the hero stands - and
## springs onto that spot. The pack takes turns: while one crouches or flies,
## the others keep circling (PACK_GAP per hero), so a pack reads as a rhythm
## to dodge, not a pile. After the bite it stands a moment (the opening to
## punish it), then lopes off and circles again.

const CIRCLE_RADIUS := 5.5
const CIRCLE_MIN := 1.2
const CIRCLE_MAX := 2.6
const WINDUP_TIME := 0.55
const LEAP_TIME := 0.35
## The leap always covers this far (the marker sits there on every machine);
## it only starts with the hero LEAP_MIN..LEAP_MAX away.
const LEAP_DIST := 5.0
const LEAP_MIN := 4.2
const LEAP_MAX := 6.2
const LEAP_HEIGHT := 0.9
const BITE_RADIUS := 1.4
const BITE_DAMAGE := 9.0
const RECOVER_TIME := 0.7
const RETREAT_TIME := 1.0
## No two jackals start a leap at the same hero within this long.
const PACK_GAP := 0.9

const RIG_PATH := "res://assets/models/chars/ash_jackal.glb"

## Hero instance id -> when (s) the next jackal may leap at them.
static var _next_leap_at: Dictionary = {}

var _circle_dir: float = 1.0
var _circle_for: float = 2.0
var _disc: MeshInstance3D
var _hop: Tween


func _init() -> void:
	xp_value = 16
	display_name = Texts.t("enemy.ash_jackal")
	max_health = 28.0
	move_speed = 6.5
	body_color = Color(0.55, 0.5, 0.44)


func nameplate_height() -> float:
	return 1.5 * maxf(base_visual_scale.y, 1.0)


func _build_body() -> void:
	if _setup_rigged_visual(RIG_PATH, "ash_jackal", {
		"idle": &"idle", "run": &"run", "run_speed": move_speed,
		"states": {AIState.CIRCLE: &"~trot", AIState.WINDUP: &"pounce", AIState.STAGGER: &"stagger",
			AIState.RECOVER: &"@loco", AIState.RETREAT: &"@loco",
			AIState.CHASE: &"@loco", AIState.IDLE: &"@loco", AIState.DEAD: &"@dead"},
	}, ArtKit.color("palettes.ash_jackal.eyes")) != null:
		return
	var torso := MeshInstance3D.new()  # fallback (and the dedicated server): a low, long box
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.3, 0.35, 1.0)
	mesh.material = flat_material(body_color)
	torso.mesh = mesh
	torso.position = Vector3(0, 0.6, 0)
	visual.add_child(torso)


func _ai_process(delta: float) -> void:
	match ai_state:
		AIState.IDLE:
			brake(delta)
			if distance_to_player() < AGGRO_RANGE:
				_enter_state(AIState.CHASE)
		AIState.CHASE:
			face_player(delta, 12.0)
			if distance_to_player() > CIRCLE_RADIUS + 1.0:
				move_towards(dir_to_player(), move_speed, delta)
			else:
				_start_circle()
		AIState.CIRCLE:
			face_player(delta, 12.0)
			var to_player := dir_to_player()
			var dist := distance_to_player()
			var tangent := to_player.cross(Vector3.UP) * _circle_dir
			var radial := to_player * clampf(dist - CIRCLE_RADIUS, -1.0, 1.0)
			move_towards((tangent + radial).normalized(), move_speed * 0.8, delta)
			if dist > CIRCLE_RADIUS + 4.0:
				_enter_state(AIState.CHASE)
			elif _state_timer >= _circle_for and dist >= LEAP_MIN and dist <= LEAP_MAX and _claim_leap():
				_start_windup()
		AIState.WINDUP:
			brake(delta)  # facing locked: the leap goes where the disc is
			if _state_timer >= WINDUP_TIME:
				_enter_state(AIState.ATTACK)
				_present_leap()
		AIState.ATTACK:
			velocity.x = _strike_forward.x * LEAP_DIST / LEAP_TIME
			velocity.z = _strike_forward.z * LEAP_DIST / LEAP_TIME
			if _state_timer >= LEAP_TIME:
				velocity.x = 0.0
				velocity.z = 0.0
				_enter_state(AIState.RECOVER)
				_bite()
		AIState.RECOVER:
			brake(delta)
			if _state_timer >= RECOVER_TIME:
				_enter_state(AIState.RETREAT)
		AIState.RETREAT:
			var away := -dir_to_player()
			visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-away.x, -away.z), minf(10.0 * delta, 1.0))
			move_towards(away, move_speed, delta)
			if _state_timer >= RETREAT_TIME:
				_start_circle()
		AIState.STAGGER:
			brake(delta)
			if _state_timer >= 0.0:
				_enter_state(AIState.RETREAT)


func _start_circle() -> void:
	_enter_state(AIState.CIRCLE)
	_circle_dir = 1.0 if randf() < 0.5 else -1.0
	_circle_for = randf_range(CIRCLE_MIN, CIRCLE_MAX)


## The pack's turn: true (and the turn is ours) when no packmate leapt at
## this hero within PACK_GAP.
func _claim_leap() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	var key := player.get_instance_id()
	var now := Time.get_ticks_msec() / 1000.0
	if now < float(_next_leap_at.get(key, -1.0)):
		return false
	_next_leap_at[key] = now + WINDUP_TIME + PACK_GAP
	return true


func _start_windup() -> void:
	var dir := dir_to_player()
	visual.rotation.y = atan2(-dir.x, -dir.z)  # square on the hero, then locked
	lock_strike()
	_enter_state(AIState.WINDUP)
	_present_windup()


func _bite() -> void:
	play_fx(&"bite")
	for victim in strike_circle(strike_point(LEAP_DIST), BITE_RADIUS, BITE_DAMAGE,
			HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, 2.5):
		VFX.enemy_hit(get_tree().current_scene, victim.global_position + Vector3(0, 1.0, 0))


func _present_state(s: AIState) -> void:
	super(s)
	match s:
		AIState.WINDUP:
			_present_windup()
		AIState.ATTACK:
			_present_leap()


## The disc fills over the crouch and the leap: it is full as the jaws close.
func _present_windup() -> void:
	_disc = VFX.telegraph_disc(get_tree().current_scene, present_origin() + present_forward() * LEAP_DIST,
		BITE_RADIUS, WINDUP_TIME + LEAP_TIME)
	Sfx.play("jackal_snarl", global_position, -6.0, 0.12)


func _present_leap() -> void:
	if _hop != null and _hop.is_valid():
		_hop.kill()
	_hop = create_tween()
	_hop.tween_property(visual, "position:y", LEAP_HEIGHT, LEAP_TIME * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_hop.tween_property(visual, "position:y", 0.0, LEAP_TIME * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	Sfx.play("swing", global_position, -8.0, 0.15, 1.4)


func _present_fx(fx: StringName) -> void:
	if fx == &"bite":
		VFX.dodge_dust(get_tree().current_scene, present_origin(), present_forward())
		Sfx.play("jackal_snarl", global_position, -4.0, 0.1, 1.35)


func _on_interrupted() -> void:
	if _disc != null and is_instance_valid(_disc):
		_disc.queue_free()
	if _hop != null and _hop.is_valid():
		_hop.kill()
	visual.position.y = 0.0
