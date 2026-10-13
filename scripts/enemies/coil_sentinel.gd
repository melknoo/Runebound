class_name CoilSentinel
extends EnemyBase
## M13b the storm family (the Stormwatch): a slate-and-copper construct the
## Circle built to guard its halls, a charge coil on its back. It punches
## what stands in front of it; every few seconds it stops and charges (its
## coil brightens, a ring grows on the floor) and then discharges a ring
## around itself. A sentinel held by a taunt discharges into its taunter
## alone - the tank's work.

const ATTACK_RANGE := 2.4
const PUNCH_AHEAD := 1.4
const PUNCH_RADIUS := 1.6
const PUNCH_DAMAGE := 14.0
const PUNCH_WINDUP := 0.7
const PUNCH_RECOVER := 1.0
const CHARGE_EVERY := 9.0
const CHARGE_TIME := 2.4
const RING_RADIUS := 5.0
const RING_DAMAGE := 18.0
const TAUNT_BOLT_DAMAGE := 22.0

const RIG_PATH := "res://assets/models/chars/coil_sentinel.glb"

var _charge_left: float = CHARGE_EVERY * 0.6
## Tests: the last discharge ("ring" or "bolt") and whom a bolt went to.
var last_discharge: String = ""
var last_bolt_to: Player = null


func _init() -> void:
	xp_value = 48
	display_name = Texts.t("enemy.coil_sentinel")
	max_health = 170.0
	move_speed = 2.2
	body_color = Color(0.3, 0.33, 0.38)
	stagger_resist = true


func _build_body() -> void:
	if _setup_rigged_visual(RIG_PATH, "coil_sentinel", {
		"idle": &"idle", "run": &"run", "run_speed": move_speed,
		"states": {AIState.WINDUP: &"punch", AIState.CIRCLE: &"charge", AIState.STAGGER: &"stagger",
			AIState.CHASE: &"@loco", AIState.IDLE: &"@loco", AIState.DEAD: &"@dead"},
	}, ArtKit.color("palettes.coil_sentinel.glow")) != null:
		return
	var body := MeshInstance3D.new()  # fallback (and the dedicated server): a slab of a construct
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.1, 1.9, 0.8)
	mesh.material = flat_material(body_color)
	body.mesh = mesh
	body.position = Vector3(0, 0.95, 0)
	visual.add_child(body)


func nameplate_height() -> float:
	return 2.7


func _ai_process(delta: float) -> void:
	_charge_left -= delta  # counts in every state: a punch cycle never starves the charge
	match ai_state:
		AIState.IDLE:
			brake(delta)
			if distance_to_player() < AGGRO_RANGE:
				_enter_state(AIState.CHASE)
		AIState.CHASE:
			face_player(delta, 5.0)
			if _charge_left <= 0.0:
				start_charge()
			elif distance_to_player() <= ATTACK_RANGE:
				lock_strike()
				_enter_state(AIState.WINDUP)
				play_fx(&"punch_tell")
			else:
				move_towards(dir_to_player(), move_speed, delta)
		AIState.WINDUP:
			brake(delta)
			if _state_timer >= PUNCH_WINDUP:
				play_fx(&"punch")
				strike_circle(strike_point(PUNCH_AHEAD), PUNCH_RADIUS, PUNCH_DAMAGE, HitInfo.DamageType.PHYSICAL,
					HitInfo.Weight.HEAVY, 6.0)
				_enter_state(AIState.RECOVER)
		AIState.CIRCLE:  # charging
			brake(delta)
			if _state_timer >= CHARGE_TIME:
				_discharge()
				_enter_state(AIState.RECOVER)
		AIState.RECOVER:
			brake(delta)
			if _state_timer >= PUNCH_RECOVER:
				_enter_state(AIState.CHASE)
		AIState.STAGGER:
			brake(delta)
			if _state_timer >= 0.0:
				_enter_state(AIState.CHASE)


## Starts a charge now (the AI does it every CHARGE_EVERY; shots and tests too).
func start_charge() -> void:
	_charge_left = CHARGE_EVERY
	lock_strike()
	_enter_state(AIState.CIRCLE)
	play_fx(&"charge")


## Authority: a taunt holds it - one bolt into the taunter; else the ring.
func _discharge() -> void:
	var taunter := taunted_by()
	if taunter != null:
		last_discharge = "bolt"
		last_bolt_to = taunter
		play_fx(&"discharge_bolt")
		StormStrike.cast(self, taunter.global_position, 1.0, 0.0, TAUNT_BOLT_DAMAGE, 0.0, 0.0, 0, get_instance_id())
		return
	last_discharge = "ring"
	play_fx(&"discharge")
	strike_circle(_strike_origin, RING_RADIUS, RING_DAMAGE, HitInfo.DamageType.LIGHTNING, HitInfo.Weight.HEAVY, 7.0)


func _present_fx(fx: StringName) -> void:
	var scene := get_tree().current_scene
	var glow := ArtKit.color("palettes.coil_sentinel.glow", Color(0.73, 0.66, 1.0))
	match fx:
		&"punch_tell":
			VFX.telegraph_disc(scene, present_origin() + present_forward() * PUNCH_AHEAD, PUNCH_RADIUS, PUNCH_WINDUP)
		&"punch":
			Sfx.play("block_clang", global_position, -4.0, 0.1, 0.6)
		&"charge":
			VFX.telegraph_disc(scene, present_origin(), RING_RADIUS, CHARGE_TIME)
			VFX.flash(scene, present_origin() + Vector3(0, 2.2, 0) - present_forward() * 0.45, glow, 1.0, CHARGE_TIME)  # the coil on its back
			Sfx.play("coil_charge", global_position, -4.0, 0.05)
		&"discharge":
			VFX.ground_ring(scene, present_origin(), glow, RING_RADIUS, 0.35)
			VFX.flash(scene, present_origin() + Vector3(0, 1.2, 0), Color(0.92, 0.88, 1.0), 2.4, 0.15)
			Sfx.play("coil_discharge", global_position, -1.0, 0.08)
			GameFeel.camera_shake(0.2)
		&"discharge_bolt":
			Sfx.play("coil_discharge", global_position, -3.0, 0.08, 1.2)
