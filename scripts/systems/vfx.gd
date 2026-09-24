class_name VFX
extends Object
## Static factory for RUNEBOUND's pixel-fantasy combat effects.
## All effects are one-shot, self-freeing, and built from small pixel sprites
## (see tools/texgen) so the VFX language stays chunky and readable.

const TEX_DIR := "res://assets/vfx/"
const THREAT_SHADER := preload("res://shaders/threat_marker.gdshader")
const PLAYER_RING_SHADER := preload("res://shaders/player_ring.gdshader")
## Enemy threat markers sort over every other transparent ground effect.
const THREAT_PRIORITY := 10
## ART_BIBLE: player ground effects keep capped opacity (never telegraph-loud).
const PLAYER_GROUND_ALPHA := 0.7

static var _tex_cache: Dictionary = {}
static var _mat_cache: Dictionary = {}
static var _gradient_cache: Dictionary = {}
static var _quad_cache: Dictionary = {}
static var _arc_cache: Dictionary = {}

## Perf A/B (LookDev "vfx_cpu"): CPU bursts need no per-feature particle
## process shader, so a session's first Ember / Earthbreaker no longer
## compiles one mid-fight. GPU bursts stay available for comparison.
static var use_cpu: bool = true
static var _lookdev_ready: bool = false


static func _ensure_lookdev() -> void:
	if _lookdev_ready:
		return
	_lookdev_ready = true
	LookDev.register(&"vfx_cpu", func(v: Variant) -> void: VFX.use_cpu = bool(v), true)


## Shutdown (GameFeel._exit_tree): statics holding GPU resources are cleared.
static func clear_caches() -> void:
	_tex_cache.clear()
	_mat_cache.clear()
	_gradient_cache.clear()
	_quad_cache.clear()
	_arc_cache.clear()
	_lookdev_ready = false
	EnemyBolt.clear_meshes()


static func _tex(name: String) -> Texture2D:
	if _tex_cache.has(name):
		return _tex_cache[name]
	var path := TEX_DIR + name + ".png"
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	if tex == null:
		# Fallback: 8x8 white square so effects still read before texgen runs.
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		tex = ImageTexture.create_from_image(img)
	_tex_cache[name] = tex
	return tex


static func _particle_material(tex: Texture2D) -> StandardMaterial3D:
	# Cached: fresh materials per burst caused first-use hitches under load.
	if _mat_cache.has(tex):
		return _mat_cache[tex]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.35
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.disable_receive_shadows = true
	_mat_cache[tex] = mat
	return mat


static func _gradient(colors: Array[Color]) -> GradientTexture1D:
	var key := ""
	for c in colors:
		key += c.to_html()
	if _gradient_cache.has(key):
		return _gradient_cache[key]
	var g := Gradient.new()
	var pts := colors.size()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in pts:
		offs.append(float(i) / float(maxi(pts - 1, 1)))
		cols.append(colors[i])
	g.offsets = offs
	g.colors = cols
	var gt := GradientTexture1D.new()
	gt.gradient = g
	gt.width = 32
	_gradient_cache[key] = gt
	return gt


## Particle quad with the burst material, shared per sprite and size.
static func _quad(tex_name: String, size: float) -> QuadMesh:
	var key := "%s@%.3f" % [tex_name, size]
	if not _quad_cache.has(key):
		var quad := QuadMesh.new()
		quad.size = Vector2(size, size)
		quad.material = _particle_material(_tex(tex_name))
		_quad_cache[key] = quad
	return _quad_cache[key]


## Generic one-shot burst. Returns the emitter (already added + self-freeing).
static func burst(root: Node, pos: Vector3, cfg: Dictionary) -> Node3D:
	_ensure_lookdev()
	if use_cpu:
		return _burst_cpu(root, pos, cfg)
	return _burst_gpu(root, pos, cfg)


