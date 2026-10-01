class_name ZoneLayout
extends RefCounted
## Baked open-zone layout (M08): the JSON that tools/worldgen/bake.py writes
## from the declarative layout — points of interest with their baked ground
## height, routes, named areas and the level-band grid. Zones build their
## content from this; tests and runners address positions by POI id.

var raw: Dictionary = {}
var size_m: float = 0.0
var origin: Vector2 = Vector2.ZERO
var pois: Array[Dictionary] = []
var routes: Array[Dictionary] = []
var areas: Array[Dictionary] = []
## M12: sub-biome ids by mask channel (R, G, B); "ash" is where all are 0.
var biome_ids: Array[String] = []
var _by_id: Dictionary = {}
var _dir: String = ""
var _biome_img: Image = null
var _biome_px_per_m: float = 1.0


static func load_from(path: String) -> ZoneLayout:
	var l := ZoneLayout.new()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_warning("ZoneLayout: cannot read " + path)
		return l
	l.raw = parsed
	l._dir = path.get_base_dir()
	l.size_m = float(l.raw.get("size_m", 0.0))
	var o: Array = l.raw.get("origin", [0, 0])
	l.origin = Vector2(float(o[0]), float(o[1]))
	for p in l.raw.get("pois", []):
		l.pois.append(p as Dictionary)
		l._by_id[String(p["id"])] = p
	for r in l.raw.get("routes", []):
		l.routes.append(r as Dictionary)
	for a in l.raw.get("areas", []):
		l.areas.append(a as Dictionary)
	var baked: Dictionary = l.raw.get("baked", {})
	for id in baked.get("biome_ids", []):
		l.biome_ids.append(String(id))
	l._biome_px_per_m = float(baked.get("biome_px_per_m", 1.0))
	return l


func find(id: String) -> Dictionary:
	return _by_id.get(id, {})


func by_type(type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in pois:
		if String(p.get("type", "")) == type:
			out.append(p)
	return out


## World position of a POI (or a sub-entry with "pos" + "y", e.g. an arena
## portal). Baked y = ground height at the centre.
static func pos_of(entry: Dictionary) -> Vector3:
	var p: Array = entry.get("pos", [0, 0])
	return Vector3(float(p[0]), float(entry.get("y", 0.0)), float(p[1]))


func poi_pos(id: String) -> Vector3:
	return pos_of(find(id))


## Enemy level from the band grid (row 0 = north, col 0 = west).
func level_at(x: float, z: float) -> int:
	var bands: Dictionary = raw.get("bands", {})
	var grid: Array = bands.get("grid", [])
	if grid.is_empty():
		return 1
	var cell := float(bands.get("cell_m", 48.0))
	var row := clampi(int((z - origin.y) / cell), 0, grid.size() - 1)
	var cols: Array = grid[row]
	var col := clampi(int((x - origin.x) / cell), 0, cols.size() - 1)
	return int(cols[col])


## Map rectangle on XZ (world metres).
func bounds() -> Rect2:
	return Rect2(origin, Vector2.ONE * size_m)


## Route polyline as world points (baked ground height is not stored for
## routes; callers use the terrain).
func route_points(id: String) -> PackedVector2Array:
	var out := PackedVector2Array()
	for r in routes:
		if String(r.get("id", "")) == id:
			for p in r.get("points", []):
				out.append(Vector2(float(p[0]), float(p[1])))
	return out


# --- M12 sub-biomes ----------------------------------------------------------

## The baked weight mask (R, G, B = biome_ids[0..2]); read from the PNG's
## bytes, so it works the same headless and on the dedicated server. Null
## when the zone has none.
func biome_image() -> Image:
	if _biome_img != null or biome_ids.is_empty():
		return _biome_img
	var file := _dir.path_join(String(raw.get("baked", {}).get("biome_file", "biome_mask.png")))
	if not FileAccess.file_exists(file):
		return null
	var img := Image.new()
	if img.load_png_from_buffer(FileAccess.get_file_as_bytes(file)) != OK:
		push_warning("ZoneLayout: cannot read " + file)
		return null
	_biome_img = img
	return _biome_img


## The mask as a texture for the terrain shader (null without a mask).
func biome_texture() -> Texture2D:
	var img := biome_image()
	return ImageTexture.create_from_image(img) if img != null else null


## Weights of the three sub-biomes at a point (bilinear, 0..1 each, their
## sum <= 1; the rest is ash). Zero without a mask.
func biome_weights(x: float, z: float) -> Vector3:
	var img := biome_image()
	if img == null:
		return Vector3.ZERO
	var fx := clampf((x - origin.x) * _biome_px_per_m - 0.5, 0.0, img.get_width() - 1.001)
	var fz := clampf((z - origin.y) * _biome_px_per_m - 0.5, 0.0, img.get_height() - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var c00 := img.get_pixel(ix, iz)
	var c10 := img.get_pixel(ix + 1, iz)
	var c01 := img.get_pixel(ix, iz + 1)
	var c11 := img.get_pixel(ix + 1, iz + 1)
	var c := c00.lerp(c10, tx).lerp(c01.lerp(c11, tx), tz)
	return Vector3(c.r, c.g, c.b)


## Weight of one sub-biome (by id) at a point; "ash" = what the others leave.
func biome_weight(id: String, x: float, z: float) -> float:
	var w := biome_weights(x, z)
	if id == "ash":
		return clampf(1.0 - w.x - w.y - w.z, 0.0, 1.0)
	var k := biome_ids.find(id)
	return w[k] if k >= 0 and k < 3 else 0.0


## The sub-biome a point belongs to ("ash" unless one holds at least half).
func biome_at(x: float, z: float) -> String:
	var w := biome_weights(x, z)
	var k := 0
	for i in 3:
		if w[i] > w[k]:
			k = i
	return biome_ids[k] if w[k] >= 0.5 and k < biome_ids.size() else "ash"


## Bounding rectangle of a sub-biome's shapes plus its blend (XZ, metres);
## the whole zone for "ash" or an unknown id.
func biome_rect(id: String) -> Rect2:
	for b in raw.get("biomes", []):
		if String(b.get("id", "")) != id:
			continue
		var r := Rect2()
		var first := true
		var grow := float(b.get("blend_m", 12.0))
		for shape: Dictionary in b.get("shapes", []):
			var box: Rect2
			if shape.has("circle"):
				var c: Array = shape["circle"]
				box = Rect2(float(c[0]) - float(c[2]), float(c[1]) - float(c[2]), float(c[2]) * 2.0, float(c[2]) * 2.0)
			else:
				var cap: Array = shape["capsule"]
				var a := Vector2(float(cap[0][0]), float(cap[0][1]))
				var e := Vector2(float(cap[1][0]), float(cap[1][1]))
				var rad := float(cap[2])
				box = Rect2(a, Vector2.ZERO).expand(e).grow(rad)
			r = box if first else r.merge(box)
			first = false
		return r.grow(grow).intersection(bounds())
	return bounds()
