class_name CharacterAnimator
extends Node
## Plays a rigged model's clips from its owner's EXISTING state — it never
## drives gameplay (hits stay timer-driven). M06 rules:
##  * manual advance in this node's physics tick, which runs after the
##    owner's (child after parent), so pose and _state_timer stay in lockstep;
##  * frozen while the owner is in hitstop -> the impact freeze the old tweens
##    could not do;
##  * locomotion speed-matched (playback = speed / clip speed, so Chill-slowed
##    enemies don't ice-skate), crossfaded; attacks blend in <= 2 frames;
##  * smooth 60 fps playback (Gate 0 decision; stepped 12 fps was rejected).
## Two backends: enemies drive their AnimationPlayer directly (cheap). A
## "layered" profile (the player) builds an AnimationTree instead:
##   base  Transition: idle / run (time-scaled) / full-body one-shots
##   upper OneShot filtered to the upper body: gestures over running legs
##   flinch OneShot in ADD mode: hit recoil on top of anything
## Owners: Player (action_started signal + state) and EnemyBase (state_entered).

const ATTACK_BLEND := 2.0 / 60.0
const LOCO_BLEND := 0.12
## A full-body one-shot always shows its first frames before locomotion may
## take it over (the Earthbreaker landing would otherwise vanish under a run).
const COMMIT := 0.1
const UPPER_BONES: Array[String] = ["spine", "chest", "head", "upper_arm.L", "upper_arm.R",
	"forearm.L", "forearm.R", "hand.L", "hand.R"]

## Perf A/B only (LookDev "anim_process"): false stops advancing every rig.
static var processing: bool = true
## Animation LOD (LookDev "anim_lod"): enemies away from the camera advance at
## 30/15 Hz — every advance re-skins the mesh, which is the rig cost that
## scales with enemy count on the iGPU. The player always runs at full rate.
static var lod: bool = true
static var camera: Camera3D = null
const LOD_NEAR := 12.0
const LOD_FAR := 24.0
static var _lookdev_ready: bool = false

var anim: AnimationPlayer
## Layered profiles only (the player); null for enemies.
var tree: AnimationTree = null
var body: CharacterBody3D
## idle, run, run_speed (m/s the run clip was authored for), actions/states ->
## one-shots; layered: upper (action -> gesture), flinch (clip), free
## (Callable: true when locomotion may take over a finished-looking one-shot).
## States map to a clip name, "@loco", "@dead", "~clip" (loop this clip for as
## long as the state lasts: strafes, dashes, dazes) or a Callable returning
## one of those (one state, several meanings). rate: optional
## Callable(clip) -> playback speed of one-shots (runtime-varying windups).
var profile: Dictionary = {}

var _one_shot: StringName = &""
var _one_shot_time: float = 0.0
var _state_loop: StringName = &""
var _loco: StringName = &""
var _base: AnimationNodeTransition
var _upper_clip: AnimationNodeAnimation
var _lod_accum: float = 0.0
var _dead: bool = false
## Player rigs never drop rate (animation precision next to the camera).
var full_rate: bool = false


static func create(owner_body: CharacterBody3D, model: Node, clip_profile: Dictionary) -> CharacterAnimator:
	if not _lookdev_ready:
		_lookdev_ready = true
		LookDev.register(&"anim_process", func(v: Variant) -> void: CharacterAnimator.processing = bool(v), true)
		LookDev.register(&"anim_lod", func(v: Variant) -> void: CharacterAnimator.lod = bool(v), true)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return null
	var a := CharacterAnimator.new()
	a.name = "CharacterAnimator"
	a.anim = players[0] as AnimationPlayer
	a.body = owner_body
	a.profile = clip_profile
	for loop_clip: StringName in [clip_profile.get("idle", &"idle"), clip_profile.get("run", &"run")]:
		if a.anim.has_animation(loop_clip):
			a.anim.get_animation(loop_clip).loop_mode = Animation.LOOP_LINEAR
	a.anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	if clip_profile.get("layered", false):
		a._build_tree(model)
	else:
		a.anim.play(clip_profile.get("idle", &"idle"))
	owner_body.add_child(a)
	if owner_body.has_signal(&"action_started"):
		owner_body.connect(&"action_started", a._on_action)
	if owner_body.has_signal(&"state_entered"):
		owner_body.connect(&"state_entered", a._on_state)
	return a