static func _burst_cpu(root: Node, pos: Vector3, cfg: Dictionary) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = cfg.get("explosiveness", 1.0)
	p.amount = cfg.get("amount", 12)
	p.lifetime = cfg.get("lifetime", 0.5)
	p.local_coords = false
	p.direction = cfg.get("direction", Vector3.UP)
	p.spread = cfg.get("spread", 60.0)
	p.initial_velocity_min = cfg.get("vel_min", 3.0)
	p.initial_velocity_max = cfg.get("vel_max", 6.0)
	p.gravity = cfg.get("gravity", Vector3(0, -9.0, 0))
	p.damping_min = cfg.get("damping", 2.0)
	p.damping_max = cfg.get("damping", 2.0) * 1.5
	p.scale_amount_min = cfg.get("scale_min", 0.8)
	p.scale_amount_max = cfg.get("scale_max", 1.4)
	p.color_ramp = _gradient(cfg.get("colors", [Color.WHITE, Color(1, 1, 1, 0)] as Array[Color])).gradient
	if cfg.has("emission_radius"):
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = cfg["emission_radius"]
	p.mesh = _quad(cfg.get("tex", "spark"), cfg.get("size", 0.18))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(p)
	p.global_position = pos
	p.emitting = true
	_free_after(p, p.lifetime + 0.4)
	return p


static func _burst_gpu(root: Node, pos: Vector3, cfg: Dictionary) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = cfg.get("explosiveness", 1.0)
	p.amount = cfg.get("amount", 12)
	p.lifetime = cfg.get("lifetime", 0.5)
	p.local_coords = false

	var pm := ParticleProcessMaterial.new()
	pm.direction = cfg.get("direction", Vector3.UP)
	pm.spread = cfg.get("spread", 60.0)
	pm.initial_velocity_min = cfg.get("vel_min", 3.0)
	pm.initial_velocity_max = cfg.get("vel_max", 6.0)
	pm.gravity = cfg.get("gravity", Vector3(0, -9.0, 0))
	pm.damping_min = cfg.get("damping", 2.0)
	pm.damping_max = cfg.get("damping", 2.0) * 1.5
	pm.scale_min = cfg.get("scale_min", 0.8)
	pm.scale_max = cfg.get("scale_max", 1.4)
	pm.color_ramp = _gradient(cfg.get("colors", [Color.WHITE, Color(1, 1, 1, 0)] as Array[Color]))
	if cfg.has("emission_radius"):
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = cfg["emission_radius"]
	p.process_material = pm

	p.draw_pass_1 = _quad(cfg.get("tex", "spark"), cfg.get("size", 0.18))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	root.add_child(p)
	p.global_position = pos
	p.emitting = true
	_free_after(p, p.lifetime + 0.4)
	return p


## Quick unshaded flash quad that pops and fades. Sells the first frame of impact.
static func flash(root: Node, pos: Vector3, color: Color, size: float = 0.7, duration: float = 0.12, tex_name: String = "flash") -> void:
	var m := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = _tex(tex_name)
	mat.albedo_color = color
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.disable_receive_shadows = true
	mat.no_depth_test = true
	quad.material = mat
	m.mesh = quad
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(m)
	m.global_position = pos
	var tw := m.create_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "scale", Vector3.ONE * 1.6, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, duration)
	tw.chain().tween_callback(m.queue_free)


## Transient impact lights are the most expensive part of a burst on the
## target iGPU and stop adding readability past a handful (a Storm Step used to
## spawn one per 1.4 m of trail) — extra pops are simply skipped.
const MAX_LIGHT_POPS := 6
static var _active_light_pops: int = 0


## Brief point light for hot impacts.
static func light_pop(root: Node, pos: Vector3, color: Color, energy: float = 3.0, radius: float = 5.0, duration: float = 0.18) -> void:
	if _active_light_pops >= MAX_LIGHT_POPS:
		return
	_active_light_pops += 1
	var l := OmniLight3D.new()
	l.tree_exiting.connect(func() -> void: VFX._active_light_pops -= 1)
	l.light_color = color
	l.light_energy = energy
	l.omni_range = radius
	l.shadow_enabled = false
	root.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, duration)
	tw.tween_callback(l.queue_free)


## Expanding broken ring on the ground: the shockwave of an impact that just
## happened (never a telegraph: dashed, short-lived, opacity capped). Drawn by
## the player_ring shader so the dashes stay crisp at any radius.
static func ground_ring(root: Node, pos: Vector3, color: Color, max_radius: float, duration: float = 0.35) -> void:
	var m := _ring_plane(max_radius, Color(color, minf(color.a, PLAYER_GROUND_ALPHA)))
	m.name = "Shockwave"
	root.add_child(m)
	m.global_position = pos + Vector3(0, 0.06, 0)
	var mat := (m.mesh as PlaneMesh).material as ShaderMaterial
	var base: Color = mat.get_shader_parameter(&"color")
	var expand := func(t: float) -> void:
		var e := 1.0 - pow(1.0 - t, 3.0)  # cubic ease-out
		mat.set_shader_parameter(&"ring_m", lerpf(0.25, max_radius, e))
		mat.set_shader_parameter(&"color", Color(base, base.a * clampf((1.0 - t) / 0.65, 0.0, 1.0)))
	var tw := m.create_tween()
	tw.tween_method(expand, 0.0, 1.0, duration)
	tw.tween_callback(m.queue_free)


