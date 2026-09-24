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
var _by_id: Dictionary = {}


static func load_from(path: String) -> ZoneLayout:
	var l := ZoneLayout.new()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_warning("ZoneLayout: cannot read " + path)
		return l
	l.raw = parsed
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