func _build_tree(model: Node) -> void:
	var idle: StringName = profile.get("idle", &"idle")
	var run: StringName = profile.get("run", &"run")
	var inputs: Array[StringName] = [idle, run]
	for clip: StringName in (profile.get("actions", {}) as Dictionary).values():
		if not inputs.has(clip) and anim.has_animation(clip):
			inputs.append(clip)
	var bt := AnimationNodeBlendTree.new()
	_base = AnimationNodeTransition.new()
	_base.xfade_time = LOCO_BLEND
	_base.allow_transition_to_self = true
	_base.input_count = inputs.size()
	bt.add_node(&"base", _base)
	for i in inputs.size():
		_base.set_input_name(i, String(inputs[i]))
		_base.set_input_reset(i, i >= 2)  # one-shots restart, loops keep their phase
		var clip_node := AnimationNodeAnimation.new()
		clip_node.animation = inputs[i]
		var node_name := StringName("clip_" + String(inputs[i]))
		bt.add_node(node_name, clip_node)
		if inputs[i] == run:
			bt.add_node(&"run_scale", AnimationNodeTimeScale.new())
			bt.connect_node(&"run_scale", 0, node_name)
			bt.connect_node(&"base", i, &"run_scale")
		else:
			bt.connect_node(&"base", i, node_name)
	var last := &"base"
	var upper := profile.get("upper", {}) as Dictionary
	if not upper.is_empty():
		var shot := AnimationNodeOneShot.new()
		shot.fadein_time = ATTACK_BLEND
		shot.fadeout_time = 0.12
		shot.filter_enabled = true
		for path in _bone_track_paths(UPPER_BONES):
			shot.set_filter_path(path, true)
		_upper_clip = AnimationNodeAnimation.new()
		_upper_clip.animation = upper.values()[0]
		bt.add_node(&"upper", shot)
		bt.add_node(&"upper_clip", _upper_clip)
		bt.connect_node(&"upper", 0, last)
		bt.connect_node(&"upper", 1, &"upper_clip")
		last = &"upper"
	var flinch_clip: StringName = profile.get("flinch", &"")
	if flinch_clip != &"" and anim.has_animation(flinch_clip):
		var add := AnimationNodeOneShot.new()
		add.mix_mode = AnimationNodeOneShot.MIX_MODE_ADD
		add.fadein_time = 1.0 / 60.0
		add.fadeout_time = 0.1
		var clip_node := AnimationNodeAnimation.new()
		clip_node.animation = flinch_clip
		bt.add_node(&"flinch", add)
		bt.add_node(&"flinch_clip", clip_node)
		bt.connect_node(&"flinch", 0, last)
		bt.connect_node(&"flinch", 1, &"flinch_clip")
		last = &"flinch"
	bt.connect_node(&"output", 0, last)
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	tree.tree_root = bt
	model.add_child(tree)
	tree.anim_player = tree.get_path_to(anim)
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true
	anim.stop()


## Track paths of the given bones as the imported clips address them.
func _bone_track_paths(bones: Array[String]) -> Array[NodePath]:
	var paths: Array[NodePath] = []
	for anim_name in anim.get_animation_list():
		var clip := anim.get_animation(anim_name)
		for i in clip.get_track_count():
			var path := clip.track_get_path(i)
			if path.get_subname_count() > 0 and bones.has(String(path.get_subname(0))) and not paths.has(path):
				paths.append(path)
	return paths


## Start a full-body one-shot at time 0 (attacks: <= 2 frame blend).
func play_one_shot(clip: StringName) -> void:
	if not anim.has_animation(clip):
		return
	_one_shot = clip
	_one_shot_time = 0.0
	if tree != null:
		_loco = &""
		_base.xfade_time = ATTACK_BLEND
		tree.set(&"parameters/base/transition_request", String(clip))
	else:
		anim.play(clip, ATTACK_BLEND)
		anim.seek(0.0, false)


