class_name ElementCarrier
extends Node3D
## M13: an element source in a dungeon - an ember bowl, a frost crystal, a
## storm coil. Any strike on it (every hit path finds its hurtbox, like a
## brazier's) gives the striking hero the element for a few seconds
## (ElementCharge). Personal and local: no state, nothing on the net but the
## hero's aura.

var element: int = ElementCharge.NONE
var id: String = ""
var _glow_mat: StandardMaterial3D


static func build(zone: ZoneBase, poi: Dictionary) -> ElementCarrier:
	var c := ElementCarrier.new()
	c.id = String(poi.get("id", ""))
	c.name = "Carrier_" + c.id
	c.element = ElementCharge.element_id(String(poi.get("element", "fire")))
	c.set_meta(&"poi_id", c.id)
	c.position = ZoneLayout.pos_of(poi)
	zone.world.add_child(c)
	return c


func _ready() -> void:
	var col := ElementCharge.color(element)
	var body := StaticBody3D.new()
	body.collision_layer = Grove.FOLIAGE_LAYER
	body.collision_mask = 0
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.9, 1.0, 0.9)
	shape_node.shape = shape
	shape_node.position = Vector3(0, 0.5, 0)
	body.add_child(shape_node)
	add_child(body)
	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.55
	base_mesh.bottom_radius = 0.42
	base_mesh.height = 0.9
	base_mesh.material = EnemyBase.flat_material(Color(0.28, 0.27, 0.27))
	base.mesh = base_mesh
	base.position = Vector3(0, 0.45, 0)
	add_child(base)
	var core := MeshInstance3D.new()
	_glow_mat = EnemyBase.flat_material(col, true, 2.4)
	match element:
		HitInfo.DamageType.FROST:
			var prism := PrismMesh.new()
			prism.size = Vector3(0.5, 0.9, 0.5)
			prism.material = _glow_mat
			core.mesh = prism
			core.position = Vector3(0, 1.35, 0)
		HitInfo.DamageType.LIGHTNING:
			var coil := CylinderMesh.new()
			coil.top_radius = 0.18
			coil.bottom_radius = 0.18
			coil.height = 0.8
			coil.material = _glow_mat
			core.mesh = coil
			core.position = Vector3(0, 1.3, 0)
		_:
			var embers := SphereMesh.new()
			embers.radius = 0.38
			embers.height = 0.4
			embers.material = _glow_mat
			core.mesh = embers
			core.position = Vector3(0, 1.0, 0)
	add_child(core)
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 1.3
	light.omni_range = 4.5
	light.shadow_enabled = false
	light.position = Vector3(0, 1.4, 0)
	add_child(light)
	Hurtbox.create(self, 0b10000, 0.55, 1.4, 1.0)


## Any strike: the striking hero (this machine's) carries the element.
func take_hit(hit: HitInfo) -> bool:
	if hit == null:
		return false
	var zone := ZoneBase.zone_of(self)
	var hero := zone.player if zone != null else null
	if hero == null or not is_instance_valid(hero):
		return false
	ElementCharge.give(hero, element)
	VFX.flash(get_tree().current_scene, global_position + Vector3(0, 1.2, 0), ElementCharge.color(element), 1.0, 0.15)
	return false
