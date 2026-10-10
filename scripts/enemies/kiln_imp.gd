class_name KilnImp
extends EnemyBase
## M13 the Ember Brood (the Ember Warrens): a small, quick thing with a
## furnace for a belly. It keeps its distance and lobs glowing lumps of slag
## where its prey stands (a disc marks the spot; the lump leaves burning
## ground), skitters away when a hero gets close, and when it dies its belly
## cracks: a ring fills around the body, then it bursts (ImpBurst).

const KEEP_MIN := 4.5
const KEEP_MAX := 9.0
const THROW_RANGE := 12.0
const WINDUP_TIME := 0.7
const RECOVER_TIME := 1.1
const THROW_EVERY := 2.6
const FLEE_SPEED := 1.15     # x move_speed while it backs off

const RIG_PATH := "res://assets/models/chars/kiln_imp.glb"

var _throw_left: float = 1.2
var _aim: Vector3 = Vector3.ZERO


func _init() -> void:
	xp_value = 24
	display_name = Texts.t("enemy.kiln_imp")
	max_health = 42.0
	move_speed = 4.4
	body_color = Color(0.3, 0.18, 0.12)


func _build_body() -> void:
	if _setup_rigged_visual(RIG_PATH, "kiln_imp", {
		"idle": &"idle", "run": &"run", "run_speed": move_speed,
		"states": {AIState.WINDUP: &"throw", AIState.STAGGER: &"stagger",
			AIState.CHASE: &"@loco", AIState.IDLE: &"@loco", AIState.RETREAT: &"@loco", AIState.DEAD: &"@dead"},
	}, ArtKit.color("palettes.kiln_imp.glow")) != null:
		return
	var body := MeshInstance3D.new()  # fallback (and the dedicated server): a squat glowing pot
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.5, 0.6, 0.45)
	mesh.material = flat_material(body_color)
	body.mesh = mesh
	body.position = Vector3(0, 0.4, 0)
	visual.add_child(body)


func nameplate_height() -> float:
	return 1.5


func _ai_process(delta: float) -> void:
	match ai_state:
		AIState.IDLE:
			brake(delta)
			if distance_to_player() < AGGRO_RANGE:
				_enter_state(AIState.CHASE)
		AIState.CHASE, AIState.RETREAT:
			face_player(delta, 8.0)
			var dist := distance_to_player()
			_throw_left -= delta
			if dist < KEEP_MIN:
				move_towards(-dir_to_player(), move_speed * FLEE_SPEED, delta)
			elif dist > KEEP_MAX:
				move_towards(dir_to_player(), move_speed, delta)
			else:
				brake(delta)
			if _throw_left <= 0.0 and dist <= THROW_RANGE and player != null and is_instance_valid(player):
				_throw_left = THROW_EVERY
				_aim = player.global_position
				lock_strike()
				_enter_state(AIState.WINDUP)
				play_fx(&"throw_tell")
		AIState.WINDUP:
			brake(delta)
			if _state_timer >= WINDUP_TIME:
				_throw()
				_enter_state(AIState.RECOVER)
		AIState.RECOVER:
			brake(delta)
			if _state_timer >= RECOVER_TIME:
				_enter_state(AIState.CHASE)
		AIState.STAGGER:
			brake(delta)
			if _state_timer >= 0.0:
				_enter_state(AIState.CHASE)


## Authority: a lump to where its prey stood when it wound up.
func _throw() -> void:
	play_fx(&"throw")
	var lump := EmberLump.new()
	lump.from = global_position + Vector3(0, 1.0, 0) + present_forward() * 0.3
	lump.target = _aim
	get_tree().current_scene.add_child(lump)


## Dead, its belly furnace bursts a moment later (the authority makes it;
## clients get a copy through HAZARD).
func _on_died() -> void:
	var at := global_position
	super()
	if net_puppet:
		return
	var burst := ImpBurst.new()
	burst.position = at
	get_tree().current_scene.add_child(burst)


func _present_fx(fx: StringName) -> void:
	match fx:
		&"throw_tell":
			VFX.flash(get_tree().current_scene, present_origin() + Vector3(0, 0.9, 0),
				ArtKit.color("palettes.kiln_imp.glow", Color(1.0, 0.6, 0.2)), 0.6, WINDUP_TIME)
			Sfx.play("imp_cackle", global_position, -6.0, 0.15, 1.0)
		&"throw":
			Sfx.play("ember_cast", global_position, -6.0, 0.1, 1.2)
