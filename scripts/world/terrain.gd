class_name Terrain
extends Node3D
## Heightmap terrain (M08): one baked height grid (tools/worldgen/bake.py)
## becomes chunked LOD meshes, one HeightMapShape3D collider and a height /
## normal query for everything that needs the ground (spawns, drops, scatter).
##  * grid: `res` x `res` samples 1 m apart, index iz * res + ix, sample
##    (0, 0) at local (origin.x, origin.y); row 0 is north (z = origin.y);
##  * meshes: CHUNK-metre chunks, three LODs (1 / 2 / 4 m) switched by
##    visibility range, a short skirt hides LOD cracks, smooth normals from the
##    grid so terrain_pixel's slope blend works unchanged; only LOD0 casts
##    shadows;
##  * collision: a single HeightMapShape3D over the same array (its cells are
##    1 m too, so no scaling), StaticBody3D on world layer 1, plus four
##    invisible border walls.
## The bake keeps every combat POI on a flat pad; the terrain shader gets the
## trails through ArtKit.masked().

const CHUNK := 32
const LOD_STEPS: Array[int] = [1, 2, 4]
## visibility_range switch points per LOD (metres from the chunk centre).
const LOD_SWITCH: Array[float] = [72.0, 150.0]
const LOD_MARGIN := 4.0
const SKIRT := 0.6
const WALL_HEIGHT := 120.0

var res: int = 0
var size_m: float = 0.0
## Local x, z of sample (0, 0).
var origin: Vector2 = Vector2.ZERO
var height_max: float = 0.0
var heights: PackedFloat32Array = PackedFloat32Array()
var normals: PackedVector3Array = PackedVector3Array()
var material: Material = null
var body: StaticBody3D
var build_ms: int = 0
var lod_enabled: bool = true
var _lods: Array[Array] = [[], [], []]  # MeshInstance3D per LOD


## Reads `<dir>/layout.json` (resolution, origin, height_max, baked.height_file)
## and the raw uint16 height file next to it. Not yet in the tree.
static func load_from(dir: String, mat: Material) -> Terrain:
	var t := Terrain.new()
	t.name = "Terrain"
	t.material = mat
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("layout.json")))
	var meta: Dictionary = parsed if parsed is Dictionary else {}
	t.res = int(meta.get("resolution", 0))
	t.size_m = float(meta.get("size_m", 0.0))
	var o: Array = meta.get("origin", [0, 0])
	t.origin = Vector2(float(o[0]), float(o[1]))
	t.height_max = float(meta.get("height_max", 1.0))
	var baked: Dictionary = meta.get("baked", {})
	var bytes := FileAccess.get_file_as_bytes(dir.path_join(String(baked.get("height_file", "height.r16"))))
	t._decode(bytes)
	return t


func _decode(bytes: PackedByteArray) -> void:
	var count := res * res
	heights.resize(count)
	if bytes.size() < count * 2:
		push_warning("Terrain: height file too short (%d bytes for %d samples)" % [bytes.size(), count])
		return
	var scale := height_max / 65535.0
	for i in count:
		heights[i] = float(bytes.decode_u16(i * 2)) * scale
	_compute_normals()


func _compute_normals() -> void:
	normals.resize(res * res)
	var last := res - 1
	for iz in res:
		var zn := maxi(iz - 1, 0)
		var zs := mini(iz + 1, last)
		for ix in res:
			var xl := maxi(ix - 1, 0)
			var xr := mini(ix + 1, last)
			var dx := (heights[iz * res + xl] - heights[iz * res + xr]) / float(xr - xl)
			var dz := (heights[zn * res + ix] - heights[zs * res + ix]) / float(zs - zn)
			normals[iz * res + ix] = Vector3(dx, 1.0, dz).normalized()


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	_build_meshes()
	_build_collision()
	build_ms = Time.get_ticks_msec() - t0
	LookDev.register(&"terrain_lod", set_lod_enabled, true)
	LookDev.register(&"terrain_shadows", set_shadows, true)


