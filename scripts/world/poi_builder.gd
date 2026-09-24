class_name PoiBuilder
extends Object
## Builders for the open-zone points of interest (M08). One static per POI
## type; the zone iterates its ZoneLayout and calls `build`. Everything stands
## on the terrain through the zone's ground seam (`ground_y` at build time);
## combat POIs sit on the flat pads the bake guarantees. Solid props above
## 0.4 m always get a collider (`blocker`), walk-through props stay low.

const DESTINATIONS := {
	"hub": "res://scenes/hub.tscn",
	"spire": "res://scenes/shattered_spire.tscn",
	"highlands": "res://scenes/ashen_highlands.tscn",
}
const PROP_RANGE := 110.0     # visibility_range_end for kit props (m)
const ROCK_RANGE := 200.0     # hull-dressed rocks


## Returns whatever the builder wants the zone to remember ({} for most).
static func build(zone: ZoneBase, poi: Dictionary) -> Dictionary:
	match String(poi.get("type", "")):
		"portal":
			return {"portal": portal(zone, poi)}
		"camp":
			return {"spawner": camp(zone, poi)}
		"ambush":
			return {"spawner": ambush(zone, poi)}
		"chest":
			return {"chest": chest(zone, poi)}
		"landmark":
			landmark(zone, poi)
		"ruin":
			return ruin(zone, poi)
		"arena":
			return arena(zone, poi)
		"dungeon":
			return {"portal": dungeon(zone, poi)}
		_:
			pass  # spawn (no geometry), waypoint (M08 phase 4), elite_patrol (phase 3)
	return {}


static func pos_of(entry: Dictionary) -> Vector3:
	return ZoneLayout.pos_of(entry)


static func yaw_of(poi: Dictionary) -> float:
	return float(poi.get("yaw", 0.0))


static func composition_of(poi: Dictionary, key: String = "composition") -> Array[String]:
	var out: Array[String] = []
	for c in poi.get(key, []):
		out.append(String(c))
	return out


# ---------------------------------------------------------------------------
# Shared pieces
# ---------------------------------------------------------------------------

