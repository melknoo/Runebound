class_name BiomeDressing
extends Object
## M12: the looks of the Highlands' sub-biomes and of the places that tell a
## story without text - built from the M12 prop kit (tools/modelgen
## generate_props.py: vl_*, bf_*, bn_*, vg_*) and world-mapped walls. Pure
## dressing: no gameplay lives here (the cursed graveyard's curse, the trial
## shrines and so on come with their own phases and build on top). Every
## solid piece over 0.4 m gets a collider; walls and blockers sit on the
## world layer, so the camera keeps clear of them like of any ruin.

const HOUSE := Vector3(5.0, 2.4, 4.4)  # footprint x, wall height, depth (vl_rafters fits it)
const WALL := 0.5


## Ashwick: ruined houses around the square (the street and the lane stay
## open), the well, fences along the lane, a cart.
static func village(zone: ZoneBase, poi: Dictionary) -> Dictionary:
	var centre := ZoneLayout.pos_of(poi)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(centre.x * 41.0 + centre.z * 23.0)
	var houses: Array[Node3D] = []
	# angles (atan2 z, x) clear of the street (east, west) and the lane (south)
	for deg: float in [40.0, 68.0, 140.0, 208.0, 246.0, 285.0, 322.0]:
		var a := deg_to_rad(deg + rng.randf_range(-6.0, 6.0))
		var r := rng.randf_range(15.0, 17.5)
		var spot := centre + Vector3(cos(a) * r, 0.0, sin(a) * r)
		var facing := atan2(centre.x - spot.x, centre.z - spot.z)  # the door looks at the square
		houses.append(house(zone, spot, facing, rng))
	var well_at := centre + Vector3(2.5, 0.0, -2.0)
	PoiBuilder.blocker(zone, Vector3(well_at.x, zone.ground_y(well_at), well_at.z), Vector3(1.8, 1.9, 1.8))
	PoiBuilder.prop(zone, "vl_well", well_at, rng.randf_range(0.0, TAU))
	var cart_at := centre + Vector3(-5.5, 0.0, 4.0)
	_solid(zone, "vl_cart", cart_at, 0.7, Vector3(2.4, 1.0, 1.4))
	return {"houses": houses}


