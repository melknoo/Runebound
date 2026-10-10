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
## Room lights: no shadows, faded out at range (Forward+ budget, ART_BIBLE),
## each a lamp on a bracket a step out from a wall.
const LIGHT_RANGE := 10.0
const LIGHT_HEIGHT := 2.9
const LIGHT_FADE_BEGIN := 38.0
const LIGHT_INSET := 1.0
const MAX_ROOM_LIGHTS := 4
## Cap course on every wall (above the top, a hair wider: the camera's margin).
const CAP_HEIGHT := 0.18
const CAP_OVERHANG := 0.12

## Visual pieces waiting to be merged: material -> chunk key -> SurfaceTool.
var _tools: Dictionary = {}
var zone: ZoneBase
var layout: DungeonLayout
var floor_body: StaticBody3D
var wall_body: StaticBody3D
## Doorways closed by a solid plug (a shortcut without a lever) by door id.
var plugs: Dictionary = {}
## M13 phase 2: the secret doorways' cracked walls by door id.
var secret_walls: Dictionary = {}
## M13 phase 4: the kit's lantern prop (origin at the lantern, its arm back to
## the wall along -Z); "" = the code-built lamp boxes.
var lamp_prop: String = ""
var lights: Array[OmniLight3D] = []


static func build(z: ZoneBase, l: DungeonLayout, floor_mat: Material, wall_mat: Material,
		light_color: Color, lamp_prop: String = "") -> DungeonBuilder:
	var b := DungeonBuilder.new()
	b.zone = z
	b.layout = l
	b.lamp_prop = lamp_prop if lamp_prop != "" and SetPieces.prop_path(lamp_prop) != "" and Net.has_view() else ""
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
		var kind := String(d.get("kind", "open"))
		if kind == "secret":  # M13 phase 2: a cracked wall that breaks
			b.secret_walls[String(d["id"])] = SecretWall.build(z, d, wall_mat)
		elif kind == "shortcut" and (d.get("inputs", []) as Array).is_empty():
			b.plugs[String(d["id"])] = b._plug(d, wall_mat)  # bars with a lever come as a gate
	for w in l.walls:
		var rect := DungeonLayout.rect_of(w)
		var top := float(w.get("top", 7.0))
		b._piece(b.wall_body, wall_mat, Vector3(rect.get_center().x, (l.base_y + top) * 0.5, rect.get_center().y),
			Vector3(rect.size.x, top - l.base_y, rect.size.y))
		b._append_box(wall_mat, Transform3D(Basis(), Vector3(rect.get_center().x, top + CAP_HEIGHT * 0.5, rect.get_center().y)),
			Vector3(rect.size.x + CAP_OVERHANG * 2.0, CAP_HEIGHT, rect.size.y + CAP_OVERHANG * 2.0))  # visual only
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
		# M13 phase 2: a room with channels stands on columns down to base_y,
		# the channels' beds lower (their sides are the columns' faces)
		var y := float(r.get("floor", 0.0))
		var holes: Array[Rect2] = []
		for c in layout.channels_of(String(r.get("id", ""))):
			var hole := DungeonLayout.rect_of(c)
			holes.append(hole)
			var bed := y - float(c.get("depth", 0.0))
			_piece(floor_body, mat, Vector3(hole.get_center().x, (layout.base_y + bed) * 0.5, hole.get_center().y),
				Vector3(hole.size.x, bed - layout.base_y, hole.size.y))
		if holes.is_empty():
			_piece(floor_body, mat, Vector3(rect.get_center().x, y - FLOOR_THICK * 0.5, rect.get_center().y),
				Vector3(rect.size.x, FLOOR_THICK, rect.size.y))
			return
		for part in subtract(rect, holes):
			_piece(floor_body, mat, Vector3(part.get_center().x, (layout.base_y + y) * 0.5, part.get_center().y),
				Vector3(part.size.x, y - layout.base_y, part.size.y))
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


