class_name RisenReeve
extends DungeonBoss
## M14a the prologue's boss: the Reeve of Ashwick, who kept the village's
## ledger and its toll gate (lore: "the coffins come first and the debts
## after"), risen with the rest of the dead and still holding the gate: nobody
## leaves without paying. The Restless's rig, half again as big, a gold glow
## in the eyes. Three things to read, each fully telegraphed:
##  * the mace: a slam ahead (the base boss's disc),
##  * the toll: every few seconds a ring fills around him, step out of it,
##  * at half his health he calls two of the buried villagers out of the
##    ground beside him (they claw their way up).
## Level 1, made for a hero at level 1-2 with a few draughts.

const TOLL_EVERY := 12.0
const TOLL_WINDUP := 1.4
const TOLL_RADIUS := 4.6
const TOLL_DAMAGE := 12.0
const MACE_DAMAGE := 14.0
const RAISE_AT: Array[float] = [0.5]
const SCALE := 1.55

const RIG_PATH := "res://assets/models/chars/grave_shambler.glb"

var _toll_left: float = TOLL_EVERY * 0.6
var _raised: int = 0
var _toll_disc: MeshInstance3D


func _init() -> void:
	super()
	xp_value = 80
	display_name = "The Risen Reeve"
	max_health = 520.0
	move_speed = 2.4
	body_color = Color(0.36, 0.34, 0.3)
	gold_piles = 3


func _build_body() -> void:
	if _setup_rigged_visual(RIG_PATH, "grave_shambler", {
		"idle": &"idle", "run": &"run", "run_speed": move_speed,
		"states": {AIState.WINDUP: &"attack", AIState.CIRCLE: &"emerge", AIState.STAGGER: &"stagger",
			AIState.CHASE: &"@loco", AIState.IDLE: &"@loco", AIState.DEAD: &"@dead"},
	}, Color("#E8B44A")) != null:
		visual.scale = Vector3.ONE * SCALE
		base_visual_scale = visual.scale
		return
	super()


func _physics_process(delta: float) -> void:
	super(delta)
	if net_puppet or ai_state == AIState.DEAD:
		return
	if _raised < RAISE_AT.size() and health.current_health <= health.max_health * RAISE_AT[_raised]:
		_raised += 1
		_raise_dead()


func _ai_process(delta: float) -> void:
	_toll_left -= delta
	match ai_state:
		AIState.IDLE:
			brake(delta)
			if player != null and distance_to_player() < AGGRO_RANGE * 2.0:
				_enter_state(AIState.CHASE)
		AIState.CHASE:
			face_player(delta, 3.5)
			move_towards(dir_to_player(), move_speed, delta)
			if _toll_left <= 0.0 and player != null and distance_to_player() < TOLL_RADIUS + 3.0:
				_toll_left = TOLL_EVERY
				_enter_state(AIState.CIRCLE)  # the toll's windup
				_present_toll()
			elif distance_to_player() <= ATTACK_RANGE:
				lock_strike()
				_enter_state(AIState.WINDUP)
				_present_windup()
		AIState.CIRCLE:
			brake(delta)
			if _state_timer >= TOLL_WINDUP:
				play_fx(&"toll")
				strike_circle(global_position, TOLL_RADIUS, TOLL_DAMAGE, HitInfo.DamageType.PHYSICAL,
					HitInfo.Weight.HEAVY, 7.0)
				_enter_state(AIState.RECOVER)
		AIState.WINDUP:
			brake(delta)
			if _state_timer >= WINDUP_TIME:
				_enter_state(AIState.RECOVER)
				play_fx(&"slam")
				strike_circle(strike_point(SLAM_AHEAD), SLAM_RADIUS, MACE_DAMAGE, HitInfo.DamageType.PHYSICAL,
					HitInfo.Weight.HEAVY, 8.0)
		AIState.RECOVER:
			brake(delta)
			if _state_timer >= RECOVER_TIME:
				_enter_state(AIState.CHASE)
		AIState.STAGGER:
			brake(delta)
			if _state_timer >= 0.0:
				_enter_state(AIState.CHASE)


## Two buried villagers beside him (GraveShambler starts buried and claws up).
func _raise_dead() -> void:
	var zone := ZoneBase.zone_of(self)
	if zone == null:
		return
	play_fx(&"raise")
	var side := global_transform.basis.x
	for s in [-1.0, 1.0]:
		var at := zone.ground_point(global_position + side * (3.2 * s) + Vector3(0, 1.0, 0), 0.2)
		zone.spawn_by_id("grave_shambler", at)


func _present_state(s: AIState) -> void:
	super(s)
	if s == AIState.CIRCLE:
		_present_toll()


func _present_toll() -> void:
	_toll_disc = VFX.telegraph_disc(get_tree().current_scene, present_origin(), TOLL_RADIUS, TOLL_WINDUP)
	Sfx.play("telegraph", global_position, -3.0, 0.1, 0.8)


func _present_fx(fx: StringName) -> void:
	var scene := get_tree().current_scene
	match fx:
		&"slam":
			var at := present_origin() + present_forward() * SLAM_AHEAD
			VFX.earthbreaker_slam(scene, at, SLAM_RADIUS)
			Sfx.play("earthbreaker_impact", at, -3.0, 0.1, 0.8)
			GameFeel.camera_shake(0.25)
		&"toll":
			VFX.ground_ring(scene, present_origin(), Color("#E8B44A"), TOLL_RADIUS, 0.4)
			VFX.earthbreaker_slam(scene, present_origin(), TOLL_RADIUS * 0.6)
			Sfx.play("rune_challenge", global_position, -2.0, 0.1, 0.7)
			GameFeel.camera_shake(0.3)
		&"raise":
			Sfx.play("boss_roar", global_position, -3.0, 0.1, 1.1)
			VFX.flash(scene, present_origin() + Vector3(0, 2.4, 0), Color("#E8B44A"), 1.4, 0.3)


func _on_interrupted() -> void:
	super()
	if _toll_disc != null and is_instance_valid(_toll_disc):
		_toll_disc.queue_free()
