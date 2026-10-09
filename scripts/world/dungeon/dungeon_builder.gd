class_name DungeonBuilder
extends Object
## M13: builds a dungeon from its baked DungeonLayout - floors (flat rooms,
## slopes, doorways), the merged wall boxes, roofs over "roofed" rooms, the
## plugs in doorways that are not open yet, room lights - and dispatches the
## points of interest by type like PoiBuilder does for the open zones.
## Colliders are one StaticBody per kind (world layer 1) with a shape per
## piece; the visible surfaces are merged into a few meshes per 32 m chunk,
## so a whole dungeon costs a handful of draw calls and still culls.

const CHUNK_M := 32.0
const FLOOR_THICK := 1.0
const RAMP_THICK := 0.6
const ROOF_THICK := 0.6
## Room lights: no shadows, faded out at range (Forward+ budget, ART_BIBLE).
const LIGHT_RANGE := 10.0
const LIGHT_HEIGHT := 2.6
const LIGHT_FADE_BEGIN := 38.0
const LIGHT_INSET := 3.2
const MAX_ROOM_LIGHTS := 4

## Visual pieces waiting to be merged: material -> chunk key -> SurfaceTool.
var _tools: Dictionary = {}
var zone: ZoneBase
var layout: DungeonLayout
var floor_body: StaticBody3D
var wall_body: StaticBody3D
## Doorways closed by a solid plug (secret walls, shortcut bars) by door id.
var plugs: Dictionary = {}
var lights: Array[OmniLight3D] = []


static func build(z: ZoneBase, l: DungeonLayout, floor_mat: Material, wall_mat: Material,
		light_color: Color) -> DungeonBuilder:
	var b := DungeonBuilder.new()
	b.zone = z
	b.layout = l
	b.floor_body = b._body("DungeonFloor")
	b.wall_body = b._body("DungeonWalls")
	for r in l.rooms:
		b._room_floor(r, floor_mat)
		if "roofed" in (r.get("tags", []) as Array):
			b._roof(r, wall_mat)
		b._room_lights(r, light_color)
	for d in l.doors:
		var rect := DungeonLayout.rect_of(d)
		var y := float(d.get("floor", 0.0))
		b._piece(b.floor_body, floor_mat, Vector3(rect.get_center().x, y - FLOOR_THICK * 0.5, rect.get_center().y),
			Vector3(rect.size.x, FLOOR_THICK, rect.size.y))
		if String(d.get("kind", "open")) in ["secret", "shortcut"]:
			b.plugs[String(d["id"])] = b._plug(d, wall_mat)
	for w in l.walls:
		var rect := DungeonLayout.rect_of(w)
		var top := float(w.get("top", 7.0))
		b._piece(b.wall_body, wall_mat, Vector3(rect.get_center().x, (l.base_y + top) * 0.5, rect.get_center().y),
			Vector3(rect.size.x, top - l.base_y, rect.size.y))
	b._commit()
	return b


