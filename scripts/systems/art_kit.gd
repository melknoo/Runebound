class_name ArtKit
extends Object
## Shared look library (M06): reads assets/art_spec.json once and hands out
## materials by role, so every surface of a biome shares one texel density,
## palette and lighting model. Static like VFX — no autoload.

const SPEC_PATH := "res://assets/art_spec.json"
const TERRAIN_SHADER := preload("res://shaders/terrain_pixel.gdshader")
const BIOME_DIR := "res://assets/textures/biome/"

static var _spec: Dictionary = {}
static var _materials: Dictionary = {}


static func spec() -> Dictionary:
	if _spec.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SPEC_PATH))
		_spec = parsed if parsed is Dictionary else {}
	return _spec


## Spec lookup by dotted path, e.g. "palettes.highlands.sky.top" or
## "color_roles.threat.body"; ramps accept an index suffix ("...ash_ground.2").
static func color(path: String, fallback: Color = Color.MAGENTA) -> Color:
	var node: Variant = spec()
	for key in path.split("."):
		if node is Dictionary and (node as Dictionary).has(key):
			node = node[key]
		elif node is Array and key.is_valid_int() and int(key) < (node as Array).size():
			node = node[int(key)]
		else:
			return fallback
	return Color(node) if node is String else fallback


static func number(path: String, fallback: float) -> float:
	var node: Variant = spec()
	for key in path.split("."):
		if node is Dictionary and (node as Dictionary).has(key):
			node = node[key]
		else:
			return fallback
	return float(node) if (node is float or node is int) else fallback


## Environment material by role. Cached: every surface of a role shares one
## material (the terrain shader needs no per-instance state).
static func material(role: StringName) -> Material:
	if _materials.has(role):
		return _materials[role]
	var mat: Material
	match role:
		&"highlands_ground":
			mat = terrain_material("hl_ash_a", "hl_ash_b", "hl_basalt", {
				"layer_b_amount": 0.38, "ember_density": 0.004,
				"ember_color": color("color_roles.env_emissive.body"),
				"ember_energy": number("emissive_caps.environment", 0.8)})
		&"highlands_rock":
			# Ledge tops read as ash (slope blend), sides as layered rock.
			mat = terrain_material("hl_ash_top", "hl_ash_a", "hl_strata", {
				"layer_b_amount": 0.25, "ember_density": 0.0, "slope_top": 0.6})
		&"runehold_ground":
			# Packed earth with grass patches; plazas/paths via paved().
			mat = terrain_material("rh_earth", "rh_turf", "rh_masonry", {
				"layer_b_amount": 0.5, "ember_density": 0.0, "macro_scale": 0.05,
				"paving": load(BIOME_DIR + "rh_flagstone.png")})
		&"runehold_meadow":
			mat = terrain_material("rh_turf", "rh_moss", "rh_earth", {
				"layer_b_amount": 0.3, "ember_density": 0.0})
		&"runehold_wall":
			# Coursed granite sides (world V = height), weathered granite caps.
			mat = terrain_material("rh_granite_top", "rh_moss", "rh_masonry", {
				"layer_b_amount": 0.18, "ember_density": 0.0, "slope_top": 0.6})
		&"runehold_roof":
			# Sod roofs: turf on the low slopes, earth on the thick eaves.
			mat = terrain_material("rh_turf", "rh_moss", "rh_earth", {
				"layer_b_amount": 0.3, "ember_density": 0.0, "slope_top": 0.5})
		&"spire_floor":
			mat = terrain_material("sp_floor", "sp_wall_top", "sp_wall", {
				"layer_b_amount": 0.2, "ember_density": 0.0})
		&"spire_wall":
			mat = terrain_material("sp_wall_top", "sp_floor", "sp_wall", {
				"layer_b_amount": 0.2, "ember_density": 0.0, "slope_top": 0.6})
		&"spire_crystal":
			mat = terrain_material("sp_crystal", "sp_crystal", "sp_crystal", {
				"layer_b_amount": 0.0, "ember_density": 0.0})
		_:
			push_warning("ArtKit: unknown material role '%s'" % role)
			mat = StandardMaterial3D.new()
	_materials[role] = mat
	return mat