## Invisible collider (world layer 1) for props that must not be walked through.
static func blocker(zone: ZoneBase, pos: Vector3, size: Vector3, yaw: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Blocker"
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = Vector3(0, size.y * 0.5, 0)
	body.add_child(col)
	zone.world.add_child(body, true)  # readable names: Blocker, Blocker2, ... (tests count them)
	body.global_position = pos
	body.rotation.y = yaw
	return body


## Hull-dressed rock standing on the terrain: the box is sunk to the lowest
## ground under its footprint (plus 0.1 m) and grown so its top clears the
## highest, and the hull's foot sinks the same span, so no gap shows on slopes.
static func rock(zone: ZoneBase, pos: Vector3, size: Vector3, yaw: float, wild_faces: int = 0) -> StaticBody3D:
	var span := Vector2(zone.ground_y(pos), zone.ground_y(pos))
	if zone.terrain != null:
		span = zone.terrain.footprint_range(pos, size, yaw)
	var drop := span.y - span.x
	var full := Vector3(size.x, size.y + drop, size.z)
	var centre := Vector3(pos.x, span.x - 0.1 + full.y * 0.5, pos.z)
	var rock_mat := zone._zone_material(&"highlands_rock", "res://assets/textures/ash_rock.png", Color(0.42, 0.36, 0.32), 2.5)
	var body := zone._add_box(centre, full, rock_mat, Vector3(0, rad_to_deg(yaw), 0), &"highlands_rock", wild_faces, drop + 0.3)
	body.name = "Rock"
	apply_range(body, ROCK_RANGE)
	return body


## Kit prop standing on the ground under `pos` (visibility range applied).
static func prop(zone: ZoneBase, prop_name: String, pos: Vector3, yaw: float = 0.0, scale: float = 1.0) -> Node3D:
	var p := pos
	p.y = zone.ground_y(pos)
	var inst := SetPieces.prop(zone.dressing(), prop_name, p, yaw, scale)
	if inst != null:
		apply_range(inst, PROP_RANGE)
	return inst


## visibility_range_end on every mesh under `node` (far dressing is culled;
## the sky LUT carries the horizon). 0 = infinite.
static func apply_range(node: Node, range_m: float) -> void:
	var meshes: Array[Node] = node.find_children("*", "GeometryInstance3D", true, false)
	if node is GeometryInstance3D:
		meshes.append(node)
	for m in meshes:
		var gi := m as GeometryInstance3D
		gi.visibility_range_end = range_m
		gi.visibility_range_end_margin = 8.0 if range_m > 0.0 else 0.0


static func has_art(zone: ZoneBase) -> bool:
	return zone.look != null and zone.look.art_pass


# ---------------------------------------------------------------------------
# POI types
# ---------------------------------------------------------------------------

static func portal(zone: ZoneBase, poi: Dictionary) -> Portal:
	var p := Portal.new()
	p.destination_scene = String(DESTINATIONS.get(String(poi.get("dest", "hub")), ""))
	p.label_text = String(poi.get("label", "PORTAL"))
	p.face_yaw = yaw_of(poi)
	p.set_meta(&"poi_id", String(poi.get("id", "")))
	p.set_meta(&"arrival", String(poi.get("arrival", "")))
	zone.world.add_child(p)
	p.global_position = pos_of(poi)
	return p


## Sealed entrance of a later dungeon (M10/M11): a locked gate the map and
## compass can point at. The rock notch around it is baked into the terrain.
static func dungeon(zone: ZoneBase, poi: Dictionary) -> Portal:
	var p := Portal.new()
	p.destination_scene = ""
	p.label_text = String(poi.get("label", "SEALED GATE"))
	p.locked = true
	p.face_yaw = yaw_of(poi)
	p.set_meta(&"poi_id", String(poi.get("id", "")))
	zone.world.add_child(p)
	p.global_position = pos_of(poi)
	# Flanking rocks frame the notch.
	var pos := pos_of(poi)
	var side := Vector3(cos(yaw_of(poi)), 0.0, -sin(yaw_of(poi)))
	for s: float in [-1.0, 1.0]:
		rock(zone, pos + side * (4.2 * s), Vector3(2.4, 4.5, 2.4), yaw_of(poi) + s * 0.3)
	return p


static func camp(zone: ZoneBase, poi: Dictionary) -> EncounterSpawner:
	var pos := pos_of(poi)
	var spawner := EncounterSpawner.new()
	spawner.name = "Camp_" + String(poi.get("id", ""))
	spawner.composition = composition_of(poi)
	spawner.trigger_radius = float(poi.get("radius", 13.0))
	spawner.set_meta(&"poi_id", String(poi.get("id", "")))
	zone.world.add_child(spawner)
	spawner.global_position = pos
	if has_art(zone):
		# Banners on the pad edge, each on its own thin collider.
		var spots: Array[Vector3] = []
		var count := int(poi.get("banners", 0))
		var pad := float(poi.get("pad", 10.0))
		for i in count:
			var a := TAU * float(i) / maxf(float(count), 1.0) + 0.7 + pos.x * 0.01
			var spot := pos + Vector3(cos(a), 0.0, sin(a)) * (pad - 2.2)
			spot.y = zone.ground_y(spot)
			blocker(zone, spot, Vector3(0.36, 3.2, 0.36))
			spots.append(spot)
		SetPieces.raider_camp(zone, pos, spots)
	return spawner


## Ambush at a pass: a tight spawner (M08 phase 3 makes it spawn around the
## hero who walks in).
static func ambush(zone: ZoneBase, poi: Dictionary) -> EncounterSpawner:
	var spawner := EncounterSpawner.new()
	spawner.name = "Ambush_" + String(poi.get("id", ""))
	spawner.composition = composition_of(poi)
	spawner.trigger_radius = float(poi.get("radius", 7.0))
	spawner.set_meta(&"poi_id", String(poi.get("id", "")))
	zone.world.add_child(spawner)
	spawner.global_position = pos_of(poi)
	return spawner


static func chest(zone: ZoneBase, poi: Dictionary, at: Vector3 = Vector3.INF) -> TreasureChest:
	var c := TreasureChest.new()
	c.min_rarity_bias = int(poi.get("rarity_bias", 0))
	c.set_meta(&"poi_id", String(poi.get("id", "")))
	zone.world.add_child(c)
	var pos := pos_of(poi) if at == Vector3.INF else at
	pos.y = zone.ground_y(pos)
	c.global_position = pos
	c.rotation.y = yaw_of(poi)
	return c


static func landmark(zone: ZoneBase, poi: Dictionary) -> void:
	var pos := pos_of(poi)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pos.x * 31.0 + pos.z * 17.0)
	match String(poi.get("prop", "rune_monolith")):
		"rune_monolith":
			var accent := zone._material_from_texture("res://assets/textures/rune_stone.png", Color(0.3, 0.4, 0.45), 1.0)
			var body := zone._add_box(Vector3(pos.x, zone.ground_y(pos) + 1.9, pos.z), Vector3(1.2, 4, 1.2),
				accent, Vector3(0, rad_to_deg(yaw_of(poi)), 0))
			body.name = "Monolith"
			if has_art(zone):
				SetPieces.wrap_collider(body, "rune_monolith")
		"charred_grove":
			for i in 6:
				var a := TAU * float(i) / 6.0 + rng.randf_range(-0.3, 0.3)
				var r := rng.randf_range(2.5, 6.5)
				var spot := pos + Vector3(cos(a) * r, 0.0, sin(a) * r)
				spot.y = zone.ground_y(spot)
				blocker(zone, spot, Vector3(0.6, 3.0, 0.6))
				prop(zone, "charred_tree", spot, rng.randf_range(0.0, TAU), rng.randf_range(1.05, 1.4))
		"bone_field":
			for i in 8:
				var a := rng.randf_range(0.0, TAU)
				var r := rng.randf_range(1.0, 6.0)
				prop(zone, "bone_pile", pos + Vector3(cos(a) * r, 0.0, sin(a) * r), rng.randf_range(0.0, TAU), rng.randf_range(0.9, 1.3))


