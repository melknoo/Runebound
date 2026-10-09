class_name IceBridge
extends PoiPuzzle
## M13: an ice anchor in a full water channel. Struck with frost (the
## Elementalist's own, or a hero carrying a frost crystal's charge) it
## freezes a strip of the channel for `seconds`: the WaterChannel lays a
## walkable floe there and opens its fence. The freeze is a request; the
## authority keeps when it melts on the server's clock (`until`, server
## msec), so every machine melts it alike - but never under a hero standing
## on it (WaterChannel checks).

var strip: Rect2 = Rect2()
var seconds: float = 12.0
var socket: ElementSocket
var _anchor_mat: StandardMaterial3D
var _loaded: bool = false


static func build(zone: ZoneBase, poi: Dictionary) -> IceBridge:
	var b := IceBridge.new()
	b.id = String(poi.get("id", ""))
	b.name = "Ice_" + b.id
	var s: Array = poi.get("strip", [0, 0, 0, 0])
	b.strip = Rect2(float(s[0]), float(s[1]), float(s[2]) - float(s[0]), float(s[3]) - float(s[1]))
	b.seconds = float(poi.get("seconds", 12.0))
	b.act_range = 30.0  # frost spells reach it from the bank
	b.state = {"until": 0, "seq": 0}
	b.set_meta(&"poi_id", b.id)
	var at := ZoneLayout.pos_of(poi)
	var dz := zone as DungeonZone
	if dz != null:  # the anchor stands on the bank's level, out of the water
		var room := dz.layout.room_at(at.x, at.z)
		at.y = float(room.get("floor", at.y))
	b.position = at
	b._build()
	zone.world.add_child(b)
	return b


static func now_msec(node: Node) -> int:
	var zone := ZoneBase.zone_of(node)
	if zone != null and zone.net_world != null:
		return zone.net_world.server_msec()
	return Time.get_ticks_msec()


func is_active() -> bool:
	return now_msec(self) < int(state.get("until", 0))


func _build() -> void:
	var stone := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.35
	mesh.bottom_radius = 0.5
	mesh.height = 2.6
	mesh.material = EnemyBase.flat_material(Color(0.36, 0.42, 0.46))
	stone.mesh = mesh
	stone.position = Vector3(0, -0.7, 0)
	add_child(stone)
	var rune := MeshInstance3D.new()
	var cap := BoxMesh.new()
	cap.size = Vector3(0.4, 0.4, 0.4)
	_anchor_mat = EnemyBase.flat_material(ElementCharge.color(HitInfo.DamageType.FROST), true, 0.6)
	cap.material = _anchor_mat
	rune.mesh = cap
	rune.position = Vector3(0, 0.75, 0)
	rune.rotation_degrees = Vector3(45, 45, 0)
	add_child(rune)
	socket = ElementSocket.new()
	socket.puzzle = self
	add_child(socket)
	socket.setup(0.6, 1.6, 0.4)


func _ready() -> void:
	super()
	if not Net.is_client() and int(state.get("until", 0)) != 0:
		state["until"] = 0  # a clock of an earlier session means nothing now
		commit()
	_loaded = true


func struck(_index: int, with_element: int, hero: Player) -> void:
	if with_element != HitInfo.DamageType.FROST:
		return
	request("freeze", 0, hero)


func act(action: String, _arg: Variant, _hero: Player) -> void:
	if action != "freeze":
		return
	state["until"] = now_msec(self) + int(seconds * 1000.0)
	state["seq"] = int(state.get("seq", 0)) + 1
	commit()


func _present() -> void:
	if _anchor_mat != null:
		_anchor_mat.emission_energy_multiplier = 3.0 if is_active() else 0.6
	if _loaded and is_active():
		VFX.frost_burst(get_tree().current_scene, global_position, 3.0)
		Sfx.play("frost_nova", global_position, -4.0, 0.1)
