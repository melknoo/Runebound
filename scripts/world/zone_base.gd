class_name ZoneBase
extends Node
## Base for every playable zone (Combat Lab, Runehold hub, regions):
## bootstraps player/camera/targeting/HUD/inventory/debug, provides greybox
## building helpers, enemy/drop plumbing, zone travel with save persistence.

var world: Node3D
var player: Player
var camera_rig: CameraRig
var targeting: TargetingSystem
var hud: Hud
var debug_overlay: DebugOverlay
var style_manager: StyleManager
var hero_ui: HeroUI
var inventory_ui: InventoryUI  # the hero window's inventory tab
var talent_ui: TalentUI        # the hero window's talent tab
var trainer_ui: TrainerUI
var enemies_root: Node3D
## Data-driven presentation (M06); null = legacy environment + greybox materials.
var look: ZoneLook = null
var _hulls: Array[MeshInstance3D] = []

var style_name: String:
	get:
		return style_manager.style_name() if style_manager != null else "-"

var _travelling: bool = false


func _ready() -> void:
	InputSetup.ensure()  # M07 actions (talents, abilities 7-8), no project.godot edit
	world = Node3D.new()
	world.name = "World"
	add_child(world)

	look = _zone_look()
	if "--legacy-look" in OS.get_cmdline_user_args():
		look = null  # before/after captures with identical framing
	if look != null:
		_build_look_environment(look)
	else:
		_build_environment()

	enemies_root = Node3D.new()
	enemies_root.name = "Enemies"
	world.add_child(enemies_root)

	_build_zone()
	_spawn_player()
	if look != null and look.ash_fall > 0.0:
		_add_ash_fall(look.ash_fall)
	# Compile every effect's shaders now rather than on the first cast in a
	# fight: drawn ahead of the camera (inside the frustum) just under the floor.
	var ahead := -camera_rig.global_transform.basis.z
	ahead = Vector3(ahead.x, 0.0, ahead.z).normalized() if absf(ahead.y) < 0.99 else Vector3.FORWARD
	var hidden := Vector3(player.global_position.x, -0.5, player.global_position.z) + ahead * 4.0
	VFX.warm_up(world, hidden)
	_warm_up_characters(hidden + Vector3(0, -1.2, 0))

	hud = Hud.new()
	hud.layer = 5
	add_child(hud)
	hud.setup(player)

	debug_overlay = DebugOverlay.new()
	add_child(debug_overlay)
	debug_overlay.setup(self)

	# M07b hero window: inventory (I), character (C) and talents (N) as tabs.
	hero_ui = HeroUI.new()
	add_child(hero_ui)
	hero_ui.setup(player)
	inventory_ui = hero_ui.inventory_tab
	talent_ui = hero_ui.talent_tab

	trainer_ui = TrainerUI.new()  # M07b: hidden until a TrainerNpc opens it
	add_child(trainer_ui)
	trainer_ui.setup(player)

	style_manager = StyleManager.new()
	add_child(style_manager)
	style_manager.setup(self, world)
	if look != null:
		style_manager.apply_look(look)

	SaveGame.restore_player(player)
	_zone_ready()
	_discover()
	if MusicDirector.instance != null:
		MusicDirector.instance.play_zone(_zone_music())

	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if "--worldcapture" in OS.get_cmdline_user_args():
		var capture: Node = (load("res://tests/world_capture.gd") as GDScript).new()
		add_child(capture)
	_attach_test_runners()


## `-- --shots=<json>` / `-- --perf=<json>`: data-driven capture and perf runs
## (tests/shot_runner.gd, tests/perf_probe.gd). Loaded dynamically so normal
## play never compiles them.
func _attach_test_runners() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			var runner: Node = (load("res://tests/shot_runner.gd") as GDScript).new()
			runner.set(&"list_path", arg.trim_prefix("--shots="))
			add_child(runner)
		elif arg.begins_with("--perf="):
			var probe: Node = (load("res://tests/perf_probe.gd") as GDScript).new()
			probe.set(&"scenario_path", arg.trim_prefix("--perf="))
			add_child(probe)


# ---------------------------------------------------------------------------
# Zone interface (override in subclasses)
# ---------------------------------------------------------------------------

## Build the zone's geometry, spawners, portals.
func _build_zone() -> void:
	pass


