class_name Cinderbark
extends EnemyBase
## M12 burnt forest: a charred tree that walks. It stands among the dead
## trunks as one of them (DORMANT: branch arms up, head bowed, a dim ember
## glow in its cracks the only tell) - solid like a trunk, but not a target.
## A hero who comes close, or a fight near it, wakes it (WAKE: it shakes
## itself free); then it is
## a slow, stagger-resistant brute: a telegraphed two-arm slam that leaves
## its burning bark on the ground (a FirePatch).

const WINDUP_TIME := 1.0
const RECOVER_TIME := 1.3
const WAKE_TIME := 0.9
const WAKE_RANGE := 6.0
## ... or a fight this close (its camp is under attack: it joins in).
const WAKE_FIGHT_RANGE := 16.0
const ATTACK_RANGE := 2.6
const SLAM_AHEAD := 1.4
const SLAM_RADIUS := 2.6
const SLAM_DAMAGE := 24.0

const RIG_PATH := "res://assets/models/chars/cinderbark.glb"
## While it stands as a tree: a trunk's body (foliage, like the forest's).
const TREE_LAYER := 0b1000000

var _disc: MeshInstance3D


func _init() -> void:
	xp_value = 50
	display_name = Texts.t("enemy.cinderbark")
	max_health = 170.0
	move_speed = 2.0
	stagger_resist = true
	loot_kind = &"brute"
	body_color = Color(0.36, 0.33, 0.3)


func _ready() -> void:
	super()
	if not net_puppet:
		_enter_state(AIState.DORMANT)
	_apply_presence(ai_state)


func _apply_presence(s: AIState) -> void:
	var tree := s == AIState.DORMANT or s == AIState.WAKE
	set_targetable(not tree)
	if tree and s == AIState.DORMANT:
		collision_layer = TREE_LAYER  # heroes bump into it like into a trunk


func _build_body() -> void:
	if _setup_rigged_visual(RIG_PATH, "cinderbark", {
		"idle": &"idle", "run": &"run", "run_speed": move_speed,
		"states": {AIState.WINDUP: &"slam", AIState.STAGGER: &"stagger", AIState.DORMANT: &"~dormant",
			AIState.WAKE: &"wake", AIState.CHASE: &"@loco", AIState.IDLE: &"@loco", AIState.DEAD: &"@dead"},
	}, ArtKit.color("palettes.cinderbark.eyes")) != null:
		return
	var trunk := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.3
	mesh.bottom_radius = 0.42
	mesh.height = 2.0
	mesh.material = flat_material(body_color)
	trunk.mesh = mesh
	trunk.position = Vector3(0, 1.0, 0)
	visual.add_child(trunk)


func nameplate_height() -> float:
	return 2.6


func _ai_process(delta: float) -> void:
	match ai_state:
		AIState.DORMANT:
			brake(delta)
			if player != null and is_instance_valid(player):
				var d := distance_to_player()
				if d <= WAKE_RANGE or (d <= WAKE_FIGHT_RANGE and player.in_combat()):
					wake()
		AIState.WAKE:
			face_player(delta, 2.0)
			brake(delta)
			if _state_timer >= WAKE_TIME:
				_enter_state(AIState.CHASE)
				_apply_presence(AIState.CHASE)
		AIState.IDLE:
			brake(delta)
			if distance_to_player() < AGGRO_RANGE:
				_enter_state(AIState.CHASE)
		AIState.CHASE:
			face_player(delta, 4.0)
			move_towards(dir_to_player(), move_speed, delta)
			if distance_to_player() <= ATTACK_RANGE:
				lock_strike()
				_enter_state(AIState.WINDUP)
				_present_windup()
		AIState.WINDUP:
			brake(delta)
			if _state_timer >= WINDUP_TIME:
				_enter_state(AIState.RECOVER)
				_slam()
		AIState.RECOVER:
			brake(delta)
			if _state_timer >= RECOVER_TIME:
				_enter_state(AIState.CHASE)
		AIState.STAGGER:
			brake(delta)
			if _state_timer >= 0.0:
				_enter_state(AIState.CHASE)


## Wakes it now (a hero came close; tests and scripted fights call it too).
func wake() -> void:
	if ai_state != AIState.DORMANT:
		return
	_enter_state(AIState.WAKE)
	_apply_presence(AIState.WAKE)
	play_fx(&"wake")


func _slam() -> void:
	var at := strike_point(SLAM_AHEAD)
	strike_circle(at, SLAM_RADIUS, SLAM_DAMAGE, HitInfo.DamageType.FIRE, HitInfo.Weight.HEAVY, 6.0)
	play_fx(&"slam")
	var patch := FirePatch.new()  # its burning bark stays on the ground
	patch.position = ZoneBase.ground_under(self, at, 0.02)
	get_tree().current_scene.add_child(patch)


func _present_state(s: AIState) -> void:
	super(s)
	_apply_presence(s)
	if s == AIState.WINDUP:
		_present_windup()


func _present_windup() -> void:
	_disc = VFX.telegraph_disc(get_tree().current_scene, present_origin() + present_forward() * SLAM_AHEAD,
		SLAM_RADIUS, WINDUP_TIME)
	Sfx.play("earthbreaker_windup", global_position, -6.0, 0.1, 0.8)


func _present_fx(fx: StringName) -> void:
	var scene := get_tree().current_scene
	match fx:
		&"wake":
			VFX.burst(scene, present_origin() + Vector3(0, 1.4, 0), {"tex": "ember", "amount": 18, "size": 0.12,
				"colors": [Color(1.0, 0.75, 0.35), Color(1.0, 0.4, 0.12, 0.0)] as Array[Color], "emission_radius": 0.6})
			Sfx.play("boss_roar", global_position, -14.0, 0.1, 1.4)
		&"slam":
			VFX.earthbreaker_slam(scene, present_origin() + present_forward() * SLAM_AHEAD, SLAM_RADIUS)
			Sfx.play("earthbreaker_impact", global_position, -4.0, 0.1, 0.8)


func _on_interrupted() -> void:
	if _disc != null and is_instance_valid(_disc):
		_disc.queue_free()