## `rect` minus `holes` as non-overlapping rectangles (guillotine cuts).
static func subtract(rect: Rect2, holes: Array[Rect2]) -> Array[Rect2]:
	var parts: Array[Rect2] = [rect]
	for hole in holes:
		var next: Array[Rect2] = []
		for p in parts:
			var cut := p.intersection(hole)
			if not cut.has_area():
				next.append(p)
				continue
			if cut.position.y > p.position.y:  # north strip
				next.append(Rect2(p.position.x, p.position.y, p.size.x, cut.position.y - p.position.y))
			if cut.end.y < p.end.y:  # south strip
				next.append(Rect2(p.position.x, cut.end.y, p.size.x, p.end.y - cut.end.y))
			if cut.position.x > p.position.x:  # west, between the strips
				next.append(Rect2(p.position.x, cut.position.y, cut.position.x - p.position.x, cut.size.y))
			if cut.end.x < p.end.x:  # east
				next.append(Rect2(cut.end.x, cut.position.y, p.end.x - cut.end.x, cut.size.y))
		parts = next
	return parts


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


## Up to four lamps per room, each on a bracket at a wall: a hall's on its
## long walls a third and two thirds along, a corridor's along one side;
## secret rooms bring their own light. `wall_dir` points from lamp to wall.
func _room_lights(r: Dictionary, color: Color) -> void:
	var rect := DungeonLayout.rect_of(r)
	var spots: Array[Vector2] = []
	var walls: Array[Vector2] = []
	var along_x := rect.size.x >= rect.size.y
	var length := rect.size.x if along_x else rect.size.y
	var short_side := minf(rect.size.x, rect.size.y)
	var sides: Array[float] = [-1.0]
	if short_side >= 12.0:
		sides.append(1.0)
	var per_side := 2 if short_side >= 12.0 else clampi(int(length / 14.0), 1, MAX_ROOM_LIGHTS)
	for side in sides:
		for i in per_side:
			var t := (i + 1.0) / (per_side + 1.0)
			var along := lerpf(rect.position.x if along_x else rect.position.y, rect.end.x if along_x else rect.end.y, t)
			var edge := (rect.get_center().y + side * (rect.size.y * 0.5 - LIGHT_INSET)) if along_x else (rect.get_center().x + side * (rect.size.x * 0.5 - LIGHT_INSET))
			spots.append(Vector2(along, edge) if along_x else Vector2(edge, along))
			walls.append(Vector2(0.0, side) if along_x else Vector2(side, 0.0))
	if "secret" in (r.get("tags", []) as Array):
		spots = spots.slice(0, 1)  # one dim lamp: it reads as a hidden room, not a dark box
	var glow := _lamp_material(color)
	for k in spots.size():
		var s := spots[k]
		var y := DungeonLayout.room_floor(r, s.x, s.y) + LIGHT_HEIGHT
		if lamp_prop != "":
			SetPieces.prop(zone.dressing(), lamp_prop, Vector3(s.x, y, s.y), atan2(-walls[k].x, -walls[k].y))
		else:
			_append_box(glow, Transform3D(Basis(), Vector3(s.x, y, s.y)), Vector3(0.26, 0.38, 0.26))
			var to_wall := walls[k] * (LIGHT_INSET * 0.5 + 0.1)
			_append_box(_bracket_mat, Transform3D(Basis(), Vector3(s.x + to_wall.x, y + 0.24, s.y + to_wall.y)),
				Vector3(0.1 + absf(to_wall.x) * 2.0, 0.08, 0.1 + absf(to_wall.y) * 2.0))
		var light := OmniLight3D.new()
		light.light_color = color
		light.light_energy = 2.2
		light.omni_range = LIGHT_RANGE
		light.omni_attenuation = 0.8
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = LIGHT_FADE_BEGIN
		light.distance_fade_length = 10.0
		zone.world.add_child(light)
		light.global_position = Vector3(s.x, y - 0.1, s.y)
		lights.append(light)


var _lamp_mats: Dictionary = {}
var _bracket_mat: Material = EnemyBase.flat_material(Color(0.16, 0.17, 0.18))


func _lamp_material(color: Color) -> Material:
	if not _lamp_mats.has(color):
		_lamp_mats[color] = EnemyBase.flat_material(color, true, 2.6)
	return _lamp_mats[color]


# ---------------------------------------------------------------------------
# Points of interest
# ---------------------------------------------------------------------------