static func _ring_plane(radius: float, color: Color) -> MeshInstance3D:
	var mat := ShaderMaterial.new()
	mat.shader = PLAYER_RING_SHADER
	mat.set_shader_parameter(&"color", color)
	mat.set_shader_parameter(&"radius_m", radius)
	mat.set_shader_parameter(&"ring_m", radius)
	mat.set_shader_parameter(&"px_per_m", ArtKit.number("texel_density.vfx_px_per_m", 32.0))
	var plane := PlaneMesh.new()
	plane.size = Vector2(radius * 2.0, radius * 2.0)
	plane.material = mat
	var m := MeshInstance3D.new()
	m.mesh = plane
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


## Project a point straight down onto world geometry. Ground effects from
## mid-air impacts (e.g. Ember Lance hitting a chest) must land on the floor,
## not hover — a floating "ground" plane reads as sliding when the camera moves.
static func _ground_point(root: Node, pos: Vector3) -> Vector3:
	var viewport := root.get_viewport()
	if viewport == null:
		return pos
	var world := viewport.find_world_3d()
	if world == null:
		return pos
	var query := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.5, pos + Vector3.DOWN * 12.0, 1)
	var result := world.direct_space_state.intersect_ray(query)
	if result.is_empty():
		return pos
	return result["position"]


## Persistent ground decal (scorch marks, cracks) that slowly fades.
## Always snapped onto the floor below `pos`.
static func decal(root: Node, pos: Vector3, tex_name: String, size: float, color: Color = Color.WHITE, life: float = 6.0) -> void:
	pos = _ground_point(root, pos)
	var m := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = _tex(tex_name)
	mat.albedo_color = color
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.disable_receive_shadows = true
	plane.material = mat
	m.mesh = plane
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(m)
	m.global_position = pos + Vector3(0, 0.03, 0)
	m.rotate_y(randf() * TAU)
	var tw := m.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 1.5).set_delay(life)
	tw.tween_callback(m.queue_free)


# ---------------------------------------------------------------------------
# Named combat effects
# ---------------------------------------------------------------------------

## Horizontal slash arc following the swing plane — reads as the sweep itself.
static func melee_slash(root: Node, pos: Vector3, dir: Vector3, flip: bool) -> void:
	var m := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(3.2, 3.2)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = _tex("slash")
	mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.disable_receive_shadows = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	plane.material = mat
	m.mesh = plane
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(m)
	m.global_position = pos
	var yaw := atan2(-dir.x, -dir.z)
	# Slight tilt toward the shoulder camera: a flat plane reads edge-on.
	m.rotation = Vector3(-0.35, yaw + (0.5 if flip else -0.5), 0)
	m.scale = Vector3(0.6, 0.6, 0.6)
	var spin := -1.6 if flip else 1.6
	var tw := m.create_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "rotation:y", m.rotation.y + spin, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "scale", Vector3.ONE * 1.15, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.12).set_delay(0.06)
	tw.chain().tween_callback(m.queue_free)

static func melee_impact(root: Node, pos: Vector3, dir: Vector3) -> void:
	flash(root, pos, Color(1.0, 0.98, 0.9), 1.0, 0.1)
	light_pop(root, pos, Color(1.0, 0.85, 0.5), 2.0, 3.5, 0.14)
	burst(root, pos, {
		"tex": "spark", "amount": 14, "lifetime": 0.32, "size": 0.24,
		"direction": (dir + Vector3.UP * 0.6).normalized(), "spread": 50.0,
		"vel_min": 5.0, "vel_max": 10.0, "gravity": Vector3(0, -14, 0),
		"colors": [Color(1, 0.95, 0.7), Color(1, 0.6, 0.25), Color(0.7, 0.3, 0.2, 0.0)] as Array[Color],
	})
	burst(root, pos, {
		"tex": "dust", "amount": 5, "lifetime": 0.45, "size": 0.3,
		"direction": dir.normalized(), "spread": 70.0,
		"vel_min": 1.0, "vel_max": 2.5, "gravity": Vector3(0, 1.0, 0), "damping": 3.0,
		"colors": [Color(0.85, 0.8, 0.75, 0.7), Color(0.6, 0.55, 0.5, 0.0)] as Array[Color],
	})


