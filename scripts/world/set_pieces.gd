class_name SetPieces
extends Object
## Reusable point-of-interest building blocks (M06 environment kit; the M08
## open Highlands places the same builders on terrain). Visual only — nothing
## here adds collision: walk-through props stay <= 0.4 m, tall props stand on
## collider tops or outside the playable area (ART_BIBLE / M06 rules).

## Biome kits (tools/modelgen/generate_props.py); a prop name is unique across
## kits (Runehold props are rh_*, Spire props sp_*).
const KIT_DIRS: Array[String] = [
	"res://assets/models/env/highlands/",
	"res://assets/models/env/runehold/",
	"res://assets/models/env/spire/",
	"res://assets/models/env/common/",
]
const SHADOW_MIN_HEIGHT := 0.6  # art_spec shadows.casters: small props don't cast
## Wind on `<prop>_cloth` surfaces: [anchor_y, full_y, amplitude] in local m
## (banners hang from the crossbar, tufts sway from the ground).
const SWAY := {
	"banner_pole": [2.9, 1.65, 0.12],
	"ash_tuft": [0.0, 0.28, 0.035],
	"rh_wall_banner": [0.0, -1.8, 0.05],  # held 0.1 m off the wall: never clips
	"rh_grass_tuft": [0.0, 0.36, 0.04],
}


## GLB path of a kit prop ("" when no kit has it).
static func prop_path(prop_name: String) -> String:
	for dir in KIT_DIRS:
		var path := dir + prop_name + ".glb"
		if ResourceLoader.exists(path):
			return path
	return ""


## Instances a kit prop under `parent` with its atlas material. Returns null
## when the prop GLB is missing (zones then simply skip the dressing).
static func prop(parent: Node3D, prop_name: String, pos: Vector3, yaw: float = 0.0, scale: float = 1.0) -> Node3D:
	var path := prop_path(prop_name)
	if path == "":
		return null
	var inst := (load(path) as PackedScene).instantiate() as Node3D
	inst.name = prop_name
	parent.add_child(inst, true)  # readable duplicates: bonfire, bonfire2, ...
	inst.global_position = pos
	inst.rotation.y = yaw
	inst.scale = Vector3.ONE * scale
	for child in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			mi.set_surface_override_material(s, surface_material(prop_name, mi.mesh.surface_get_material(s)))
		if mi.get_aabb().size.y * scale < SHADOW_MIN_HEIGHT:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return inst


## Kit material for an imported prop surface, matched by the Blender material
## name: <prop>_glow -> dim emissive, <prop>_cloth -> wind sway, a part with
## its own baked atlas (e.g. treasure_chest_lid) -> that atlas, else the
## prop's atlas.
static func surface_material(prop_name: String, imported: Material) -> Material:
	var mat_name := imported.resource_name if imported != null else ""
	if mat_name != "" and mat_name != prop_name + "_body" and not mat_name.ends_with("_glow") 			and not mat_name.ends_with("_cloth") and ResourceLoader.exists("res://assets/textures/env/%s_atlas.png" % mat_name):
		return ArtKit.prop_material(mat_name)
	if mat_name.ends_with("_glow"):
		var std := imported as StandardMaterial3D
		var glow_color := std.emission if std != null else Color(1, 0.5, 0.2)
		return ArtKit.glow_material(glow_color, ArtKit.number("emissive_caps.environment", 0.8))
	if mat_name.ends_with("_cloth"):
		var sway: Array = SWAY.get(prop_name, [0.0, 1.0, 0.05])
		return ArtKit.sway_material(prop_name, sway[0], sway[1], sway[2])
	return ArtKit.prop_material(prop_name)


