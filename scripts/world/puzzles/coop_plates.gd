class_name CoopPlates
extends PoiPuzzle
## M13b: plates held at once (the co-op dungeon). `plates` stone plates, far
## enough apart that one hero weighs one; each counts while a living hero
## stands on it (never a push block). Every plate held for `hold` seconds
## opens the group: for `open_for` seconds (then it closes again - a gate on
## it never closes on a hero), or for good when `open_for` is 0. The
## authority judges (the server from its hero proxies) and keeps the time on
## the server's clock; every machine shows how many plates are held.

const SIZE := 2.0
const CHECK_EVERY := 0.1
const HEIGHT_BAND := 1.5
const OPEN_XP := 40
## Bots help while their leader is this close (m).
const BOT_REACH := 30.0

var plate_pos: Array[Vector3] = []
var hold: float = 1.0
var open_for: float = 20.0
var _held_for: float = 0.0
var _check_left: float = 0.0
var _rewarded: bool = false
var _was_open: bool = false
var _glows: Array[StandardMaterial3D] = []
var _label: Label3D


static func build(zone: ZoneBase, poi: Dictionary) -> CoopPlates:
	var c := CoopPlates.new()
	c.id = String(poi.get("id", ""))
	c.name = "CoopPlates_" + c.id
	c.hold = float(poi.get("hold", 1.0))
	c.open_for = float(poi.get("open_for", 20.0))
	c.position = ZoneLayout.pos_of(poi)
	var down: Array = []
	for p: Array in poi.get("plates", []):
		c.plate_pos.append(Vector3(float(p[0]), c.position.y, float(p[1])))
		down.append(false)
	c.act_range = 40.0
	c.state = {"down": down, "until": 0, "solved": false}
	c.set_meta(&"poi_id", c.id)
	c._build()
	zone.world.add_child(c)
	return c


func now_msec() -> int:
	return IceBridge.now_msec(self)


## Open right now (for good, or until the time runs out).
func is_active() -> bool:
	return is_solved() or now_msec() < int(state.get("until", 0))


## M13b bots: where helpers stand - every plate, while the group is shut and
## the leader is about.
func bot_stations(leader: Player) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if is_active() or leader == null or leader.global_position.distance_to(global_position) > BOT_REACH:
		return out
	for at in plate_pos:
		out.append({"pos": at, "pull": -1})
	return out


func held_count() -> int:
	var n := 0
	for d: Variant in state.get("down", []):
		if bool(d):
			n += 1
	return n


func _build() -> void:
	for at in plate_pos:
		var plate := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(SIZE, 0.12, SIZE)
		mesh.material = EnemyBase.flat_material(Color(0.3, 0.32, 0.38))
		plate.mesh = mesh
		add_child(plate)
		plate.position = at - position + Vector3(0, 0.04, 0)
		var rune := MeshInstance3D.new()
		var rune_mesh := BoxMesh.new()
		rune_mesh.size = Vector3(SIZE * 0.55, 0.02, SIZE * 0.55)
		var glow := EnemyBase.flat_material(Color(0.62, 0.55, 1.0), true, 0.2)
		rune_mesh.material = glow
		rune.mesh = rune_mesh
		rune.position = Vector3(0, 0.07, 0)
		plate.add_child(rune)
		_glows.append(glow)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0, 2.6, 0)
	_label.modulate = Color(0.78, 0.72, 1.0)
	UiTheme.label3d(_label)
	add_child(_label)


## Which plates bear a living hero right now (the authority's heroes).
func weighed() -> Array:
	var out: Array = []
	var zone := ZoneBase.zone_of(self)
	for at in plate_pos:
		var area := Rect2(at.x - SIZE * 0.5, at.z - SIZE * 0.5, SIZE, SIZE)
		var on := false
		if zone != null:
			for p in zone.players:
				if p != null and is_instance_valid(p) and not p.health.is_dead \
						and area.has_point(Vector2(p.global_position.x, p.global_position.z)) \
						and absf(p.global_position.y - at.y) < HEIGHT_BAND:
					on = true
					break
		out.append(on)
	return out


func _physics_process(delta: float) -> void:
	if Net.is_client() or is_solved():
		return
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = CHECK_EVERY
	var changed := false
	var now_down := weighed()
	if now_down != (state.get("down", []) as Array):
		state["down"] = now_down
		changed = true
	var until := int(state.get("until", 0))
	if until != 0 and now_msec() >= until:  # closed again: every machine's gates follow the commit
		state["until"] = 0
		changed = true
	if not now_down.has(false) and not now_down.is_empty():
		_held_for += CHECK_EVERY
		if _held_for >= hold and not is_active():
			if open_for <= 0.0:
				state["solved"] = true
			else:
				state["until"] = now_msec() + int(open_for * 1000.0)
			changed = true
			if not _rewarded:
				_rewarded = true
				reward_party(OPEN_XP, "ui.coop.plates_open")
	else:
		_held_for = 0.0
	if changed:
		commit()


func _present() -> void:
	var down: Array = state.get("down", [])
	var open := is_active()
	for i in _glows.size():
		var on := i < down.size() and bool(down[i])
		_glows[i].emission_energy_multiplier = 2.2 if open else (1.2 if on else 0.2)
	if _label != null:
		_label.text = "" if open else "%d / %d" % [held_count(), plate_pos.size()]
	if open != _was_open:
		_was_open = open
		Sfx.play("block_clang", global_position, -8.0, 0.05, 1.3 if open else 0.8)
