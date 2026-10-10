class_name CinderBeetle
extends EnemyBase
## M13 the Ember Brood (the Ember Warrens): a beetle the size of a dog with
## a slag-plated head. It waits dug into the floor (BURIED: no body, no
## hurtbox) until a hero comes near or fights close by, then tunnels under
## its prey - a trail of dust - and breaks out beneath it: a ring fills, and
## whoever still stands in it when the floor bursts is struck. Up, it bites;
## its head plate turns most of a blow struck from the front (hit it from
## the side or behind). After a while up, or when its prey runs off, it
## digs in again and comes up under it once more.

const WAKE_RANGE := 9.0
const WAKE_FIGHT_RANGE := 20.0
const TUNNEL_SPEED := 7.0
const TUNNEL_MAX := 3.0      # it breaks out this long after digging in, near or not
const TUNNEL_REACH := 1.2    # ... or as soon as it is this close under its prey
const EMERGE_TIME := 0.9
const EMERGE_RADIUS := 1.8
const EMERGE_DAMAGE := 14.0
const BURROW_TIME := 0.6
const UP_TIME := 7.0
const FAR_BURROW := 9.0      # its prey this far away: it digs in after it
const WINDUP_TIME := 0.55
const ATTACK_TIME := 0.15
const RECOVER_TIME := 0.8
const ATTACK_RANGE := 1.7
const ATTACK_DAMAGE := 13.0
const STRIKE_AHEAD := 1.0
const STRIKE_RADIUS := 1.2
## A blow from within this cone in front lands on the head plate.
const FRONT_DOT := 0.4
const FRONT_ARMOR := 0.35
const DIG_FX_EVERY := 0.45

const RIG_PATH := "res://assets/models/chars/cinder_beetle.glb"

## Woken (it hunts from under the floor); a fresh camp beetle sleeps dug in.
var awake: bool = false
var _burst_done: bool = false
var _up_left: float = UP_TIME
var _dig_fx_left: float = 0.0
var _disc: MeshInstance3D


func _init() -> void:
	xp_value = 28
	display_name = Texts.t("enemy.cinder_beetle")
	max_health = 70.0
	move_speed = 3.4
	body_color = Color(0.22, 0.17, 0.14)


func _ready() -> void:
	super()
	if not net_puppet:
		_enter_state(AIState.BURIED)
	_apply_presence(ai_state)


## Under the floor: unseen and not a target (every machine, from the state).
func _apply_presence(s: AIState) -> void:
	var under := s == AIState.BURIED or s == AIState.EMERGE
	set_targetable(not under)
	visual.visible = s != AIState.BURIED


func _build_body() -> void:
	if _setup_rigged_visual(RIG_PATH, "cinder_beetle", {
		"idle": &"idle", "run": &"run", "run_speed": move_speed,
		"states": {AIState.WINDUP: &"bite", AIState.STAGGER: &"stagger", AIState.EMERGE: &"emerge",
			AIState.BLINK: &"burrow", AIState.CHASE: &"@loco", AIState.IDLE: &"@loco", AIState.DEAD: &"@dead"},
	}, ArtKit.color("palettes.cinder_beetle.glow")) != null:
		return
	var shell := MeshInstance3D.new()  # fallback (and the dedicated server): a low domed shell
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.8, 0.45, 1.1)
	mesh.material = flat_material(body_color)
	shell.mesh = mesh
	shell.position = Vector3(0, 0.35, 0)
	visual.add_child(shell)


## Never walks home: it digs and tunnels.
func _should_return(_delta: float) -> bool:
	return false


