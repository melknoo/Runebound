class_name BrazierPuzzle
extends PoiPuzzle
## M12 puzzle: the chapel braziers of Ashwick. Three cold braziers; a hit
## with anything (a sword, a bolt, a thorn - every class's basic attack)
## lights one, and it burns WINDOW seconds. All three alight at once and the
## crypt opens: a chest at the altar. In co-op several heroes can share the
## work (each brazier is a request to the server).

const WINDOW := 10.0
const SOLVE_XP := 60
## Chapel shell (local: entrance on +Z) and the braziers inside.
const WIDTH := 7.0
const DEPTH := 9.0
const WALL_H := 3.0
const SPOTS: Array[Vector2] = [Vector2(-2.4, -2.0), Vector2(2.4, -2.0), Vector2(0.0, 1.6)]
const CHEST_SPOT := Vector2(0.0, -3.4)

var _fires: Array[Node3D] = [null, null, null]
var _poi: Dictionary = {}
## Authority: when each brazier was lit (msec, -1 = cold).
var _lit_at: Array[float] = [-1.0, -1.0, -1.0]


static func build(zone: ZoneBase, poi: Dictionary) -> BrazierPuzzle:
	var puzzle := BrazierPuzzle.new()
	puzzle.name = "Braziers_" + String(poi.get("id", ""))
	puzzle.id = String(poi.get("id", ""))
	puzzle._poi = poi
	puzzle.act_range = 30.0  # bolts and thorns light them from range
	var pos := ZoneLayout.pos_of(poi)
	pos.y = zone.ground_y(pos)
	puzzle.position = pos
	puzzle.rotation.y = PoiBuilder.yaw_of(poi)
	puzzle.state = {"lit": [false, false, false], "solved": false}
	zone.world.add_child(puzzle)
	puzzle._build_chapel(zone)
	return puzzle


func _local(v: Vector2) -> Vector3:
	return global_transform * Vector3(v.x, 0.0, v.y)


func _build_chapel(zone: ZoneBase) -> void:
	var yaw := rotation.y
	var mat := zone._zone_material(&"highlands_ruin", "res://assets/textures/ash_rock.png", Color(0.36, 0.32, 0.3), 2.5)
	var hw := WIDTH * 0.5
	var hd := DEPTH * 0.5
	# [local centre, length, along_x, height]: back, both sides, the door wall's stubs
	for piece: Array in [[Vector2(0, -hd), WIDTH, true, WALL_H + 0.8], [Vector2(-hw, 0), DEPTH, false, WALL_H],
			[Vector2(hw, 0), DEPTH, false, WALL_H * 0.75], [Vector2(-hw * 0.65, hd), WIDTH * 0.35, true, WALL_H],
			[Vector2(hw * 0.65, hd), WIDTH * 0.35, true, WALL_H * 0.6]]:
		var at := _local(piece[0])
		var size := Vector3(float(piece[1]), float(piece[3]), 0.55) if piece[2] else Vector3(0.55, float(piece[3]), float(piece[1]))
		var span := zone.terrain.footprint_range(at, size, yaw) if zone.terrain != null else Vector2(at.y, at.y)
		var full := Vector3(size.x, size.y + (span.y - span.x) + 0.3, size.z)
		var body := zone._add_box(Vector3(at.x, span.x - 0.3 + full.y * 0.5, at.z), full, mat, Vector3(0, rad_to_deg(yaw), 0))
		body.name = "ChapelWall"
		if PoiBuilder.has_art(zone):
			SetPieces.masonry_wall(body, &"highlands_ruin", 3.0, true)
	for i in SPOTS.size():
		var spot := _local(SPOTS[i])
		PoiBuilder.blocker(zone, Vector3(spot.x, zone.ground_y(spot), spot.z), Vector3(0.7, 1.1, 0.7))
		if PoiBuilder.has_art(zone):
			PoiBuilder.prop(zone, "brazier", spot, yaw)
		var target := BrazierTarget.new()
		target.puzzle = self
		target.index = i
		target.name = "BrazierTarget%d" % i
		add_child(target)
		target.global_position = Vector3(spot.x, zone.ground_y(spot), spot.z)
		target.setup()


## A hit on brazier `index` (BrazierTarget; the hero who struck it).
func strike(index: int, hero: Player) -> void:
	if is_solved() or index < 0 or index >= 3 or bool((state["lit"] as Array)[index]):
		return
	request("light", index, hero)


func act(action: String, arg: Variant, _hero: Player) -> void:
	if action != "light" or is_solved():
		return
	var index := int(arg)
	if index < 0 or index >= 3:
		return
	_lit_at[index] = float(Time.get_ticks_msec())
	var lit: Array = state["lit"]
	lit[index] = true
	if lit.all(func(v: Variant) -> bool: return bool(v)):
		state["solved"] = true
		reward_party(SOLVE_XP, "ui.puzzle.solved")
	commit()


func _process(_delta: float) -> void:
	# Authority: a brazier burns out after WINDOW unless all three were lit.
	if Net.is_client() or is_solved():
		return
	var lit: Array = state.get("lit", [false, false, false])
	var changed := false
	for i in 3:
		if bool(lit[i]) and _lit_at[i] >= 0.0 and float(Time.get_ticks_msec()) - _lit_at[i] > WINDOW * 1000.0:
			lit[i] = false
			_lit_at[i] = -1.0
			changed = true
	if changed:
		commit()


func _ready() -> void:
	super._ready()
	# A reload never brings back half-lit braziers (their burn time is gone).
	if not Net.is_client() and not is_solved():
		state["lit"] = [false, false, false]
		_present()


func _present() -> void:
	var lit: Array = state.get("lit", [false, false, false])
	for i in 3:
		var on := bool(lit[i]) or is_solved()
		if on and _fires[i] == null:
			_fires[i] = _make_fire(_local(SPOTS[i]))
		elif not on and _fires[i] != null:
			_fires[i].queue_free()
			_fires[i] = null


func _make_fire(at: Vector3) -> Node3D:
	var zone := ZoneBase.zone_of(self)
	var root := Node3D.new()
	root.name = "BrazierFire"
	add_child(root)
	root.global_position = at + Vector3(0, 1.12, 0)
	if zone != null and PoiBuilder.has_art(zone):
		var flame := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.3, 0.45, 0.3)
		flame.mesh = box
		flame.position = Vector3(0, 0.2, 0)
		flame.material_override = ArtKit.glow_material(ArtKit.color("color_roles.fire.core", Color("#FFB347")), 1.6)
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(flame)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.6, 0.3)
		light.light_energy = 1.4
		light.omni_range = 6.0
		light.position = Vector3(0, 0.5, 0)
		root.add_child(light)
		root.add_child(SetPieces._embers())
		Sfx.play("ember_cast", root.global_position, -6.0)
	return root


func _on_solved() -> void:
	var zone := ZoneBase.zone_of(self)
	if zone == null:
		return
	var at := _local(CHEST_SPOT)
	var chest := PoiBuilder.chest(zone, {"id": id + "_chest", "rarity_bias": 1, "pos": [at.x, at.z], "yaw": rotation.y + PI},
		Vector3(at.x, 0.0, at.z))
	if chest != null:
		chest.name = "PuzzleChest_" + id
	if PoiBuilder.has_art(zone):
		VFX.light_pop(zone, at + Vector3(0, 1.0, 0), Color(1.0, 0.7, 0.4), 3.0, 8.0, 0.6)