## Broken masonry: a yawed rectangle of wall pieces with gaps, rubble rocks at
## the corners, a chest inside, an optional ambush waiting in it.
static func ruin(zone: ZoneBase, poi: Dictionary) -> Dictionary:
	var pos := pos_of(poi)
	var yaw := yaw_of(poi)
	var walls := clampi(int(poi.get("walls", 4)), 2, 6)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pos.x * 13.0 + pos.z * 7.0)
	var hw := 4.8   # half extents of the footprint
	var hd := 3.6
	var thick := 0.6
	var ruin_mat := zone._zone_material(&"highlands_ruin", "res://assets/textures/ash_rock.png", Color(0.36, 0.32, 0.3), 2.5)
	# Candidate pieces: [local centre (x, z), length, along_x, height]
	var pieces := [
		[Vector2(0, -hd), hw * 2.0, true, 2.8],            # north wall, whole
		[Vector2(-hw, -hd * 0.45), hd * 1.1, false, 2.2],  # west, north part
		[Vector2(hw, hd * 0.4), hd * 1.2, false, 1.6],     # east, south part
		[Vector2(-hw * 0.5, hd), hw * 1.0, true, 1.4],     # south, west stub
		[Vector2(hw * 0.55, hd), hw * 0.7, true, 2.0],     # south, east stub
		[Vector2(hw, -hd * 0.6), hd * 0.7, false, 2.6],    # east, north stub
	]
	var out := {"walls": [], "chest": null, "spawner": null}
	for i in walls:
		var piece: Array = pieces[i]
		var local: Vector2 = piece[0]
		var length: float = piece[1]
		var along_x: bool = piece[2]
		var height: float = piece[3]
		var world_xz := local.rotated(-yaw)
		var centre := Vector3(pos.x + world_xz.x, 0.0, pos.z + world_xz.y)
		centre.y = zone.ground_y(centre) + height * 0.5 - 0.25
		var size := Vector3(length, height, thick) if along_x else Vector3(thick, height, length)
		var body := zone._add_box(centre, size, ruin_mat, Vector3(0, rad_to_deg(yaw), 0))
		body.name = "RuinWall"
		if has_art(zone):
			SetPieces.masonry_wall(body, &"highlands_ruin", 2.6, i % 2 == 0)
		(out["walls"] as Array).append(body)
	# Rubble at two corners.
	for corner: Vector2 in [Vector2(-hw, -hd), Vector2(hw, hd)]:
		var c := corner.rotated(-yaw)
		var rp := Vector3(pos.x + c.x * 1.15, 0.0, pos.z + c.y * 1.15)
		rock(zone, rp, Vector3(rng.randf_range(1.2, 1.8), rng.randf_range(0.7, 1.1), rng.randf_range(1.0, 1.5)), rng.randf_range(0.0, TAU))
	if poi.get("chest", false):
		var inner := Vector2(0.0, -hd * 0.45).rotated(-yaw)
		out["chest"] = chest(zone, poi, Vector3(pos.x + inner.x, 0.0, pos.z + inner.y))
	var ambushers := composition_of(poi, "ambush")
	if not ambushers.is_empty():
		var spawner := EncounterSpawner.new()
		spawner.name = "Ambush_" + String(poi.get("id", ""))
		spawner.composition = ambushers
		spawner.trigger_radius = 6.5
		spawner.set_meta(&"poi_id", String(poi.get("id", "")))
		zone.world.add_child(spawner)
		spawner.global_position = pos
		out["spawner"] = spawner
	return out