func _ai_process(delta: float) -> void:
	match ai_state:
		AIState.BURIED:
			if not awake:
				brake(delta)
				if player != null and is_instance_valid(player):
					var d := distance_to_player()
					if d <= WAKE_RANGE or (d <= WAKE_FIGHT_RANGE and player.in_combat()):
						wake()
				return
			_tunnel(delta)
		AIState.EMERGE:
			brake(delta)
			if not _burst_done and _state_timer >= EMERGE_TIME * 0.75:
				_burst_done = true
				for victim in strike_circle(global_position, EMERGE_RADIUS, EMERGE_DAMAGE,
						HitInfo.DamageType.PHYSICAL, HitInfo.Weight.MEDIUM, 4.0):
					VFX.melee_impact(get_tree().current_scene, victim.global_position + Vector3(0, 1.0, 0), Vector3.UP)
				play_fx(&"breach")
			if _state_timer >= EMERGE_TIME:
				_up_left = UP_TIME
				_enter_state(AIState.CHASE)
				_apply_presence(AIState.CHASE)
		AIState.IDLE, AIState.CHASE:
			face_player(delta, 7.0)
			move_towards(dir_to_player(), move_speed, delta)
			_up_left -= delta
			var dist := distance_to_player()
			if _up_left <= 0.0 or (dist > FAR_BURROW and dist < INF):
				_enter_state(AIState.BLINK)  # digging in
				play_fx(&"dig")
			elif dist <= ATTACK_RANGE:
				lock_strike()
				_enter_state(AIState.WINDUP)
				_present_windup()
		AIState.WINDUP:
			brake(delta)
			if _state_timer >= WINDUP_TIME:
				_enter_state(AIState.ATTACK)
				for victim in strike_circle(strike_point(STRIKE_AHEAD), STRIKE_RADIUS, ATTACK_DAMAGE,
						HitInfo.DamageType.PHYSICAL, HitInfo.Weight.MEDIUM, 3.0):
					VFX.melee_impact(get_tree().current_scene, victim.global_position + Vector3(0, 1.0, 0), _strike_forward)
				play_fx(&"bite")
		AIState.ATTACK:
			brake(delta)
			if _state_timer >= ATTACK_TIME:
				_enter_state(AIState.RECOVER)
		AIState.RECOVER:
			brake(delta)
			if _state_timer >= RECOVER_TIME:
				_enter_state(AIState.CHASE)
		AIState.BLINK:
			brake(delta)
			if _state_timer >= BURROW_TIME:
				_enter_state(AIState.BURIED)
				_apply_presence(AIState.BURIED)
		AIState.STAGGER:
			brake(delta)
			if _state_timer >= 0.0:
				_enter_state(AIState.CHASE)


## Wakes it: it digs towards its prey at once (camps, the Broodmother's brood).
func wake() -> void:
	awake = true
	if ai_state == AIState.BURIED:
		_state_timer = 0.0


## Under the floor towards its prey; out beneath it (or wherever it got to).
func _tunnel(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		brake(delta)
		return
	var flat := player.global_position - global_position
	flat.y = 0.0
	if flat.length() > TUNNEL_REACH:
		move_towards(flat.normalized(), TUNNEL_SPEED, delta)
	else:
		brake(delta)
	_dig_fx_left -= delta
	if _dig_fx_left <= 0.0:
		_dig_fx_left = DIG_FX_EVERY
		play_fx(&"trail")
	if flat.length() <= TUNNEL_REACH or _state_timer >= TUNNEL_MAX:
		velocity.x = 0.0
		velocity.z = 0.0
		_burst_done = false
		face_player(1.0, 1.0)
		_enter_state(AIState.EMERGE)
		_apply_presence(AIState.EMERGE)
		_present_emerge()


## Its head plate: a blow from the front glances off (on every machine the
## spark; the authority's copy judges the damage).
func take_hit(hit: HitInfo) -> bool:
	if hit != null and targetable and ai_state != AIState.DEAD and from_front(hit):
		if not net_puppet:
			hit.damage *= FRONT_ARMOR
		VFX.flash(get_tree().current_scene, present_origin() + present_forward() * 0.6 + Vector3(0, 0.5, 0),
			Color(1.0, 0.7, 0.35), 0.5, 0.1)
	return super(hit)


## Was the blow struck from in front of its head?
func from_front(hit: HitInfo) -> bool:
	var attacker := hit.attacker_player()
	var src := attacker.global_position if attacker != null else hit.source_position
	var to := src - global_position
	to.y = 0.0
	if to.length() < 0.05:
		return false
	return to.normalized().dot(present_forward()) >= FRONT_DOT


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
	_disc = VFX.telegraph_disc(scene, present_origin(), EMERGE_RADIUS, EMERGE_TIME * 0.75)
	VFX.dodge_dust(scene, present_origin(), Vector3.UP)
	Sfx.play("chitter", global_position, -4.0, 0.1, 0.9)


func _present_windup() -> void:
	_disc = VFX.telegraph_disc(get_tree().current_scene, present_origin() + present_forward() * STRIKE_AHEAD,
		STRIKE_RADIUS, WINDUP_TIME)
	Sfx.play("chitter", global_position, -6.0, 0.15, 1.2)


func _present_fx(fx: StringName) -> void:
	var scene := get_tree().current_scene
	match fx:
		&"trail":
			VFX.dodge_dust(scene, present_origin(), Vector3.UP)
		&"dig":
			VFX.dodge_dust(scene, present_origin(), Vector3.UP)
			Sfx.play("earthbreaker_impact", global_position, -14.0, 0.1, 1.6)
		&"breach":
			VFX.ember_impact(scene, present_origin() + Vector3(0, 0.3, 0))
			Sfx.play("earthbreaker_impact", global_position, -6.0, 0.1, 1.3)
		&"bite":
			Sfx.play("swing", global_position, -6.0, 0.15, 1.3)


func _on_interrupted() -> void:
	if _disc != null and is_instance_valid(_disc):
		_disc.queue_free()
