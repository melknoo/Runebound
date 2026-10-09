class_name Grotto
extends Object
## M12 small caves: a grotto in the open world, no scene change. Walls and a
## roof of rock hulls around a room (the roof's hull has its underside, the
## camera sees it from inside), the entrance toward the POI's yaw, a light
## inside. Big enough for the camera (4.6 m high, 6 m wide). Contents: a
## chest; `lock: boulder` seals the entrance with a slab that the boulder
## puzzle outside lowers (the tome grotto in the burnt forest; its tome comes
## with M12 phase 7).

const WIDTH := 6.0
const DEPTH := 6.4
const HEIGHT := 4.6
const WALL := 1.3
const ROOF := 1.4
## The room sits this far behind the pad centre (the pad's front stays free).
const BACK_SHIFT := 2.0


static func build(zone: ZoneBase, poi: Dictionary) -> Dictionary:
	var yaw := PoiBuilder.yaw_of(poi)
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	var side := Vector3(fwd.z, 0.0, -fwd.x)
	var pad_centre := ZoneLayout.pos_of(poi)
	var centre := pad_centre - fwd * BACK_SHIFT
	centre.y = zone.ground_y(centre)
	var floor_y := centre.y
	var rng := RandomNumberGenerator.new()
	rng.seed = int(centre.x * 61.0 + centre.z * 29.0)
	var at := func(x: float, z: float) -> Vector3:
		return centre + side * x + fwd * z
	var hw := WIDTH * 0.5
	var hd := DEPTH * 0.5
	var walls: Array[StaticBody3D] = []
	# back, left, right, the two front jambs (a 3 m entrance in the middle)
	for piece: Array in [[0.0, -hd - WALL * 0.5, WIDTH + WALL * 2.0, WALL], [-hw - WALL * 0.5, 0.0, WALL, DEPTH],
			[hw + WALL * 0.5, 0.0, WALL, DEPTH], [-hw + 0.75, hd + WALL * 0.5, 1.5 + WALL, WALL],
			[hw - 0.75, hd + WALL * 0.5, 1.5 + WALL, WALL]]:
		var p: Vector3 = at.call(float(piece[0]), float(piece[1]))
		walls.append(PoiBuilder.rock(zone, p, Vector3(float(piece[2]), HEIGHT + 0.6, float(piece[3])), yaw))
	var roof_mat := zone._zone_material(&"highlands_rock", "res://assets/textures/ash_rock.png", Color(0.42, 0.36, 0.32), 2.5)
	var roof_size := Vector3(WIDTH + WALL * 2.0 + 0.4, ROOF, DEPTH + WALL + 0.6)
	var roof_at: Vector3 = at.call(0.0, -WALL * 0.3)
	var roof := zone._add_box(Vector3(roof_at.x, floor_y + HEIGHT + ROOF * 0.5, roof_at.z), roof_size, roof_mat,
		Vector3(0, rad_to_deg(yaw), 0), &"highlands_rock", 0, 0.15, true)
	roof.name = "GrottoRoof"
	roof.set_meta(&"floating", true)  # a roof, not a rock standing on the ground
	PoiBuilder.apply_range(roof, PoiBuilder.ROCK_RANGE)
	# rubble outside so it reads as a rock outcrop, not a box
	for k in 5:
		var a := rng.randf_range(-PI * 0.8, PI * 0.8) + PI
		var r := rng.randf_range(4.5, 6.0)
		var rp := centre + (fwd * cos(a) + side * sin(a)) * r
		PoiBuilder.rock(zone, rp, Vector3(rng.randf_range(1.4, 2.4), rng.randf_range(1.6, 3.2), rng.randf_range(1.4, 2.2)),
			rng.randf_range(0.0, TAU))
	if PoiBuilder.has_art(zone):
		var light := OmniLight3D.new()
		var tome := bool(poi.get("tome", false))
		light.light_color = ArtKit.color("color_roles.player_accent.body", Color("#3CBEB4")) if tome else Color(1.0, 0.62, 0.32)
		light.light_energy = 1.1
		light.omni_range = 6.5
		light.shadow_enabled = false
		zone.dressing().add_child(light)
		light.global_position = Vector3(centre.x, floor_y + 2.6, centre.z) - fwd * 0.8
	var out := {"walls": walls, "roof": roof, "centre": centre, "chest": null, "door": null, "puzzle": null, "tome": null}
	if bool(poi.get("tome", false)):  # M12 phase 7: the tome on its lectern at the back
		var tp: Vector3 = at.call(0.0, -hd + 1.2)
		out["tome"] = Tome.build(zone, tp, yaw)
	else:
		var cp: Vector3 = at.call(0.0, -hd + 1.2)
		out["chest"] = PoiBuilder.chest(zone, {"id": String(poi.get("id", "")) + "_chest", "rarity_bias": 1,
			"pos": [cp.x, cp.z], "yaw": yaw}, Vector3(cp.x, 0.0, cp.z), true)  # M13: opens once
	if String(poi.get("lock", "")) == "boulder":
		var door_at: Vector3 = at.call(0.0, hd + WALL * 0.5)
		var door := PoiBuilder.rock(zone, door_at, Vector3(3.2, HEIGHT - 0.2, WALL * 0.9), yaw)
		door.name = "GrottoDoor"
		out["door"] = door
		var open := func() -> void:
			if is_instance_valid(door):
				var down := door.global_position - Vector3(0, HEIGHT + 0.5, 0)
				var tw := door.create_tween()
				tw.tween_property(door, "global_position", down, 1.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				tw.tween_callback(func() -> void: door.collision_layer = 0)
				Sfx.play("earthbreaker_impact", door_at, -6.0, 0.1, 0.55)
		# the track runs across the front, left to right, ending right of the door
		var track_start: Vector3 = at.call(-2.6, hd + WALL + 1.8)
		out["puzzle"] = BoulderPuzzle.create(zone, String(poi.get("id", "")) + "_boulder", track_start, side, 7, open)
	return out
