class_name LavaValve
extends PoiPuzzle
## M13: a quench valve by the wall of the Broodmother's brood hall. Turn it
## ([E]) and water hisses into its lava runnel (`runnel`, an index into her
## arena's runnels): the runnel crusts over for a while (Broodmother.
## crust_runnel) - firm, cold ground across the burning hall. Its cistern
## refills for a few seconds before it turns again. The turn is a request;
## the authority keeps `turns` (how often it crusted) and `until` (the
## refill, server clock); every machine shows the wheel and the steam.

const REFILL := 10.0

var runnel: int = 0
var _wheel: Node3D
var _loaded: bool = false
var _last_turns: int = 0


static func build(zone: ZoneBase, poi: Dictionary) -> LavaValve:
	var v := LavaValve.new()
	v.id = String(poi.get("id", ""))
	v.name = "Valve_" + v.id
	v.runnel = int(poi.get("runnel", 0))
	v.act_range = 6.0
	v.state = {"turns": 0, "until": 0}
	v.set_meta(&"poi_id", v.id)
	v.position = ZoneLayout.pos_of(poi)
	v.rotation.y = float(poi.get("yaw", 0.0))
	v._build()
	zone.world.add_child(v)
	v._loaded = true
	return v


func now_msec() -> int:
	return IceBridge.now_msec(self)


func is_ready() -> bool:
	return now_msec() >= int(state.get("until", 0))


func _build() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Grove.FOLIAGE_LAYER
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.9, 1.4, 0.7)
	col.shape = shape
	col.position = Vector3(0, 0.7, 0)
	body.add_child(col)
	add_child(body)
	var iron := EnemyBase.flat_material(Color(0.16, 0.15, 0.15))
	var copper := EnemyBase.flat_material(ArtKit.color("palettes.warrens.ore.2", Color(0.58, 0.4, 0.2)))
	var post := MeshInstance3D.new()
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.6, 1.2, 0.5)
	post_mesh.material = iron
	post.mesh = post_mesh
	post.position = Vector3(0, 0.6, 0)
	add_child(post)
	var pipe := MeshInstance3D.new()
	var pipe_mesh := BoxMesh.new()
	pipe_mesh.size = Vector3(0.22, 0.22, 1.4)
	pipe_mesh.material = copper
	pipe.mesh = pipe_mesh
	pipe.position = Vector3(0, 0.3, 0.75)
	add_child(pipe)
	_wheel = Node3D.new()
	_wheel.position = Vector3(0, 1.25, 0.3)
	add_child(_wheel)
	for k in 4:
		var spoke := MeshInstance3D.new()
		var spoke_mesh := BoxMesh.new()
		spoke_mesh.size = Vector3(0.9, 0.08, 0.08)
		spoke_mesh.material = copper
		spoke.mesh = spoke_mesh
		spoke.rotation.z = k * PI * 0.25
		_wheel.add_child(spoke)
	var sw := PuzzleSwitch.new()
	sw.text_key = "ui.prompt.valve"
	sw.reach = 2.2
	sw.on_use = func(hero: Player) -> void: request("turn", 0, hero)
	sw.usable = func(_hero: Player) -> bool: return is_ready()
	add_child(sw)
	sw.position = Vector3(0, 0.2, 0.8)


func _ready() -> void:
	super()
	if not Net.is_client() and int(state.get("until", 0)) != 0:
		state["until"] = 0  # a clock of an earlier session means nothing now
		commit()
	_last_turns = int(state.get("turns", 0))


## Authority: the Broodmother's runnel crusts over (if she is there).
func act(action: String, _arg: Variant, _hero: Player) -> void:
	if action != "turn" or not is_ready():
		return
	for e in EnemyBase.all_enemies:
		var mother := e as Broodmother
		if mother != null and is_instance_valid(mother) and not mother.net_puppet and mother.crust_runnel(runnel):
			state["turns"] = int(state.get("turns", 0)) + 1
			state["until"] = now_msec() + int(REFILL * 1000.0)
			commit()
			return


func _present() -> void:
	var turns := int(state.get("turns", 0))
	if not _loaded or turns == _last_turns:
		_last_turns = turns
		return
	_last_turns = turns
	var tw := _wheel.create_tween()
	tw.tween_property(_wheel, "rotation:z", _wheel.rotation.z + TAU, 0.8).set_trans(Tween.TRANS_QUAD)