# ---------------------------------------------------------------------------
# Queries (world space)
# ---------------------------------------------------------------------------

## Bilinear ground height under world (x, z); clamped to the grid.
func height_at(x: float, z: float) -> float:
	var fx := clampf(x - global_position.x - origin.x, 0.0, float(res - 1) - 0.001)
	var fz := clampf(z - global_position.z - origin.y, 0.0, float(res - 1) - 0.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	var i := iz * res + ix
	var top := heights[i] * (1.0 - tx) + heights[i + 1] * tx
	var bottom := heights[i + res] * (1.0 - tx) + heights[i + res + 1] * tx
	return global_position.y + top * (1.0 - tz) + bottom * tz


## Smooth ground normal under world (x, z).
func normal_at(x: float, z: float) -> Vector3:
	var fx := clampf(x - global_position.x - origin.x, 0.0, float(res - 1) - 0.001)
	var fz := clampf(z - global_position.z - origin.y, 0.0, float(res - 1) - 0.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	var i := iz * res + ix
	var top := normals[i].lerp(normals[i + 1], tx)
	var bottom := normals[i + res].lerp(normals[i + res + 1], tx)
	return top.lerp(bottom, tz).normalized()


## Lowest and highest ground under a yawed box footprint (for sinking rocks
## and walls into slopes so no gap shows).
func footprint_range(pos: Vector3, size: Vector3, yaw: float) -> Vector2:
	var lo := INF
	var hi := -INF
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var nx := maxi(int(ceil(size.x)), 1)
	var nz := maxi(int(ceil(size.z)), 1)
	for i in nx + 1:
		for j in nz + 1:
			var local := Vector2(lerpf(-hx, hx, float(i) / nx), lerpf(-hz, hz, float(j) / nz)).rotated(-yaw)
			var h := height_at(pos.x + local.x, pos.z + local.y)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return Vector2(lo, hi)


## World-space corners of the grid on XZ.
func bounds() -> Rect2:
	return Rect2(Vector2(global_position.x, global_position.z) + origin, Vector2.ONE * float(res - 1))


# ---------------------------------------------------------------------------
# LookDev switches
# ---------------------------------------------------------------------------

## LOD off = LOD0 everywhere (perf A/B of the LOD scheme itself).
func set_lod_enabled(on: bool) -> void:
	lod_enabled = on
	for lod in _lods.size():
		for mi: MeshInstance3D in _lods[lod]:
			if on:
				_apply_range(mi, lod)
			else:
				mi.visibility_range_begin = 0.0
				mi.visibility_range_end = 0.0
				mi.visible = lod == 0


func set_shadows(on: bool) -> void:
	for mi: MeshInstance3D in _lods[0]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func chunk_count() -> int:
	return _lods[0].size()


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

func _apply_range(mi: MeshInstance3D, lod: int) -> void:
	mi.visible = true
	mi.visibility_range_begin = LOD_SWITCH[lod - 1] if lod > 0 else 0.0
	mi.visibility_range_end = LOD_SWITCH[lod] if lod < LOD_SWITCH.size() else 0.0
	mi.visibility_range_begin_margin = LOD_MARGIN if lod > 0 else 0.0
	mi.visibility_range_end_margin = LOD_MARGIN if lod < LOD_SWITCH.size() else 0.0


func _build_meshes() -> void:
	var chunks_per_side := (res - 1) / CHUNK
	for cz in chunks_per_side:
		for cx in chunks_per_side:
			var centre := Vector3(origin.x + cx * CHUNK + CHUNK * 0.5, 0.0, origin.y + cz * CHUNK + CHUNK * 0.5)
			for lod in LOD_STEPS.size():
				var mi := MeshInstance3D.new()
				mi.name = "Chunk_%d_%d_L%d" % [cx, cz, lod]
				mi.mesh = _build_chunk(cx, cz, LOD_STEPS[lod], centre)
				mi.material_override = material
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod == 0 \
					else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(mi)
				mi.position = centre
				_apply_range(mi, lod)
				_lods[lod].append(mi)


## One chunk at `step` metres per quad; vertices relative to `centre`.
func _build_chunk(cx: int, cz: int, step: int, centre: Vector3) -> ArrayMesh:
	var n := CHUNK / step + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var indices := PackedInt32Array()
	verts.resize(n * n)
	norms.resize(n * n)
	var x0 := cx * CHUNK
	var z0 := cz * CHUNK
	for j in n:
		var iz := z0 + j * step
		for i in n:
			var ix := x0 + i * step
			var k := iz * res + ix
			verts[j * n + i] = Vector3(origin.x + ix, heights[k], origin.y + iz) - centre
			norms[j * n + i] = normals[k]
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i
			var b := a + 1
			var c := a + n
			var d := c + 1
			# Godot front faces are clockwise seen from the front: (a, b, c)
			# with c = +z, b = +x faces up.
			indices.append_array(PackedInt32Array([a, b, c, b, d, c]))
	# Skirts: every edge drops SKIRT metres so a coarser neighbour never shows
	# a crack. Normals up: they take the top texture like the ground.
	var edge_loops: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]
	for i in n:
		edge_loops[0].append(i)                    # north (z0), +x order
		edge_loops[1].append((n - 1) * n + i)      # south
		edge_loops[2].append(i * n)                # west, +z order
		edge_loops[3].append(i * n + n - 1)        # east
	var outward := [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]  # -z, +z, -x, +x
	for e in 4:
		var loop := edge_loops[e]
		var base := verts.size()
		for idx in loop:
			verts.append(verts[idx] + Vector3.DOWN * SKIRT)
			norms.append(Vector3.UP)
		for i in loop.size() - 1:
			var top_a := loop[i]
			var top_b := loop[i + 1]
			var low_a := base + i
			var low_b := base + i + 1
			# Wind so the face points outward from the chunk.
			var pa := verts[top_a]
			var pb := verts[top_b]
			var pc := verts[low_a]
			var facing := (pc - pa).cross(pb - pa)
			if facing.dot(outward[e]) >= 0.0:
				indices.append_array(PackedInt32Array([top_a, top_b, low_a, top_b, low_b, low_a]))
			else:
				indices.append_array(PackedInt32Array([top_a, low_a, top_b, top_b, low_a, low_b]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _build_collision() -> void:
	body = StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := HeightMapShape3D.new()
	shape.map_width = res
	shape.map_depth = res
	shape.map_data = heights
	col.shape = shape
	body.add_child(col)
	add_child(body)
	# The shape is centred on its node; sample (0, 0) must land on `origin`.
	body.position = Vector3(origin.x + float(res - 1) * 0.5, 0.0, origin.y + float(res - 1) * 0.5)
	# Border walls just outside the grid (the rim mountains hide them).
	var half := float(res - 1) * 0.5
	var centre := Vector3(origin.x + half, WALL_HEIGHT * 0.5, origin.y + half)
	for side: Array in [[Vector3(half + 1.0, 0, 0), Vector3(2.0, WALL_HEIGHT, half * 2.0 + 4.0)],
			[Vector3(-half - 1.0, 0, 0), Vector3(2.0, WALL_HEIGHT, half * 2.0 + 4.0)],
			[Vector3(0, 0, half + 1.0), Vector3(half * 2.0 + 4.0, WALL_HEIGHT, 2.0)],
			[Vector3(0, 0, -half - 1.0), Vector3(half * 2.0 + 4.0, WALL_HEIGHT, 2.0)]]:
		var wall := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = side[1]
		wall.shape = box
		body.add_child(wall)
		wall.position = centre - body.position + side[0]