## One ruined house: three walls and a door wall with a gap, one corner fallen
## in, the charred rafters on top (or fallen in). Walls follow the slope down
## to the lowest ground under them.
static func house(zone: ZoneBase, pos: Vector3, yaw: float, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "House"
	zone.world.add_child(root, true)
	root.global_position = Vector3(pos.x, zone.ground_y(pos), pos.z)
	var hx := HOUSE.x * 0.5
	var hz := HOUSE.z * 0.5
	var collapsed := rng.randf() < 0.35
	# [local centre (x, z), length, along_x, height]
	var pieces := [
		[Vector2(0.0, -hz), HOUSE.x, true, HOUSE.y],                              # back
		[Vector2(-hx, 0.0), HOUSE.z, false, HOUSE.y],                             # left
		[Vector2(hx, -hz * 0.35), HOUSE.z * 0.65, false, HOUSE.y * (0.55 if collapsed else 1.0)],  # right, broken
		[Vector2(-hx * 0.62, hz), HOUSE.x * 0.38, true, HOUSE.y],                 # door wall, left of the gap
		[Vector2(hx * 0.62, hz), HOUSE.x * 0.38, true, HOUSE.y * 0.8],            # door wall, right
	]
	var mat := zone._zone_material(&"highlands_ruin", "res://assets/textures/ash_rock.png", Color(0.36, 0.32, 0.3), 2.5)
	for i in pieces.size():
		var piece: Array = pieces[i]
		var local: Vector2 = piece[0]
		var length: float = piece[1]
		var along_x: bool = piece[2]
		var height: float = piece[3]
		var world_xz := local.rotated(-yaw)
		var at := Vector3(pos.x + world_xz.x, 0.0, pos.z + world_xz.y)
		var size := Vector3(length, height, WALL) if along_x else Vector3(WALL, height, length)
		var span := Vector2(zone.ground_y(at), zone.ground_y(at))
		if zone.terrain != null:
			span = zone.terrain.footprint_range(at, size, yaw)
		var full := Vector3(size.x, size.y + (span.y - span.x) + 0.3, size.z)
		var body := zone._add_box(Vector3(at.x, span.x - 0.3 + full.y * 0.5, at.z), full, mat, Vector3(0, rad_to_deg(yaw), 0))
		body.name = "HouseWall"
		if PoiBuilder.has_art(zone):
			SetPieces.masonry_wall(body, &"highlands_ruin", 2.6, i < 2)
	if PoiBuilder.has_art(zone):
		var top := Vector3(pos.x, zone.ground_y(pos) - 0.05, pos.z)
		if collapsed:
			# the roof came down: rafters on the floor, slanting
			var fallen := PoiBuilder.prop(zone, "vl_rafters", pos, yaw + 0.15, 0.95)
			if fallen != null:
				fallen.global_position = top + Vector3(0, -2.0, 0)
				fallen.rotation.z = 0.35
		else:
			var rafters := PoiBuilder.prop(zone, "vl_rafters", pos, yaw)
			if rafters != null:
				rafters.global_position.y = top.y
	return root


## The graveyard's looks (its curse comes in a later phase): rows of
## headstones and wooden crosses, a broken fence around them with gaps toward
## the paths (`gaps`: directions as angles, atan2(z, x)), two dead trees. The
## centre stays open.
static func graveyard(zone: ZoneBase, poi: Dictionary, gaps: Array[float] = []) -> void:
	var centre := ZoneLayout.pos_of(poi)
	var yaw := PoiBuilder.yaw_of(poi)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(centre.x * 29.0 + centre.z * 37.0)
	for row in 3:
		for col in 5:
			var local := Vector2(-6.0 + col * 3.0 + rng.randf_range(-0.3, 0.3), -5.5 + row * 3.6 + rng.randf_range(-0.3, 0.3))
			if local.length() < 3.2:
				continue  # the open middle
			var w := local.rotated(-yaw)
			var spot := centre + Vector3(w.x, 0.0, w.y)
			var cross := rng.randf() < 0.4
			_solid(zone, "vl_grave_cross" if cross else "vl_grave", spot, yaw + rng.randf_range(-0.15, 0.15),
				Vector3(0.6, 0.95, 0.35), rng.randf_range(0.9, 1.1))
	var radius := float(poi.get("pad", 10.0)) + 0.5
	var segments := 14
	for i in segments:
		var a := TAU * (float(i) + 0.5) / float(segments)
		var on_path := false
		for g in gaps:
			on_path = on_path or absf(angle_difference(a, g)) < deg_to_rad(22.0)
		if on_path or rng.randf() < 0.15:
			continue  # gaps: the paths and the broken bits
		var spot := centre + Vector3(cos(a) * radius, 0.0, sin(a) * radius)
		_solid(zone, "vl_fence", spot, -a + PI * 0.5 + rng.randf_range(-0.08, 0.08), Vector3(2.4, 0.95, 0.25))
	for side: float in [-1.0, 1.0]:
		var spot := centre + Vector3(side * 7.5, 0.0, side * -6.0)
		PoiBuilder.blocker(zone, Vector3(spot.x, zone.ground_y(spot), spot.z), Vector3(0.6, 3.0, 0.6))
		PoiBuilder.prop(zone, "bf_snag", spot, rng.randf_range(0.0, TAU), 0.8)


## Fences along the village lane, a few posts missing; never on a pad
## (`exclude` circles x, z, radius) or another path (`avoid`).
static func lane_fences(zone: ZoneBase, points: PackedVector2Array, offset: float, seed_value: int,
		exclude: Array[Vector3] = [], avoid: Callable = Callable()) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var placed := 0
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var dir := (b - a).normalized()
		var side := dir.orthogonal()
		var length := a.distance_to(b)
		var t := 3.0
		while t < length - 3.0:
			for s: float in [-1.0, 1.0]:
				if rng.randf() < 0.35:
					continue
				var p := a + dir * t + side * offset * s
				if Scatter._excluded(p, exclude) or (avoid.is_valid() and bool(avoid.call(p))):
					continue
				_solid(zone, "vl_fence", Vector3(p.x, 0.0, p.y), atan2(-dir.y, dir.x) + rng.randf_range(-0.1, 0.1),
					Vector3(2.4, 0.95, 0.25))
				placed += 1
			t += 2.6
	return placed


## A place that tells a story, by `kind` (the layout's vignette POIs).
static func vignette(zone: ZoneBase, poi: Dictionary) -> void:
	if not PoiBuilder.has_art(zone):
		return
	var pos := ZoneLayout.pos_of(poi)
	var yaw := PoiBuilder.yaw_of(poi)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pos.x * 53.0 + pos.z * 19.0)
	var at := func(x: float, z: float) -> Vector3:
		var w := Vector2(x, z).rotated(-yaw)
		return pos + Vector3(w.x, 0.0, w.y)
	match String(poi.get("kind", "")):
		"fallen":
			# soldiers of the old guard where they fell, facing the pass
			for k in 3:
				PoiBuilder.prop(zone, "vg_fallen", at.call(-2.0 + k * 2.1, rng.randf_range(-1.0, 1.0)), yaw + rng.randf_range(-0.6, 0.6))
			_solid(zone, "vg_spears", at.call(0.5, -2.6), yaw, Vector3(1.6, 1.6, 1.6), 0.9)
			PoiBuilder.prop(zone, "bone_pile", at.call(2.8, 1.6), rng.randf_range(0.0, TAU))
		"abandoned_camp":
			# a raider camp left in a hurry: tents down, the fire long cold
			_solid(zone, "vg_tent", at.call(-2.5, -1.0), yaw + 0.4, Vector3(2.6, 1.2, 2.2))
			_solid(zone, "vg_tent", at.call(2.8, -1.8), yaw - 0.9, Vector3(2.6, 1.2, 2.2))
			for k in 6:
				var a := TAU * k / 6.0
				PoiBuilder.prop(zone, "stone_cluster", at.call(cos(a) * 0.9, 1.5 + sin(a) * 0.9), a, 1.3)
			PoiBuilder.prop(zone, "log_seat", at.call(-1.4, 2.8), yaw + 0.3)
			PoiBuilder.prop(zone, "bone_pile", at.call(1.2, 3.2), rng.randf_range(0.0, TAU))
		"cart":
			_solid(zone, "vl_cart", at.call(0.0, 0.0), yaw, Vector3(2.4, 1.0, 1.4))
			PoiBuilder.prop(zone, "vg_fallen", at.call(1.9, 1.4), yaw + 2.2)
		"barricade":
			_solid(zone, "vl_barricade", at.call(-1.5, 0.0), yaw, Vector3(2.7, 1.3, 1.0))
			_solid(zone, "vl_barricade", at.call(1.6, 0.4), yaw + 0.2, Vector3(2.7, 1.3, 1.0))
			PoiBuilder.prop(zone, "vg_fallen", at.call(0.2, 2.0), yaw + 3.0)
		"last_stand":
			_solid(zone, "vg_spears", at.call(0.0, 0.0), yaw, Vector3(1.8, 1.6, 1.8))
			for k in 2:
				PoiBuilder.prop(zone, "vg_fallen", at.call(-1.2 + k * 2.6, 1.6 + k * 0.4), yaw + 1.2 + k * 2.0)
		"skeleton":
			skeleton(zone, pos, yaw, rng)
		"ribs":
			for k in 3:
				var root: Vector3 = at.call(-2.8 + k * 2.6, rng.randf_range(-0.5, 0.5))
				_rib(zone, root, yaw + rng.randf_range(-0.2, 0.2), rng.randf_range(0.7, 1.0))
			_solid(zone, "bn_vertebra", at.call(1.0, 3.5), yaw + 1.2, Vector3(1.6, 1.2, 0.9), 0.9)


