class_name VFX
extends Object
## Static factory for RUNEBOUND's pixel-fantasy combat effects.
## All effects are one-shot, self-freeing, and built from small pixel sprites
## (see tools/texgen) so the VFX language stays chunky and readable.

const TEX_DIR := "res://assets/vfx/"

static var _tex_cache: Dictionary = {}
static var _mat_cache: Dictionary = {}
static var _gradient_cache: Dictionary = {}


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


## Generic one-shot burst. Returns the emitter (already added + self-freeing).
static func burst(root: Node, pos: Vector3, cfg: Dictionary) -> GPUParticles3D:
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

	var quad := QuadMesh.new()
	var size: float = cfg.get("size", 0.18)
	quad.size = Vector2(size, size)
	quad.material = _particle_material(_tex(cfg.get("tex", "spark")))
	p.draw_pass_1 = quad

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
	root.add_child(m)
	m.global_position = pos
	var tw := m.create_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "scale", Vector3.ONE * 1.6, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, duration)
	tw.chain().tween_callback(m.queue_free)


## Brief point light for hot impacts.
static func light_pop(root: Node, pos: Vector3, color: Color, energy: float = 3.0, radius: float = 5.0, duration: float = 0.18) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = radius
	l.shadow_enabled = false
	root.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, duration)
	tw.tween_callback(l.queue_free)


## Expanding flat ring on the ground (shockwaves, telegraphs that pop).
static func ground_ring(root: Node, pos: Vector3, color: Color, max_radius: float, duration: float = 0.35) -> void:
	var m := MeshInstance3D.new()
	var quad := PlaneMesh.new()
	quad.size = Vector2(1, 1)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.3
	mat.albedo_texture = _tex("ring")
	mat.albedo_color = color
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.disable_receive_shadows = true
	quad.material = mat
	m.mesh = quad
	root.add_child(m)
	m.global_position = pos + Vector3(0, 0.06, 0)
	m.scale = Vector3.ONE * 0.2
	var tw := m.create_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "scale", Vector3(max_radius * 2.0, 1.0, max_radius * 2.0), duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, duration).set_delay(duration * 0.35)
	tw.chain().tween_callback(m.queue_free)


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


static func death_burst(root: Node, pos: Vector3, color: Color) -> void:
	flash(root, pos, color.lightened(0.4), 1.1, 0.16)
	light_pop(root, pos, color, 2.5, 4.0, 0.25)
	burst(root, pos, {
		"tex": "shard", "amount": 14, "lifetime": 0.6, "size": 0.22,
		"spread": 85.0, "vel_min": 4.0, "vel_max": 8.0, "gravity": Vector3(0, -18, 0),
		"emission_radius": 0.3,
		"colors": [color.lightened(0.3), color, Color(color.r * 0.5, color.g * 0.5, color.b * 0.5, 0.0)] as Array[Color],
	})
	burst(root, pos, {
		"tex": "dust", "amount": 8, "lifetime": 0.7, "size": 0.4,
		"spread": 90.0, "vel_min": 1.0, "vel_max": 2.0, "gravity": Vector3(0, 0.5, 0), "damping": 2.5,
		"colors": [Color(0.4, 0.35, 0.45, 0.6), Color(0.25, 0.2, 0.3, 0.0)] as Array[Color],
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
	ground_ring(root, pos, Color(1.0, 0.8, 0.45), radius, 0.4)
	ground_ring(root, pos, Color(0.9, 0.6, 0.3, 0.7), radius * 0.7, 0.3)
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


## Jagged lightning arc between two points: thin emissive segments with
## jittered midpoints, quick fade. The core readable element of Chain Spark.
static func lightning_arc(root: Node, from: Vector3, to: Vector3, color: Color = Color(1.0, 0.95, 0.5)) -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.0
	mat.disable_receive_shadows = true

	var dir := to - from
	var length := dir.length()
	if length < 0.1:
		holder.queue_free()
		return
	var segments := maxi(int(length / 0.7), 2)
	var prev := from
	for i in segments:
		var t := float(i + 1) / float(segments)
		var point := from.lerp(to, t)
		if i < segments - 1:
			point += Vector3(randf_range(-0.3, 0.3), randf_range(-0.25, 0.25), randf_range(-0.3, 0.3))
		var seg := MeshInstance3D.new()
		var box := BoxMesh.new()
		var seg_len := prev.distance_to(point)
		box.size = Vector3(0.06, 0.06, seg_len)
		box.material = mat
		seg.mesh = box
		holder.add_child(seg)
		seg.global_position = (prev + point) * 0.5
		if seg_len > 0.01 and absf((point - prev).normalized().dot(Vector3.UP)) < 0.99:
			seg.look_at(point, Vector3.UP)
		prev = point
	light_pop(root, to, color, 2.0, 4.0, 0.15)
	var tw := holder.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.18).set_delay(0.05)
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


## Attach a looping ember trail to a projectile; freed with its parent.
static func attach_ember_trail(parent: Node3D) -> void:
	var p := GPUParticles3D.new()
	p.amount = 48
	p.lifetime = 0.45
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.ZERO
	pm.spread = 180.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.4
	pm.gravity = Vector3(0, 1.2, 0)
	pm.scale_min = 0.8
	pm.scale_max = 1.6
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.15
	pm.color_ramp = _gradient([Color(1, 0.9, 0.55), Color(1, 0.5, 0.15), Color(0.5, 0.1, 0.05, 0.0)] as Array[Color])
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.18, 0.18)
	quad.material = _particle_material(_tex("ember"))
	p.draw_pass_1 = quad
	parent.add_child(p)


## Telegraph disc shown under an enemy wind-up or ground-targeted attack.
static func telegraph_disc(root: Node, pos: Vector3, radius: float, duration: float, color: Color = Color(1.0, 0.3, 0.2, 0.5)) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(radius * 2.0, radius * 2.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = _tex("telegraph")
	mat.albedo_color = color
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.disable_receive_shadows = true
	plane.material = mat
	m.mesh = plane
	root.add_child(m)
	m.global_position = pos + Vector3(0, 0.05, 0)
	var tw := m.create_tween()
	tw.tween_property(mat, "albedo_color:a", color.a * 1.6, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(m.queue_free)
	return m


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