func _body(body_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = 1
	body.collision_mask = 0
	zone.world.add_child(body, true)
	return body


## One box: a collision shape on `body` and the same box in the merged mesh.
func _piece(body: StaticBody3D, mat: Material, centre: Vector3, size: Vector3, basis: Basis = Basis()) -> void:
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.transform = Transform3D(basis, centre)
	body.add_child(col)
	_append_box(mat, Transform3D(basis, centre), size)


func _append_box(mat: Material, xform: Transform3D, size: Vector3) -> void:
	var key := Vector2i(floori(xform.origin.x / CHUNK_M), floori(xform.origin.z / CHUNK_M))
	if not _tools.has(mat):
		_tools[mat] = {}
	var by_chunk: Dictionary = _tools[mat]
	if not by_chunk.has(key):
		by_chunk[key] = SurfaceTool.new()
	var box := BoxMesh.new()
	box.size = size
	(by_chunk[key] as SurfaceTool).append_from(box, 0, xform)


func _commit() -> void:
	var holder := Node3D.new()
	holder.name = "DungeonMesh"
	zone.world.add_child(holder, true)
	for mat: Material in _tools:
		var by_chunk: Dictionary = _tools[mat]
		for key: Vector2i in by_chunk:
			var mi := MeshInstance3D.new()
			mi.name = "Chunk_%d_%d" % [key.x, key.y]
			mi.mesh = (by_chunk[key] as SurfaceTool).commit()
			mi.material_override = mat
			holder.add_child(mi, true)
	_tools.clear()


## A room's floor: one slab when flat; a slope splits it into the flat ends
## and a tilted slab whose top runs exactly between them.
func _room_floor(r: Dictionary, mat: Material) -> void:
	var rect := DungeonLayout.rect_of(r)
	var slope: Dictionary = r.get("slope", {})
	if slope.is_empty():
		var y := float(r.get("floor", 0.0))
		_piece(floor_body, mat, Vector3(rect.get_center().x, y - FLOOR_THICK * 0.5, rect.get_center().y),
			Vector3(rect.size.x, FLOOR_THICK, rect.size.y))
		return
	var along_x := String(slope.get("axis", "z")) == "x"
	var span: Array = slope["span"]
	var ys: Array = slope["y"]
	var a := float(span[0])
	var b := float(span[1])
	var lo := rect.position.x if along_x else rect.position.y
	var hi := rect.end.x if along_x else rect.end.y
	var width := rect.size.y if along_x else rect.size.x
	var across := rect.get_center().y if along_x else rect.get_center().x
	var flat := func(from: float, to: float, y: float) -> void:
		if to - from < 0.01:
			return
		var mid := (from + to) * 0.5
		var centre := Vector3(mid, y - FLOOR_THICK * 0.5, across) if along_x else Vector3(across, y - FLOOR_THICK * 0.5, mid)
		var size := Vector3(to - from, FLOOR_THICK, width) if along_x else Vector3(width, FLOOR_THICK, to - from)
		_piece(floor_body, mat, centre, size)
	flat.call(lo, minf(a, b), float(ys[0]) if a < b else float(ys[1]))
	flat.call(maxf(a, b), hi, float(ys[1]) if a < b else float(ys[0]))
	# the tilted slab: local X along the slope, Y its upward normal
	var y0 := float(ys[0])
	var y1 := float(ys[1])
	var run := b - a
	var dir := Vector3(run, y1 - y0, 0.0) if along_x else Vector3(0.0, y1 - y0, run)
	var length := dir.length()
	dir = dir / length
	var normal := Vector3(-(y1 - y0), run, 0.0).normalized() if along_x else Vector3(0.0, run, -(y1 - y0)).normalized()
	if normal.y < 0.0:
		normal = -normal
	var basis := Basis(dir, normal, dir.cross(normal))
	var top_mid := Vector3((a + b) * 0.5, (y0 + y1) * 0.5, across) if along_x else Vector3(across, (y0 + y1) * 0.5, (a + b) * 0.5)
	_piece(floor_body, mat, top_mid - normal * RAMP_THICK * 0.5, Vector3(length, RAMP_THICK, width), basis)


## A lid over a roofed room (the secret vault, the tome room): the camera's
## spring arm stays under it, and from outside the room reads as rock.
func _roof(r: Dictionary, mat: Material) -> void:
	var rect := DungeonLayout.rect_of(r).grow(1.5)
	var top := DungeonLayout.room_floor(r, rect.get_center().x, rect.get_center().y) + float(r.get("wall_h", 7.0))
	_piece(wall_body, mat, Vector3(rect.get_center().x, top - ROOF_THICK * 0.5, rect.get_center().y),
		Vector3(rect.size.x, ROOF_THICK, rect.size.y))


## A doorway that is not open yet: a solid block filling it, as high as the
## lower wall beside it (a cracked wall, a barred shortcut).
func _plug(d: Dictionary, mat: Material) -> StaticBody3D:
	var rect := DungeonLayout.rect_of(d)
	var y := float(d.get("floor", 0.0))
	var h := float(d.get("wall_h", 6.0))
	var body := zone._add_box(Vector3(rect.get_center().x, y + h * 0.5, rect.get_center().y),
		Vector3(rect.size.x, h, rect.size.y), mat)
	body.name = "Plug_" + String(d["id"])
	return body


## Up to four lights per room: in from the corners of a hall, along the
## middle of a corridor; none in secret rooms (their own light comes with
## their content).
func _room_lights(r: Dictionary, color: Color) -> void:
	if "secret" in (r.get("tags", []) as Array):
		return
	var rect := DungeonLayout.rect_of(r)
	var spots: Array[Vector2] = []
	var short_side := minf(rect.size.x, rect.size.y)
	if short_side >= 12.0:
		var inner := rect.grow(-LIGHT_INSET)
		spots = [inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]
	else:
		var along_x := rect.size.x >= rect.size.y
		var length := rect.size.x if along_x else rect.size.y
		var count := clampi(int(length / 14.0), 1, MAX_ROOM_LIGHTS)
		for i in count:
			var t := (i + 0.5) / count
			spots.append(Vector2(lerpf(rect.position.x, rect.end.x, t), rect.get_center().y) if along_x
				else Vector2(rect.get_center().x, lerpf(rect.position.y, rect.end.y, t)))
	for s in spots:
		var light := OmniLight3D.new()
		light.light_color = color
		light.light_energy = 1.7
		light.omni_range = LIGHT_RANGE
		light.omni_attenuation = 0.8
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = LIGHT_FADE_BEGIN
		light.distance_fade_length = 10.0
		zone.world.add_child(light)
		light.global_position = Vector3(s.x, DungeonLayout.room_floor(r, s.x, s.y) + LIGHT_HEIGHT, s.y)
		lights.append(light)


# ---------------------------------------------------------------------------
# Points of interest
# ---------------------------------------------------------------------------

## Returns what the zone wants to remember for a POI ({} for most).
static func build_poi(z: ZoneBase, poi: Dictionary) -> Dictionary:
	match String(poi.get("type", "")):
		"portal":
			return {"portal": PoiBuilder.portal(z, poi)}
		"chest":
			return {"chest": PoiBuilder.chest(z, poi)}
		"camp":
			return {"spawner": camp(z, poi)}
		"lore":
			return {"lore": LoreObject.build(z, poi)}
	return {}


## A camp inside a room: fixed spots (the default ring could land in a wall),
## a leash about the room's size, saved clears (respawn after its minutes,
## never while a hero is near).
static func camp(z: ZoneBase, poi: Dictionary) -> EncounterSpawner:
	var spawner := EncounterSpawner.new()
	var id := String(poi.get("id", ""))
	spawner.name = "Camp_" + id
	spawner.composition = PoiBuilder.composition_of(poi)
	spawner.trigger_radius = float(poi.get("radius", 10.0))
	spawner.camp_id = id
	spawner.respawn_minutes = float(poi.get("respawn_min", 10.0))
	spawner.rearm_radius = float(poi.get("rearm_radius", 30.0))
	spawner.leash = float(poi.get("leash", 18.0))
	var ys: Array = poi.get("spots_y", [])
	var spots: Array = poi.get("spots", [])
	for i in spots.size():
		var s: Array = spots[i]
		spawner.spots.append(Vector3(float(s[0]), float(ys[i]) if i < ys.size() else 0.0, float(s[1])))
	spawner.set_meta(&"poi_id", id)
	z.world.add_child(spawner)
	spawner.global_position = ZoneLayout.pos_of(poi)
	return spawner
