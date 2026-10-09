class_name SecretWall
extends PoiPuzzle
## M13: a cracked wall that closes a secret doorway. It looks like the wall
## around it but for a few fine cracks; three strikes (any hit: a basic
## attack, a bolt, a thorn - every class has one) break it for the party.
## The strikes count on the authority (shared state, a hit at most every
## STRIKE_GAP seconds per hero, so one volley is one strike); broken, the wall
## crumbles and stays open (kept in the world).

const HITS := 3
const STRIKE_GAP := 0.35
const FOUND_XP := 60

var rect: Rect2 = Rect2()
var floor_y: float = 0.0
var height: float = 6.0
var _body: StaticBody3D
var _crack_mat: StandardMaterial3D
var _last_strike: int = -100000
var _loaded: bool = false


static func build(zone: ZoneBase, door: Dictionary, wall_mat: Material) -> SecretWall:
	var w := SecretWall.new()
	w.id = String(door.get("id", ""))
	w.name = "SecretWall_" + w.id
	w.rect = DungeonLayout.rect_of(door)
	w.floor_y = float(door.get("floor", 0.0))
	w.height = float(door.get("wall_h", 6.0))
	w.act_range = maxf(w.rect.size.x, w.rect.size.y) * 0.5 + 3.0
	w.state = {"hits": 0, "solved": false}
	w.set_meta(&"poi_id", w.id)
	w.position = Vector3(w.rect.get_center().x, w.floor_y, w.rect.get_center().y)
	w._build(wall_mat)
	zone.world.add_child(w)
	return w


func _build(wall_mat: Material) -> void:
	_body = StaticBody3D.new()
	_body.collision_layer = 1  # a wall like the others (the camera stops at it too)
	_body.collision_mask = 0
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(rect.size.x, height, rect.size.y)
	box.material = wall_mat
	mesh.mesh = box
	mesh.position = Vector3(0, height * 0.5, 0)
	_body.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	col.shape = shape
	col.position = mesh.position
	_body.add_child(col)
	add_child(_body)
	# the tell: fine cracks on both faces, a faint cold glow in them
	_crack_mat = EnemyBase.flat_material(Color(0.12, 0.2, 0.22), true, 0.25)
	var across_x := rect.size.x >= rect.size.y
	var st := SurfaceTool.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	for face: float in [-1.0, 1.0]:
		for k in 5:
			var crack := BoxMesh.new()
			var length := rng.randf_range(0.5, 1.3)
			crack.size = Vector3(0.05, length, 0.02) if across_x else Vector3(0.02, length, 0.05)
			var along := rng.randf_range(-0.6, 0.6)
			var depth := (rect.size.y if across_x else rect.size.x) * 0.5 + 0.01
			var at := Vector3(along, rng.randf_range(0.6, 2.4), face * depth) if across_x else Vector3(face * depth, rng.randf_range(0.6, 2.4), along)
			var tilt := Basis(Vector3.FORWARD if across_x else Vector3.RIGHT, rng.randf_range(-0.6, 0.6))
			st.append_from(crack, 0, Transform3D(tilt, at))
	var cracks := MeshInstance3D.new()
	cracks.name = "Cracks"
	cracks.mesh = st.commit()
	cracks.material_override = _crack_mat
	_body.add_child(cracks)
	# what the strikes find: a hurtbox through the wall, poking out of both faces
	var reach := minf(rect.size.x, rect.size.y) * 0.5 + 0.4
	Hurtbox.create(self, 0b10000, reach, 3.0, 1.5)


func _ready() -> void:
	super()
	_loaded = true


## A hit from any hero's attack (the hurtbox): one strike, asked of the authority.
func take_hit(hit: HitInfo) -> bool:
	if hit == null or is_solved():
		return false
	var zone := ZoneBase.zone_of(self)
	var hero := zone.player if zone != null else null
	if hero == null or Time.get_ticks_msec() - _last_strike < int(STRIKE_GAP * 1000.0):
		return false
	_last_strike = Time.get_ticks_msec()
	request("strike", 0, hero)
	return false


func act(action: String, _arg: Variant, _hero: Player) -> void:
	if action != "strike" or is_solved():
		return
	state["hits"] = int(state.get("hits", 0)) + 1
	if int(state["hits"]) >= HITS:
		state["solved"] = true
		reward_party(FOUND_XP, "ui.dungeon.secret_found")
	commit()


func _present() -> void:
	if _crack_mat != null:
		_crack_mat.emission_energy_multiplier = 0.25 + 0.9 * float(int(state.get("hits", 0)))
	if _body != null and not is_solved() and _loaded and int(state.get("hits", 0)) > 0:
		VFX.flash(self, global_position + Vector3(0, 1.4, 0), Color(0.6, 0.85, 0.85), 1.2, 0.12)
		Sfx.play("impact_flesh", global_position, -8.0, 0.1, 0.6)


## Every machine, once (also on load): the wall is gone.
func _on_solved() -> void:
	if _body == null:
		return
	_body.collision_layer = 0
	for child in get_children():
		if child is Hurtbox:
			(child as Hurtbox).collision_layer = 0
	if not _loaded:
		_body.visible = false
		return
	var tw := _body.create_tween()
	tw.tween_property(_body, "position:y", -height - 0.5, 1.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void: _body.visible = false)
	VFX.ground_ring(self, global_position, Color(0.55, 0.5, 0.45), 4.0, 0.6)
	Sfx.play("earthbreaker_impact", global_position, -4.0, 0.1, 0.7)
	GameFeel.camera_shake(0.25)