## Upper-body gesture over whatever the legs do (layered profiles only).
func play_upper(clip: StringName) -> void:
	if tree == null or _upper_clip == null or not anim.has_animation(clip):
		return
	_upper_clip.animation = clip
	tree.set(&"parameters/upper/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Additive hit recoil on top of the current pose (layered profiles only).
func flinch() -> void:
	if tree != null and profile.get("flinch", &"") != &"":
		tree.set(&"parameters/flinch/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func _on_action(action: StringName) -> void:
	var gesture: StringName = (profile.get("upper", {}) as Dictionary).get(action, &"")
	if gesture != &"":
		play_upper(gesture)
		return
	var clip: StringName = (profile.get("actions", {}) as Dictionary).get(action, &"")
	if clip != &"":
		play_one_shot(clip)


func _on_state(state: int) -> void:
	var entry: Variant = (profile.get("states", {}) as Dictionary).get(state, &"")
	var clip := StringName((entry as Callable).call()) if entry is Callable else StringName(entry)
	_state_loop = &""
	if clip == &"@dead":
		_dead = true
	elif clip == &"@loco":
		_one_shot = &""
	elif String(clip).begins_with("~"):
		# A running one-shot (the stab that just landed) plays out first.
		_state_loop = StringName(String(clip).substr(1))
		if anim.has_animation(_state_loop):
			anim.get_animation(_state_loop).loop_mode = Animation.LOOP_LINEAR
		else:
			_state_loop = &""
	elif clip != &"":
		play_one_shot(clip)


func _physics_process(delta: float) -> void:
	if anim == null or _dead or not processing:
		return
	if float(body.get(&"_hitstop_left")) > 0.0:
		return  # impact freeze in lockstep with the owner's own hitstop
	var speed := Vector2(body.velocity.x, body.velocity.z).length()
	if _one_shot != &"":
		_one_shot_time += delta
		if not _one_shot_running():
			_one_shot = &""
		elif _one_shot_time >= COMMIT and speed > 0.6 and _owner_free():
			_one_shot = &""  # moving on after the action: run instead of sliding through its follow-through
	var rate := 1.0
	if _one_shot != &"" and profile.get("rate") is Callable:
		rate = float((profile["rate"] as Callable).call(_one_shot))
	if _one_shot == &"" and _state_loop != &"":
		_play_loco(_state_loop, 1.0)
	elif _one_shot == &"":
		var run_clip: StringName = profile.get("run", &"run")
		var target: StringName = run_clip if speed > 0.6 else profile.get("idle", &"idle")
		if target == run_clip:
			rate = clampf(speed / float(profile.get("run_speed", 6.8)), 0.5, 1.8)
		_play_loco(target, rate)
	if tree != null:
		tree.advance(delta)
		return
	var interval := _lod_interval()
	if interval <= 0.0:
		anim.advance(delta * rate)
		return
	_lod_accum += delta * rate
	if _lod_accum >= interval:
		anim.advance(_lod_accum)
		_lod_accum = 0.0


func _one_shot_running() -> bool:
	if tree != null:
		return _one_shot_time < anim.get_animation(_one_shot).length
	return anim.current_animation == _one_shot and anim.is_playing()


func _owner_free() -> bool:
	var free: Variant = profile.get("free")
	return free is Callable and bool((free as Callable).call())


func _play_loco(target: StringName, rate: float) -> void:
	if tree != null:
		tree.set(&"parameters/run_scale/scale", rate)
		if _loco != target:
			_loco = target
			_base.xfade_time = LOCO_BLEND
			tree.set(&"parameters/base/transition_request", String(target))
		return
	if anim.current_animation != target:
		anim.play(target, LOCO_BLEND)


## 0 = every tick; otherwise seconds between advances by camera distance.
## One-shots (attacks, telegraph windups) always run at full rate: their
## timing is what the player reads.
func _lod_interval() -> float:
	if full_rate or not lod or _one_shot != &"":
		return 0.0
	if camera == null or not is_instance_valid(camera):
		camera = body.get_viewport().get_camera_3d()
		if camera == null:
			return 0.0
	var d := camera.global_position.distance_to(body.global_position)
	if d < LOD_NEAR:
		return 0.0
	return 1.0 / 30.0 if d < LOD_FAR else 1.0 / 15.0
