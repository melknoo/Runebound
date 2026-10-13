class_name StormAcolyte
extends EnemyBase
## M13b the storm family (the Stormwatch): an acolyte of the old Circle in a
## burnt robe, a copper circlet, the storm in its hands. It keeps its
## distance and calls a bolt down where its prey stands (a disc marks it);
## the bolt leaps on to one more hero within 4 m - heroes who bunch up pay
## for it. When a hero closes in it backs off.

const KEEP_MIN := 6.0
const KEEP_MAX := 11.0
const CAST_RANGE := 16.0
const WINDUP_TIME := 0.6
const RECOVER_TIME := 0.9
const CAST_EVERY := 3.2
const FLEE_SPEED := 1.1
## The bolt: its disc, its fall, its leap.
const BOLT_RADIUS := 1.4
const BOLT_DELAY := 0.75
const BOLT_DAMAGE := 12.0
const LEAP_RANGE := 4.0
const LEAP_DAMAGE := 8.0

const RIG_PATH := "res://assets/models/chars/storm_acolyte.glb"

var _cast_left: float = 1.4
var _aim: Vector3 = Vector3.ZERO


func _init() -> void:
	xp_value = 28
	display_name = Texts.t("enemy.storm_acolyte")
	max_health = 54.0
	move_speed = 3.7
	body_color = Color(0.24, 0.23, 0.32)


func _build_body() -> void:
	if _setup_rigged_visual(RIG_PATH, "storm_acolyte", {
		"idle": &"idle", "run": &"glide", "run_speed": move_speed,
		"states": {AIState.WINDUP: &"charge", AIState.RECOVER: &"cast", AIState.STAGGER: &"stagger",
			AIState.CHASE: &"@loco", AIState.IDLE: &"@loco", AIState.RETREAT: &"@loco", AIState.DEAD: &"@dead"},
	}, ArtKit.color("palettes.storm_acolyte.glow")) != null:
		return
	var body := MeshInstance3D.new()  # fallback (and the dedicated server): a robed figure
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.5, 1.6, 0.4)
	mesh.material = flat_material(body_color)
	body.mesh = mesh
	body.position = Vector3(0, 0.8, 0)
	visual.add_child(body)


func nameplate_height() -> float:
	return 2.2


func _ai_process(delta: float) -> void:
	match ai_state:
		AIState.IDLE:
			brake(delta)
			if distance_to_player() < AGGRO_RANGE:
				_enter_state(AIState.CHASE)
		AIState.CHASE, AIState.RETREAT:
			face_player(delta, 8.0)
			var dist := distance_to_player()
			_cast_left -= delta
			if dist < KEEP_MIN:
				move_towards(-dir_to_player(), move_speed * FLEE_SPEED, delta)
			elif dist > KEEP_MAX:
				move_towards(dir_to_player(), move_speed, delta)
			else:
				brake(delta)
			if _cast_left <= 0.0 and dist <= CAST_RANGE and player != null and is_instance_valid(player):
				_cast_left = CAST_EVERY
				_aim = player.global_position
				lock_strike()
				_enter_state(AIState.WINDUP)
				play_fx(&"cast_tell")
		AIState.WINDUP:
			brake(delta)
			if _state_timer >= WINDUP_TIME:
				play_fx(&"cast")
				StormStrike.cast(self, _aim, BOLT_RADIUS, BOLT_DELAY, BOLT_DAMAGE, LEAP_RANGE, LEAP_DAMAGE, 1,
					get_instance_id())
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
		&"cast_tell":
			VFX.flash(get_tree().current_scene, present_origin() + Vector3(0, 1.7, 0),
				ArtKit.color("palettes.storm_acolyte.glow", Color(0.73, 0.66, 1.0)), 0.7, WINDUP_TIME)
			Sfx.play("caster_charge", global_position, -8.0, 0.1, 1.4)
		&"cast":
			Sfx.play("ball_lightning_zap", global_position, -6.0, 0.1, 1.2)
