class_name CollapsingFloor
extends Node3D
## M13: a floor of stone rows over a pit (a dry layout channel) that drop
## away on the server's clock - even rows, then odd rows, a crack-red warning
## before each fall - so a hero crosses in rhythm, waiting on the rows that
## hold. Every machine moves the rows alike (no state, no traffic). A hero
## who falls lands on the pit's bed: hurt (never the last point) and set
## back at the pit's edge (`back`), judged by its own machine.

const WARN := 0.6
const FALL_DEPTH := 2.2

var rect: Rect2 = Rect2()
var floor_y: float = 0.0
var depth: float = 3.0
var rows: int = 4
var period: float = 4.0
var down: float = 1.5
var back: Vector3 = Vector3.ZERO
var damage: float = 14.0
var _along_x: bool = true
var _tiles: Array[StaticBody3D] = []
var _tile_mats: Array[StandardMaterial3D] = []
var _down: Array[bool] = []
## Tests: falls this machine's hero took.
var falls: int = 0


static func build(zone: ZoneBase, layout: DungeonLayout, poi: Dictionary) -> CollapsingFloor:
	var f := CollapsingFloor.new()
	var ch := layout.channel(String(poi.get("channel", "")))
	f.name = "Collapse_" + String(poi.get("id", ""))
	f.rect = DungeonLayout.rect_of(ch)
	f.floor_y = float(ch.get("floor", 0.0))
	f.depth = float(ch.get("depth", 3.0))
	f.rows = int(poi.get("rows", 4))
	f.period = float(poi.get("period", 4.0))
	f.down = float(poi.get("down", 1.5))
	f.damage = float(poi.get("damage", 14.0))
	var b: Array = poi.get("back", [0, 0])
	f.back = Vector3(float(b[0]), zone.ground_y(Vector3(float(b[0]), 0, float(b[1]))), float(b[1]))
	f.set_meta(&"poi_id", String(poi.get("id", "")))
	f.position = Vector3(f.rect.get_center().x, f.floor_y, f.rect.get_center().y)
	zone.world.add_child(f)
	return f


func _ready() -> void:
	_along_x = rect.size.x >= rect.size.y
	var length := rect.size.x if _along_x else rect.size.y
	var across := rect.size.y if _along_x else rect.size.x
	var row_len := length / float(rows)
	for r in rows:
		var body := StaticBody3D.new()
		body.name = "Row%d" % r
		body.collision_layer = 1
		body.collision_mask = 0
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(row_len - 0.08, 0.6, across) if _along_x else Vector3(across, 0.6, row_len - 0.08)
		col.shape = shape
		body.add_child(col)
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = shape.size
		var mat := EnemyBase.flat_material(Color(0.36, 0.35, 0.34))
		box.material = mat
		mesh.mesh = box
		body.add_child(mesh)
		add_child(body)
		var off := -length * 0.5 + row_len * (r + 0.5)
		body.position = Vector3(off, -0.3, 0) if _along_x else Vector3(0, -0.3, off)
		_tiles.append(body)
		_tile_mats.append(mat)
		_down.append(false)


func _now_s() -> float:
	var zone := ZoneBase.zone_of(self)
	if zone != null and zone.net_world != null:
		return zone.net_world.server_msec() / 1000.0
	return float(Time.get_ticks_msec()) / 1000.0


## Seconds into row r's cycle (it is down for the first `down` of them).
func row_phase(r: int, now_s: float) -> float:
	return fposmod(now_s - float(r % 2) * period * 0.5, period)


func row_down(r: int, now_s: float) -> bool:
	return row_phase(r, now_s) < down


func _process(_delta: float) -> void:
	var now := _now_s()
	for r in rows:
		var ph := row_phase(r, now)
		var want := ph < down
		if want != _down[r]:
			_down[r] = want
			_tiles[r].collision_layer = 0 if want else 1
			var y := -0.3 - FALL_DEPTH if want else -0.3
			var tw := _tiles[r].create_tween()
			tw.tween_property(_tiles[r], "position:y", y, 0.25 if want else 0.4)
		var warn := not want and ph > period - WARN
		_tile_mats[r].albedo_color = Color(0.55, 0.22, 0.18) if warn else Color(0.36, 0.35, 0.34)


func _physics_process(_delta: float) -> void:
	var zone := ZoneBase.zone_of(self)
	var hero := zone.player if zone != null else null
	if hero == null or not is_instance_valid(hero) or hero.health.is_dead:
		return
	var p := hero.global_position
	if rect.has_point(Vector2(p.x, p.z)) and p.y < floor_y - 0.8:
		fell(hero)


## This machine's hero dropped into the pit: hurt, and back at the edge.
func fell(hero: Player) -> void:
	falls += 1
	var dmg := minf(damage, hero.health.current_health - 1.0)  # never the last point
	if dmg > 0.0:
		hero.take_hit(HitInfo.create(dmg, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, hero.global_position))
	hero.global_position = back + Vector3(0, 0.2, 0)
	hero.velocity = Vector3.ZERO
	hero.teleports += 1  # puppets snap instead of sliding out of the pit
	hero.feel_shake(0.3)
