class_name SmoulderWisp
extends EnemyBase
## M12 burnt forest: an ember spirit floating in the smoke. It keeps away and
## spits embers (a slow, readable bolt). Corner it and it blinks: a puff of
## smoke (the tell), gone, and it rises again a few metres off - the heroes
## have to keep up with it, or a tank pulls it in.

const PREFERRED_MIN := 6.0
const PREFERRED_MAX := 11.0
const WINDUP_TIME := 0.8
const RECOVER_TIME := 1.2
const BOLT_SPEED := 10.0
const BOLT_DAMAGE := 10.0
const BLINK_TIME := 0.45
const BLINK_COOLDOWN := 6.0
const BLINK_TRIGGER := 4.0
const BLINK_MIN := 6.0
const BLINK_MAX := 9.0

const RIG_PATH := "res://assets/models/chars/smoulder_wisp.glb"

var _blink_ready_at: float = 0.0
var _blink_to: Vector3 = Vector3.INF


func _init() -> void:
	xp_value = 22
	display_name = Texts.t("enemy.smoulder_wisp")
	max_health = 34.0
	move_speed = 3.4
	body_color = Color(0.85, 0.42, 0.18)


func _build_body() -> void:
	if _setup_rigged_visual(RIG_PATH, "smoulder_wisp", {
		"idle": &"idle", "run": &"glide", "run_speed": move_speed,
		"states": {AIState.WINDUP: &"charge", AIState.RECOVER: &"cast", AIState.STAGGER: &"stagger",
			AIState.CHASE: &"@loco", AIState.IDLE: &"@loco", AIState.DEAD: &"@dead"},
	}, ArtKit.color("palettes.smoulder_wisp.eyes")) != null:
		return
	var core := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.3
	mesh.height = 0.6
	mesh.material = flat_material(body_color, true, 1.5)
	core.mesh = mesh
	core.position = Vector3(0, 1.0, 0)
	visual.add_child(core)


func _ai_process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	match ai_state:
		AIState.IDLE:
			brake(delta)
			if distance_to_player() < AGGRO_RANGE:
				_enter_state(AIState.CHASE)
		AIState.CHASE:
			face_player(delta)
			var dist := distance_to_player()
			if dist < BLINK_TRIGGER and now >= _blink_ready_at:
				_start_blink()
				return
			if dist < PREFERRED_MIN:
				move_towards(-dir_to_player(), move_speed, delta)
			elif dist > PREFERRED_MAX:
				move_towards(dir_to_player(), move_speed, delta)
			else:
				brake(delta)
				if _state_timer > 0.4:
					_enter_state(AIState.WINDUP)
					_present_windup()
		AIState.WINDUP:
			face_player(delta, 3.0)
			brake(delta)
			if _state_timer >= WINDUP_TIME:
				_enter_state(AIState.RECOVER)
				_spit()
		AIState.RECOVER:
			brake(delta)
			if _state_timer >= RECOVER_TIME:
				_enter_state(AIState.CHASE)
		AIState.BLINK:
			brake(delta)
			if _state_timer >= BLINK_TIME and _blink_to != Vector3.INF:
				global_position = _blink_to
				_blink_to = Vector3.INF
				play_fx(&"blink_in")
				_enter_state(AIState.CHASE)
		AIState.STAGGER:
			brake(delta)
			if _state_timer >= 0.0:
				_enter_state(AIState.CHASE)


## Away from the hero, somewhere on the ground BLINK_MIN..MAX off, in the
## open: never through a wall or a trunk (a free line from here), so the
## heroes can always see and reach it. No free spot: it stays.
func _start_blink() -> void:
	_blink_ready_at = Time.get_ticks_msec() / 1000.0 + BLINK_COOLDOWN
	var away := -dir_to_player()
	var space := get_world_3d().direct_space_state
	for attempt in 6:
		var dir := away.rotated(Vector3.UP, randf_range(-1.2, 1.2))
		var to := ZoneBase.ground_under(self, global_position + dir * randf_range(BLINK_MIN, BLINK_MAX), 0.1)
		if absf(to.y - global_position.y) > 2.5:
			continue  # not off a ledge or up a cliff
		var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.0, 0), to + Vector3(0, 1.0, 0),
			0b1 | Grove.FOLIAGE_LAYER)
		if not space.intersect_ray(ray).is_empty():
			continue
		_blink_to = to
		_enter_state(AIState.BLINK)
		play_fx(&"blink_out")
		return


func _spit() -> void:
	play_fx(&"spit")
	if player == null or not is_instance_valid(player):
		return
	var origin := global_position + Vector3(0, 1.2, 0) + present_forward() * 0.4
	var target := player.global_position + Vector3(0, 1.0, 0)
	var bolt := EnemyBolt.new()
	bolt.setup((target - origin).normalized(), BOLT_SPEED, BOLT_DAMAGE)
	bolt.shooter_id = get_instance_id()
	bolt.position = origin
	get_tree().current_scene.add_child(bolt)


func _present_state(s: AIState) -> void:
	super(s)
	if s == AIState.WINDUP:
		_present_windup()


func _present_windup() -> void:
	Sfx.play("ember_cast", global_position, -6.0, 0.1, 1.3)


func _present_fx(fx: StringName) -> void:
	var scene := get_tree().current_scene
	var smoke := {"tex": "ember", "amount": 16, "size": 0.14, "vel_min": 1.0, "vel_max": 2.5, "gravity": Vector3(0, 1.5, 0),
		"colors": [Color(1.0, 0.6, 0.25), Color(0.25, 0.22, 0.22, 0.0)] as Array[Color], "emission_radius": 0.5}
	match fx:
		&"blink_out":
			VFX.burst(scene, present_origin() + Vector3(0, 1.0, 0), smoke)
			visual.visible = false
			Sfx.play("storm_step", global_position, -10.0, 0.1, 0.7)
		&"blink_in":
			visual.visible = true
			VFX.burst(scene, global_position + Vector3(0, 1.0, 0), smoke)
		&"spit":
			VFX.flash(scene, global_position + Vector3(0, 1.2, 0), Color(1.0, 0.6, 0.25), 0.8, 0.12)
			Sfx.play("ember_fire", global_position, -8.0, 0.1, 1.2)
