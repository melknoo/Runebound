class_name SyncLevers
extends PoiPuzzle
## M13b: levers (or storm coils) so far apart that one hero cannot reach
## them all within `window` seconds (the bake asserts the distance): the
## party splits up and pulls them at once. A pulled one shows it until its
## window runs out; all of them within one window solve it for good. The
## pulls are requests; the authority keeps the times on the server's clock.

const SOLVE_XP := 60
## Bots help while their leader is this close (m).
const BOT_REACH := 34.0

var levers: Array[Vector3] = []
var yaws: Array[float] = []
var window: float = 2.0
## "lever" (a handle) or "coil" (a copper coil that is struck).
var look: String = "lever"
var _handles: Array[Node3D] = []
var _glows: Array[StandardMaterial3D] = []
var _loaded: bool = false


static func build(zone: ZoneBase, poi: Dictionary) -> SyncLevers:
	var s := SyncLevers.new()
	s.id = String(poi.get("id", ""))
	s.name = "SyncLevers_" + s.id
	s.window = float(poi.get("window", 2.0))
	s.look = String(poi.get("look", "lever"))
	s.position = ZoneLayout.pos_of(poi)
	var pulled: Array = []
	for l: Array in poi.get("levers", []):
		s.levers.append(Vector3(float(l[0]), s.position.y, float(l[1])))
		s.yaws.append(float(l[2]) if l.size() > 2 else 0.0)
		pulled.append(0)
	s.act_range = 60.0
	s.state = {"pulled": pulled, "solved": false}
	s.set_meta(&"poi_id", s.id)
	s._build()
	zone.world.add_child(s)
	s._loaded = true
	return s


func now_msec() -> int:
	return IceBridge.now_msec(self)


func is_active() -> bool:
	return is_solved()


## Is lever i pulled and still inside its window?
func pulled_now(i: int) -> bool:
	var pulled: Array = state.get("pulled", [])
	return i < pulled.size() and int(pulled[i]) > 0 and now_msec() - int(pulled[i]) < int(window * 1000.0)


## M13b bots: in front of every lever (`pull` its index) until it is solved,
## while the leader is about.
func bot_stations(leader: Player) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if is_solved() or leader == null or leader.global_position.distance_to(global_position) > BOT_REACH:
		return out
	for i in levers.size():
		out.append({"pos": levers[i] + Vector3(sin(yaws[i]), 0.0, cos(yaws[i])) * 1.2, "pull": i})
	return out


func pulled_count() -> int:
	var n := 0
	for i in levers.size():
		if pulled_now(i):
			n += 1
	return n


func _build() -> void:
	for i in levers.size():
		var holder := Node3D.new()
		add_child(holder)
		holder.position = levers[i] - position
		holder.rotation.y = yaws[i]
		var body := StaticBody3D.new()
		body.collision_layer = Grove.FOLIAGE_LAYER
		body.collision_mask = 0
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.8, 1.4, 0.8)
		col.shape = shape
		col.position = Vector3(0, 0.7, 0)
		body.add_child(col)
		holder.add_child(body)
		var glow := EnemyBase.flat_material(Color(0.62, 0.55, 1.0), true, 0.2)
		_glows.append(glow)
		var handle := Node3D.new()
		holder.add_child(handle)
		if look == "coil":
			var base := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.32
			cyl.bottom_radius = 0.42
			cyl.height = 1.3
			cyl.material = EnemyBase.flat_material(Color(0.25, 0.42, 0.36))
			base.mesh = cyl
			base.position = Vector3(0, 0.65, 0)
			holder.add_child(base)
			var cap := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 0.26
			sphere.height = 0.52
			sphere.material = glow
			cap.mesh = sphere
			handle.position = Vector3(0, 1.45, 0)
			handle.add_child(cap)
		else:
			var post := MeshInstance3D.new()
			var post_mesh := BoxMesh.new()
			post_mesh.size = Vector3(0.7, 1.0, 0.5)
			post_mesh.material = EnemyBase.flat_material(Color(0.3, 0.32, 0.38))
			post.mesh = post_mesh
			post.position = Vector3(0, 0.5, 0)
			holder.add_child(post)
			var rune := MeshInstance3D.new()
			var rune_mesh := BoxMesh.new()
			rune_mesh.size = Vector3(0.36, 0.36, 0.04)
			rune_mesh.material = glow
			rune.mesh = rune_mesh
			rune.position = Vector3(0, 0.6, 0.27)
			holder.add_child(rune)
			handle.position = Vector3(0, 1.0, 0.28)
			var bar := MeshInstance3D.new()
			var bar_mesh := BoxMesh.new()
			bar_mesh.size = Vector3(0.1, 0.9, 0.1)
			bar_mesh.material = EnemyBase.flat_material(Color(0.55, 0.4, 0.22))
			bar.mesh = bar_mesh
			bar.position = Vector3(0, 0.4, 0)
			handle.add_child(bar)
		_handles.append(handle)
		var sw := PuzzleSwitch.new()
		sw.text_key = "ui.coop.coil" if look == "coil" else "ui.prompt.pull"
		sw.reach = 2.2
		var index := i
		sw.on_use = func(hero: Player) -> void: request("pull", index, hero)
		sw.usable = func(_hero: Player) -> bool: return not is_solved() and not pulled_now(index)
		holder.add_child(sw)
		sw.position = Vector3(0, 0.2, 0.75)


func _ready() -> void:
	super()
	if not Net.is_client() and not is_solved():
		(state["pulled"] as Array).fill(0)  # a clock of an earlier session means nothing now


func act(action: String, arg: Variant, _hero: Player) -> void:
	if action != "pull" or is_solved():
		return
	var i := int(arg)
	var pulled: Array = state["pulled"]
	if i < 0 or i >= pulled.size() or pulled_now(i):
		return
	pulled[i] = now_msec()
	var all := true
	for j in pulled.size():
		if not pulled_now(j):
			all = false
	if all:
		state["solved"] = true
		reward_party(SOLVE_XP, "ui.coop.sync_done")
	commit()


## Authority: a pull whose window ran out springs back (every machine sees it).
func _physics_process(_delta: float) -> void:
	if Net.is_client() or is_solved() or Engine.get_physics_frames() % 6 != 0:
		return
	var pulled: Array = state.get("pulled", [])
	var expired := false
	for i in pulled.size():
		if int(pulled[i]) > 0 and not pulled_now(i):
			pulled[i] = 0
			expired = true
	if expired:
		commit()


func _present() -> void:
	var solved := is_solved()
	for i in _handles.size():
		var on := solved or pulled_now(i)
		_glows[i].emission_energy_multiplier = 2.4 if solved else (1.4 if on else 0.2)
		var h := _handles[i]
		if look == "coil":
			continue
		var want := Vector3(-70, 0, 0) if on else Vector3(35, 0, 0)
		if not _loaded:
			h.rotation_degrees = want
		elif not h.rotation_degrees.is_equal_approx(want):
			var tw := h.create_tween()
			tw.tween_property(h, "rotation_degrees", want, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _loaded:
		if solved:
			VFX.light_pop(self, global_position + Vector3(0, 1.4, 0), Color(0.72, 0.62, 1.0), 3.0, 8.0, 0.3)
		Sfx.play("storm_step" if look == "coil" else "block_clang", global_position, -8.0, 0.1)
