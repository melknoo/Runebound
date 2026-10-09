class_name PressurePlate
extends PoiPuzzle
## M13: a stone plate in the floor. Weighed down by a living hero standing on
## it or a push block resting on it; the authority looks (offline this
## machine, online the server - its hero proxies stand where their owners
## walk) and tells everyone. A latching plate stays down once pressed. Gates
## and water waiting on it follow `is_active()` (down right now).

const SIZE := 2.0
const CHECK_EVERY := 0.1
const HEIGHT_BAND := 1.5

var latch: bool = false
var _plate: MeshInstance3D
var _glow_mat: StandardMaterial3D
var _check_left: float = 0.0
var _loaded: bool = false


static func build(zone: ZoneBase, poi: Dictionary) -> PressurePlate:
	var p := PressurePlate.new()
	p.id = String(poi.get("id", ""))
	p.name = "Plate_" + p.id
	p.latch = bool(poi.get("latch", false))
	p.act_range = 4.0
	p.state = {"down": false, "solved": false}
	p.set_meta(&"poi_id", p.id)
	p.position = ZoneLayout.pos_of(poi)
	p._build()
	zone.world.add_child(p)
	return p


func is_down() -> bool:
	return bool(state.get("down", false))


func is_active() -> bool:
	return is_down()


func _build() -> void:
	_plate = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(SIZE, 0.12, SIZE)
	mesh.material = EnemyBase.flat_material(Color(0.34, 0.36, 0.38))
	_plate.mesh = mesh
	_plate.position = Vector3(0, 0.04, 0)
	add_child(_plate)
	var rune := MeshInstance3D.new()
	var rune_mesh := BoxMesh.new()
	rune_mesh.size = Vector3(SIZE * 0.5, 0.02, SIZE * 0.5)
	_glow_mat = EnemyBase.flat_material(Color(0.3, 0.85, 0.9), true, 0.2)
	rune_mesh.material = _glow_mat
	rune.mesh = rune_mesh
	rune.position = Vector3(0, 0.07, 0)
	_plate.add_child(rune)


func _ready() -> void:
	super()
	_loaded = true


## Is anything on it right now? Living heroes (the server's proxies online)
## and push blocks of this zone.
func weighed() -> bool:
	var zone := ZoneBase.zone_of(self)
	if zone == null:
		return false
	var area := Rect2(global_position.x - SIZE * 0.5, global_position.z - SIZE * 0.5, SIZE, SIZE)
	for p in zone.players:
		if p != null and is_instance_valid(p) and not p.health.is_dead \
				and area.has_point(Vector2(p.global_position.x, p.global_position.z)) \
				and absf(p.global_position.y - global_position.y) < HEIGHT_BAND:
			return true
	if zone is DungeonZone:
		for key: String in (zone as DungeonZone).puzzles:
			var block := (zone as DungeonZone).puzzles[key] as PushBlock
			if block != null:
				var at := block.rest_position()
				if area.has_point(Vector2(at.x, at.z)):
					return true
	return false


func _physics_process(delta: float) -> void:
	if Net.is_client() or (latch and is_down()):
		return
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = CHECK_EVERY
	var now := weighed()
	if now != is_down():
		state["down"] = now
		state["solved"] = now and latch
		commit()


func _present() -> void:
	if _plate == null:
		return
	var y := -0.05 if is_down() else 0.04
	_glow_mat.emission_energy_multiplier = 2.2 if is_down() else 0.2
	if not _loaded:
		_plate.position.y = y
		return
	var tw := _plate.create_tween()
	tw.tween_property(_plate, "position:y", y, 0.15)
	Sfx.play("block_clang", global_position, -12.0, 0.1, 1.4 if is_down() else 1.0)
