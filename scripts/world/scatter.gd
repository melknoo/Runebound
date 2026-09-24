class_name Scatter
extends Object
## Rule-placed ground scatter (M06 environment kit; the M08 open zone reuses it
## on its heightmap). Nothing is hand-placed:
##  * items hug obstacle footprints (a band just outside each box), so open
##    combat space stays clear for telegraphs (ART_BIBLE: <= 0.02 m there);
##  * exclusion circles keep camps, spawn, portals and chests clean;
##  * ground height comes from a Callable (flat today, a heightmap later).
## Instances are bucketed into CHUNK-sized MultiMeshes: one draw per item and
## chunk, no shadows, culled beyond VISIBLE_RANGE.

const CHUNK := 16.0
const VISIBLE_RANGE := 42.0
## Keeps items out of neighbouring boxes and clear of their hull edges.
const INSIDE_MARGIN := 0.2
## Meta on each chunk node: PackedVector3Array of its instances' world positions.
const POINTS_META := &"scatter_points"


## rules:
##   area       Rect2 on XZ where scatter may land
##   obstacles  [{pos: Vector3, size: Vector3, yaw: float}] box footprints
##   exclude    [Vector3(x, z, radius)] keep-clear circles
##   height_at  Callable(x, z) -> float, default flat 0
##   normal_at  Callable(x, z) -> Vector3, optional: instances tilt to the slope
##   tilt       0..1 how much of that tilt to apply (default 1 when normal_at is set)
##   seed       int (placement is deterministic)
##   items      [{prop, per_m (clusters per metre of footprint perimeter),
##               band: Vector2 (min, max distance outside the footprint),
##               scale: Vector2 (min, max),
##               cluster: Vector2i (min, max instances per cluster, default 1),
##               spread: float (cluster radius in m)}]
## Returns the number of instances placed.
static func populate(zone: ZoneBase, rules: Dictionary) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(rules.get("seed", 1))
	var area: Rect2 = rules["area"]
	var obstacles: Array = rules.get("obstacles", [])
	var exclude: Array = rules.get("exclude", [])
	var height_at: Callable = rules.get("height_at", func(_x: float, _z: float) -> float: return 0.0)
	var normal_at: Callable = rules.get("normal_at", Callable())
	var tilt := float(rules.get("tilt", 1.0))
	var placed := 0
	for item: Dictionary in rules.get("items", []):
		var mesh := _item_mesh(String(item["prop"]))
		if mesh == null:
			continue
		var scale_range: Vector2 = item["scale"]
		var cluster: Vector2i = item.get("cluster", Vector2i(1, 1))
		var spread: float = item.get("spread", 0.0)
		var chunks := {}  # Vector2i -> Array of Transform3D
		for ob: Dictionary in obstacles:
			for centre in _around(ob, item, rng):
				for j in rng.randi_range(cluster.x, cluster.y):
					# clumps read as growth; a lone row of tufts reads as a pattern
					var p := centre + Vector2.from_angle(rng.randf() * TAU) * spread * sqrt(rng.randf())
					if not area.has_point(p) or _inside_any(p, obstacles) or _excluded(p, exclude):
						continue
					var s := rng.randf_range(scale_range.x, scale_range.y)
					var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * s)
					if normal_at.is_valid() and tilt > 0.0:
						var n: Vector3 = normal_at.call(p.x, p.y)
						if n.dot(Vector3.UP) < 0.9999:
							basis = Basis(Quaternion(Vector3.UP, Vector3.UP.slerp(n, tilt))) * basis
					var key := Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK))
					if not chunks.has(key):
						chunks[key] = []
					(chunks[key] as Array).append(Transform3D(basis, Vector3(p.x, float(height_at.call(p.x, p.y)), p.y)))
		for key: Vector2i in chunks:
			placed += _emit_chunk(zone, key, chunks[key], mesh, String(item["prop"]))
	return placed


## Candidate points on a box footprint's perimeter, pushed outward into the
## band (biased toward the edge, where debris collects).
static func _around(ob: Dictionary, item: Dictionary, rng: RandomNumberGenerator) -> PackedVector2Array:
	var size: Vector3 = ob["size"]
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var pos: Vector3 = ob["pos"]
	var centre := Vector2(pos.x, pos.z)
	var yaw: float = ob["yaw"]
	var band: Vector2 = item["band"]
	var perimeter := 4.0 * (hx + hz)
	var out := PackedVector2Array()
	for i in int(perimeter * float(item["per_m"])):
		var u := rng.randf() * perimeter
		var local: Vector2
		var normal: Vector2
		if u < 2.0 * hx:
			local = Vector2(-hx + u, -hz)
			normal = Vector2(0, -1)
		elif u < 2.0 * (hx + hz):
			local = Vector2(hx, -hz + u - 2.0 * hx)
			normal = Vector2(1, 0)
		elif u < 4.0 * hx + 2.0 * hz:
			local = Vector2(hx - (u - 2.0 * (hx + hz)), hz)
			normal = Vector2(0, 1)
		else:
			local = Vector2(-hx, hz - (u - 4.0 * hx - 2.0 * hz))
			normal = Vector2(-1, 0)
		local += normal * lerpf(band.x, band.y, rng.randf() * rng.randf())
		out.append(centre + local.rotated(-yaw))  # matches Node3D rotation.y
	return out


static func _inside_any(p: Vector2, obstacles: Array) -> bool:
	for ob: Dictionary in obstacles:
		var pos: Vector3 = ob["pos"]
		var size: Vector3 = ob["size"]
		var local := (p - Vector2(pos.x, pos.z)).rotated(float(ob["yaw"]))
		if absf(local.x) < size.x * 0.5 + INSIDE_MARGIN and absf(local.y) < size.z * 0.5 + INSIDE_MARGIN:
			return true
	return false


static func _excluded(p: Vector2, exclude: Array) -> bool:
	for c: Vector3 in exclude:
		if p.distance_to(Vector2(c.x, c.y)) < c.z:
			return true
	return false


## The prop's mesh with its kit materials baked into the surfaces (a MultiMesh
## renders the mesh's own surface materials).
static func _item_mesh(prop_name: String) -> Mesh:
	var path := SetPieces.prop_path(prop_name)
	if path == "":
		return null
	var inst := (load(path) as PackedScene).instantiate()
	var found := inst.find_children("*", "MeshInstance3D", true, false)
	var mesh: Mesh = null
	if not found.is_empty():
		mesh = ((found[0] as MeshInstance3D).mesh as Mesh).duplicate() as Mesh
		for s in mesh.get_surface_count():
			mesh.surface_set_material(s, SetPieces.surface_material(prop_name, mesh.surface_get_material(s)))
	inst.free()
	return mesh


static func _emit_chunk(zone: ZoneBase, key: Vector2i, transforms: Array, mesh: Mesh, prop_name: String) -> int:
	var origin := Vector3((key.x + 0.5) * CHUNK, 0.0, (key.y + 0.5) * CHUNK)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	# World positions kept on the node: the headless renderer stores no
	# MultiMesh buffers, so tests (and debugging) read these instead.
	var points := PackedVector3Array()
	for i in transforms.size():
		var t: Transform3D = transforms[i]
		points.append(t.origin)
		t.origin -= origin
		mm.set_instance_transform(i, t)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Scatter_%s_%d_%d" % [prop_name, key.x, key.y]
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = VISIBLE_RANGE
	mmi.visibility_range_end_margin = 4.0
	mmi.set_meta(POINTS_META, points)
	zone.dressing().add_child(mmi)
	mmi.global_position = origin
	return transforms.size()
