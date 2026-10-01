class_name Critter
extends Node3D
## M12: a harmless animal of the Highlands - scenery only. No body, no
## collider, no outline (the outline means "can act", ART_BIBLE), never an
## enemy or a target, nothing on the net: every machine keeps its own
## (CritterField puts them around the local hero). It grazes or pecks until
## a hero comes near, then flees: a hare sits up and bolts away in hops, a
## crow takes off and flies off. Once gone it frees itself.

enum Kind { HARE, CROW }
enum State { IDLE, ALERT, FLEE, GONE }

const RIGS := {Kind.HARE: "res://assets/models/chars/ash_hare.glb", Kind.CROW: "res://assets/models/chars/carrion_crow.glb"}
const ATLAS := {Kind.HARE: "ash_hare", Kind.CROW: "carrion_crow"}
## Drawn a little larger than life, so they read at the camera's distance.
const SIZE := {Kind.HARE: 1.35, Kind.CROW: 1.4}
const CHECK := 0.25
const HARE_ALERT := 11.0      # it sits up and watches
const HARE_FLEE := 7.0        # it bolts
const HARE_SPEED := 7.5
const HARE_RUN := 2.4         # s per bolt; still pressed, it bolts again
const HARE_CALM := 14.0       # a bolt ends with every hero this far off
const HARE_BOLTS := 3         # bolts before it is gone for good
const CROW_FLEE := 8.0
const CROW_SPEED := 6.0
const CROW_CLIMB := 3.2
const CROW_GONE := 3.5        # s of flight, then out of sight

var kind: Kind = Kind.HARE
var state: State = State.IDLE
var zone: ZoneBase
var anim: AnimationPlayer = null
var height: float = 0.0       # a flying crow above the ground
var bolts: int = 0
var _model: Node3D
var _t: float = 0.0
var _check_left: float = 0.0
var _flee_dir := Vector3.ZERO
var _turn_left: float = 0.0
var _wander_left: float = 0.0
var _lod_accum: float = 0.0


static func create(z: ZoneBase, k: Kind, pos: Vector3, parent: Node = null) -> Critter:
	var c := Critter.new()
	c.kind = k
	c.zone = z
	c.name = "Hare" if k == Kind.HARE else "Crow"
	(parent if parent != null else z.world).add_child(c, true)
	c.global_position = Vector3(pos.x, z.ground_y(pos), pos.z)
	c.rotation.y = randf() * TAU
	c._check_left = randf() * CHECK
	c._wander_left = randf_range(2.0, 6.0)
	c._build()
	return c


func _build() -> void:
	if DisplayServer.get_name() == "headless":
		return  # tests: the behaviour without a model
	var scene := ArtKit.rig_scene(String(RIGS[kind]))
	if scene == null:
		return
	_model = scene.instantiate() as Node3D
	_model.rotation.y = PI
	_model.scale = Vector3.ONE * float(SIZE[kind])
	add_child(_model)
	var mat := ArtKit.character_material(String(ATLAS[kind])).duplicate() as StandardMaterial3D
	mat.stencil_mode = BaseMaterial3D.STENCIL_MODE_DISABLED  # no outline: an animal never acts
	mat.next_pass = null
	for mi: Node in _model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).set_surface_override_material(0, mat)
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var players := _model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		anim = players[0] as AnimationPlayer
		anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		for clip: StringName in [&"idle", &"hop", &"fly"]:
			if anim.has_animation(clip):
				anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		anim.play(&"idle")
		anim.seek(randf() * anim.current_animation_length, true)


func _play(clip: StringName) -> void:
	if anim != null and anim.has_animation(clip) and anim.current_animation != clip:
		anim.play(clip, 0.12)


