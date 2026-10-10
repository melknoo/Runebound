class_name ChannelLurker
extends EnemyBase
## M13 the Drowned: an eel-thing from the cistern's drains. It waits under
## the floor (BURIED: no body, no hurtbox, a ripple at most), rises when a
## hero comes near, rears back while its maw fills with light and spits a
## bolt of cistern water at its prey - then it stays up, spent, for a breath
## (the moment to punish it) before it sinks and rises again a few metres
## away. It never walks; it only sinks and surfaces.

const WAKE_RANGE := 13.0
## ... or a hero fighting this close (its camp is under attack: a caster
## standing off still meets it).
const WAKE_FIGHT_RANGE := 24.0
const EMERGE_TIME := 0.6
const UP_TIME := 0.5         # risen, facing its prey before the spit
const WINDUP_TIME := 0.8
const RECOVER_TIME := 1.6    # spent: up and open
const SUBMERGE_TIME := 0.45
const UNDER_TIME := 1.2
const RELOCATE := 5.5        # how far from home it may surface
const BOLT_SPEED := 10.0
const BOLT_DAMAGE := 13.0
const MOUTH := Vector3(0, 1.7, -0.5)

const RIG_PATH := "res://assets/models/chars/channel_lurker.glb"

## Sinking (a CIRCLE state: it plays the submerge clip, then goes BURIED).
var _sinking: bool = false


func _init() -> void:
	xp_value = 28
	display_name = Texts.t("enemy.channel_lurker")
	max_health = 60.0
	move_speed = 0.0
	body_color = Color(0.22, 0.36, 0.38)
	immobile = true


func _ready() -> void:
	super()
	if not net_puppet:
		_enter_state(AIState.BURIED)
	_apply_presence(ai_state)


func _apply_presence(s: AIState) -> void:
	var under := s == AIState.BURIED or s == AIState.EMERGE
	set_targetable(not under)
	visual.visible = s != AIState.BURIED


func _build_body() -> void:
	if _setup_rigged_visual(RIG_PATH, "channel_lurker", {
		"idle": &"idle", "run": &"idle", "run_speed": 1.0,
		"states": {AIState.EMERGE: &"emerge", AIState.WINDUP: &"charge", AIState.RECOVER: &"spit",
			AIState.CIRCLE: &"submerge", AIState.STAGGER: &"stagger", AIState.IDLE: &"@loco",
			AIState.CHASE: &"@loco", AIState.DEAD: &"@dead"},
	}, ArtKit.color("palettes.channel_lurker.eyes")) != null:
		return
	var neck := MeshInstance3D.new()  # fallback: a rearing column
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.18
	mesh.bottom_radius = 0.3
	mesh.height = 1.8
	mesh.material = flat_material(body_color)
	neck.mesh = mesh
	neck.position = Vector3(0, 0.9, 0)
	visual.add_child(neck)


func _ai_process(delta: float) -> void:
	brake(delta)
	match ai_state:
		AIState.BURIED:
			if _state_timer < UNDER_TIME or player == null or not is_instance_valid(player):
				return
			var d := distance_to_player()
			if d <= WAKE_RANGE or (d <= WAKE_FIGHT_RANGE and player.in_combat()):
				_enter_state(AIState.EMERGE)
				_apply_presence(AIState.EMERGE)
				_present_emerge()
		AIState.EMERGE:
			face_player(delta, 8.0)
			if _state_timer >= EMERGE_TIME:
				_enter_state(AIState.CHASE)
				_apply_presence(AIState.CHASE)
		AIState.IDLE, AIState.CHASE:
			face_player(delta, 6.0)
			if _state_timer >= UP_TIME:
				_enter_state(AIState.WINDUP)
				_present_windup()
		AIState.WINDUP:
			face_player(delta, 3.0)
			if _state_timer >= WINDUP_TIME:
				_spit()
		AIState.RECOVER:
			if _state_timer >= RECOVER_TIME:
				_enter_state(AIState.CIRCLE)  # sinking
		AIState.CIRCLE:
			if _state_timer >= SUBMERGE_TIME:
				_relocate()
				_enter_state(AIState.BURIED)
				_apply_presence(AIState.BURIED)
		AIState.STAGGER:
			if _state_timer >= 0.0:
				_enter_state(AIState.CIRCLE)  # hurt, it dives


## It never walks (no leash walk home): sinking and surfacing near home is
## its whole way of moving.
func _should_return(_delta: float) -> bool:
	return false


## Under the floor it moves to another spot near home (unseen).
func _relocate() -> void:
	var anchor := home if home != Vector3.INF else global_position
	for attempt in 6:
		var a := randf() * TAU
		var p := anchor + Vector3(cos(a), 0.0, sin(a)) * randf_range(1.5, RELOCATE)
		var zone := ZoneBase.zone_of(self)
		if zone is DungeonZone and (not (zone as DungeonZone).layout.is_walkable(p.x, p.z)
				or (zone as DungeonZone).layout.in_channel(p.x, p.z)):
			continue  # never in a wall or out in the water, where no blade reaches it
		global_position = ZoneBase.ground_under(self, p, 0.05)
		return


func _spit() -> void:
	_enter_state(AIState.RECOVER)
	play_fx(&"spit")
	if player == null or not is_instance_valid(player):
		return
	var origin := global_position + _mouth_offset()
	var target := player.global_position + Vector3(0, 1.0, 0)
	var bolt := EnemyBolt.new()
	bolt.setup((target - origin).normalized(), BOLT_SPEED, BOLT_DAMAGE)
	bolt.shooter_id = get_instance_id()
	bolt.position = origin
	get_tree().current_scene.add_child(bolt)


func _mouth_offset() -> Vector3:
	var fwd := present_forward()
	return Vector3(0, MOUTH.y, 0) + fwd * -MOUTH.z


func _present_state(s: AIState) -> void:
	super(s)
	_apply_presence(s)
	match s:
		AIState.EMERGE:
			_present_emerge()
		AIState.WINDUP:
			_present_windup()


func _present_emerge() -> void:
	VFX.frost_burst(get_tree().current_scene, present_origin(), 1.4)
	Sfx.play("water_splash", global_position, -6.0, 0.1, 1.1)


func _present_windup() -> void:
	VFX.flash(get_tree().current_scene, present_origin() + _mouth_offset(), ArtKit.color("palettes.channel_lurker.eyes",
		Color(0.6, 1.0, 0.9)), 0.8, WINDUP_TIME)
	Sfx.play("caster_charge", global_position, -6.0, 0.1, 0.8)


func _present_fx(fx: StringName) -> void:
	if fx == &"spit":
		Sfx.play("bolt_fire", global_position, -4.0, 0.1, 0.7)
