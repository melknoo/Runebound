class_name QuenchTrough
extends PoiPuzzle
## M13: a quench trough in the Slag Reeve's smelting hall - a stone tank of
## water under a tipping bucket on a chain. Pull the chain ([E]) and the
## bucket dumps its water over the trough's side: if the Reeve stands
## beside it, his crust cracks (SlagReeve.quench). The bucket refills for a
## few seconds before it can tip again. The pull is a request; the authority
## keeps `pulls` (how often it tipped), `cooled` (how often it caught him)
## and `until` (the refill, server clock); every machine shows the splash.

const REFILL := 6.0

var _bucket: Node3D
var _loaded: bool = false
var _last_pulls: int = 0


static func build(zone: ZoneBase, poi: Dictionary) -> QuenchTrough:
	var q := QuenchTrough.new()
	q.id = String(poi.get("id", ""))
	q.name = "Quench_" + q.id
	q.act_range = 6.0
	q.state = {"pulls": 0, "cooled": 0, "until": 0}
	q.set_meta(&"poi_id", q.id)
	q.position = ZoneLayout.pos_of(poi)
	q.rotation.y = float(poi.get("yaw", 0.0))
	q._build()
	zone.world.add_child(q)
	q._loaded = true
	return q


func now_msec() -> int:
	return IceBridge.now_msec(self)


## Ready to tip again?
func is_ready() -> bool:
	return now_msec() >= int(state.get("until", 0))


func _build() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Grove.FOLIAGE_LAYER  # heroes and enemies bump it, the camera passes
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.4, 0.8, 1.2)
	col.shape = shape
	col.position = Vector3(0, 0.4, 0)
	body.add_child(col)
	add_child(body)
	var stone := EnemyBase.flat_material(ArtKit.color("palettes.warrens.wall.3", Color(0.18, 0.14, 0.11)))
	var tank := MeshInstance3D.new()
	var tank_mesh := BoxMesh.new()
	tank_mesh.size = Vector3(2.4, 0.8, 1.2)
	tank_mesh.material = stone
	tank.mesh = tank_mesh
	tank.position = Vector3(0, 0.4, 0)
	add_child(tank)
	var water := MeshInstance3D.new()
	var water_mesh := BoxMesh.new()
	water_mesh.size = Vector3(2.1, 0.06, 0.9)
	water_mesh.material = WaterChannel.water_material()
	water.mesh = water_mesh
	water.position = Vector3(0, 0.78, 0)
	add_child(water)
	# the gallows and the bucket on its chain
	var iron := EnemyBase.flat_material(Color(0.16, 0.15, 0.15))
	for part: Array in [[Vector3(0.14, 3.0, 0.14), Vector3(1.05, 1.5, -0.5)], [Vector3(1.3, 0.14, 0.14), Vector3(0.45, 3.0, -0.5)]]:
		var beam := MeshInstance3D.new()
		var beam_mesh := BoxMesh.new()
		beam_mesh.size = part[0]
		beam_mesh.material = iron
		beam.mesh = beam_mesh
		beam.position = part[1]
		add_child(beam)
	_bucket = Node3D.new()
	_bucket.position = Vector3(0.0, 2.9, -0.5)
	add_child(_bucket)
	var chain := MeshInstance3D.new()
	var chain_mesh := BoxMesh.new()
	chain_mesh.size = Vector3(0.05, 0.7, 0.05)
	chain_mesh.material = iron
	chain.mesh = chain_mesh
	chain.position = Vector3(0, -0.35, 0)
	_bucket.add_child(chain)
	var pail := MeshInstance3D.new()
	var pail_mesh := CylinderMesh.new()
	pail_mesh.top_radius = 0.32
	pail_mesh.bottom_radius = 0.24
	pail_mesh.height = 0.5
	pail_mesh.material = EnemyBase.flat_material(ArtKit.color("palettes.warrens.timber.2", Color(0.27, 0.19, 0.12)))
	pail.mesh = pail_mesh
	pail.position = Vector3(0, -0.95, 0)
	_bucket.add_child(pail)
	var sw := PuzzleSwitch.new()
	sw.text_key = "ui.prompt.chain"
	sw.reach = 2.4
	sw.on_use = func(hero: Player) -> void: request("pull", 0, hero)
	sw.usable = func(_hero: Player) -> bool: return is_ready()
	add_child(sw)
	sw.position = Vector3(0, 0.2, 0.9)


func _ready() -> void:
	super()
	if not Net.is_client() and int(state.get("until", 0)) != 0:
		state["until"] = 0  # a clock of an earlier session means nothing now
		commit()
	_last_pulls = int(state.get("pulls", 0))


## Authority: tip the bucket; the Reeve beside the trough is quenched.
func act(action: String, _arg: Variant, _hero: Player) -> void:
	if action != "pull" or not is_ready():
		return
	state["pulls"] = int(state.get("pulls", 0)) + 1
	state["until"] = now_msec() + int(REFILL * 1000.0)
	for e in EnemyBase.all_enemies:
		var reeve := e as SlagReeve
		if reeve != null and is_instance_valid(reeve) and not reeve.net_puppet and reeve.quench(global_position):
			state["cooled"] = int(state.get("cooled", 0)) + 1
	commit()


func _present() -> void:
	var pulls := int(state.get("pulls", 0))
	if not _loaded or pulls == _last_pulls:
		_last_pulls = pulls
		return
	_last_pulls = pulls
	var tw := _bucket.create_tween()
	tw.tween_property(_bucket, "rotation_degrees:x", 120.0, 0.25)
	tw.tween_interval(0.4)
	tw.tween_property(_bucket, "rotation_degrees:x", 0.0, 0.8)
	var splash_at := global_position + global_transform.basis.z * 1.4 + Vector3(0, 0.6, 0)
	VFX.frost_burst(get_tree().current_scene, splash_at, 2.4)
	Sfx.play("wave_surge", splash_at, -4.0, 0.1, 1.3)
