class_name RockHull
extends Object
## Reusable rock-formation builder (M06 environment kit). Turns a box volume
## into a faceted, terraced rock hull:
##  * every vertex moves only OUTWARD from the box (min MARGIN), so the hull
##    contains the box by construction — wrapping an existing collider never
##    changes collision, camera or aim (world layer 1 stays the box);
##  * displacement is a pure function of position (+ per-build band table), so
##    shared edge vertices of neighbouring faces coincide (watertight);
##  * horizontal strata step back as they rise, with an explicit ledge row at
##    every band boundary -> real shelves whose tops the terrain shader covers
##    in ash (the side push is capped by the camera/player margin, so the
##    formation reads through ledges and facets, not through big bulges);
##  * flat (faceted) normals, vertex-color AO darkening crevices and the foot.
## Used today to dress greybox colliders; M08 can place formations directly.

const MARGIN := 0.08          # min outward offset (x sqrt(3) still > 0 at corners)
const SEGMENT := 0.9          # target horizontal grid spacing in metres
const LEDGE := 0.03           # height of the step row under each band boundary


## size: box extents; seed: formation identity; side_max/top_max: max outward
## push on walkable sides/tops (camera spring margin 0.3 m); wild_faces: bitmask
## of faces facing outside the playable area that may bulge up to wild_max
## (bit 0 +X, 1 -X, 2 +Z, 3 -Z).
static func build(size: Vector3, seed: int, side_max: float = 0.3, top_max: float = 0.28,
		wild_faces: int = 0, wild_max: float = 1.6) -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 0.6
	noise.fractal_octaves = 2
	var h := size * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var strata := 0.8 + float(absi(seed) % 5) * 0.08
	var band_count := maxi(int(ceil(size.y / strata)), 1)
	# Band push table (0..1 of the face limit). The margin caps the push at
	# ~0.3 m, so gentle steps would make 3-8 cm shelves nobody sees: bands
	# alternate far/near instead -> ~20 cm ash shelves (out -> in going up) and
	# dark overhang lips (in -> out) = readable strata inside the margin.
	var bands := PackedFloat32Array()
	var far := rng.randf() < 0.5
	for k in band_count:
		bands.append(rng.randf_range(0.78, 1.0) if far else rng.randf_range(0.05, 0.3))
		far = not far if rng.randf() < 0.85 else far
	var ctx := {"h": h, "noise": noise, "bands": bands, "strata": strata, "side_max": side_max,
		"top_max": top_max, "wild_faces": wild_faces, "wild_max": wild_max}

	# Vertical rows for side faces: a pair at every band boundary (ledge).
	var ys := PackedFloat32Array([-h.y])
	for k in range(1, band_count):
		var yb := -h.y + k * strata
		if yb < h.y - LEDGE * 2.0:
			ys.append(yb - LEDGE)
			ys.append(yb)
	ys.append(h.y)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)  # -1 = flat normals: every facet reads as a plane
	# Faces: axis index, sign. The bottom face is skipped (buried in the floor).
	for face: Array in [[0, 1.0], [0, -1.0], [2, 1.0], [2, -1.0], [1, 1.0]]:
		var axis: int = face[0]
		var sgn: float = face[1]
		var u_axis := 2 if axis == 0 else 0
		var v_axis := 1 if axis != 1 else 2
		var nu := maxi(int(ceil(size[u_axis] / _segment(size[u_axis]))), 1)
		var v_values := PackedFloat32Array()
		if v_axis == 1:
			v_values = ys
		else:
			var nv := maxi(int(ceil(size[v_axis] / _segment(size[v_axis]))), 1)
			for j in nv + 1:
				v_values.append(lerpf(-h[v_axis], h[v_axis], float(j) / nv))
		var grid: Array = []
		for v in v_values:
			var row: Array[Vector3] = []
			for i in nu + 1:
				var p := Vector3.ZERO
				p[axis] = h[axis] * sgn
				p[u_axis] = lerpf(-h[u_axis], h[u_axis], float(i) / nu)
				p[v_axis] = v
				row.append(_displace(p, ctx))
			grid.append(row)
		var outward := Vector3.ZERO
		outward[axis] = sgn
		for j in grid.size() - 1:
			for i in nu:
				var a: Vector3 = grid[j][i]
				var b: Vector3 = grid[j][i + 1]
				var c: Vector3 = grid[j + 1][i + 1]
				var d: Vector3 = grid[j + 1][i]
				_tri(st, a, b, c, h, outward)
				_tri(st, a, c, d, h, outward)
	st.generate_normals()
	return st.commit()


## Horizontal grid spacing: ledges carry the read, so long walls get a coarse
## grid (every hull triangle is drawn in prepass, color and shadow passes).
static func _segment(extent: float) -> float:
	return SEGMENT if extent <= 12.0 else (1.6 if extent <= 40.0 else 2.4)


static func _displace(p: Vector3, ctx: Dictionary) -> Vector3:
	var h: Vector3 = ctx["h"]
	# Outward direction: sum of the normals of every face the point lies on.
	var out := Vector3.ZERO
	var on_top := false
	var wild := false
	var wild_faces: int = ctx["wild_faces"]
	for axis in 3:
		if absf(absf(p[axis]) - h[axis]) < 0.001:
			var s := signf(p[axis])
			if axis == 1:
				if s > 0.0:
					on_top = true
					out.y += 1.0
				continue  # bottom rim: no downward push
			out[axis] += s
			var bit := (0 if s > 0.0 else 1) if axis == 0 else (2 if s > 0.0 else 3)
			if wild_faces & (1 << bit):
				wild = true
	if out == Vector3.ZERO:
		out = Vector3.UP
	out = out.normalized()
	var n := (ctx["noise"] as FastNoiseLite).get_noise_3dv(p) * 0.5 + 0.5
	var push: float
	if on_top and out.y > 0.9:
		push = MARGIN + n * (float(ctx["top_max"]) - MARGIN)
	else:
		var limit: float = ctx["wild_max"] if wild else ctx["side_max"]
		var bands: PackedFloat32Array = ctx["bands"]
		var band := clampi(int(floorf((p.y + h.y) / float(ctx["strata"]) + 0.0001)), 0, bands.size() - 1)
		var share := clampf(bands[band] + (n - 0.5) * 0.3, 0.0, 1.0)
		push = MARGIN + (limit - MARGIN) * share
	var moved := p + out * push
	# Foot: sink the bottom rim a little so no gap shows against the floor.
	if p.y <= -h.y + 0.001:
		moved.y -= 0.15
	return moved


## Godot front faces are clockwise: the front normal of (a, b, c) is
## (c - a) x (b - a). Swap to face `outward` so culling and normals are right.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, h: Vector3, outward: Vector3) -> void:
	var verts := [a, b, c]
	if (c - a).cross(b - a).dot(outward) < 0.0:
		verts = [a, c, b]
	for v: Vector3 in verts:
		st.set_color(_shade(v, h))
		st.add_vertex(v)


## Vertex color: darker toward the foot (ambient occlusion from the floor) and
## in recesses, so ledge undersides and crevices read without SSAO.
static func _shade(v: Vector3, h: Vector3) -> Color:
	var height01 := clampf((v.y + h.y) / maxf(h.y * 2.0, 0.01), 0.0, 1.0)
	var foot := lerpf(0.6, 1.0, smoothstep(0.0, 0.4, height01))
	var inset := 1.0 - clampf(0.3 - maxf(absf(v.x) - h.x, absf(v.z) - h.z), 0.0, 0.3) * 0.5
	var g := foot * inset
	return Color(g, g, g)
