class_name MonolithPuzzle
extends PoiPuzzle
## M12 puzzle: the Crossroads stones. A rune crystal sends a beam to the first
## of three standing stones; each stone turns in eighths ([E]) and passes the
## beam on only while its rune face looks at the next one. When the last
## stone faces the seal, the beam lights it and the seal opens a chest. Any
## class, any number of heroes (each turn is a request to the server).

const SOLVE_XP := 60
## Layout (local metres; the source, three stones, the seal).
const SOURCE := Vector2(-5.0, 3.0)
const STONES: Array[Vector2] = [Vector2(-3.2, -1.6), Vector2(1.0, -3.2), Vector2(4.4, 0.4)]
const SEAL := Vector2(0.6, 3.6)
const STEP := TAU / 8.0

var _stone_nodes: Array[Node3D] = []
var _beams: Array[MeshInstance3D] = []
var _seal: Node3D
## Per stone: the eighth that faces the next node (the solution).
var _targets: Array[int] = []


static func build(zone: ZoneBase, poi: Dictionary) -> MonolithPuzzle:
	var puzzle := MonolithPuzzle.new()
	puzzle.name = "Monoliths_" + String(poi.get("id", ""))
	puzzle.id = String(poi.get("id", ""))
	puzzle.act_range = 12.0
	var pos := ZoneLayout.pos_of(poi)
	pos.y = zone.ground_y(pos)
	puzzle.position = pos
	puzzle.rotation.y = PoiBuilder.yaw_of(poi)
	puzzle._compute_targets()
	# start turned away from the solution (seeded per place, never solved)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pos.x * 7.0 + pos.z * 13.0)
	var rot: Array = []
	for i in STONES.size():
		rot.append((puzzle._targets[i] + rng.randi_range(2, 6)) % 8)
	puzzle.state = {"rot": rot, "solved": false}
	zone.world.add_child(puzzle)
	puzzle._build(zone)
	puzzle._present()
	return puzzle


func _compute_targets() -> void:
	_targets.clear()
	for i in STONES.size():
		var next := STONES[i + 1] if i + 1 < STONES.size() else SEAL
		var d := next - STONES[i]
		# eighth k faces (sin(k * STEP), cos(k * STEP)) in local x / z
		_targets.append(posmod(roundi(atan2(d.x, d.y) / STEP), 8))


func _local(v: Vector2, y: float = 0.0) -> Vector3:
	return global_transform * Vector3(v.x, y, v.y)


func _build(zone: ZoneBase) -> void:
	var yaw := rotation.y
	if PoiBuilder.has_art(zone):
		PoiBuilder.prop(zone, "sp_crystal_cluster", _local(SOURCE), yaw, 1.2)
		_seal = PoiBuilder.prop(zone, "rune_seal", _local(SEAL), yaw, 1.0)
	for i in STONES.size():
		var spot := _local(STONES[i])
		spot.y = zone.ground_y(spot)
		PoiBuilder.blocker(zone, spot, Vector3(0.9, 2.0, 0.9))
		var pivot := Node3D.new()
		pivot.name = "Stone%d" % i
		add_child(pivot)
		pivot.global_position = spot
		if PoiBuilder.has_art(zone):
			var stone := SetPieces.prop(pivot, "rune_monolith", spot, 0.0, 0.5)
			if stone != null:
				stone.position = Vector3.ZERO
			var face := MeshInstance3D.new()  # the rune face: shows where the stone looks
			var box := BoxMesh.new()
			box.size = Vector3(0.18, 0.5, 0.06)
			face.mesh = box
			face.material_override = ArtKit.glow_material(ArtKit.color("color_roles.player_accent.hot", Color("#9FF2E6")), 1.2)
			face.position = Vector3(0, 1.3, 0.36)
			pivot.add_child(face)
		var sw := PuzzleSwitch.new()
		sw.text_key = "ui.prompt.turn"
		sw.reach = 2.4
		sw.prompt_height = 2.2
		var index := i
		sw.on_use = func(hero: Player) -> void: request("turn", index, hero)
		sw.usable = func(_hero: Player) -> bool: return not is_solved()
		add_child(sw)
		sw.global_position = spot
		_stone_nodes.append(pivot)
	for k in STONES.size() + 1:
		var beam := MeshInstance3D.new()
		beam.name = "Beam%d" % k
		var box := BoxMesh.new()
		box.size = Vector3(0.09, 0.09, 1.0)
		beam.mesh = box
		beam.material_override = ArtKit.glow_material(ArtKit.color("color_roles.player_accent.hot", Color("#9FF2E6")), 2.0)
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.visible = false
		add_child(beam)
		_beams.append(beam)


## How far the beam gets: 0 = to the first stone only, 3 = to the seal.
func beam_reach() -> int:
	var rot: Array = state.get("rot", [])
	var reach := 0
	for i in STONES.size():
		if i < rot.size() and int(rot[i]) == _targets[i]:
			reach += 1
		else:
			break
	return reach


func act(action: String, arg: Variant, _hero: Player) -> void:
	if action != "turn" or is_solved():
		return
	var i := int(arg)
	var rot: Array = state["rot"]
	if i < 0 or i >= rot.size():
		return
	rot[i] = (int(rot[i]) + 1) % 8
	if beam_reach() >= STONES.size():
		state["solved"] = true
		reward_party(SOLVE_XP, "ui.puzzle.solved")
	commit()


func _present() -> void:
	if _stone_nodes.is_empty():
		return
	var rot: Array = state.get("rot", [])
	for i in _stone_nodes.size():
		var target := rotation.y + float(int(rot[i]) if i < rot.size() else 0) * STEP
		var cur := _stone_nodes[i].global_rotation.y
		var want := cur + wrapf(target - cur, -PI, PI)  # the short way round
		var tw := _stone_nodes[i].create_tween()
		tw.tween_property(_stone_nodes[i], "global_rotation:y", want, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var reach := beam_reach()
	var points: Array[Vector3] = [_local(SOURCE, 1.3)]
	for i in STONES.size():
		points.append(_local(STONES[i], 1.3))
	points.append(_local(SEAL, 0.35))
	for k in _beams.size():
		var on := k <= reach
		_beams[k].visible = on
		if on:
			var a := points[k]
			var b := points[k + 1]
			_beams[k].global_position = (a + b) * 0.5
			_beams[k].look_at(b, Vector3.UP)
			_beams[k].scale = Vector3(1.0, 1.0, a.distance_to(b))


func _on_solved() -> void:
	var zone := ZoneBase.zone_of(self)
	if zone == null:
		return
	var at := _local(SEAL)
	PoiBuilder.chest(zone, {"id": id + "_chest", "rarity_bias": 1, "pos": [at.x, at.z], "yaw": rotation.y}, Vector3(at.x, 0.0, at.z), true)  # M13: opens once
	if PoiBuilder.has_art(zone):
		VFX.light_pop(zone, at + Vector3(0, 0.6, 0), ArtKit.color("color_roles.player_accent.hot", Color("#9FF2E6")), 3.0, 7.0, 0.6)
