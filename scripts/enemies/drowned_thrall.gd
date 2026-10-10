class_name DrownedThrall
extends EnemyBase
## M13 the Drowned (the Hollow Cistern): a keeper who never came back up,
## bloated with cistern water. Slow and heavy; it raises both arms and
## brings them down on a disc ahead. Dead, it bursts: the water it held
## spreads into a puddle that slows whoever wades in (DrownedPuddle).

const WINDUP_TIME := 0.75
const ATTACK_TIME := 0.15
const RECOVER_TIME := 0.9
const ATTACK_RANGE := 1.9
const ATTACK_DAMAGE := 15.0
const STRIKE_AHEAD := 1.1
const STRIKE_RADIUS := 1.45

const RIG_PATH := "res://assets/models/chars/drowned_thrall.glb"

var _disc: MeshInstance3D


func _init() -> void:
	xp_value = 26
	display_name = Texts.t("enemy.drowned_thrall")
	max_health = 85.0
	move_speed = 2.8
	body_color = Color(0.36, 0.44, 0.42)


func _build_body() -> void:
	if _setup_rigged_visual(RIG_PATH, "drowned_thrall", {
		"idle": &"idle", "run": &"run", "run_speed": move_speed,
		"states": {AIState.WINDUP: &"attack", AIState.STAGGER: &"stagger",
			AIState.CHASE: &"@loco", AIState.IDLE: &"@loco", AIState.DEAD: &"@dead"},
	}, ArtKit.color("palettes.drowned_thrall.eyes")) != null:
		return
	var torso := MeshInstance3D.new()  # fallback (and the dedicated server): a bloated barrel
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.38
	mesh.bottom_radius = 0.32
	mesh.height = 1.3
	mesh.material = flat_material(body_color)
	torso.mesh = mesh
	torso.position = Vector3(0, 0.85, 0)
	visual.add_child(torso)


func _ai_process(delta: float) -> void:
	match ai_state:
		AIState.IDLE:
			brake(delta)
			if distance_to_player() < AGGRO_RANGE:
				_enter_state(AIState.CHASE)
		AIState.CHASE:
			face_player(delta, 6.0)
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
						HitInfo.DamageType.PHYSICAL, HitInfo.Weight.MEDIUM, 4.0):
					VFX.melee_impact(get_tree().current_scene, victim.global_position + Vector3(0, 1.0, 0), _strike_forward)
				play_fx(&"slap")
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
	if s == AIState.WINDUP:
		_present_windup()


func _present_windup() -> void:
	_disc = VFX.telegraph_disc(get_tree().current_scene, present_origin() + present_forward() * STRIKE_AHEAD,
		STRIKE_RADIUS, WINDUP_TIME)
	Sfx.play("telegraph", global_position, -6.0, 0.1, 0.8)


func _present_fx(fx: StringName) -> void:
	if fx == &"slap":
		var at := present_origin() + present_forward() * STRIKE_AHEAD
		VFX.frost_burst(get_tree().current_scene, at, STRIKE_RADIUS * 0.8)
		Sfx.play("swing", at, -6.0, 0.15, 0.6)


func _on_interrupted() -> void:
	if _disc != null and is_instance_valid(_disc):
		_disc.queue_free()


## Dead, it bursts: a slowing puddle where it fell (the authority makes it;
## clients get a copy through HAZARD).
func _on_died() -> void:
	var at := global_position
	super()
	if net_puppet:
		return
	var puddle := DrownedPuddle.new()
	puddle.position = at
	get_tree().current_scene.add_child(puddle)