## Returns what the zone wants to remember for a POI ({} for most).
static func build_poi(z: ZoneBase, l: DungeonLayout, poi: Dictionary) -> Dictionary:
	match String(poi.get("type", "")):
		"portal":
			var p := PoiBuilder.portal(z, poi)
			if poi.has("unlock_flag"):  # M13: the way out behind the end boss
				p.set_locked(not SaveGame.has_flag(StringName(String(poi["unlock_flag"]))))
			return {"portal": p}
		"chest":
			return {"chest": PoiBuilder.chest(z, poi, Vector3.INF, true)}  # dungeon chests open once
		"camp":
			return {"spawner": camp(z, poi)}
		"lore":
			return {"lore": LoreObject.build(z, poi)}
		"rune":
			var r := DungeonRune.build(z, poi)
			return {"rune": r, "puzzle": r}
		"arena":
			return {"arena": arena(z, l, poi)}
		"lever":  # M13 phase 2: the mechanical puzzle kit
			return {"puzzle": PuzzleLever.build(z, poi)}
		"plate":
			return {"puzzle": PressurePlate.build(z, poi)}
		"block":
			return {"puzzle": PushBlock.build(z, poi)}
		"beam":
			return {"puzzle": BeamPuzzle.build(z, poi)}
		"water":
			return {"water": WaterChannel.build(z, l, poi)}
		"reset":
			return {"switch": reset_switch(z, poi)}
		"carrier":  # M13 phase 3: elements and traps
			return {"carrier": ElementCarrier.build(z, poi)}
		"element":
			return {"puzzle": ElementPuzzle.build(z, poi)}
		"ice":
			return {"puzzle": IceBridge.build(z, poi)}
		"trap":
			return {"trap": ClockTrap.build(z, poi)}
		"collapse":
			return {"trap": CollapsingFloor.build(z, l, poi)}
		"drain":  # M13 phase 5: the bosses' rooms
			return {"puzzle": BasinDrain.build(z, l, poi)}
		"pylon":
			return {"puzzle": FloodPylon.build(z, poi)}
		"quench":  # M13 phase 7: the Warrens' bosses' rooms
			return {"puzzle": QuenchTrough.build(z, poi)}
		"valve":
			return {"puzzle": LavaValve.build(z, poi)}
	return {}


## A rune slab that sends a puzzle's blocks home ([E]): a stuck block never
## locks a puzzle for good.
static func reset_switch(z: ZoneBase, poi: Dictionary) -> PuzzleSwitch:
	var sw := PuzzleSwitch.new()
	sw.name = "Reset_" + String(poi.get("id", ""))
	sw.id = String(poi.get("id", ""))
	sw.text_key = "ui.prompt.reset"
	sw.reach = 2.0
	var targets: Array = poi.get("targets", [])
	sw.on_use = func(hero: Player) -> void:
		var dz := z as DungeonZone
		if dz == null:
			return
		for t in targets:
			var block := dz.puzzles.get(String(t)) as PushBlock
			if block != null:
				block.request("reset", 0, hero)
	var slab := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.9, 0.3, 0.9)
	mesh.material = EnemyBase.flat_material(Color(0.3, 0.6, 0.65), true, 0.5)
	slab.mesh = mesh
	slab.position = Vector3(0, 0.15, 0)
	sw.add_child(slab)
	z.world.add_child(sw)
	sw.global_position = ZoneLayout.pos_of(poi)
	return sw


## A boss's room: the BossArena in its middle, the room's rect as the fight's
## bounds (the boss stays in, the reset counts who is in).
static func arena(z: ZoneBase, l: DungeonLayout, poi: Dictionary) -> BossArena:
	var a := BossArena.new()
	a.arena_id = String(poi.get("id", ""))
	a.name = "Arena_" + a.arena_id
	a.boss_id = String(poi.get("boss", "dungeon_boss"))
	a.flag = StringName(String(poi.get("flag", "")))
	a.trigger_radius = float(poi.get("trigger", 9.0))
	a.reward = String(poi.get("reward", "mid"))
	a.rect = DungeonLayout.rect_of(l.room(String(poi.get("room", ""))))
	a.poi = poi
	a.set_meta(&"poi_id", a.arena_id)
	z.world.add_child(a)
	a.global_position = ZoneLayout.pos_of(poi)
	return a


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
