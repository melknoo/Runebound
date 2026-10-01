class_name GraveShambler
extends EnemyBase
## M12 the Restless (Ashwick): a dead villager. It waits under the ground
## where it was buried (BURIED: no body, no hurtbox, not a target) until a
## hero comes near, then claws its way out - a ring on the ground fills, and
## whoever still stands in it when the earth breaks takes the burst. After
## that it shambles and rakes with both claws (a disc ahead, like the
## raiders' axe, a little slower).

const WINDUP_TIME := 0.6
const ATTACK_TIME := 0.15
const RECOVER_TIME := 0.75
const ATTACK_RANGE := 1.8
const ATTACK_DAMAGE := 13.0
const STRIKE_AHEAD := 1.0
const STRIKE_RADIUS := 1.3
const EMERGE_TIME := 1.0
const EMERGE_RANGE := 7.0
const EMERGE_RADIUS := 2.2
const EMERGE_DAMAGE := 10.0
## A buried one rises anyway this long after it was put in the ground.
const BURIED_MAX := 6.0

const RIG_PATH := "res://assets/models/chars/grave_shambler.glb"

var _burst_done: bool = false
var _disc: MeshInstance3D


func _init() -> void:
	xp_value = 22
	display_name = Texts.t("enemy.grave_shambler")
	max_health = 60.0
	move_speed = 3.6
	body_color = Color(0.4, 0.43, 0.36)


func _ready() -> void:
	super()
	if not net_puppet:
		_enter_state(AIState.BURIED)
	_apply_presence(ai_state)  # a puppet may arrive buried, too


## Under the ground: unseen and not a target (every machine, from the state).
func _apply_presence(s: AIState) -> void:
	var under := s == AIState.BURIED or s == AIState.EMERGE
	set_targetable(not under)
	visual.visible = s != AIState.BURIED


func _build_body() -> void:
	if _setup_rigged_visual(RIG_PATH, "grave_shambler", {
		"idle": &"idle", "run": &"run", "run_speed": move_speed,
		"states": {AIState.WINDUP: &"attack", AIState.STAGGER: &"stagger", AIState.EMERGE: &"emerge",
			AIState.CHASE: &"@loco", AIState.IDLE: &"@loco", AIState.DEAD: &"@dead"},
	}, ArtKit.color("palettes.grave_shambler.eyes")) != null:
		return
	var torso := MeshInstance3D.new()  # fallback (and the dedicated server): a hunched box
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.5, 1.2, 0.35)
	mesh.material = flat_material(body_color)
	torso.mesh = mesh
	torso.position = Vector3(0, 0.75, 0)
	visual.add_child(torso)


func _ai_process(delta: float) -> void:
	match ai_state:
		AIState.BURIED:
			brake(delta)
			var near := player != null and is_instance_valid(player) and distance_to_player() <= EMERGE_RANGE
			if near or _state_timer >= BURIED_MAX:
				_burst_done = false
				_enter_state(AIState.EMERGE)
				_apply_presence(AIState.EMERGE)
				_present_emerge()
		AIState.EMERGE:
			brake(delta)
			if not _burst_done and _state_timer >= EMERGE_TIME * 0.7:
				_burst_done = true
				for victim in strike_circle(global_position, EMERGE_RADIUS, EMERGE_DAMAGE,
						HitInfo.DamageType.PHYSICAL, HitInfo.Weight.MEDIUM, 3.0):
					VFX.melee_impact(get_tree().current_scene, victim.global_position + Vector3(0, 1.0, 0), Vector3.UP)
				play_fx(&"breach")
			if _state_timer >= EMERGE_TIME:
				_enter_state(AIState.CHASE)
				_apply_presence(AIState.CHASE)
		AIState.IDLE:
			brake(delta)
			if distance_to_player() < AGGRO_RANGE:
				_enter_state(AIState.CHASE)
		AIState.CHASE:
			face_player(delta)
			move_towards(dir_to_player(), move_speed, delta)
			if distance_to_player() <= ATTACK_RANGE:
				lock_strike()
				_enter_state(AIState.WINDUP)
				_present_windup()
		AIState.WINDUP:
			brake(delta)
			if _state_timer >= WINDUP_TIME:
				_enter_state(AIState.ATTACK)
				for victim in strike_circle(strike_point(STRIKE_AHEAD), STRIKE_RADIUS, ATTACK_DAMAGE,
						HitInfo.DamageType.PHYSICAL, HitInfo.Weight.MEDIUM, 3.5):
					VFX.melee_impact(get_tree().current_scene, victim.global_position + Vector3(0, 1.0, 0), _strike_forward)
				Sfx.play("swing", global_position, -6.0, 0.15, 0.7)
		AIState.ATTACK:
			brake(delta)
			if _state_timer >= ATTACK_TIME:
				_enter_state(AIState.RECOVER)
		AIState.RECOVER:
			brake(delta)
			if _state_timer >= RECOVER_TIME:
				_enter_state(AIState.CHASE)
		AIState.STAGGER:
			brake(delta)
			if _state_timer >= 0.0:
				_enter_state(AIState.CHASE)


func _present_state(s: AIState) -> void:
	super(s)
	_apply_presence(s)
	match s:
		AIState.EMERGE:
			_present_emerge()
		AIState.WINDUP:
			_present_windup()


func _present_emerge() -> void:
	var scene := get_tree().current_scene
	_disc = VFX.telegraph_disc(scene, present_origin(), EMERGE_RADIUS, EMERGE_TIME * 0.7)
	VFX.dodge_dust(scene, present_origin(), Vector3.UP)
	Sfx.play("telegraph", global_position, -4.0)


func _present_windup() -> void:
	_disc = VFX.telegraph_disc(get_tree().current_scene, present_origin() + present_forward() * STRIKE_AHEAD,
		STRIKE_RADIUS, WINDUP_TIME)
	Sfx.play("telegraph", global_position, -6.0)


func _present_fx(fx: StringName) -> void:
	if fx == &"breach":
		var scene := get_tree().current_scene
		VFX.earthbreaker_slam(scene, present_origin(), EMERGE_RADIUS)
		Sfx.play("earthbreaker_impact", global_position, -8.0, 0.1, 1.3)


func _on_interrupted() -> void:
	if _disc != null and is_instance_valid(_disc):
		_disc.queue_free()
