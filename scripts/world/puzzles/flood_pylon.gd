class_name FloodPylon
extends PoiPuzzle
## M13: a frost pylon in the Deepmaw's flooding ring. Any strike on it (every
## hit path finds its hurtbox) is a request; on the authority it freezes the
## risen flood for a while (Deepmaw.freeze_flood). Its state only counts the
## strikes that froze it (a flash on every machine).

var _crystal_mat: StandardMaterial3D
var _last_strike: int = -100000
var _loaded: bool = false


static func build(zone: ZoneBase, poi: Dictionary) -> FloodPylon:
	var p := FloodPylon.new()
	p.id = String(poi.get("id", ""))
	p.name = "Pylon_" + p.id
	p.act_range = 30.0
	p.state = {"froze": 0}
	p.set_meta(&"poi_id", p.id)
	p.position = ZoneLayout.pos_of(poi)
	p._build()
	zone.world.add_child(p)
	p._loaded = true
	return p


func _build() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Grove.FOLIAGE_LAYER
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.9, 2.4, 0.9)
	col.shape = shape
	col.position = Vector3(0, 1.2, 0)
	body.add_child(col)
	add_child(body)
	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.38
	base_mesh.bottom_radius = 0.5
	base_mesh.height = 1.0
	base_mesh.material = EnemyBase.flat_material(Color(0.24, 0.3, 0.32))
	base.mesh = base_mesh
	base.position = Vector3(0, 0.5, 0)
	add_child(base)
	var crystal := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(0.6, 1.5, 0.6)
	_crystal_mat = EnemyBase.flat_material(ElementCharge.color(HitInfo.DamageType.FROST), true, 1.2)
	prism.material = _crystal_mat
	crystal.mesh = prism
	crystal.position = Vector3(0, 1.75, 0)
	add_child(crystal)
	var light := OmniLight3D.new()
	light.light_color = ElementCharge.color(HitInfo.DamageType.FROST)
	light.light_energy = 1.0
	light.omni_range = 4.0
	light.shadow_enabled = false
	light.position = Vector3(0, 2.0, 0)
	add_child(light)
	Hurtbox.create(self, 0b10000, 0.6, 2.4, 1.3)


func take_hit(hit: HitInfo) -> bool:
	if hit == null:
		return false
	var zone := ZoneBase.zone_of(self)
	var hero := zone.player if zone != null else null
	if hero == null or Time.get_ticks_msec() - _last_strike < 400:
		return false
	_last_strike = Time.get_ticks_msec()
	request("strike", 0, hero)
	return false


## Authority: freeze the Deepmaw's flood, if one is up.
func act(action: String, _arg: Variant, _hero: Player) -> void:
	if action != "strike":
		return
	for e in EnemyBase.all_enemies:
		var maw := e as Deepmaw
		if maw != null and is_instance_valid(maw) and not maw.net_puppet and maw.freeze_flood():
			state["froze"] = int(state.get("froze", 0)) + 1
			commit()
			return


func _present() -> void:
	if _loaded and _crystal_mat != null:
		VFX.frost_burst(get_tree().current_scene, global_position + Vector3(0, 1.6, 0), 2.0)
