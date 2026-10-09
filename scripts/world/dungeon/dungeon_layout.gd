class_name DungeonLayout
extends RefCounted
## M13: a baked dungeon layout (tools/worldgen/dungeon_bake.py): rooms with a
## floor height or a slope, the doorways between them, the merged wall boxes
## and the points of interest (a ZoneLayout, so POI lookups, the map bounds
## and tests work as in the Highlands). The floor heights here are the
## ground seam of a dungeon zone (`DungeonZone.ground_y`).

var pois: ZoneLayout
var rooms: Array[Dictionary] = []
var doors: Array[Dictionary] = []
var walls: Array[Dictionary] = []
## M13 phase 2: sunken water channels in rooms ({id, room, rect, floor, depth}).
var channels: Array[Dictionary] = []
var base_y: float = -1.0
var entry: String = ""
var _rooms_by_id: Dictionary = {}
var _doors_by_id: Dictionary = {}


static func load_from(dir: String) -> DungeonLayout:
	var l := DungeonLayout.new()
	l.pois = ZoneLayout.load_from(dir.path_join("layout.json"))
	var raw := l.pois.raw
	l.base_y = float(raw.get("base_y", -1.0))
	l.entry = String(raw.get("entry", ""))
	for r in raw.get("rooms", []):
		l.rooms.append(r as Dictionary)
		l._rooms_by_id[String(r["id"])] = r
	for d in raw.get("doors", []):
		l.doors.append(d as Dictionary)
		l._doors_by_id[String(d["id"])] = d
	for w in raw.get("walls", []):
		l.walls.append(w as Dictionary)
	for c in raw.get("channels", []):
		l.channels.append(c as Dictionary)
	return l


func channel(id: String) -> Dictionary:
	for c in channels:
		if String(c.get("id", "")) == id:
			return c
	return {}


## The channels inside a room.
func channels_of(room_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in channels:
		if String(c.get("room", "")) == room_id:
			out.append(c)
	return out


static func rect_of(entry: Dictionary) -> Rect2:
	var r: Array = entry.get("rect", [0, 0, 0, 0])
	return Rect2(float(r[0]), float(r[1]), float(r[2]) - float(r[0]), float(r[3]) - float(r[1]))


static func _inside(rect: Rect2, x: float, z: float, margin: float = 0.0) -> bool:
	return x >= rect.position.x + margin and x <= rect.end.x - margin \
		and z >= rect.position.y + margin and z <= rect.end.y - margin


func room(id: String) -> Dictionary:
	return _rooms_by_id.get(id, {})


func door(id: String) -> Dictionary:
	return _doors_by_id.get(id, {})


func room_at(x: float, z: float) -> Dictionary:
	for r in rooms:
		if _inside(rect_of(r), x, z):
			return r
	return {}


func door_at(x: float, z: float) -> Dictionary:
	for d in doors:
		if _inside(rect_of(d), x, z):
			return d
	return {}


## Floor of a room at a point: flat, or a slope along x / z over a span.
static func room_floor(r: Dictionary, x: float, z: float) -> float:
	var slope: Dictionary = r.get("slope", {})
	if slope.is_empty():
		return float(r.get("floor", 0.0))
	var c := x if String(slope.get("axis", "z")) == "x" else z
	var span: Array = slope["span"]
	var ys: Array = slope["y"]
	var t := clampf((c - float(span[0])) / (float(span[1]) - float(span[0])), 0.0, 1.0)
	return lerpf(float(ys[0]), float(ys[1]), t)


## The floor under a point (a room or a doorway); `fallback` outside both.
func floor_at(x: float, z: float, fallback: float = 0.0) -> float:
	var r := room_at(x, z)
	if not r.is_empty():
		for c in channels:  # a channel's bed lies below its room's floor
			if String(c.get("room", "")) == String(r.get("id", "")) and _inside(rect_of(c), x, z):
				return float(c.get("floor", 0.0)) - float(c.get("depth", 0.0))
		return room_floor(r, x, z)
	var d := door_at(x, z)
	if not d.is_empty():
		return float(d.get("floor", 0.0))
	return fallback


func is_walkable(x: float, z: float) -> bool:
	return not room_at(x, z).is_empty() or not door_at(x, z).is_empty()


## `pos` moved into the nearest room (at least `margin` from its walls) when it
## stands outside every room and doorway (a late joiner's spot beside a hero).
func clamp_inside(pos: Vector3, margin: float = 1.0) -> Vector3:
	if is_walkable(pos.x, pos.z):
		return pos
	var best := pos
	var best_d := INF
	for r in rooms:
		var rect := rect_of(r).grow(-margin)
		var p := Vector2(clampf(pos.x, rect.position.x, rect.end.x), clampf(pos.z, rect.position.y, rect.end.y))
		var d := p.distance_squared_to(Vector2(pos.x, pos.z))
		if d < best_d:
			best_d = d
			best = Vector3(p.x, room_floor(r, p.x, p.y), p.y)
	return best


func bounds() -> Rect2:
	return pois.bounds()


## Rooms carrying a tag ("secret", "roofed", "arena", "combat", "entry").
func rooms_tagged(tag: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in rooms:
		if tag in (r.get("tags", []) as Array):
			out.append(r)
	return out