## The nearest hero (puppets too: everyone scares the animals).
func _nearest_hero() -> Player:
	if zone == null:
		return null
	var best: Player = null
	var best_d := INF
	for p in zone.players:
		if p == null or not is_instance_valid(p):
			continue
		var d := p.global_position.distance_squared_to(global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


func _process(delta: float) -> void:
	if state == State.GONE:
		return
	_t += delta
	_check_left -= delta
	var hero: Player = null
	var dist := INF
	if _check_left <= 0.0 or state == State.FLEE:
		_check_left = CHECK
		hero = _nearest_hero()
		if hero != null:
			dist = hero.global_position.distance_to(global_position)
	if kind == Kind.HARE:
		_hare(delta, hero, dist)
	else:
		_crow(delta, hero, dist)
	_animate(delta)


func _hare(delta: float, hero: Player, dist: float) -> void:
	match state:
		State.IDLE:
			if hero != null and dist < HARE_FLEE:
				_bolt(hero)
			elif hero != null and dist < HARE_ALERT:
				state = State.ALERT
				_t = 0.0
				_face(hero.global_position - global_position)
				_play(&"alert")
			else:
				_wander_left -= delta
				if _wander_left <= 0.0:
					_wander_left = randf_range(3.0, 7.0)
					rotation.y += randf_range(-1.5, 1.5)
		State.ALERT:
			if hero != null and dist < HARE_FLEE:
				_bolt(hero)
			elif hero != null and dist > HARE_ALERT + 3.0:
				state = State.IDLE
				_play(&"idle")
		State.FLEE:
			_turn_left -= delta
			if _turn_left <= 0.0:  # the zigzag
				_turn_left = randf_range(0.35, 0.7)
				_flee_dir = _flee_dir.rotated(Vector3.UP, randf_range(-0.6, 0.6))
			_step(_flee_dir * HARE_SPEED * delta)
			_face(_flee_dir)
			if _t >= HARE_RUN:
				if hero != null and dist < HARE_CALM:
					if bolts >= HARE_BOLTS:
						_gone()
					else:
						_bolt(hero)
				else:
					state = State.IDLE
					_play(&"idle")


func _bolt(hero: Player) -> void:
	state = State.FLEE
	bolts += 1
	_t = 0.0
	var away := global_position - hero.global_position
	away.y = 0.0
	_flee_dir = (away.normalized() if away.length() > 0.1 else Vector3.FORWARD).rotated(Vector3.UP, randf_range(-0.5, 0.5))
	_turn_left = randf_range(0.3, 0.6)
	_play(&"hop")


func _crow(delta: float, hero: Player, dist: float) -> void:
	match state:
		State.IDLE:
			if hero != null and dist < CROW_FLEE:
				state = State.FLEE
				_t = 0.0
				var away := global_position - hero.global_position
				away.y = 0.0
				_flee_dir = (away.normalized() if away.length() > 0.1 else Vector3.FORWARD).rotated(Vector3.UP, randf_range(-0.7, 0.7))
				_face(_flee_dir)
				_play(&"takeoff")
				Sfx.play("wing_beat", global_position, -16.0, 0.2, 2.2)
			else:
				_wander_left -= delta
				if _wander_left <= 0.0:
					_wander_left = randf_range(2.0, 5.0)
					rotation.y += randf_range(-1.2, 1.2)
		State.FLEE:
			if _t > 0.3:
				_play(&"fly")
			height += CROW_CLIMB * delta * minf(_t / 0.3, 1.0)
			_step(_flee_dir * CROW_SPEED * delta)
			if _t >= CROW_GONE:
				_gone()


## Along the ground (or `height` above it for a crow in the air).
func _step(move: Vector3) -> void:
	var p := global_position + move
	p.y = (zone.ground_y(p) if zone != null else 0.0) + height
	global_position = p


func _face(dir: Vector3) -> void:
	if dir.length_squared() > 0.001:
		rotation.y = atan2(-dir.x, -dir.z)


func _gone() -> void:
	state = State.GONE
	queue_free()


## Animation LOD like the enemies': far animals advance at 30 / 15 Hz.
func _animate(delta: float) -> void:
	if anim == null:
		return
	_lod_accum += delta
	var interval := 0.0
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		var d := cam.global_position.distance_to(global_position)
		interval = 0.0 if d < 14.0 else (1.0 / 30.0 if d < 28.0 else 1.0 / 15.0)
	if _lod_accum >= interval:
		anim.advance(_lod_accum)
		_lod_accum = 0.0