# ---------------------------------------------------------------------------
# Characters (M06): StandardMaterial3D on purpose — toon diffuse, rim, stencil
# outline are built in, and EnemyBase's per-instance hit flash keeps working.
# ---------------------------------------------------------------------------

const CHAR_TEX_DIR := "res://assets/textures/char/"
## Meta flag: the material's emission stays enabled (effects change energy only).
const KEEP_EMISSION := &"keep_emission"
static var _rig_scenes: Dictionary = {}  # path -> PackedScene
## Live body materials for the outline switch (debug key O, perf A/B) — weak,
## so a static never keeps a material (and its stencil next pass) alive past
## the rendering server.
static var _char_materials: Array[WeakRef] = []
static var _lookdev_ready: bool = false


## Called on shutdown (GameFeel._exit_tree): statics holding GPU resources
## past the servers' teardown crash the process on exit.
static func clear_caches() -> void:
	_materials.clear()
	_char_materials.clear()
	_rig_scenes.clear()
	_spec = {}
	_lookdev_ready = false


## Rig GLB scene, kept loaded: the resource cache drops a PackedScene once no
## instance is alive, so every camp trigger would re-read it from disk.
## Returns null when the file is missing (callers keep their legacy visuals).
static func rig_scene(path: String) -> PackedScene:
	if not _rig_scenes.has(path):
		_rig_scenes[path] = load(path) if ResourceLoader.exists(path) else null
	return _rig_scenes[path]


## Per-instance body material bound to a character's baked pixel atlas
## (64 px/m = 2:1 over the environment, Gate 0).
static func character_material(atlas_id: String) -> StandardMaterial3D:
	_ensure_lookdev()
	var mat := StandardMaterial3D.new()
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.roughness = 0.65
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC
	mat.rim_enabled = true
	mat.rim = 0.35
	mat.rim_tint = 0.6
	# Hit flash drives only the energy: toggling emission_enabled would build a
	# new shader variant on the first hit (a visible hitch on this iGPU).
	mat.emission_enabled = true
	mat.emission = Color.WHITE
	mat.emission_energy_multiplier = 0.0
	mat.set_meta(KEEP_EMISSION, true)
	var path := CHAR_TEX_DIR + atlas_id + "_atlas.png"
	if ResourceLoader.exists(path):
		mat.albedo_texture = load(path)
	_apply_outline(mat)
	_char_materials.append(weakref(mat))
	return mat


## Environment prop body material (shared per prop atlas, 32 px/m): toon like
## everything else, but no outline — outlines stay a character read.
static func prop_material(atlas_id: String) -> StandardMaterial3D:
	var key := StringName("prop_" + atlas_id)
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.roughness = 0.75
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC
	var path := "res://assets/textures/env/%s_atlas.png" % atlas_id
	if ResourceLoader.exists(path):
		mat.albedo_texture = load(path)
	_materials[key] = mat
	return mat


const WIND_SHADER := preload("res://shaders/wind_sway.gdshader")


## Prop part that sways in the wind (same look as prop_material). The weight
## runs from 0 at `anchor_y` to 1 at `full_y` (local metres; full_y below
## anchor_y hangs from the top). Shared per prop.
static func sway_material(atlas_id: String, anchor_y: float, full_y: float, amplitude: float) -> ShaderMaterial:
	var key := StringName("sway_" + atlas_id)
	if _materials.has(key):
		return _materials[key]
	var mat := ShaderMaterial.new()
	mat.shader = WIND_SHADER
	var path := "res://assets/textures/env/%s_atlas.png" % atlas_id
	if ResourceLoader.exists(path):
		mat.set_shader_parameter(&"atlas", load(path))
	mat.set_shader_parameter(&"anchor_y", anchor_y)
	mat.set_shader_parameter(&"full_y", full_y)
	mat.set_shader_parameter(&"amplitude", amplitude)
	_materials[key] = mat
	return mat