## Called after the full bootstrap (player, HUD, save restore) finished.
func _zone_ready() -> void:
	pass


## Music key for tools/musicgen tracks (`<key>_explore` / `<key>_combat`);
## "" = no music in this zone.
func _zone_music() -> String:
	return ""


func _player_spawn_point() -> Vector3:
	return Vector3(0, 0.2, 6)


## M07: level of an enemy spawned at `pos` (1 = base balance). Zones map
## their areas; bosses override by type.
func _enemy_level(_enemy: EnemyBase, _pos: Vector3) -> int:
	return 1


## M07: the place name shown on arrival; "" = no title card, no discovery XP
## (debug spaces like the Combat Lab).
func zone_title() -> String:
	return ""


const DISCOVERY_XP := 150


## Title card on every arrival; the first visit also pays discovery XP.
func _discover() -> void:
	var title := zone_title()
	if title == "":
		return
	var flag := StringName("discovered_" + scene_file_path.get_file().get_basename())
	var first := not SaveGame.has_flag(flag)
	hud.title_card(title, "DISCOVERED  +%d XP" % DISCOVERY_XP if first else "")
	if first:
		SaveGame.set_flag(flag)
		player.progression.add_xp(DISCOVERY_XP)


## Opt-in data-driven presentation (M06). Returning a ZoneLook switches the
## zone to the pixel sky, ZoneLook lighting/fog/grading and ArtKit materials;
## null keeps the legacy environment below untouched.
func _zone_look() -> ZoneLook:
	return null


## Material for a greybox surface: ArtKit's role material when the zone's look
## has the art pass on, otherwise the legacy tiled texture.
func _zone_material(role: StringName, tex_path: String, fallback: Color, uv_scale: float) -> Material:
	if look != null and look.art_pass:
		return ArtKit.material(role)
	return _material_from_texture(tex_path, fallback, uv_scale)


## Environment palette per zone.
func _environment_colors() -> Dictionary:
	return {
		"sky_top": Color(0.12, 0.08, 0.22),
		"sky_horizon": Color(0.45, 0.22, 0.3),
		"fog": Color(0.35, 0.2, 0.35),
		"sun": Color(1.0, 0.85, 0.7),
		"sun_energy": 1.2,
	}


# ---------------------------------------------------------------------------
# Bootstrap pieces
# ---------------------------------------------------------------------------

func _build_environment() -> void:
	var colors := _environment_colors()
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = colors["sky_top"]
	sky_mat.sky_horizon_color = colors["sky_horizon"]
	sky_mat.ground_bottom_color = Color(0.08, 0.06, 0.12)
	sky_mat.ground_horizon_color = (colors["sky_horizon"] as Color).darkened(0.25)
	sky_mat.sun_angle_max = 30.0
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.1
	env.glow_hdr_threshold = 1.1
	# Level 3 only (default also blurs level 5): tighter pixel-friendly bloom and
	# ~0.6 ms less GPU on the iGPU (M06 perf bank, captures_perf/).
	env.set_glow_level(4, 0.0)
	env.fog_enabled = true
	env.fog_light_color = colors["fog"]
	env.fog_density = 0.012
	env.fog_sky_affect = 0.2
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	world.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 35, 0)
	sun.light_color = colors["sun"]
	sun.light_energy = colors["sun_energy"]
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 60.0
	world.add_child(sun)

	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-30, 205, 0)
	rim.light_color = Color(0.4, 0.3, 0.7)
	rim.light_energy = 0.5
	world.add_child(rim)


const SKY_SHADER := preload("res://shaders/sky_pixel.gdshader")


