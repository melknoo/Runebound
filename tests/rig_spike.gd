extends Node
## M06 A4 rig & animation spike. Proves the Blender 5.2 -> GLB -> Godot path
## before any real character is built on it.
## Headless:  godot --headless --path . res://tests/rig_spike.tscn
## Windowed:  godot --path . --resolution 1600x900 res://tests/rig_spike.tscn -- --spike-visual
##            (captures to captures_shots/rig_spike + 29-instance perf in the lab)

const GLB := "res://assets/models/spike/spike_biped.glb"
const ATLAS := "res://assets/textures/stone.png"  # stand-in pixel atlas for the spike
const UPPER_BODY: Array[String] = ["spine", "chest", "head", "upper_arm.L", "upper_arm.R",
	"forearm.L", "forearm.R", "hand.L", "hand.R"]

var _failures: Array[String] = []
var _world: Node3D


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		_failures.append(label)
		printerr("  FAIL: " + label)


func _ready() -> void:
	_world = Node3D.new()
	add_child(_world)
	_run.call_deferred()


func _run() -> void:
	print("== RUNEBOUND rig spike ==")
	var packed := load(GLB) as PackedScene
	_check(packed != null, "spike GLB imports as a scene")
	if packed == null:
		_finish()
		return
	var model := packed.instantiate() as Node3D
	_world.add_child(model)
	var skel := model.find_children("*", "Skeleton3D", true, false)
	var anim_players := model.find_children("*", "AnimationPlayer", true, false)
	_check(skel.size() == 1, "one Skeleton3D")
	_check(anim_players.size() == 1, "one AnimationPlayer")
	if skel.is_empty() or anim_players.is_empty():
		_finish()
		return
	var skeleton := skel[0] as Skeleton3D
	var player := anim_players[0] as AnimationPlayer
	_check(skeleton.get_bone_count() == 17, "17 bones (got %d)" % skeleton.get_bone_count())

	# --- clips + lengths (authored at 60 fps) ---
	var names := player.get_animation_list()
	_check(names.has("idle") and names.has("run") and names.has("attack"), "clips idle/run/attack present %s" % [names])
	if names.has("attack"):
		_check(absf(player.get_animation("attack").length - 0.5) < 0.02, "attack length 0.5 s")
		_check(absf(player.get_animation("run").length - 0.6) < 0.02, "run length 0.6 s")
		_check(absf(player.get_animation("idle").length - 1.0) < 0.02, "idle length 1.0 s")

	# --- color fidelity: sRGB spec -> linear in Blender -> sRGB albedo in Godot ---
	var mesh_inst := model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var body_mat := mesh_inst.mesh.surface_get_material(0) as StandardMaterial3D
	_check(body_mat != null, "body surface has a StandardMaterial3D")
	if body_mat != null:
		var got := body_mat.albedo_color
		var want := Color("3a404d")
		var err := maxf(maxf(absf(got.r - want.r), absf(got.g - want.g)), absf(got.b - want.b))
		_check(err < 2.0 / 255.0, "body albedo matches spec #3A404D (got #%s)" % got.to_html(false))
	_check(mesh_inst.mesh.get_surface_count() <= 3, "at most 3 surfaces (got %d)" % mesh_inst.mesh.get_surface_count())
	var uvs: PackedVector2Array = mesh_inst.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	_check(uvs.size() > 0, "mesh carries UVs for the pixel atlas")

	# --- manual advance, attack contact moves the hand, loops ---
	for loop_name in ["idle", "run"]:
		player.get_animation(loop_name).loop_mode = Animation.LOOP_LINEAR
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var hand := skeleton.find_bone("hand.R")
	player.play("attack")
	player.advance(0.0)
	var hand_rest := skeleton.get_bone_global_pose(hand).origin
	player.advance(7.0 / 60.0)
	var hand_contact := skeleton.get_bone_global_pose(hand).origin
	_check(absf(player.current_animation_position - 7.0 / 60.0) < 0.001, "manual advance is frame-exact")
	_check(hand_rest.distance_to(hand_contact) > 0.2, "attack swings the hand (%.2f m)" % hand_rest.distance_to(hand_contact))
	player.play("run")
	player.advance(1.3)
	_check(player.is_playing() and player.current_animation_position < 0.6, "run loops")
	var hips := skeleton.find_bone("hips")
	var root_bone := skeleton.find_bone("root")
	var root_drift := skeleton.get_bone_global_pose(root_bone).origin.length()
	var hip_offset := Vector2(skeleton.get_bone_global_pose(hips).origin.x, skeleton.get_bone_global_pose(hips).origin.z).length()
	_check(root_drift < 0.01 and hip_offset < 0.15, "no root motion, hips stay over origin")

	# --- BoneAttachment3D carries a weapon ---
	var attach := BoneAttachment3D.new()
	attach.bone_name = "hand.R"
	skeleton.add_child(attach)
	var sword := MeshInstance3D.new()
	var blade := BoxMesh.new()
	blade.size = Vector3(0.1, 0.9, 0.04)
	sword.mesh = blade
	attach.add_child(sword)
	player.play("attack")
	player.advance(0.0)
	await get_tree().process_frame
	var sword_rest := sword.global_position
	player.advance(7.0 / 60.0)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(sword.global_position.distance_to(sword_rest) > 0.2, "weapon follows the hand bone")

	# --- AnimationTree: legs keep running while the upper body attacks ---
	var tree := _build_layer_tree(model, player, skeleton)
	tree.set("parameters/upper/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	tree.advance(0.0)
	tree.advance(7.0 / 60.0)
	var attack_anim := player.get_animation("attack")
	var run_anim := player.get_animation("run")
	var arm_q := skeleton.get_bone_pose_rotation(skeleton.find_bone("upper_arm.R"))
	var arm_want := _sample_rotation(attack_anim, "upper_arm.R", 7.0 / 60.0)
	var leg_q := skeleton.get_bone_pose_rotation(skeleton.find_bone("thigh.L"))
	var leg_want := _sample_rotation(run_anim, "thigh.L", 7.0 / 60.0)
	_check(arm_q.angle_to(arm_want) < 0.05, "upper body plays the attack one-shot")
	_check(leg_q.angle_to(leg_want) < 0.05, "legs keep the run under the one-shot (bone filter)")
	tree.queue_free()

	# --- per-instance hit flash on a skinned mesh ---
	var a := _instance_with_own_materials(packed)
	var b := _instance_with_own_materials(packed)
	var mat_a := _surface_mat(a)
	var mat_b := _surface_mat(b)
	mat_a.emission_enabled = true
	mat_a.emission = Color.WHITE
	_check(mat_a != mat_b and not mat_b.emission_enabled, "hit flash stays on its own instance")

	# --- toon + stencil outline + pixel atlas on the skinned material ---
	mat_b.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat_b.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat_b.albedo_texture = load(ATLAS)
	mat_b.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC
	mat_b.stencil_mode = BaseMaterial3D.STENCIL_MODE_OUTLINE
	mat_b.stencil_outline_thickness = 0.012
	mat_b.stencil_color = Color("0b0810")
	_check(mat_b.stencil_mode == BaseMaterial3D.STENCIL_MODE_OUTLINE, "stencil outline configurable on the skinned material")

	if "--spike-visual" in OS.get_cmdline_user_args():
		await _visual_pass(packed)
	_finish()


func _build_layer_tree(model: Node3D, player: AnimationPlayer, skeleton: Skeleton3D) -> AnimationTree:
	var tree := AnimationTree.new()
	model.add_child(tree)
	tree.anim_player = tree.get_path_to(player)
	var blend := AnimationNodeBlendTree.new()
	var loco := AnimationNodeAnimation.new()
	loco.animation = &"run"
	var shot := AnimationNodeAnimation.new()
	shot.animation = &"attack"
	var one_shot := AnimationNodeOneShot.new()
	one_shot.filter_enabled = true
	var attack_anim := player.get_animation("attack")
	for i in attack_anim.get_track_count():
		var path := attack_anim.track_get_path(i)
		if path.get_subname_count() > 0 and UPPER_BODY.has(String(path.get_subname(0))):
			one_shot.set_filter_path(path, true)
	blend.add_node(&"loco", loco)
	blend.add_node(&"shot", shot)
	blend.add_node(&"upper", one_shot)
	blend.connect_node(&"upper", 0, &"loco")
	blend.connect_node(&"upper", 1, &"shot")
	blend.connect_node(&"output", 0, &"upper")
	tree.tree_root = blend
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true
	player.stop()
	return tree


func _sample_rotation(anim: Animation, bone: String, time: float) -> Quaternion:
	for i in anim.get_track_count():
		if anim.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		var path := anim.track_get_path(i)
		if path.get_subname_count() > 0 and String(path.get_subname(0)) == bone:
			return anim.rotation_track_interpolate(i, time)
	return Quaternion.IDENTITY


func _instance_with_own_materials(packed: PackedScene) -> Node3D:
	var inst := packed.instantiate() as Node3D
	_world.add_child(inst)
	for child in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if mat != null:
				mi.set_surface_override_material(s, mat.duplicate())
	return inst


func _surface_mat(inst: Node3D) -> StandardMaterial3D:
	var mi := inst.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	return mi.get_surface_override_material(0) as StandardMaterial3D


# ---------------------------------------------------------------------------
# Windowed: look captures + 29-instance cost inside the real Combat Lab
# ---------------------------------------------------------------------------

func _visual_pass(packed: PackedScene) -> void:
	for child in _world.get_children():
		child.queue_free()
	var lab := (load("res://scenes/combat_lab.tscn") as PackedScene).instantiate() as ZoneBase
	get_tree().root.add_child(lab)
	await get_tree().create_timer(1.0).timeout
	lab.kill_all_enemies()
	lab.player.god_mode = true
	await get_tree().create_timer(0.5).timeout

	# One hero instance in front of the camera for look captures.
	var hero := _instance_with_own_materials(packed)
	hero.reparent(lab.world)
	hero.global_position = lab.player.global_position + Vector3(0, 0, -3.0)
	hero.rotation.y = 0.0  # Blender -Y front -> faces +Z = toward the camera
	var mat := _surface_mat(hero)
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.albedo_texture = load(ATLAS)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC
	var hp := hero.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	hp.get_animation("run").loop_mode = Animation.LOOP_LINEAR
	hp.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
	hp.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	lab.camera_rig._pitch = -0.2
	for outline: bool in [false, true]:
		mat.stencil_mode = BaseMaterial3D.STENCIL_MODE_OUTLINE if outline else BaseMaterial3D.STENCIL_MODE_DISABLED
		mat.stencil_outline_thickness = 0.012
		mat.stencil_color = Color("0b0810")
		var tag := "outline" if outline else "plain"
		for pose: Array in [["idle", 0.5], ["run", 0.15], ["attack", 7.0 / 60.0]]:
			hp.play(pose[0])
			hp.seek(pose[1], true)
			await _capture("%s_%s" % [pose[0], tag])
	hero.queue_free()

	# Cost of 29 animated rigged instances (outline on) vs none, lab lit.
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var base := await _measure(4.0, [])
	var crowd: Array[AnimationPlayer] = []
	for i in 29:
		var inst := _instance_with_own_materials(packed)
		inst.reparent(lab.world)
		inst.global_position = lab.player.global_position + Vector3((i % 6 - 2.5) * 1.6, 0, -4.0 - (i / 6) * 1.8)
		var m := _surface_mat(inst)
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		m.stencil_mode = BaseMaterial3D.STENCIL_MODE_OUTLINE
		m.stencil_outline_thickness = 0.012
		var ap := inst.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		ap.get_animation("run").loop_mode = Animation.LOOP_LINEAR
		ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		ap.play("run")
		ap.seek(randf() * 0.6, true)
		crowd.append(ap)
	await _capture("crowd_29")
	var loaded := await _measure(6.0, crowd)
	print("spike perf: empty %.1f FPS gpu %.2f ms | 29 rigged+outline %.1f FPS gpu %.2f ms | delta gpu %.2f ms" % [
		base["fps"], base["gpu"], loaded["fps"], loaded["gpu"], loaded["gpu"] - base["gpu"]])
	_check(loaded["fps"] >= 60.0, "29 rigged, outlined, animated instances keep 60 FPS in the lab (%.1f)" % loaded["fps"])


func _measure(seconds: float, crowd: Array[AnimationPlayer]) -> Dictionary:
	var vp := get_viewport().get_viewport_rid()
	var t := 0.0
	var frames := 0
	var gpu := 0.0
	while t < seconds:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		for ap in crowd:
			ap.advance(dt)
		t += dt
		frames += 1
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	return {"fps": frames / maxf(t, 0.001), "gpu": gpu / maxi(frames, 1)}


func _capture(shot_name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var dir := ProjectSettings.globalize_path("res://captures_shots/rig_spike")
	DirAccess.make_dir_recursive_absolute(dir)
	var marker := ProjectSettings.globalize_path("res://captures_shots/.gdignore")
	if not FileAccess.file_exists(marker):
		FileAccess.open(marker, FileAccess.WRITE).close()
	img.save_png("%s/%s.png" % [dir, shot_name])
	print("capture: ", shot_name)


func _finish() -> void:
	print("== %d failures ==" % _failures.size())
	get_tree().quit(1 if _failures.size() > 0 else 0)
