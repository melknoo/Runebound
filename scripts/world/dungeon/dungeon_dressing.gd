class_name DungeonDressing
extends Object
## M13: rule-placed dressing of a dungeon from its kit - nothing hand-placed,
## nothing with collision (relief on wall faces <= 0.3 m proud, lamps above
## head height, grates flush in the floor, scatter at the walls' feet):
##   arch     relief arches on the long walls of halls, every ~8 m
##   pipe     pipe runs along one wall of corridors, 3 m up
##   grate    a drain in each larger hall
##   sluice   a sluice frame where a channel meets a wall
##   scatter  [{prop, per_m, band, scale, cluster, spread}] at the walls' feet
## Doors, POIs and channels keep their spots clear. Seeded: the same look on
## every machine and every visit.

const ARCH_EVERY := 8.0
const DOOR_CLEAR := 3.4
const POI_CLEAR := 2.4


static func dress(zone: DungeonZone, kit: Dictionary, seed_value: int) -> void:
	var layout := zone.layout
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var pois: Array[Vector3] = []
	for poi in layout.pois.pois:
		pois.append(ZoneLayout.pos_of(poi))
	for r in layout.rooms:
		var rect := DungeonLayout.rect_of(r)
		var hall := minf(rect.size.x, rect.size.y) >= 12.0
		var sloped := not (r.get("slope", {}) as Dictionary).is_empty()
		for side in 4:
			var face := _face(rect, side)
			var inward: Vector2 = face["inward"]
			var a: Vector2 = face["a"]
			var b: Vector2 = face["b"]
			var length := a.distance_to(b)
			if hall and kit.has("arch"):
				var count := int(length / ARCH_EVERY)
				for k in count:
					var t := (k + 0.5) / float(count)
					var p := a.lerp(b, t)
					if _blocked(zone, p, pois):
						continue
					_place(zone, String(kit["arch"]), p, r, inward)
			if not hall and not sloped and kit.has("pipe") and side == _long_side(rect) and length >= 8.0:
				var runs := int(length / 4.0)
				for k in runs:
					var p := a.lerp(b, (k + 0.5) / float(runs)) + inward * 0.18
					if _blocked(zone, p, pois):
						continue
					var at := Vector3(p.x, DungeonLayout.room_floor(r, p.x, p.y) + 3.0, p.y)
					SetPieces.prop(zone.dressing(), String(kit["pipe"]), at, atan2(inward.x, inward.y))
		if hall and kit.has("grate") and rect.get_area() >= 300.0 and not sloped:
			for attempt in 12:
				var g := Vector2(rng.randf_range(rect.position.x + 3.0, rect.end.x - 3.0), rng.randf_range(rect.position.y + 3.0, rect.end.y - 3.0))
				if _blocked(zone, g, pois, 3.0) or _in_channel(layout, g):
					continue
				SetPieces.prop(zone.dressing(), String(kit["grate"]), Vector3(g.x, DungeonLayout.room_floor(r, g.x, g.y) + 0.002, g.y),
					rng.randf_range(0.0, PI))
				break
	if kit.has("sluice"):
		for c in layout.channels:
			var crect := DungeonLayout.rect_of(c)
			var room := layout.room(String(c.get("room", "")))
			var rr := DungeonLayout.rect_of(room)
			var y := float(c.get("floor", 0.0))
			if crect.size.x >= crect.size.y:  # across the room west-east: frames on both end walls
				for end_x: float in [rr.position.x, rr.end.x]:
					var inward := Vector2(1.0 if end_x == rr.position.x else -1.0, 0.0)
					SetPieces.prop(zone.dressing(), String(kit["sluice"]), Vector3(end_x, y, crect.get_center().y),
						atan2(inward.x, inward.y))
			else:
				for end_z: float in [rr.position.y, rr.end.y]:
					var inward := Vector2(0.0, 1.0 if end_z == rr.position.y else -1.0)
					SetPieces.prop(zone.dressing(), String(kit["sluice"]), Vector3(crect.get_center().x, y, end_z),
						atan2(inward.x, inward.y))
	if kit.has("scatter"):
		_scatter(zone, kit["scatter"] as Array, seed_value + 7)


## Side 0..3 (north, south, west, east) of a room: its end points and the
## direction into the room.
static func _face(rect: Rect2, side: int) -> Dictionary:
	match side:
		0: return {"a": rect.position, "b": Vector2(rect.end.x, rect.position.y), "inward": Vector2(0, 1)}
		1: return {"a": Vector2(rect.position.x, rect.end.y), "b": rect.end, "inward": Vector2(0, -1)}
		2: return {"a": rect.position, "b": Vector2(rect.position.x, rect.end.y), "inward": Vector2(1, 0)}
	return {"a": Vector2(rect.end.x, rect.position.y), "b": rect.end, "inward": Vector2(-1, 0)}


static func _long_side(rect: Rect2) -> int:
	return 0 if rect.size.x >= rect.size.y else 2


## Near a doorway, a POI or a channel's mouth.
static func _blocked(zone: DungeonZone, p: Vector2, pois: Array[Vector3], poi_clear: float = POI_CLEAR) -> bool:
	for d in zone.layout.doors:
		if DungeonLayout.rect_of(d).get_center().distance_to(p) < DOOR_CLEAR + float(d.get("width", 4.0)) * 0.5:
			return true
	for q in pois:
		if Vector2(q.x, q.z).distance_to(p) < poi_clear:
			return true
	for c in zone.layout.channels:
		if DungeonLayout.rect_of(c).grow(1.2).has_point(p):
			return true
	return false


static func _in_channel(layout: DungeonLayout, p: Vector2) -> bool:
	for c in layout.channels:
		if DungeonLayout.rect_of(c).grow(1.0).has_point(p):
			return true
	return false


## Scatter at the walls' feet, only on walkable floor out of the channels.
static func _scatter(zone: DungeonZone, items: Array, seed_value: int) -> void:
	var layout := zone.layout
	var obstacles: Array[Dictionary] = []
	for w in layout.walls:
		var rect := DungeonLayout.rect_of(w)
		obstacles.append({"pos": Vector3(rect.get_center().x, 0.0, rect.get_center().y),
			"size": Vector3(rect.size.x, 4.0, rect.size.y), "yaw": 0.0})
	var exclude: Array[Vector3] = []
	for poi in layout.pois.pois:
		var p := ZoneLayout.pos_of(poi)
		exclude.append(Vector3(p.x, p.z, 2.2))
	for d in layout.doors:
		var c := DungeonLayout.rect_of(d).get_center()
		exclude.append(Vector3(c.x, c.y, float(d.get("width", 4.0)) * 0.5 + 1.0))
	var keep := func(x: float, z: float) -> float:
		return 1.0 if layout.is_walkable(x, z) and not _in_channel(layout, Vector2(x, z)) else 0.0
	var dressed: Array = []
	for item: Dictionary in items:
		var it := item.duplicate()
		it["weight"] = keep
		dressed.append(it)
	Scatter.populate(zone, {
		"area": layout.bounds(),
		"obstacles": obstacles,
		"exclude": exclude,
		"height_at": func(x: float, z: float) -> float: return layout.floor_at(x, z, 0.0),
		"seed": seed_value,
		"items": dressed,
	})


static func _place(zone: DungeonZone, prop_name: String, p: Vector2, room: Dictionary, inward: Vector2) -> void:
	SetPieces.prop(zone.dressing(), prop_name, Vector3(p.x, DungeonLayout.room_floor(room, p.x, p.y), p.y),
		atan2(inward.x, inward.y))
