class_name GaleWraith
extends EnemyBase
## M13b the storm family: a scrap of wind the Galebinder has given a shape -
## quick and thin, it circles in, marks a short lane at its prey and dives
## down it. Few blows tear it apart. It comes in waves, one for every hero.

const ATTACK_RANGE := 5.5
const WINDUP_TIME := 0.55
const DIVE_TIME := 0.3
const DIVE_LENGTH := 5.0
const DIVE_HALF_WIDTH := 0.6
const DIVE_DAMAGE := 9.0
const RECOVER_TIME := 0.9

const RIG_PATH := "res://assets/models/chars/gale_wraith.glb"

var _dive_dir := Vector3.FORWARD


func _init() -> void:
	xp_value = 14
	display_name = Texts.t("enemy.gale_wraith")
	max_health = 30.0
	move_speed = 5.4
	body_color = Color(0.7, 0.72, 0.9)


func _build_body() -> void:
	if _setup_rigged_visual(RIG_PATH, "gale_wraith", {
		"idle": &"idle", "run": &"glide", "run_speed": move_speed,
		"states": {AIState.WINDUP: &"charge", AIState.ATTACK: &"cast", AIState.STAGGER: &"stagger",
			AIState.CHASE: &"@loco", AIState.IDLE: &"@loco", AIState.DEAD: &"@dead"},
	}, ArtKit.color("palettes.gale_wraith.eyes")) != null:
		return
	var core := MeshInstance3D.new()  # fallback (and the dedicated server): a pale wisp
	var mesh := SphereMesh.new()
	mesh.radius = 0.28
	mesh.height = 0.56
	mesh.material = flat_material(body_color, true, 1.2)
	core.mesh = mesh
	core.position = Vector3(0, 1.0, 0)
	visual.add_child(core)


func _ai_process(delta: float) -> void:
	match ai_state:
		AIState.IDLE:
			brake(delta)
			if distance_to_player() < AGGRO_RANGE * 1.5:
				_enter_state(AIState.CHASE)
		AIState.CHASE:
			face_player(delta, 9.0)
			move_towards(dir_to_player(), move_speed, delta)
			if distance_to_player() <= ATTACK_RANGE:
				lock_strike()
				_dive_dir = _strike_forward
				_enter_state(AIState.WINDUP)
				play_fx(&"dive_tell")
		AIState.WINDUP:
			brake(delta)
			if _state_timer >= WINDUP_TIME:
				strike_lane(_strike_origin, _dive_dir, DIVE_LENGTH, DIVE_HALF_WIDTH, DIVE_DAMAGE,
					HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, 4.0)
				play_fx(&"dive")
				_enter_state(AIState.ATTACK)
		AIState.ATTACK:  # the dive itself: it shoots down its lane
			velocity.x = _dive_dir.x * DIVE_LENGTH / DIVE_TIME
			velocity.z = _dive_dir.z * DIVE_LENGTH / DIVE_TIME
			if _state_timer >= DIVE_TIME:
				_enter_state(AIState.RECOVER)
		AIState.RECOVER:
			brake(delta)
			if _state_timer >= RECOVER_TIME:
				_enter_state(AIState.CHASE)
		AIState.STAGGER:
			brake(delta)
			if _state_timer >= 0.0:
				_enter_state(AIState.CHASE)


func _present_fx(fx: StringName) -> void:
	match fx:
		&"dive_tell":
			VFX.telegraph_lane(get_tree().current_scene, present_origin(), present_forward(), DIVE_LENGTH,
				DIVE_HALF_WIDTH * 2.0, WINDUP_TIME)
			Sfx.play("wraith_shriek", global_position, -8.0, 0.15)
		&"dive":
			Sfx.play("gale_gust", global_position, -10.0, 0.1, 1.5)