## Horizon silhouettes baked once per zone into an azimuth lookup (R far ridge
## + volcano, G near ridge, B landmark spire; heights / 0.4). The sky shader
## then needs one fetch per pixel instead of ~10 noise evaluations. Noise is
## sampled on a circle so the lookup wraps seamlessly at +-PI.
static func _bake_silhouettes(l: ZoneLook) -> ImageTexture:
	const W := 2048
	var far_noise := FastNoiseLite.new()
	far_noise.seed = 11
	far_noise.frequency = 0.9
	far_noise.fractal_octaves = 3
	var near_noise := FastNoiseLite.new()
	near_noise.seed = 37
	near_noise.frequency = 1.8
	near_noise.fractal_octaves = 3
	var img := Image.create(W, 1, false, Image.FORMAT_RGB8)
	for x in W:
		var az := (float(x) / W - 0.5) * TAU  # shader: u = az / TAU + 0.5
		var c := Vector2(cos(az), sin(az))
		var far := 0.07 + (far_noise.get_noise_2dv(c * 1.6) * 0.5 + 0.5) * 0.06 + _peak(az, l.volcano)
		var near := 0.035 + (near_noise.get_noise_2dv(c * 1.6) * 0.5 + 0.5) * 0.04
		img.set_pixel(x, 0, Color(clampf(far / 0.4, 0, 1), clampf(near / 0.4, 0, 1), clampf(_peak(az, l.spire) / 0.4, 0, 1)))
	return ImageTexture.create_from_image(img)


static func _peak(az: float, p: Vector3) -> float:
	var d := absf(wrapf(az - p.x, -PI, PI))
	return maxf(p.z * (1.0 - d / maxf(p.y, 0.001)), 0.0)


## M06 environment: pixel sky (no ambient/reflection contribution, so its
## animation never re-filters a radiance map), ZoneLook ambient color, depth +
## height fog with aerial perspective, level-3 glow, key + rim light.
func _build_look_environment(l: ZoneLook) -> void:
	if l.interior:
		_build_interior_environment(l)
		return
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	var sky_params := {
		"top_color": l.sky_top, "mid_color": l.sky_mid, "horizon_color": l.sky_horizon,
		"sun_color": l.sun_disc, "bands": l.sky_bands, "cloud_color": l.cloud_color,
		"cloud_lit_color": l.cloud_lit_color, "cloud_amount": l.cloud_amount,
		"far_color": l.silhouette_far, "near_color": l.silhouette_near,
		"volcano": l.volcano, "spire": l.spire,
		"clouds": load("res://assets/textures/biome/sky_clouds.png"),
		"silhouettes": _bake_silhouettes(l),
	}
	for key: String in sky_params:
		sky_mat.set_shader_parameter(StringName(key), sky_params[key])
	var sky := Sky.new()
	sky.sky_material = sky_mat
	# The shader animates clouds with TIME, which would make AUTOMATIC pick
	# REALTIME and re-filter a radiance cubemap every frame (+~5 ms on the
	# iGPU) although nothing samples it (ambient = color, reflections off).
	# QUALITY filters once; the background itself still animates.
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = l.ambient_color
	env.ambient_light_energy = l.ambient_energy
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = l.tonemap
	env.tonemap_exposure = l.exposure
	env.glow_enabled = true
	env.glow_intensity = l.glow_intensity
	env.glow_bloom = l.glow_bloom
	env.glow_hdr_threshold = l.glow_threshold
	env.set_glow_level(4, 0.0)
	env.fog_enabled = true
	env.fog_light_color = l.fog_color
	env.fog_density = l.fog_density
	env.fog_height = l.fog_height
	env.fog_height_density = l.fog_height_density
	env.fog_aerial_perspective = l.fog_aerial
	env.fog_sky_affect = l.fog_sky_affect
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	world.add_child(world_env)
	# Look-dev / perf A/B switches (shot lists and perf scenarios use them).
	var sky_toggle := func(on: bool) -> void:
		env.background_mode = Environment.BG_SKY if on else Environment.BG_COLOR
		env.background_color = l.sky_mid
	LookDev.register(&"sky", sky_toggle, true)
	var hull_toggle := func(on: bool) -> void:
		for hull: MeshInstance3D in _hulls:
			if is_instance_valid(hull):
				hull.visible = on
				(hull.get_parent().get_child(0) as MeshInstance3D).visible = not on
	LookDev.register(&"hulls", hull_toggle, true)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = l.sun_rotation_deg
	sun.light_color = l.sun_color
	sun.light_energy = l.sun_energy
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 60.0
	world.add_child(sun)

	var rim := DirectionalLight3D.new()
	rim.name = "Rim"
	rim.rotation_degrees = l.rim_rotation_deg
	rim.light_color = l.rim_color
	rim.light_energy = l.rim_energy
	rim.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY  # no second sun disc
	world.add_child(rim)