## The bone field's centrepiece: a giant skeleton half sunk in the dust -
## the skull at the head, a line of vertebrae, ribs arching over both sides
## (their roots are the only colliders, the arcs are overhead).
static func skeleton(zone: ZoneBase, pos: Vector3, yaw: float, rng: RandomNumberGenerator) -> void:
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	var side := Vector3(fwd.z, 0.0, -fwd.x)
	var skull_at := pos + fwd * 7.5
	_solid(zone, "bn_skull", skull_at, yaw + PI * 0.5, Vector3(3.2, 2.0, 2.0))
	for k in 5:
		var v := pos + fwd * (4.5 - k * 2.2)
		_solid(zone, "bn_vertebra", v, yaw + PI * 0.5 + rng.randf_range(-0.2, 0.2), Vector3(1.6, 1.1, 0.9), rng.randf_range(0.85, 1.05))
	for k in 4:
		var along := pos + fwd * (3.0 - k * 2.0)
		for s: float in [-1.0, 1.0]:
			# roots 3.5 m out, each arc bends in over the spine (a cage to walk in)
			_rib(zone, along + side * s * 3.5, atan2(side.x * s, side.z * s), 1.0 - k * 0.08)


## One giant rib rooted at `root`, bending toward `yaw` (the arc overhead).
static func _rib(zone: ZoneBase, root: Vector3, yaw: float, scale: float) -> void:
	PoiBuilder.blocker(zone, Vector3(root.x, zone.ground_y(root), root.z), Vector3(0.7, 2.2, 0.7) * Vector3(scale, 1.0, scale), yaw)
	var rib := PoiBuilder.prop(zone, "bn_rib", root, yaw, scale)
	if rib != null:
		rib.global_position.y -= 0.1


