class_name ChainPuzzle
extends PoiPuzzle
## M13b: the lightning chain. A charged coil (the source) and a receiver
## stand too far apart for one hero: living heroes within `link` metres of
## each other carry the lightning from the coil to the receiver (the bake
## asserts how many it takes). Closed for `hold` seconds, the chain solves it
## for good. Every machine draws the chain it sees from its own positions;
## the authority (the server, from its proxies) judges. A hero in the chain
## takes `damage` a second while it is unsolved (each owner its own hero) -
## the healer's moment.

const CHECK_EVERY := 0.1
const ARC_EVERY := 0.16
const HURT_EVERY := 0.5
const HEIGHT_BAND := 2.5
const SOLVE_XP := 60
const ARC_COLOR := Color(0.78, 0.7, 1.0)

var source: Vector3
var receiver: Vector3
var link: float = 8.0
var hold: float = 2.0
var damage: float = 0.0
## The heroes in the chain right now on this machine, coil to receiver
## (every connected hero while it is not closed: the arcs show the reach).
var path: Array[Player] = []
var closed: bool = false
var _held_for: float = 0.0
var _check_left: float = 0.0
var _arc_left: float = 0.0
var _hurt_left: float = HURT_EVERY
var _tops: Array[StandardMaterial3D] = []
var _trace: Dictionary = {}


static func build(zone: ZoneBase, poi: Dictionary) -> ChainPuzzle:
	var c := ChainPuzzle.new()
	c.id = String(poi.get("id", ""))
	c.name = "Chain_" + c.id
	c.link = float(poi.get("link", 8.0))
	c.hold = float(poi.get("hold", 2.0))
	c.damage = float(poi.get("damage", 0.0))
	c.position = ZoneLayout.pos_of(poi)
	var s: Array = poi.get("source", [0, 0])
	var r: Array = poi.get("receiver", [0, 0])
	c.source = Vector3(float(s[0]), c.position.y, float(s[1]))
	c.receiver = Vector3(float(r[0]), c.position.y, float(r[1]))
	c.act_range = c.source.distance_to(c.receiver) + c.link
	c.state = {"solved": false}
	c.set_meta(&"poi_id", c.id)
	c._build()
	zone.world.add_child(c)
	return c


## The chain through `heroes` (living, within `link` of each other) from
## `from` to `to`: the connected heroes in BFS order, and whether one of them
## reaches `to`. Pure, so tests and bots can ask too.
static func trace(heroes: Array[Player], from: Vector3, to: Vector3, reach: float) -> Dictionary:
	var parent: Dictionary = {}  # hero instance id -> the node before it (null = the coil)
	var order: Array[Player] = []
	var frontier: Array[Vector3] = [from]
	var frontier_heroes: Array = [null]
	var closed_at: Player = null
	while not frontier.is_empty():
		var at: Vector3 = frontier.pop_front()
		var by: Variant = frontier_heroes.pop_front()
		for h in heroes:
			if h == null or not is_instance_valid(h) or h.health.is_dead or parent.has(h.get_instance_id()):
				continue
			var hp := h.global_position
			if Vector2(hp.x - at.x, hp.z - at.z).length() <= reach and absf(hp.y - at.y) <= HEIGHT_BAND:
				parent[h.get_instance_id()] = by
				order.append(h)
				frontier.append(hp)
				frontier_heroes.append(h)
				if closed_at == null and Vector2(hp.x - to.x, hp.z - to.z).length() <= reach:
					closed_at = h
	var chain: Array[Player] = []
	if closed_at != null:
		var cur: Variant = closed_at
		while cur != null:
			chain.push_front(cur as Player)
			cur = parent.get((cur as Player).get_instance_id())
	return {"connected": order, "chain": chain, "closed": closed_at != null, "parent": parent}


## M13b bots: evenly along the line from the coil to the receiver, as many
## places as the chain needs conductors, while the leader is about.
func bot_stations(leader: Player) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if is_solved() or leader == null or leader.global_position.distance_to(global_position) > act_range:
		return out
	var k := maxi(ceili(Vector2(receiver.x - source.x, receiver.z - source.z).length() / link) - 1, 1)
	for i in k:
		out.append({"pos": source.lerp(receiver, float(i + 1) / float(k + 1)), "pull": -1})
	return out