## Camp heart: low stone ring (walk-through), flickering fire light (no
## shadows), rising embers and the crackle loop.
static func bonfire(zone: ZoneBase, pos: Vector3) -> Node3D:
	var root := prop(zone.dressing(), "bonfire", pos, fposmod(pos.x * 1.7 + pos.z, TAU))
	if root == null:
		return null
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.58, 0.28)
	light.light_energy = 1.6
	light.omni_range = 7.0
	light.shadow_enabled = false
	root.add_child(light)
	light.position = Vector3(0, 0.7, 0)
	var flicker := light.create_tween().set_loops()
	flicker.tween_property(light, "light_energy", 1.25, 0.31).set_trans(Tween.TRANS_SINE)
	flicker.tween_property(light, "light_energy", 1.75, 0.43).set_trans(Tween.TRANS_SINE)
	root.add_child(_embers())
	zone.call(&"_add_ambience", "campfire_loop", pos, -12.0)
	return root


static func _embers() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 14
	p.lifetime = 1.5
	p.local_coords = false
	p.position = Vector3(0, 0.2, 0)
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 22.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.3
	pm.gravity = Vector3(0, 0.35, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.25
	pm.scale_min = 0.6
	pm.scale_max = 1.1
	pm.color_ramp = VFX._gradient([Color(1.0, 0.85, 0.45), Color(1.0, 0.45, 0.15), Color(0.6, 0.15, 0.05, 0.0)] as Array[Color])
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	quad.material = VFX._particle_material(VFX._tex("ember"))
	p.draw_pass_1 = quad
	return p


## Raider camp POI: bonfire at the heart, log seats facing it and bone piles
## around it (all low, walk-through), hide banners on the given ridge-top
## spots facing the camp.
static func raider_camp(zone: ZoneBase, center: Vector3, banner_spots: Array[Vector3] = []) -> void:
	bonfire(zone, center)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(center.x * 97.0 + center.z * 31.0)
	var seat_a := rng.randf_range(0.0, TAU)
	for i in 2:
		var a := seat_a + i * rng.randf_range(2.2, 2.8)
		# log axis tangential to the fire ring: it reads as a seat, not a spoke
		var seat := center + Vector3(cos(a), 0.0, sin(a)) * 1.55
		seat.y = zone.ground_y(seat)
		prop(zone.dressing(), "log_seat", seat, PI * 0.5 - a + rng.randf_range(-0.2, 0.2))
	for i in 3:
		var a := rng.randf_range(0.0, TAU)
		var r := rng.randf_range(2.4, 3.4)
		var spot := center + Vector3(cos(a) * r, 0.0, sin(a) * r)
		spot.y = zone.ground_y(spot)
		prop(zone.dressing(), "bone_pile", spot, rng.randf_range(0.0, TAU))
	for spot in banner_spots:
		var to_camp := Vector2(center.x - spot.x, center.z - spot.z)
		prop(zone.dressing(), "banner_pole", spot, atan2(-to_camp.x, -to_camp.y) + PI)


## Replaces a greybox collider's look with a kit prop that contains it (the
## StaticBody and its shape stay untouched; the box mesh is hidden).
static func wrap_collider(body: StaticBody3D, prop_name: String) -> Node3D:
	var inst := prop(body, prop_name, body.global_position - Vector3(0, (body.get_child(1) as CollisionShape3D).shape.get(&"size").y * 0.5, 0))
	if inst == null:
		return null
	inst.rotation = Vector3.ZERO  # inherits the body's yaw
	(body.get_child(0) as MeshInstance3D).visible = false
	return inst


# ---------------------------------------------------------------------------
# Settlement builders (Runehold kit; the same calls build M08+ villages).
# Big surfaces use world-mapped terrain roles, so walls, huts and ground share
# one texel grid; Blender props only add the trim.
# ---------------------------------------------------------------------------

static func _box_size(body: StaticBody3D) -> Vector3:
	return ((body.get_child(1) as CollisionShape3D).shape as BoxShape3D).size


## Coursed wall on a greybox wall collider: the box keeps its mesh with the
## masonry role; one merged mesh adds a cap course and piers every
## ~pier_every m (<= 0.3 m above the top: camera spring margin; <= 0.25 m
## proud: the 0.42 m player capsule never reaches them). Give corner piers
## (end_piers) to one wall per corner, so coplanar caps never z-fight.
## Returns the pier offsets along the wall (banners go between them).
static func masonry_wall(body: StaticBody3D, role: StringName, pier_every: float = 6.0, end_piers: bool = true) -> PackedFloat32Array:
	var size := _box_size(body)
	var mat := ArtKit.material(role)
	((body.get_child(0) as MeshInstance3D).mesh as BoxMesh).material = mat
	var along_x := size.x >= size.z
	var length := size.x if along_x else size.z
	var thick := size.z if along_x else size.x
	var top := size.y * 0.5
	var st := SurfaceTool.new()
	var add_box := func(extent: Vector3, centre: Vector3) -> void:
		var b := BoxMesh.new()
		b.size = extent if along_x else Vector3(extent.z, extent.y, extent.x)
		var c := centre if along_x else Vector3(centre.z, centre.y, centre.x)
		st.append_from(b, 0, Transform3D(Basis(), c))
	add_box.call(Vector3(length + 0.2, 0.18, thick + 0.2), Vector3(0, top + 0.07, 0))  # cap course
	var segments := maxi(roundi(length / pier_every), 1)
	var offsets := PackedFloat32Array()
	for i in segments + 1:
		var t := -length * 0.5 + length * i / segments
		offsets.append(t)
		var is_end := i == 0 or i == segments
		if is_end and not end_piers:
			continue
		var w := 1.5 if is_end else 0.9
		var d := 1.5 if is_end else thick + 0.36
		var h := size.y + (0.3 if is_end else 0.26)
		add_box.call(Vector3(w, h, d), Vector3(t, h * 0.5 - top, 0))
	var mi := MeshInstance3D.new()
	mi.name = "WallTrim"
	mi.mesh = st.commit()
	mi.material_override = mat
	body.add_child(mi)
	return offsets


## Settlement hut on its two greybox colliders: the body box gets the masonry
## role, the roof slab turns into a sod gable (contains the slab: eaves
## 0.15 m out, ridge 0.3 m over its top), the trim prop adds timber, door and
## lit windows. door_back turns the trim around (the box is not square).
static func hut(body: StaticBody3D, roof: StaticBody3D, wall_role: StringName, roof_role: StringName, door_back: bool = false) -> void:
	((body.get_child(0) as MeshInstance3D).mesh as BoxMesh).material = ArtKit.material(wall_role)
	(roof.get_child(0) as MeshInstance3D).visible = false
	var gable := MeshInstance3D.new()
	gable.name = "SodRoof"
	gable.mesh = gable_mesh(_box_size(roof), 0.15, 0.3)
	gable.material_override = ArtKit.material(roof_role)
	roof.add_child(gable)
	prop(body, "rh_hut_trim", body.global_position - Vector3(0, _box_size(body).y * 0.5, 0), PI if door_back else 0.0)


## Gable roof around a slab of the given size (ridge along X): thick vertical
## eaves (their sides read as sod edge), low slopes (read as turf).
static func gable_mesh(size: Vector3, eave: float, rise: float) -> ArrayMesh:
	var hx := size.x * 0.5 + eave
	var hz := size.z * 0.5 + eave
	var y0 := -size.y * 0.5 - 0.05
	var y1 := size.y * 0.5
	var y2 := size.y * 0.5 + rise
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Counter-clockwise seen from outside = front face in Godot (normals from
	# the winding, flipped to Godot's clockwise front-face convention below).
	var tri := func(a: Vector3, b: Vector3, c: Vector3) -> void:
		var n := (b - a).cross(c - a).normalized()
		for v: Vector3 in [a, c, b]:
			st.set_normal(n)
			st.add_vertex(v)
	for sx: float in [-1.0, 1.0]:
		var x := sx * hx
		var b0 := Vector3(x, y0, -hz)
		var b1 := Vector3(x, y0, hz)
		var e1 := Vector3(x, y1, hz)
		var r := Vector3(x, y2, 0.0)
		var e0 := Vector3(x, y1, -hz)
		if sx > 0.0:   # facing +X: CCW seen from +X is b1 -> b0 -> e0 ...
			tri.call(b1, b0, e0)
			tri.call(b1, e0, e1)
			tri.call(e1, e0, r)
		else:
			tri.call(b0, b1, e1)
			tri.call(b0, e1, e0)
			tri.call(e0, e1, r)
	for sz: float in [-1.0, 1.0]:
		var z := sz * hz
		var a := Vector3(-hx, y0, z)
		var b := Vector3(hx, y0, z)
		var c := Vector3(hx, y1, z)
		var d := Vector3(-hx, y1, z)
		var r0 := Vector3(-hx, y2, 0.0)
		var r1 := Vector3(hx, y2, 0.0)
		if sz > 0.0:   # facing +Z
			tri.call(a, b, c)
			tri.call(a, c, d)
			tri.call(d, c, r1)
			tri.call(d, r1, r0)
		else:
			tri.call(b, a, d)
			tri.call(b, d, c)
			tri.call(c, d, r0)
			tri.call(c, r0, r1)
	# underside, facing down
	tri.call(Vector3(-hx, y0, -hz), Vector3(hx, y0, -hz), Vector3(hx, y0, hz))
	tri.call(Vector3(-hx, y0, -hz), Vector3(hx, y0, hz), Vector3(-hx, y0, hz))
	return st.commit()


## Runehold hearth: granite ring stones wrap the ring colliders, the log
## colliders hide under the fire prop (same log yaws), warm light without
## shadows, breathing flame tongues, embers and the crackle loop.
static func hearth(zone: ZoneBase, pos: Vector3, stones: Array[StaticBody3D], logs: Array[StaticBody3D],
		energy: float = 2.2, light_range: float = 9.0) -> Node3D:
	for body in stones:
		var stone := wrap_collider(body, "rh_hearth_stone")
		if stone != null:
			stone.rotation.y = fposmod(body.global_position.x * 3.1 + body.global_position.z * 1.7, TAU)
	for body in logs:
		(body.get_child(0) as MeshInstance3D).visible = false
	var root := prop(zone.dressing(), "rh_hearth_fire", pos)
	if root == null:
		return null
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.62, 0.3)
	light.light_energy = energy
	light.omni_range = light_range
	light.shadow_enabled = false
	root.add_child(light)
	light.position = Vector3(0, 1.0, 0)
	var flicker := light.create_tween().set_loops()
	flicker.tween_property(light, "light_energy", energy * 0.78, 0.35).set_trans(Tween.TRANS_SINE)
	flicker.tween_property(light, "light_energy", energy * 1.05, 0.42).set_trans(Tween.TRANS_SINE)
	var flames := root.find_child("flames", true, false) as Node3D
	if flames != null:
		var breathe := flames.create_tween().set_loops()
		breathe.tween_property(flames, "scale", Vector3(1.06, 0.84, 1.06), 0.27).set_trans(Tween.TRANS_SINE)
		breathe.tween_property(flames, "scale", Vector3(0.95, 1.12, 0.95), 0.33).set_trans(Tween.TRANS_SINE)
		var sway := flames.create_tween().set_loops()
		sway.tween_property(flames, "rotation:y", 0.35, 0.9).set_trans(Tween.TRANS_SINE)
		sway.tween_property(flames, "rotation:y", -0.2, 1.1).set_trans(Tween.TRANS_SINE)
	var embers := _embers()
	embers.amount = 22
	root.add_child(embers)
	zone.call(&"_add_ambience", "campfire_loop", pos + Vector3(0, 0.5, 0), -6.0)
	return root


## Banner on a wall's inner face: face = point on the face at the banner top,
## inward = face normal into the courtyard.
static func wall_banner(zone: ZoneBase, face: Vector3, inward: Vector3) -> Node3D:
	var yaw := atan2(inward.x, inward.z)  # prop front (+Z) along inward
	return prop(zone.dressing(), "rh_wall_banner", face + inward * 0.13, yaw)