## A kit prop with a box collider under it (props over 0.4 m are solid).
static func _solid(zone: ZoneBase, prop_name: String, pos: Vector3, yaw: float, size: Vector3, scale: float = 1.0) -> Node3D:
	var ground := Vector3(pos.x, zone.ground_y(pos), pos.z)
	PoiBuilder.blocker(zone, ground, size * scale, yaw)
	return PoiBuilder.prop(zone, prop_name, pos, yaw, scale)


## The burnt forest's undergrowth on top of the Grove trunks: thick snags,
## fallen logs (solid) and smouldering stumps (walk-through, glowing).
static func forest_details(zone: ZoneBase, layout: ZoneLayout, clearings: Array[Vector3], avoid: Callable,
		seed_value: int) -> Dictionary:
	var weight := func(x: float, z: float) -> float: return layout.biome_weight("burnt_forest", x, z)
	var area := layout.biome_rect("burnt_forest")
	var snags := Grove.plant(zone, {
		"prop": "bf_snag", "area": area, "weight": weight, "density": 0.32, "spacing": 7.0,
		"scale": Vector2(0.85, 1.25), "lean": 0.08, "exclude": clearings, "avoid": avoid,
		"height_at": zone.terrain.height_at, "collider": Vector2(0.32, 4.0), "range": 160.0, "seed": seed_value,
	})
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 1
	var logs := 0
	for i in 160:
		if logs >= 26:
			break
		var p := area.position + Vector2(rng.randf(), rng.randf()) * area.size
		if float(weight.call(p.x, p.y)) < 0.7 or Scatter._excluded(p, clearings) or bool(avoid.call(p)):
			continue
		var log_yaw := rng.randf_range(0.0, TAU)
		_solid(zone, "bf_log", Vector3(p.x, 0.0, p.y), log_yaw, Vector3(3.6, 0.55, 0.55), rng.randf_range(0.85, 1.15))
		logs += 1
	return {"snags": snags, "logs": logs}