func is_active() -> bool:
	return is_solved()


func _build() -> void:
	for at: Vector3 in [source, receiver]:
		var holder := Node3D.new()
		add_child(holder)
		holder.position = at - position
		var body := StaticBody3D.new()
		body.collision_layer = Grove.FOLIAGE_LAYER
		body.collision_mask = 0
		var col := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = 0.6
		shape.height = 2.6
		col.shape = shape
		col.position = Vector3(0, 1.3, 0)
		body.add_child(col)
		holder.add_child(body)
		var pylon := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.3
		cyl.bottom_radius = 0.6
		cyl.height = 2.4
		cyl.material = EnemyBase.flat_material(Color(0.25, 0.42, 0.36))
		pylon.mesh = cyl
		pylon.position = Vector3(0, 1.2, 0)
		holder.add_child(pylon)
		var top := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.4
		sphere.height = 0.8
		var glow := EnemyBase.flat_material(ARC_COLOR, true, 1.2 if at == source else 0.2)
		sphere.material = glow
		top.mesh = sphere
		top.position = Vector3(0, 2.6, 0)
		holder.add_child(top)
		_tops.append(glow)


func _physics_process(delta: float) -> void:
	var zone := ZoneBase.zone_of(self)
	if zone == null or is_solved():
		return
	_check_left -= delta
	if _check_left <= 0.0:
		_check_left = CHECK_EVERY
		_trace = trace(zone.party(), source, receiver, link)
		path.assign(_trace["connected"])
		closed = bool(_trace["closed"])
		if not Net.is_client():
			if closed:
				_held_for += CHECK_EVERY
				if _held_for >= hold:
					state["solved"] = true
					reward_party(SOLVE_XP, "ui.coop.chain_done")
					commit()
					return
			else:
				_held_for = 0.0
	_hurt_left -= delta
	if _hurt_left <= 0.0:
		_hurt_left = HURT_EVERY
		if damage > 0.0:  # each owner hurts its own conductor
			for h in path:
				if is_instance_valid(h) and h.net_role == Player.NetRole.OWNER and not h.health.is_dead:
					h.take_hit(HitInfo.create(damage * HURT_EVERY, HitInfo.DamageType.LIGHTNING, HitInfo.Weight.LIGHT,
						h.global_position))
	_arc_left -= delta
	if _arc_left <= 0.0 and Net.has_view() and not _trace.is_empty():
		_arc_left = ARC_EVERY
		_draw_arcs()


func _draw_arcs() -> void:
	var parent: Dictionary = _trace["parent"]
	var lift := Vector3(0, 1.2, 0)
	for h: Player in _trace["connected"]:
		if not is_instance_valid(h):
			continue
		var by: Variant = parent.get(h.get_instance_id())
		var from := source + Vector3(0, 2.6, 0) if by == null or not is_instance_valid(by) else (by as Player).global_position + lift
		VFX.lightning_arc(self, from, h.global_position + lift, ARC_COLOR)
	var chain: Array = _trace["chain"]
	if bool(_trace["closed"]) and not chain.is_empty() and is_instance_valid(chain.back()):
		VFX.lightning_arc(self, (chain.back() as Player).global_position + lift, receiver + Vector3(0, 2.6, 0), Color(1.0, 0.97, 0.85))
	if _tops.size() > 1:
		_tops[1].emission_energy_multiplier = 2.4 if bool(_trace["closed"]) else 0.2


func _present() -> void:
	if is_solved() and _tops.size() > 1:
		_tops[0].emission_energy_multiplier = 2.4
		_tops[1].emission_energy_multiplier = 2.4


func _on_solved() -> void:
	path.clear()
	VFX.light_pop(self, receiver + Vector3(0, 2.6, 0), ARC_COLOR, 4.0, 9.0, 0.35)
	Sfx.play("storm_step", receiver, -2.0, 0.05, 0.7)