static func enemy_hit(root: Node, pos: Vector3, color: Color = Color(1.0, 0.35, 0.3)) -> void:
	flash(root, pos, Color(1, 1, 1), 0.35, 0.08)
	burst(root, pos, {
		"tex": "spark", "amount": 6, "lifetime": 0.25, "size": 0.12,
		"spread": 80.0, "vel_min": 3.0, "vel_max": 5.0,
		"colors": [Color.WHITE, color, Color(color.r, color.g, color.b, 0.0)] as Array[Color],
	})


## Death = the 0.22 s gameplay shrink dressed as burning out: body-coloured
## shards drop, pixel ash drifts up with a few embers (no soft smoke clouds).
static func death_burst(root: Node, pos: Vector3, color: Color) -> void:
	flash(root, pos, color.lightened(0.4), 1.0, 0.14)
	light_pop(root, pos, color, 2.0, 3.5, 0.2)
	burst(root, pos, {
		"tex": "shard", "amount": 10, "lifetime": 0.55, "size": 0.2,
		"spread": 85.0, "vel_min": 4.0, "vel_max": 7.5, "gravity": Vector3(0, -18, 0),
		"emission_radius": 0.3,
		"colors": [color.lightened(0.3), color, Color(color.r * 0.5, color.g * 0.5, color.b * 0.5, 0.0)] as Array[Color],
	})
	burst(root, pos, {
		"tex": "dust", "amount": 16, "lifetime": 1.1, "size": 0.12,
		"direction": Vector3.UP, "spread": 70.0, "vel_min": 0.8, "vel_max": 2.2,
		"gravity": Vector3(0, 0.9, 0), "damping": 1.2, "emission_radius": 0.35,
		"colors": [Color(0.62, 0.57, 0.55, 0.95), Color(0.4, 0.36, 0.36, 0.8), Color(0.25, 0.22, 0.24, 0.0)] as Array[Color],
	})
	burst(root, pos, {
		"tex": "ember", "amount": 6, "lifetime": 0.8, "size": 0.08,
		"direction": Vector3.UP, "spread": 50.0, "vel_min": 1.0, "vel_max": 2.6,
		"gravity": Vector3(0, 1.4, 0), "emission_radius": 0.3,
		"colors": [ArtKit.color("color_roles.fire.core"), ArtKit.color("color_roles.fire.body"),
			Color(ArtKit.color("color_roles.fire.edge"), 0.0)] as Array[Color],
	})


static func dodge_dust(root: Node, pos: Vector3, dir: Vector3) -> void:
	burst(root, pos + Vector3(0, 0.15, 0), {
		"tex": "dust", "amount": 8, "lifetime": 0.4, "size": 0.28,
		"direction": (-dir + Vector3.UP * 0.4).normalized(), "spread": 35.0,
		"vel_min": 1.5, "vel_max": 3.0, "gravity": Vector3(0, 1.5, 0), "damping": 3.5,
		"colors": [Color(0.8, 0.78, 0.72, 0.8), Color(0.55, 0.5, 0.48, 0.0)] as Array[Color],
	})


static func ember_cast(root: Node, pos: Vector3) -> void:
	flash(root, pos, Color(1.0, 0.7, 0.3), 0.5, 0.1, "glyph")
	burst(root, pos, {
		"tex": "ember", "amount": 6, "lifetime": 0.3, "size": 0.1,
		"spread": 90.0, "vel_min": 1.0, "vel_max": 2.5, "gravity": Vector3(0, 2.0, 0),
		"colors": [Color(1, 0.9, 0.5), Color(1, 0.5, 0.15, 0.0)] as Array[Color],
	})