## Colossus arena on the north plateau: a half ring of rock hulls (the charge
## needs walls to slam into), the boss trigger and the two gates behind it.
static func arena(zone: ZoneBase, poi: Dictionary) -> Dictionary:
	var centre := pos_of(poi)
	var radius := float(poi.get("radius", 16.0))
	var out := {"centre": centre, "portals": [], "trigger": null, "boss_spawn": centre}
	var bo: Array = poi.get("boss_offset", [0, -8])
	out["boss_spawn"] = Vector3(centre.x + float(bo[0]), 0.0, centre.z + float(bo[1]))
	# Rocks on the north half ring, leaving the gate gap due north.
	for deg: float in [-118.0, -82.0, -46.0, 46.0, 82.0, 118.0]:
		var a := deg_to_rad(deg)
		var spot := centre + Vector3(sin(a) * (radius + 1.5), 0.0, -cos(a) * (radius + 1.5))
		var size := Vector3(4.6, 5.0, 3.0)
		rock(zone, spot, size, -a, 0)
	# South half: lower boulders so the plateau still reads open.
	for deg: float in [150.0, 180.0, 210.0]:
		var a := deg_to_rad(deg)
		var spot := centre + Vector3(sin(a) * (radius + 3.0), 0.0, -cos(a) * (radius + 3.0))
		rock(zone, spot, Vector3(3.0, 2.0, 2.4), -a + 0.4)
	if has_art(zone):
		for deg: float in [-100.0, -64.0, 64.0, 100.0]:
			var a := deg_to_rad(deg)
			var spot := centre + Vector3(sin(a) * (radius + 1.5), 0.0, -cos(a) * (radius + 1.5))
			var top := spot
			top.y = zone.ground_y(spot) + 5.0 - 0.1
			var to_arena := Vector2(centre.x - spot.x, centre.z - spot.z)
			var pole := SetPieces.prop(zone.dressing(), "banner_pole", top, atan2(-to_arena.x, -to_arena.y) + PI)
			if pole != null:
				apply_range(pole, PROP_RANGE)
	var trig := EncounterSpawner.new()
	trig.name = "BossTrigger"
	trig.composition = [] as Array[String]
	trig.trigger_radius = float(poi.get("trigger_radius", 12.0))
	var to: Array = poi.get("trigger_offset", [0, 4])
	zone.world.add_child(trig)
	trig.global_position = Vector3(centre.x + float(to[0]), centre.y, centre.z + float(to[1]))
	trig.set_physics_process(false)  # the zone drives it
	out["trigger"] = trig
	var colossus_down := SaveGame.has_flag(&"colossus_defeated")
	for sub in poi.get("portals", []):
		var p := Portal.new()
		p.destination_scene = String(DESTINATIONS.get(String(sub.get("dest", "hub")), ""))
		p.label_text = String(sub.get("label", "PORTAL"))
		p.locked = not colossus_down
		var ppos := pos_of(sub)
		var face := Vector2(centre.x - ppos.x, centre.z - ppos.z)
		p.face_yaw = atan2(face.x, face.y)
		p.set_meta(&"poi_id", String(sub.get("id", "")))
		p.set_meta(&"arrival", String(sub.get("arrival", "")))
		zone.world.add_child(p)
		p.global_position = ppos
		(out["portals"] as Array).append(p)
	return out
