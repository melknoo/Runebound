class_name ElementPuzzle
extends PoiPuzzle
## M13: element targets - kilns to light with fire, copper posts to feed
## with lightning. A target takes its element from a strike (the hit's own,
## or the hero's carried charge from a source in the room) and stays lit
## `window` seconds (0 = for good). All lit at once: solved for good (gates
## wait on it). `ordered` targets take the element one after the other, each
## within `window` of the one before - a spark led from post to post; out of
## time, the chain goes dark again. The authority keeps the lit set (a
## strike is a request) and lets targets burn out.

const SOLVE_XP := 60

var element: int = HitInfo.DamageType.FIRE
var window: float = 10.0
var ordered: bool = false
var targets: Array[Vector3] = []
var _lit_at: Array[int] = []  # authority: when each target was lit (msec)
var _sockets: Array[ElementSocket] = []
var _flames: Array[MeshInstance3D] = []
var _lights: Array[OmniLight3D] = []
var _loaded: bool = false


static func build(zone: ZoneBase, poi: Dictionary) -> ElementPuzzle:
	var p := ElementPuzzle.new()
	p.id = String(poi.get("id", ""))
	p.name = "Element_" + p.id
	p.element = ElementCharge.element_id(String(poi.get("element", "fire")))
	p.window = float(poi.get("window", 10.0))
	p.ordered = bool(poi.get("ordered", false))
	var lit: Array = []
	var reach := 6.0
	var centre := ZoneLayout.pos_of(poi)
	for t: Array in poi.get("targets", []):
		var at := Vector3(float(t[0]), zone.ground_y(Vector3(float(t[0]), 0, float(t[1]))), float(t[1]))
		p.targets.append(at)
		p._lit_at.append(0)
		lit.append(false)
		reach = maxf(reach, at.distance_to(centre) + 30.0)  # ranged spells light them from afar
	p.act_range = reach
	p.state = {"lit": lit, "solved": false}
	p.set_meta(&"poi_id", p.id)
	p.position = centre
	p._build()
	zone.world.add_child(p)
	return p


func is_lit(i: int) -> bool:
	var lit: Array = state.get("lit", [])
	return i < lit.size() and bool(lit[i])


func lit_count() -> int:
	var n := 0
	for i in targets.size():
		if is_lit(i):
			n += 1
	return n


func _build() -> void:
	for i in targets.size():
		var holder := Node3D.new()
		add_child(holder)
		holder.position = targets[i] - position
		var body := StaticBody3D.new()
		body.collision_layer = Grove.FOLIAGE_LAYER
		body.collision_mask = 0
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.0, 1.4, 1.0)
		col.shape = shape
		col.position = Vector3(0, 0.7, 0)
		body.add_child(col)
		holder.add_child(body)
		var stand := MeshInstance3D.new()
		var mesh: PrimitiveMesh = BoxMesh.new() if element == HitInfo.DamageType.FIRE else CylinderMesh.new()
		if mesh is BoxMesh:
			(mesh as BoxMesh).size = Vector3(1.0, 1.4, 1.0)  # a kiln
		else:
			(mesh as CylinderMesh).top_radius = 0.18  # a copper post
			(mesh as CylinderMesh).bottom_radius = 0.24
			(mesh as CylinderMesh).height = 2.0
		mesh.material = EnemyBase.flat_material(Color(0.32, 0.3, 0.3) if element == HitInfo.DamageType.FIRE else Color(0.55, 0.35, 0.2))
		stand.mesh = mesh
		stand.position = Vector3(0, 0.7 if element == HitInfo.DamageType.FIRE else 1.0, 0)
		holder.add_child(stand)
		var flame := MeshInstance3D.new()
		var glow := SphereMesh.new()
		glow.radius = 0.32
		glow.height = 0.5
		glow.material = EnemyBase.flat_material(ElementCharge.color(element), true, 3.0)
		flame.mesh = glow
		flame.position = Vector3(0, 1.6 if element == HitInfo.DamageType.FIRE else 2.1, 0)
		flame.visible = false
		holder.add_child(flame)
		_flames.append(flame)
		var light := OmniLight3D.new()
		light.light_color = ElementCharge.color(element)
		light.omni_range = 4.0
		light.light_energy = 0.0
		light.shadow_enabled = false
		light.position = flame.position
		holder.add_child(light)
		_lights.append(light)
		var socket := ElementSocket.new()
		socket.puzzle = self
		socket.index = i
		holder.add_child(socket)
		socket.setup(0.55, 1.6, 1.0)
		_sockets.append(socket)


func _ready() -> void:
	super()
	if not Net.is_client():
		# a target lit in an earlier visit has long burnt out; a solved set stays
		var lit: Array = state.get("lit", [])
		if not is_solved() and lit.has(true):
			for i in lit.size():
				lit[i] = false
			commit()
	_loaded = true


## A socket was struck with `element` by this machine's hero.
func struck(index: int, with_element: int, hero: Player) -> void:
	if with_element != element or is_solved():
		return
	request("light", index, hero)


func act(action: String, arg: Variant, _hero: Player) -> void:
	if action != "light" or is_solved():
		return
	var i := int(arg)
	var lit: Array = state["lit"]
	if i < 0 or i >= lit.size():
		return
	if ordered:
		if i != lit_count():
			return  # out of turn: the spark has not reached it yet
		if bool(lit[i]):
			return
	lit[i] = true
	_lit_at[i] = Time.get_ticks_msec()
	if lit_count() == targets.size():
		state["solved"] = true
		reward_party(SOLVE_XP, "ui.puzzle.solved")
	commit()


## Authority: targets burn out after `window`; an ordered chain goes dark
## when the last spark is too old.
func _process(_delta: float) -> void:
	if Net.is_client() or is_solved() or window <= 0.0:
		return
	var now := Time.get_ticks_msec()
	var lit: Array = state.get("lit", [])
	var changed := false
	if ordered:
		var n := lit_count()
		if n > 0 and now - _lit_at[n - 1] > int(window * 1000.0):
			for i in lit.size():
				lit[i] = false
			changed = true
	else:
		for i in lit.size():
			if bool(lit[i]) and now - _lit_at[i] > int(window * 1000.0):
				lit[i] = false
				changed = true
	if changed:
		commit()


func _present() -> void:
	if _flames.is_empty():
		return
	for i in _flames.size():
		var on := is_lit(i) or is_solved()
		var was := _flames[i].visible
		_flames[i].visible = on
		_lights[i].light_energy = 1.6 if on else 0.0
		if on and not was and _loaded:
			var at := _flames[i].global_position
			VFX.flash(get_tree().current_scene, at, ElementCharge.color(element), 1.3, 0.15)
			if element == HitInfo.DamageType.LIGHTNING and i > 0:
				VFX.lightning_arc(get_tree().current_scene, _flames[i - 1].global_position, at, ElementCharge.color(element))
			Sfx.play("ember_impact" if element == HitInfo.DamageType.FIRE else "chain_spark", at, -6.0, 0.1)