static func ember_impact(root: Node, pos: Vector3) -> void:
	flash(root, pos, Color(1.0, 0.95, 0.7), 1.6, 0.14)
	flash(root, pos, Color(1.0, 0.6, 0.2, 0.9), 2.4, 0.2)
	light_pop(root, pos, Color(1.0, 0.55, 0.2), 6.0, 8.0, 0.28)
	ground_ring(root, _ground_point(root, pos), Color(1.0, 0.7, 0.3, 0.9), 1.6, 0.28)
	burst(root, pos, {
		"tex": "ember", "amount": 26, "lifetime": 0.55, "size": 0.2,
		"spread": 85.0, "vel_min": 4.0, "vel_max": 9.0, "gravity": Vector3(0, -5, 0),
		"emission_radius": 0.2,
		"colors": [Color(1, 0.95, 0.6), Color(1, 0.55, 0.15), Color(0.6, 0.15, 0.1, 0.0)] as Array[Color],
	})
	burst(root, pos, {
		"tex": "spark", "amount": 8, "lifetime": 0.3, "size": 0.22,
		"spread": 90.0, "vel_min": 6.0, "vel_max": 11.0, "gravity": Vector3(0, -8, 0),
		"colors": [Color(1, 1, 0.9), Color(1, 0.7, 0.3, 0.0)] as Array[Color],
	})
	burst(root, pos, {
		"tex": "smoke", "amount": 5, "lifetime": 0.6, "size": 0.42,
		"direction": Vector3.UP, "spread": 40.0,
		"vel_min": 0.8, "vel_max": 1.6, "gravity": Vector3(0, 1.8, 0), "damping": 2.0,
		"colors": [Color(0.35, 0.25, 0.28, 0.7), Color(0.2, 0.15, 0.18, 0.0)] as Array[Color],
	})
	decal(root, pos, "scorch", 1.4, Color(1, 1, 1, 0.85), 5.0)


static func burn_tick(root: Node, pos: Vector3) -> void:
	burst(root, pos, {
		"tex": "ember", "amount": 4, "lifetime": 0.4, "size": 0.1,
		"direction": Vector3.UP, "spread": 30.0,
		"vel_min": 0.8, "vel_max": 1.6, "gravity": Vector3(0, 2.5, 0),
		"colors": [Color(1, 0.8, 0.4), Color(1, 0.4, 0.1, 0.0)] as Array[Color],
	})


static func earthbreaker_slam(root: Node, pos: Vector3, radius: float) -> void:
	flash(root, pos + Vector3(0, 0.3, 0), Color(1.0, 0.9, 0.7), 1.4, 0.14)
	light_pop(root, pos, Color(1.0, 0.75, 0.4), 5.0, radius * 2.0, 0.3)
	# physical element: off-white shockwave, a warm inner echo
	ground_ring(root, pos, ArtKit.color("color_roles.physical.body"), radius, 0.4)
	ground_ring(root, pos, Color(0.9, 0.6, 0.3, 0.5), radius * 0.7, 0.3)
	burst(root, pos + Vector3(0, 0.2, 0), {
		"tex": "shard", "amount": 18, "lifetime": 0.7, "size": 0.26,
		"direction": Vector3.UP, "spread": 55.0,
		"vel_min": 5.0, "vel_max": 10.0, "gravity": Vector3(0, -22, 0),
		"emission_radius": radius * 0.4,
		"colors": [Color(0.75, 0.6, 0.45), Color(0.5, 0.4, 0.32), Color(0.3, 0.25, 0.2, 0.0)] as Array[Color],
	})
	burst(root, pos, {
		"tex": "dust", "amount": 14, "lifetime": 0.8, "size": 0.5,
		"direction": Vector3.UP, "spread": 80.0,
		"vel_min": 2.0, "vel_max": 4.0, "gravity": Vector3(0, 0.5, 0), "damping": 2.5,
		"emission_radius": radius * 0.5,
		"colors": [Color(0.7, 0.62, 0.5, 0.8), Color(0.45, 0.4, 0.34, 0.0)] as Array[Color],
	})
	decal(root, pos, "cracks", radius * 1.6, Color(1, 1, 1, 0.9), 6.0)


## Unit box with a shared lightning material (core or fringe) per colour.
static func _arc_box(color: Color, core: bool) -> BoxMesh:
	var key := "%s_%s" % [color.to_html(), core]
	if _arc_cache.has(key):
		return _arc_cache[key]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.disable_receive_shadows = true
	mat.disable_fog = true  # lightning is instant and bright, even in haze
	if core:
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 3.0
	else:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_color = Color(color, 0.6)
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	box.material = mat
	_arc_cache[key] = box
	return box


## One jagged polyline of core + fringe segments under `holder`.
static func _arc_line(holder: Node3D, points: Array[Vector3], core_color: Color, fringe_color: Color, thick: float) -> void:
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var seg_len := a.distance_to(b)
		if seg_len < 0.01:
			continue
		for layer: Array in [[fringe_color, false, thick * 2.8], [core_color, true, thick]]:
			var seg := MeshInstance3D.new()
			seg.mesh = _arc_box(layer[0], layer[1])
			seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			holder.add_child(seg)
			seg.global_position = (a + b) * 0.5
			if absf((b - a).normalized().dot(Vector3.UP)) < 0.99:
				seg.look_at(b, Vector3.UP)
			var base := Vector3(layer[2], layer[2], seg_len)
			seg.scale = base
			seg.set_meta(&"base", base)