## Emissive part (visor, sigil, eyes): unaffected by hit flash.
static func glow_material(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.disable_fog = true  # enemy eyes / player runes stay readable in haze
	return mat


static func _apply_outline(mat: StandardMaterial3D) -> void:
	var outline: bool = LookDev.get_value(&"outline", spec().get("outline", {}).get("default", true))
	mat.stencil_mode = BaseMaterial3D.STENCIL_MODE_OUTLINE if outline else BaseMaterial3D.STENCIL_MODE_DISABLED
	mat.stencil_outline_thickness = number("outline.thickness", 0.012)
	mat.stencil_color = color("outline.color", Color(0.04, 0.03, 0.06))


static func _ensure_lookdev() -> void:
	if _lookdev_ready:
		return
	_lookdev_ready = true
	var refresh := func(_v: Variant) -> void:
		var live: Array[WeakRef] = []
		for ref in ArtKit._char_materials:
			var m := ref.get_ref() as StandardMaterial3D
			if m != null:
				ArtKit._apply_outline(m)
				live.append(ref)
		ArtKit._char_materials = live
	LookDev.register(&"outline", refresh, spec().get("outline", {}).get("default", true))


## Per-zone copy of a ground role with paved plazas (x, z, radius) and path
## segments (x0, z0, x1, z1) in world metres — shader-side, no geometry, so the
## same call paves the M08 heightmap.
static func paved(role: StringName, plazas: Array[Vector3], paths: Array[Vector4], width: float = 1.8) -> ShaderMaterial:
	var mat := (material(role) as ShaderMaterial).duplicate() as ShaderMaterial
	var circles := PackedVector4Array()
	for c in plazas.slice(0, 4):
		circles.append(Vector4(c.x, c.y, c.z, 0.0))
	var segs := PackedVector4Array()
	for s in paths.slice(0, 8):
		segs.append(s)
	circles.resize(4)
	segs.resize(8)
	mat.set_shader_parameter(&"circles", circles)
	mat.set_shader_parameter(&"paved_circles", mini(plazas.size(), 4))
	mat.set_shader_parameter(&"paths", segs)
	mat.set_shader_parameter(&"paved_paths", mini(paths.size(), 8))
	mat.set_shader_parameter(&"path_width", width)
	return mat


## Per-zone copy of a floor role with emissive rune channels along line
## segments (x0, z0, x1, z1), world metres, max 16 (shader-side like paved()).
static func inlaid(role: StringName, segments: Array[Vector4], color: Color, energy: float = 0.7) -> ShaderMaterial:
	var mat := (material(role) as ShaderMaterial).duplicate() as ShaderMaterial
	var segs := PackedVector4Array()
	for seg in segments.slice(0, 16):
		segs.append(seg)
	segs.resize(16)
	mat.set_shader_parameter(&"lines", segs)
	mat.set_shader_parameter(&"rune_lines", mini(segments.size(), 16))
	mat.set_shader_parameter(&"rune_color", color)
	mat.set_shader_parameter(&"rune_energy", energy)
	return mat


static func terrain_material(top_a: String, top_b: String, side: String, params: Dictionary = {}) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = TERRAIN_SHADER
	mat.set_shader_parameter(&"top_a", load(BIOME_DIR + top_a + ".png"))
	mat.set_shader_parameter(&"top_b", load(BIOME_DIR + top_b + ".png"))
	mat.set_shader_parameter(&"side_tex", load(BIOME_DIR + side + ".png"))
	mat.set_shader_parameter(&"macro_noise", load(BIOME_DIR + "macro_noise.png"))
	mat.set_shader_parameter(&"px_per_m", number("texel_density.environment_px_per_m", 32.0))
	for key: String in params:
		mat.set_shader_parameter(StringName(key), params[key])
	return mat
