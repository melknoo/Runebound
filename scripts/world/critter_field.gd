class_name CritterField
extends Node3D
## M12: the Highlands' animals, kept around the local hero - at most
## MAX_ACTIVE, spawned SPAWN_MIN..SPAWN_MAX away (out of the way of the
## camera where it can), freed beyond DESPAWN. Hares live in the ash and the
## village, crows on the village's graves and the bone field; the burnt forest
## is silent. Never in a camp's, shrine's or arena's clearing. Only machines
## with a view keep a field (the dedicated server has none), and nothing of it
## goes over the net. LookDev "critters" switches it off (perf A/B).

const MAX_ACTIVE := 8
const SPAWN_MIN := 22.0
const SPAWN_MAX := 42.0
const DESPAWN := 58.0
const CHECK := 1.0
const CLEARING := 16.0        # metres around a combat pad without animals
const FLOCK := 3              # crows come in groups of up to this many

static var enabled: bool = true
static var _lookdev_ready: bool = false

var zone: ZoneBase
var layout: ZoneLayout
var critters: Array[Critter] = []
var _clearings: Array[Vector3] = []   # x, z, radius
var _check_left: float = 0.5
var _rng := RandomNumberGenerator.new()


static func allowed() -> bool:
	return Net.has_view()


static func create(z: ZoneBase, l: ZoneLayout) -> CritterField:
	if not allowed() or l == null:
		return null
	if not _lookdev_ready:
		_lookdev_ready = true
		LookDev.register(&"critters", func(v: Variant) -> void: CritterField.enabled = bool(v), true)
	var field := CritterField.new()
	field.name = "Critters"
	field.zone = z
	field.layout = l
	field._rng.randomize()
	for poi in l.pois:
		var type := String(poi.get("type", ""))
		if type in ["camp", "ruin", "ambush", "trial", "nest", "cursed", "arena", "lurker", "elite_patrol"]:
			var p := ZoneLayout.pos_of(poi)
			field._clearings.append(Vector3(p.x, p.z, float(poi.get("pad", 0.0)) + CLEARING))
	z.world.add_child(field)
	return field


## Which animal (or none, -1) lives at mask weights `w` (village, forest,
## bones); `roll` in 0..1 picks between the two where both live.
static func kind_for(w: Vector3, roll: float) -> int:
	if w.y > 0.4:
		return -1                       # the burnt forest: no animals
	if w.z > 0.5:
		return Critter.Kind.CROW        # the bone field
	if w.x > 0.5:
		return Critter.Kind.CROW if roll < 0.6 else Critter.Kind.HARE  # the village: graves and gardens
	return Critter.Kind.HARE if roll < 0.85 else Critter.Kind.CROW     # the ash


func _process(delta: float) -> void:
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = CHECK
	tick()


## One check: drop the gone and the far, maybe bring one (or a flock).
func tick() -> void:
	var hero: Player = zone.player if zone != null else null
	var live: Array[Critter] = []
	for c in critters:
		if not is_instance_valid(c) or c.state == Critter.State.GONE:
			continue
		if not enabled or hero == null or c.global_position.distance_to(hero.global_position) > DESPAWN:
			c.queue_free()
			continue
		live.append(c)
	critters = live
	if enabled and hero != null and is_instance_valid(hero) and critters.size() < MAX_ACTIVE:
		_try_spawn(hero)


func _try_spawn(hero: Player) -> void:
	var facing := Vector3.ZERO
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		facing = -cam.global_transform.basis.z
		facing.y = 0.0
		facing = facing.normalized()
	for attempt in 6:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, _rng.randf() * TAU)
		if facing != Vector3.ZERO and dir.dot(facing) > 0.35 and attempt < 4:
			continue  # rather where the camera does not look: they walk into view instead of popping in
		var p := hero.global_position + dir * _rng.randf_range(SPAWN_MIN, SPAWN_MAX)
		if not _fits(p):
			continue
		var kind := kind_for(layout.biome_weights(p.x, p.z), _rng.randf())
		if kind < 0:
			continue
		var count := 1 if kind == Critter.Kind.HARE else _rng.randi_range(1, FLOCK)
		for i in mini(count, MAX_ACTIVE - critters.size()):
			var at := p + Vector3(_rng.randf_range(-1.8, 1.8), 0.0, _rng.randf_range(-1.8, 1.8))
			critters.append(Critter.create(zone, kind as Critter.Kind, at, self))
		return


## Open ground in the zone, away from every hero and every combat pad, not on a slope.
func _fits(p: Vector3) -> bool:
	var b := layout.bounds().grow(-12.0)
	if not b.has_point(Vector2(p.x, p.z)):
		return false
	for c in _clearings:
		if Vector2(p.x, p.z).distance_to(Vector2(c.x, c.y)) < c.z:
			return false
	for h in zone.players:
		if is_instance_valid(h) and h.global_position.distance_to(p) < SPAWN_MIN * 0.8:
			return false
	var y := zone.ground_y(p)
	return absf(zone.ground_y(p + Vector3(1.0, 0, 0)) - y) < 0.7 and absf(zone.ground_y(p + Vector3(0, 0, 1.0)) - y) < 0.7