## Jagged, branching lightning arc: a white-hot core inside a violet-blue
## fringe (ART_BIBLE lightning), gone in ~0.2 s by thinning out. The core
## readable element of Chain Spark and Storm Step. Meshes and materials are
## shared per colour, so arcs never compile or allocate mid-fight.
static func lightning_arc(root: Node, from: Vector3, to: Vector3, color: Color = Color(1.0, 0.95, 0.5)) -> void:
	var length := from.distance_to(to)
	if length < 0.1:
		return
	var holder := Node3D.new()
	root.add_child(holder)
	var fringe := ArtKit.color("color_roles.lightning.edge", Color(0.49, 0.55, 1.0))
	var core := color.lerp(Color.WHITE, 0.35)
	var segments := maxi(int(length / 0.7), 2)
	var points: Array[Vector3] = [from]
	for i in segments:
		var p := from.lerp(to, float(i + 1) / float(segments))
		if i < segments - 1:
			p += Vector3(randf_range(-0.3, 0.3), randf_range(-0.25, 0.25), randf_range(-0.3, 0.3))
		points.append(p)
	_arc_line(holder, points, core, fringe, 0.05)
	# one or two short forks off interior joints
	for k in (1 if length < 3.0 else 2):
		var j := randi_range(1, points.size() - 2) if points.size() > 2 else 0
		var start := points[j]
		var off := Vector3(randf_range(-1, 1), randf_range(-0.2, 0.6), randf_range(-1, 1)).normalized() * randf_range(0.35, 0.7)
		var mid := start + off * 0.5 + Vector3(randf_range(-0.1, 0.1), randf_range(-0.1, 0.1), randf_range(-0.1, 0.1))
		_arc_line(holder, [start, mid, start + off] as Array[Vector3], core, fringe, 0.03)
	light_pop(root, to, color, 2.0, 4.0, 0.15)
	var thin_out := func(t: float) -> void:
		for seg in holder.get_children():
			var base: Vector3 = seg.get_meta(&"base")
			(seg as Node3D).scale = Vector3(base.x * t, base.y * t, base.z)
	var tw := holder.create_tween()
	tw.tween_interval(0.05)
	tw.tween_method(thin_out, 1.0, 0.0, 0.16)
	tw.tween_callback(holder.queue_free)


## Lightning dash trail: arcs skimming the ground along the dash path.
static func storm_trail(root: Node, from: Vector3, to: Vector3) -> void:
	var steps := maxi(int(from.distance_to(to) / 1.4), 2)
	for i in steps:
		var t := float(i) / float(steps - 1)
		var pos := from.lerp(to, t) + Vector3(0, 0.25, 0)
		var jitter := Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4))
		lightning_arc(root, pos + jitter, pos + Vector3(randf_range(-0.6, 0.6), randf_range(0.3, 0.9), randf_range(-0.6, 0.6)),
			Color(0.75, 0.85, 1.0))
	burst(root, from.lerp(to, 0.5) + Vector3(0, 0.4, 0), {
		"tex": "spark", "amount": 12, "lifetime": 0.35, "size": 0.16,
		"spread": 90.0, "vel_min": 2.0, "vel_max": 5.0, "emission_radius": from.distance_to(to) * 0.4,
		"colors": [Color(1, 1, 0.9), Color(0.6, 0.7, 1.0, 0.0)] as Array[Color],
	})