## ZoneLook interior: colour background (no sky shader, no radiance map), the
## same ambient / fog / glow path, one cold top light with shadows.
func _build_interior_environment(l: ZoneLook) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = l.background
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = l.ambient_color
	env.ambient_light_energy = l.ambient_energy
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = l.tonemap
	env.tonemap_exposure = l.exposure
	env.glow_enabled = true
	env.glow_intensity = l.glow_intensity
	env.glow_bloom = l.glow_bloom
	env.glow_hdr_threshold = l.glow_threshold
	env.set_glow_level(4, 0.0)
	env.fog_enabled = true
	env.fog_light_color = l.fog_color
	env.fog_density = l.fog_density
	env.fog_height = l.fog_height
	env.fog_height_density = l.fog_height_density
	env.fog_aerial_perspective = 0.0
	env.fog_sky_affect = 0.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	world.add_child(world_env)
	var hull_toggle := func(on: bool) -> void:
		for hull: MeshInstance3D in _hulls:
			if is_instance_valid(hull):
				hull.visible = on
				(hull.get_parent().get_child(0) as MeshInstance3D).visible = not on
	LookDev.register(&"hulls", hull_toggle, true)
	var top := DirectionalLight3D.new()
	top.name = "Sun"
	top.rotation_degrees = l.sun_rotation_deg
	top.light_color = l.sun_color
	top.light_energy = l.sun_energy
	top.shadow_enabled = true
	top.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	top.directional_shadow_max_distance = 60.0
	top.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	world.add_child(top)
	if l.rim_energy > 0.0:
		var rim := DirectionalLight3D.new()
		rim.name = "Rim"
		rim.rotation_degrees = l.rim_rotation_deg
		rim.light_color = l.rim_color
		rim.light_energy = l.rim_energy
		rim.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
		world.add_child(rim)


func _spawn_player() -> void:
	player = Player.new()
	player.name = "Player"
	player.class_data = ClassData.load_by_id(SaveGame.active_class_id())
	world.add_child(player)
	player.global_position = _player_spawn_point()

	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	world.add_child(camera_rig)
	camera_rig.set_target(player)
	player.camera_rig = camera_rig
	player.player_died.connect(_on_player_died)

	targeting = TargetingSystem.new()
	targeting.name = "Targeting"
	world.add_child(targeting)
	targeting.player = player
	targeting.camera_rig = camera_rig
	player.targeting = targeting


func _on_player_died() -> void:
	player.health.heal_full()
	player.global_position = _player_spawn_point()
	player.velocity = Vector3.ZERO
	GameFeel.camera_shake(0.4)


# ---------------------------------------------------------------------------
# Greybox building helpers
# ---------------------------------------------------------------------------

