class_name PushBlock
extends PoiPuzzle
## M13: a stone block that slides one cell at a time on a grid (pressure
## plates, bridges). The local hero pushes by walking into it along a grid
## axis for a moment (or [E] beside it); the push is a request, the authority
## checks the hero stands behind it and the next cell is free (inside the
## grid, on walkable floor outside channels, no other block, no hero) and
## moves it. The cell is the state, so no physics runs on the server and a
## block can never jam between cells. A reset switch sends it home.

const SIZE := 1.8
const PUSH_HOLD := 0.3
const PUSH_EVERY := 0.45
const PUSH_REACH := 2.2
const BEHIND_DOT := 0.7

## Home (cell 0, 0) on the floor, the cell size and the grid it may use (XZ).
var home: Vector3 = Vector3.ZERO
var cell: float = 2.0
var grid: Rect2 = Rect2()
var _body: StaticBody3D
var _hold: float = 0.0
var _push_left: float = 0.0
var _switch: PuzzleSwitch
var _loaded: bool = false


static func build(zone: ZoneBase, poi: Dictionary) -> PushBlock:
	var b := PushBlock.new()
	b.id = String(poi.get("id", ""))
	b.name = "Block_" + b.id
	b.home = ZoneLayout.pos_of(poi)
	b.cell = float(poi.get("cell", 2.0))
	var g: Array = poi.get("grid", [0, 0, 0, 0])
	b.grid = Rect2(float(g[0]), float(g[1]), float(g[2]) - float(g[0]), float(g[3]) - float(g[1]))
	b.act_range = PUSH_REACH + 1.0
	b.state = {"cell": [0, 0]}
	b.set_meta(&"poi_id", b.id)
	b.position = b.home
	b._build()
	zone.world.add_child(b)
	return b


func cell_of() -> Vector2i:
	var c: Array = state.get("cell", [0, 0])
	return Vector2i(int(c[0]), int(c[1]))


## Where the block rests for its state (the floor point under its middle).
func rest_position(at: Vector2i = Vector2i(-9999, -9999)) -> Vector3:
	var c := cell_of() if at.x == -9999 else at
	return home + Vector3(c.x * cell, 0.0, c.y * cell)


func _build() -> void:
	_body = StaticBody3D.new()
	_body.name = "Stone"
	_body.collision_layer = Grove.FOLIAGE_LAYER  # heroes and enemies bump it, the camera passes
	_body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * SIZE
	col.shape = shape
	col.position = Vector3(0, SIZE * 0.5, 0)
	_body.add_child(col)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * SIZE
	box.material = EnemyBase.flat_material(Color(0.42, 0.44, 0.45))
	mesh.mesh = box
	mesh.position = col.position
	_body.add_child(mesh)
	add_child(_body)
	_switch = PuzzleSwitch.new()
	_switch.text_key = "ui.prompt.push"
	_switch.reach = 2.4
	_switch.on_use = func(hero: Player) -> void:
		var d := _push_dir(hero, true)
		if d != Vector2i.ZERO:
			request("push", [d.x, d.y], hero)
	_body.add_child(_switch)
	_switch.position = Vector3(0, 0.2, 0)


func _ready() -> void:
	super()
	_loaded = true


## The grid axis from `hero` through the block (ZERO when it is not behind it
## along an axis); `any` = [E] beside it, any side counts.
func _push_dir(hero: Player, any: bool = false) -> Vector2i:
	var to := rest_position() - hero.global_position
	to.y = 0.0
	if to.length() > PUSH_REACH + (0.6 if any else 0.0):
		return Vector2i.ZERO
	var d := Vector2i(int(signf(to.x)), 0) if absf(to.x) >= absf(to.z) else Vector2i(0, int(signf(to.z)))
	if d == Vector2i.ZERO:
		return d
	var axis := Vector3(d.x, 0, d.y)
	if not any and to.normalized().dot(axis) < BEHIND_DOT:
		return Vector2i.ZERO
	return d


## The local hero walks into the block: after PUSH_HOLD a push, then one
## every PUSH_EVERY while it keeps walking.
func _process(delta: float) -> void:
	var zone := ZoneBase.zone_of(self)
	var hero := zone.player if zone != null else null
	if hero == null or not is_instance_valid(hero) or hero.input_locked:
		_hold = 0.0
		return
	_push_left = maxf(_push_left - delta, 0.0)
	var d := _push_dir(hero)
	if d == Vector2i.ZERO or hero.intent == null or hero.intent.move_dir.dot(Vector3(d.x, 0, d.y)) < 0.6:
		_hold = 0.0
		return
	_hold += delta
	if _hold >= PUSH_HOLD and _push_left <= 0.0:
		_push_left = PUSH_EVERY
		request("push", [d.x, d.y], hero)


## Can the block rest on cell `c`? Inside the grid, on plain floor, clear of
## the other blocks and of heroes.
func cell_free(c: Vector2i) -> bool:
	var at := rest_position(c)
	var half := cell * 0.5
	if not grid.encloses(Rect2(at.x - half, at.z - half, cell, cell).grow(-0.05)):
		return false
	var zone := ZoneBase.zone_of(self)
	if zone is DungeonZone:
		var lay := (zone as DungeonZone).layout
		for corner: Vector2 in [Vector2(-half, -half), Vector2(half, -half), Vector2(-half, half), Vector2(half, half)]:
			var px := at.x + corner.x * 0.9
			var pz := at.z + corner.y * 0.9
			if not lay.is_walkable(px, pz) or absf(lay.floor_at(px, pz, -99.0) - home.y) > 0.05:
				return false
		for key: String in (zone as DungeonZone).puzzles:
			var other := (zone as DungeonZone).puzzles[key] as PushBlock
			if other != null and other != self and other.rest_position().distance_to(at) < cell * 0.9:
				return false
	if zone != null:
		for p in zone.players:
			if p != null and is_instance_valid(p) and Vector2(p.global_position.x - at.x, p.global_position.z - at.z).length() < SIZE * 0.5 + 0.45:
				return false
	return true


func act(action: String, arg: Variant, hero: Player) -> void:
	match action:
		"push":
			var a := arg as Array
			if a == null or a.size() < 2 or hero == null:
				return
			var d := Vector2i(clampi(int(a[0]), -1, 1), clampi(int(a[1]), -1, 1))
			if absi(d.x) + absi(d.y) != 1:
				return
			# the pusher must stand behind the block (the server's proxy may lag a little)
			var to := rest_position() - hero.global_position
			to.y = 0.0
			if to.length() > PUSH_REACH + NET_MARGIN or to.normalized().dot(Vector3(d.x, 0, d.y)) < 0.4:
				return
			var next := cell_of() + d
			if not cell_free(next):
				return
			state["cell"] = [next.x, next.y]
			commit()
		"reset":
			if cell_of() != Vector2i.ZERO and cell_free(Vector2i.ZERO):
				state["cell"] = [0, 0]
				commit()


func _present() -> void:
	if _body == null:
		return
	var target := rest_position() - global_position
	if not _loaded:
		_body.position = target
		return
	var tw := _body.create_tween()
	tw.tween_property(_body, "position", target, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	Sfx.play("earthbreaker_impact", rest_position(), -14.0, 0.1, 1.5)