## Crystalline frost explosion (Fracture Rune detonation).
static func frost_burst(root: Node, pos: Vector3, radius: float) -> void:
	flash(root, pos + Vector3(0, 0.4, 0), Color(0.8, 0.97, 1.0), 1.6, 0.14)
	light_pop(root, pos, Color(0.5, 0.85, 1.0), 5.0, radius * 2.0, 0.25)
	ground_ring(root, pos, Color(0.55, 0.9, 1.0, 0.9), radius, 0.35)
	burst(root, pos + Vector3(0, 0.3, 0), {
		"tex": "shard", "amount": 20, "lifetime": 0.6, "size": 0.24,
		"direction": Vector3.UP, "spread": 65.0,
		"vel_min": 4.0, "vel_max": 8.5, "gravity": Vector3(0, -16, 0),
		"emission_radius": radius * 0.35,
		"colors": [Color(0.95, 1.0, 1.0), Color(0.55, 0.85, 1.0), Color(0.3, 0.5, 0.8, 0.0)] as Array[Color],
	})
	burst(root, pos, {
		"tex": "dust", "amount": 10, "lifetime": 0.7, "size": 0.4,
		"direction": Vector3.UP, "spread": 80.0,
		"vel_min": 1.0, "vel_max": 2.2, "gravity": Vector3(0, 0.6, 0), "damping": 2.5,
		"emission_radius": radius * 0.4,
		"colors": [Color(0.75, 0.9, 1.0, 0.7), Color(0.5, 0.65, 0.85, 0.0)] as Array[Color],
	})


static func chill_tick(root: Node, pos: Vector3) -> void:
	burst(root, pos, {
		"tex": "shard", "amount": 3, "lifetime": 0.5, "size": 0.1,
		"direction": Vector3.UP, "spread": 40.0,
		"vel_min": 0.3, "vel_max": 0.8, "gravity": Vector3(0, -1.0, 0),
		"colors": [Color(0.8, 0.95, 1.0, 0.9), Color(0.5, 0.7, 0.9, 0.0)] as Array[Color],
	})


static func shock_tick(root: Node, pos: Vector3) -> void:
	burst(root, pos, {
		"tex": "spark", "amount": 3, "lifetime": 0.2, "size": 0.13,
		"spread": 90.0, "vel_min": 1.5, "vel_max": 3.0,
		"colors": [Color(1, 1, 0.7), Color(1, 0.9, 0.4, 0.0)] as Array[Color],
	})


## Attach a looping particle trail to a projectile; freed with its parent.
## CPU particles (no process shader to compile on the first cast).
static func attach_trail(parent: Node3D, tex_name: String, colors: Array[Color], amount: int = 48, size: float = 0.18) -> void:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 0.45
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.4
	p.gravity = Vector3(0, 1.2, 0)
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.6
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.15
	p.color_ramp = _gradient(colors).gradient
	p.mesh = _quad(tex_name, size)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)


static func attach_ember_trail(parent: Node3D) -> void:
	attach_trail(parent, "ember", [ArtKit.color("color_roles.fire.core"), ArtKit.color("color_roles.fire.body"),
		Color(ArtKit.color("color_roles.fire.edge"), 0.0)] as Array[Color])


## Enemy threat disc under a wind-up (ART_BIBLE telegraph): crimson area with
## a near-white rim; the fill grows from the centre to the rim over
## `duration` = visible progress to the strike. Fog-exempt, sorted on top.
## The only red, filled shape in the game — player effects never use it.
static func telegraph_disc(root: Node, pos: Vector3, radius: float, duration: float) -> MeshInstance3D:
	var m := _threat_plane(Vector2(radius * 2.0, radius * 2.0), 0)
	root.add_child(m)
	m.global_position = pos + Vector3(0, 0.05, 0)
	_run_progress(m, &"progress", duration)
	return m


## Enemy threat lane (charges): same language, filling from the attacker
## toward the far end over `duration`.
static func telegraph_lane(root: Node, start: Vector3, dir: Vector3, length: float, width: float, duration: float) -> MeshInstance3D:
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	var m := _threat_plane(Vector2(width, length), 1)
	root.add_child(m)
	m.global_position = Vector3(start.x, 0.05, start.z) + flat * length * 0.5
	m.rotation.y = atan2(-flat.x, -flat.z)
	_run_progress(m, &"progress", duration)
	return m


## Expanding enemy shockwave band (Vessel): the same threat language as a
## ring. The caller drives the radius (`ring_r`) from its own gameplay tween,
## so what is drawn is exactly the band that hits (+- half_width).
static func threat_ring(root: Node, center: Vector3, max_radius: float, half_width: float) -> MeshInstance3D:
	var size := Vector2.ONE * (max_radius + half_width) * 2.0
	var m := _threat_plane(size, 2)
	var mat := (m.mesh as PlaneMesh).material as ShaderMaterial
	mat.set_shader_parameter(&"ring_w", half_width)
	mat.set_shader_parameter(&"ring_r", 0.0)
	root.add_child(m)
	m.global_position = center + Vector3(0, 0.05, 0)
	return m