func _material_from_texture(tex_path: String, fallback: Color, uv_scale: float = 8.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	if ResourceLoader.exists(tex_path):
		mat.albedo_texture = load(tex_path)
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	else:
		mat.albedo_color = fallback
	mat.roughness = 0.9
	return mat


## `dress` (M06): when the zone's look has the art pass on, the visible box is
## replaced by a RockHull that contains it, using ArtKit material `dress`; the
## StaticBody and its BoxShape3D stay exactly as before. `wild_faces` lets
## faces that point out of the playable area bulge (RockHull bitmask).
func _add_box(pos: Vector3, size: Vector3, mat: Material, rot_degrees: Vector3 = Vector3.ZERO,
		dress: StringName = &"", wild_faces: int = 0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	mesh.mesh = box
	body.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	world.add_child(body)
	body.global_position = pos
	body.rotation_degrees = rot_degrees
	if dress != &"" and look != null and look.art_pass:
		_dress_box(body, mesh, size, dress, wild_faces)
	return body


var _dressing: Node3D


## Container for visual-only kit props (keeps `world`'s direct children — which
## tests count — untouched).
func dressing() -> Node3D:
	if _dressing == null:
		_dressing = Node3D.new()
		_dressing.name = "Dressing"
		world.add_child(_dressing)
	return _dressing


## Rigged enemy types instanced once, frozen under the floor inside the view,
## so their GLBs, materials and lit pipeline variants are ready before the
## first camp triggers (M06 B2 warm-up). Kept out of enemies_root (never
## counted) and freed after a few frames. Zones list the types they field.
func _warm_up_ids() -> Array[String]:
	return ["rusher", "caster"]


## A fresh enemy of a spawn id, not yet in the tree (spawning and warm-up).
static func make_enemy(id: String) -> EnemyBase:
	match id:
		"caster":
			return RangedCaster.new()
		"assassin":
			return Assassin.new()
		"brute":
			return Brute.new()
		"warden":
			return HollowWarden.new()
		"colossus":
			return AshveinColossus.new()
		"vessel":
			return ShatteredVessel.new()
	return MeleeRusher.new()


func _warm_up_characters(spot: Vector3) -> void:
	var holder := Node3D.new()
	holder.name = "WarmUp"
	world.add_child(holder)
	for id in _warm_up_ids():
		var e := make_enemy(id)
		holder.add_child(e)
		e.process_mode = Node.PROCESS_MODE_DISABLED  # no AI, no animation, no physics step
		e.global_position = spot
	var ref: WeakRef = weakref(holder)
	get_tree().create_timer(0.3).timeout.connect(func() -> void:
		var h: Node = ref.get_ref()
		if h != null:
			h.queue_free()
	)


## Ground footprints of the dressed obstacles (Scatter hugs their bases):
## every RockHull-dressed box plus `extra` collider bodies (walls, huts).
func scatter_obstacles(extra: Array[StaticBody3D] = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for hull in _hulls:
		if is_instance_valid(hull):
			out.append(footprint(hull.get_parent() as StaticBody3D))
	for body in extra:
		out.append(footprint(body))
	return out


## Box footprint of a greybox collider body, in Scatter's obstacle format.
static func footprint(body: StaticBody3D) -> Dictionary:
	var shape := (body.get_child(1) as CollisionShape3D).shape as BoxShape3D
	return {"pos": body.global_position, "size": shape.size, "yaw": body.global_rotation.y}


## Visual-only ground beyond a walled zone (no collision: the walls keep the
## player in), a hair under the floor so it never fights it.
func _add_ground_skirt(role: StringName, extent: float) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "GroundSkirt"
	var plane := PlaneMesh.new()
	plane.size = Vector2(extent, extent)
	mi.mesh = plane
	mi.material_override = ArtKit.material(role)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dressing().add_child(mi)
	mi.position = Vector3(0, -0.012, 0)


## Slow ash flakes in a box that travels with the camera rig; world-space
## particles, so the fall doesn't slide along with the player (ZoneLook.ash_fall).
func _add_ash_fall(density: float) -> void:
	var p := GPUParticles3D.new()
	p.name = "AshFall"
	p.amount = maxi(int(180.0 * density), 1)
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-14, -7, -14), Vector3(28, 14, 28))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(12, 4, 12)
	pm.direction = Vector3(0.4, -1.0, 0.25)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.25
	pm.initial_velocity_max = 0.6
	pm.gravity = Vector3(0.1, -0.12, 0.06)
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	pm.color_ramp = VFX._gradient([Color(0.62, 0.58, 0.56, 0.0), Color(0.62, 0.58, 0.56, 0.9),
		Color(0.5, 0.46, 0.45, 0.0)] as Array[Color])
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	quad.material = VFX._particle_material(VFX._tex("dust"))
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	camera_rig.add_child(p)
	p.position = Vector3(0, 2.0, 0)


func _dress_box(body: StaticBody3D, box_mesh: MeshInstance3D, size: Vector3, role: StringName, wild_faces: int) -> void:
	var p := body.global_position
	var seed := int(p.x * 73.0) ^ int(p.z * 151.0) ^ int(p.y * 37.0) ^ int(size.x * 11.0 + size.z * 5.0)
	var hull := MeshInstance3D.new()
	hull.name = "RockHull"
	hull.mesh = RockHull.build(size, seed, 0.3, 0.28, wild_faces)
	hull.material_override = ArtKit.material(role)
	body.add_child(hull)
	box_mesh.visible = false
	_hulls.append(hull)


## Looping ambient sound at a position (or global when pos is INF). Loop
## points live in the WAV's .import (edit/loop_mode = Forward): the old
## runtime loop_end from data.size() was wrong once the importer compressed
## the stream (QOA), cutting every loop short.
func _add_ambience(key: String, pos: Vector3 = Vector3.INF, volume_db: float = -8.0) -> void:
	var path := "res://assets/sfx/%s_01.wav" % key
	if not ResourceLoader.exists(path):
		return
	var stream: AudioStream = load(path)
	if pos == Vector3.INF:
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.volume_db = volume_db
		p.bus = &"Ambience"
		p.autoplay = true
		world.add_child(p)
	else:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = stream
		p3.volume_db = volume_db
		p3.unit_size = 6.0
		p3.max_distance = 30.0
		p3.bus = &"Ambience"
		p3.autoplay = true
		world.add_child(p3)
		p3.global_position = pos


# ---------------------------------------------------------------------------
# Enemies + loot plumbing
# ---------------------------------------------------------------------------

func _spawn_enemy(enemy: EnemyBase, pos: Vector3) -> void:
	enemy.level = _enemy_level(enemy, pos)
	enemies_root.add_child(enemy)
	enemy.global_position = pos
	enemy.player = player
	enemy.enemy_died.connect(_on_enemy_died)


func spawn_by_id(id: String, pos: Vector3) -> EnemyBase:
	if id == "elite":
		return spawn_elite(-1, pos)
	var enemy := make_enemy(id if id in ["caster", "assassin", "brute", "warden"] else "rusher")
	_spawn_enemy(enemy, pos)
	return enemy


func spawn_rusher(pos: Vector3 = Vector3.INF) -> void:
	spawn_by_id("rusher", _resolve_spawn_pos(pos))


func spawn_caster(pos: Vector3 = Vector3.INF) -> void:
	spawn_by_id("caster", _resolve_spawn_pos(pos))


func spawn_assassin(pos: Vector3 = Vector3.INF) -> void:
	spawn_by_id("assassin", _resolve_spawn_pos(pos))


func spawn_brute(pos: Vector3 = Vector3.INF) -> void:
	spawn_by_id("brute", _resolve_spawn_pos(pos))


func spawn_elite(kind: int = -1, pos: Vector3 = Vector3.INF) -> EnemyBase:
	pos = _resolve_spawn_pos(pos)
	var enemy := MeleeRusher.new()
	_spawn_enemy(enemy, pos)
	var modifier := EliteModifier.new()
	modifier.name = "EliteModifier"
	modifier.kind = (randi() % 2 if kind < 0 else kind) as EliteModifier.Kind
	enemy.add_child(modifier)
	return enemy


func _resolve_spawn_pos(pos: Vector3) -> Vector3:
	if pos != Vector3.INF:
		return pos
	var angle := randf() * TAU
	var dist := randf_range(9.0, 18.0)
	return player.global_position + Vector3(cos(angle) * dist, 0.2, sin(angle) * dist)


func _on_enemy_died(enemy: EnemyBase) -> void:
	if player != null and is_instance_valid(player):
		var xp := enemy.xp_reward()
		player.progression.add_xp(xp)
		GameFeel.float_text(enemy.global_position + Vector3(0, 2.2, 0), "+%d XP" % xp,
			ArtKit.color("color_roles.experience.body", Color("#9FB4FF")))
	var item: ItemData = null
	if enemy.is_elite:
		item = ItemGenerator.generate(2)
	elif enemy is Brute:
		if randf() < 0.6:
			item = ItemGenerator.generate(1)
	elif randf() < 0.2:
		item = ItemGenerator.generate(0)
	if item != null:
		ItemGenerator.apply_item_level(item, enemy.level)
		spawn_item_drop(item, enemy.global_position)
	# M07b: every kill pays gold; bosses scatter theirs into several piles.
	var piles := 4 if enemy is ShatteredVessel else (3 if enemy is AshveinColossus else 1)
	spawn_gold_piles(enemy.gold_reward(), enemy.global_position, piles)


func spawn_gold_drop(amount: int, pos: Vector3) -> GoldDrop:
	var drop := GoldDrop.new()
	drop.amount = amount
	drop.player = player
	drop.position = Vector3(pos.x, 0.0, pos.z)
	world.add_child(drop)
	drop.picked_up.connect(func(_amount: int) -> void: SaveGame.request_save())
	return drop


## Splits `amount` into `piles` drops around `pos` (bosses, chests).
func spawn_gold_piles(amount: int, pos: Vector3, piles: int = 1) -> void:
	if amount <= 0:
		return
	piles = clampi(piles, 1, amount)
	var base := amount / piles
	var rest := amount - base * piles
	for i in piles:
		var offset := Vector3.ZERO
		if piles > 1:
			var a := TAU * float(i) / float(piles) + randf_range(-0.3, 0.3)
			offset = Vector3(cos(a), 0.0, sin(a)) * randf_range(0.7, 1.1)
		spawn_gold_drop(base + (1 if i < rest else 0), pos + offset)


func debug_add_gold(amount: int) -> void:
	player.add_gold(amount)
	hud.toast("+%d gold (debug)" % amount, ArtKit.color("color_roles.resonance.hot", Color("#FFD97A")))


func spawn_item_drop(item: ItemData, pos: Vector3) -> ItemDrop:
	var drop := ItemDrop.new()
	drop.item = item
	drop.player = player
	drop.position = Vector3(pos.x, 0.0, pos.z)
	world.add_child(drop)
	drop.picked_up.connect(func(picked: ItemData) -> void:
		hud.toast("[%s] %s" % [ItemData.rarity_name(picked.rarity), picked.display_name],
			ItemData.rarity_color(picked.rarity))
		SaveGame.request_save()
	)
	return drop


func debug_drop_item(legendary: bool) -> void:
	var item := ItemGenerator.generate_legendary() if legendary else ItemGenerator.generate(1)
	var offset := Vector3(randf_range(-1.5, 1.5), 0, randf_range(-2.5, -1.5))
	spawn_item_drop(item, player.global_position + player.facing() * 2.0 + offset)


# ---------------------------------------------------------------------------
# Debug-overlay hooks
# ---------------------------------------------------------------------------

func enemy_count() -> int:
	return enemies_root.get_child_count()


func kill_all_enemies() -> void:
	for child in enemies_root.get_children():
		var enemy := child as EnemyBase
		if enemy != null and enemy.ai_state != EnemyBase.AIState.DEAD:
			enemy.take_hit(HitInfo.create(99999.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, enemy.global_position))


func heal_player() -> void:
	player.health.heal_full()


func toggle_god_mode() -> void:
	player.god_mode = not player.god_mode


func reset_cooldowns() -> void:
	player.reset_cooldowns()
	player.gain_resonance(player.max_resource())


func reset_lab() -> void:
	for child in enemies_root.get_children():
		child.queue_free()
	player.global_position = _player_spawn_point()
	player.velocity = Vector3.ZERO
	player.health.heal_full()
	player.resonance = 0.0
	player.resonance_changed.emit(0.0, player.max_resource())
	player.reset_cooldowns()


func stress_test() -> void:
	for i in 6:
		spawn_rusher()
	for i in 3:
		spawn_caster()
	for i in 2:
		spawn_assassin()
	spawn_brute()
	spawn_elite()


## Debug [9] (F1 overlay): a real fresh start. Clears the live character too
## (gear, inventory, level, talents) and world flags, deletes the save, then
## reloads Runehold. Wiping only the file kept the items in memory, and the
## next save wrote them straight back.
func wipe_save() -> void:
	player.equipment.inventory.clear()
	player.equipment.equipped.clear()
	player.equipment._recompute()
	player.equipment.changed.emit()
	player.progression.from_dict({})
	SaveGame.wipe()
	hud.toast("Fresh start: save, gear, level and flags wiped", Color(1, 0.4, 0.4))
	if DisplayServer.get_name() != "headless":
		get_tree().change_scene_to_file.call_deferred("res://scenes/hub.tscn")


func cycle_style() -> void:
	style_manager.cycle()


# ---------------------------------------------------------------------------
# Zone travel
# ---------------------------------------------------------------------------

func travel_to(scene_path: String) -> void:
	if _travelling:
		return
	_travelling = true
	SaveGame.current_zone = scene_path
	SaveGame.save_now()
	Sfx.play_ui("portal_travel", -4.0)
	if MusicDirector.instance != null:
		MusicDirector.instance.stop(0.5)
	# Fade out, then swap scenes.
	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 20
	add_child(fade_layer)
	var fade := ColorRect.new()
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.color = Color(0.02, 0.01, 0.04, 0.0)
	fade_layer.add_child(fade)
	var tw := fade.create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.35)
	tw.tween_callback(func() -> void:
		get_tree().change_scene_to_file(scene_path)
	)