static func set_threat_ring(m: MeshInstance3D, radius: float) -> void:
	((m.mesh as PlaneMesh).material as ShaderMaterial).set_shader_parameter(&"ring_r", radius)


static func _threat_plane(size: Vector2, shape: int) -> MeshInstance3D:
	var body := ArtKit.color("color_roles.threat.body", Color(0.91, 0.157, 0.235))
	var mat := ShaderMaterial.new()
	mat.shader = THREAT_SHADER
	mat.render_priority = THREAT_PRIORITY
	mat.set_shader_parameter(&"shape", shape)
	mat.set_shader_parameter(&"size_m", size)
	mat.set_shader_parameter(&"base_color", Color(body, 0.2))
	mat.set_shader_parameter(&"fill_color", Color(body, 0.55))
	mat.set_shader_parameter(&"rim_color", ArtKit.color("color_roles.threat.rim", Color(1.0, 0.957, 0.941)))
	mat.set_shader_parameter(&"px_per_m", ArtKit.number("texel_density.vfx_px_per_m", 32.0))
	var plane := PlaneMesh.new()
	plane.size = size
	plane.material = mat
	var m := MeshInstance3D.new()
	m.name = "ThreatMarker"
	m.mesh = plane
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


## Player ground marker (e.g. Fracture Rune arming): a broken ring whose
## dashes light up one by one over `duration`. Never a filled disc — that
## shape belongs to enemy danger. Opacity capped (PLAYER_GROUND_ALPHA).
static func player_ring(root: Node, pos: Vector3, radius: float, duration: float, color: Color) -> MeshInstance3D:
	var m := _ring_plane(radius, Color(color, minf(color.a, PLAYER_GROUND_ALPHA)))
	m.name = "PlayerRing"
	((m.mesh as PlaneMesh).material as ShaderMaterial).set_shader_parameter(&"lit", 0.0)
	root.add_child(m)
	m.global_position = pos + Vector3(0, 0.04, 0)
	_run_progress(m, &"lit", duration)
	return m


## Tweens a marker's shader progress parameter 0 -> 1, then frees it.
static func _run_progress(m: MeshInstance3D, param: StringName, duration: float) -> void:
	var mat := (m.mesh as PlaneMesh).material as ShaderMaterial
	var tw := m.create_tween()
	tw.tween_method(func(t: float) -> void: mat.set_shader_parameter(param, t), 0.0, 1.0, duration)
	tw.tween_callback(m.queue_free)


## Draw every effect once at `hidden` so shader variants and pipelines compile
## at zone start instead of on the first cast mid-fight. `hidden` must lie
## INSIDE the camera frustum (culled draws compile nothing) but under the
## floor surface, e.g. a few metres ahead of the camera, 0.5 m down.
static func warm_up(root: Node, hidden: Vector3) -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	holder.global_position = hidden
	EnemyBolt.build_visual(holder)
	_free_after(holder, 0.3)
	# Forward+ specialises pipelines by the light types touching a draw: one
	# pop that reaches the player and the ground compiles the omni-lit
	# variants before the first impact light of a fight does.
	light_pop(root, hidden + Vector3(0, 1.0, 0), Color.WHITE, 0.05, 8.0, 0.2)
	burst(root, hidden, {"tex": "spark", "amount": 2, "lifetime": 0.1})
	burst(root, hidden, {"tex": "dust", "amount": 2, "lifetime": 0.1, "emission_radius": 0.2})
	flash(root, hidden, Color.WHITE, 0.3, 0.1)
	ground_ring(root, hidden, Color.WHITE, 1.0, 0.1)
	decal(root, hidden, "scorch", 1.0, Color.WHITE, 0.1)
	lightning_arc(root, hidden, hidden + Vector3(0, 0, 2))
	telegraph_disc(root, hidden, 1.0, 0.1)
	_free_after(threat_ring(root, hidden, 1.0, 0.3), 0.1)
	player_ring(root, hidden, 1.0, 0.1, Color.WHITE)


static func _free_after(node: Node, seconds: float) -> void:
	var timer := node.get_tree().create_timer(seconds) if node.is_inside_tree() else null
	if timer == null:
		node.queue_free()
		return
	# Weakref: SceneTreeTimers outlive nodes (zone travel frees effects early),
	# and a lambda capturing a freed node makes the engine log an error.
	var ref: WeakRef = weakref(node)
	timer.timeout.connect(func() -> void:
		var n: Node = ref.get_ref()
		if n != null:
			n.queue_free()
	)
