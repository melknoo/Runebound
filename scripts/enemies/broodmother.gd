class_name Broodmother
extends DungeonBoss
## M13 the Ember Warrens' end boss: the queen of the cinder beetles, a
## slag-plated beetle the size of a cart with a glowing egg sac. Close, she
## bites ahead; at range she draws a lane and charges down it; every few
## seconds she digs in, tunnels under her prey and breaks out beneath it (a
## wide ring fills first). She lays cinder beetles (one at a time) that dig
## in and hunt on their own. Below half her health the hall's lava runnels fill: standing
## in one burns - unless a quench valve by the wall crusts that runnel over
## for a while (no harm, firm ground). The runnels come from her arena (the
## layout POI); the authority runs the fight, every machine shows it.

const BITE_RANGE := 3.2
const BITE_AHEAD := 2.0
const BITE_RADIUS := 2.4
const BITE_WINDUP := 0.8
const BITE_DAMAGE := 14.0
const BITE_RECOVER := 1.6
const CHARGE_MIN := 6.0
const CHARGE_MAX := 16.0
const CHARGE_WINDUP := 1.0
const CHARGE_SPEED := 13.0
const CHARGE_DAMAGE := 20.0
const CHARGE_COOLDOWN := 8.0
const CHARGE_HALF_WIDTH := 1.6
const CHARGE_RECOVER := 1.6
const BURROW_EVERY := 20.0
const DIG_TIME := 0.8
const TUNNEL_TIME := 1.5
const TUNNEL_SPEED := 9.0
const EMERGE_TIME := 1.1
const EMERGE_RADIUS := 3.0
const EMERGE_DAMAGE := 18.0
const LAY_EVERY := 28.0
const LAY_TIME := 1.0
const BROOD_MAX := 2
const RUNNEL_EVERY := 16.0
const RUNNEL_RISE := 1.5
const RUNNEL_TIME := 8.0
const RUNNEL_TICK := 0.6
const RUNNEL_DAMAGE := 7.0
const CRUST_TIME := 8.0

const RIG_PATH := "res://assets/models/chars/broodmother.glb"

## The arena's lava runnels (XZ rects, from the layout POI).
var runnels: Array[Rect2] = []
## Authority: "" (dry), "rise", "up"; per runnel the crust's seconds left.
var lava: String = ""
var crust_left: Array[float] = []
var _lava_t: float = 0.0
var _lava_left: float = RUNNEL_EVERY * 0.5
var _lava_tick: float = 0.0
var _attack: String = ""
var _charge_cd: float = 3.0
var _charge_dir: Vector3 = Vector3.FORWARD
var _charge_hit: bool = false
var _burrow_left: float = BURROW_EVERY * 0.7
var _lay_left: float = LAY_EVERY * 0.6
var _burst_done: bool = false
var _planes: Array[MeshInstance3D] = []
var _groove_mat: StandardMaterial3D
var _crust_mat: StandardMaterial3D
var _telegraph: MeshInstance3D


func _init() -> void:
	super()
	xp_value = 900
	display_name = "The Ember Broodmother"
	max_health = 820.0
	move_speed = 3.0
	body_color = Color(0.2, 0.15, 0.12)


func setup_from_poi(poi: Dictionary) -> void:
	runnels.clear()
	crust_left.clear()
	for r: Array in poi.get("runnels", []):
		runnels.append(Rect2(float(r[0]), float(r[1]), float(r[2]) - float(r[0]), float(r[3]) - float(r[1])))
		crust_left.append(0.0)
	if is_inside_tree():
		_build_runnels()  # a co-op client's puppet learns its arena after it spawned


func _ready() -> void:
	super()
	_build_runnels()


func nameplate_height() -> float:
	return 3.8


func _build_body() -> void:
	if _setup_rigged_visual(RIG_PATH, "broodmother", {
		"idle": &"idle", "run": &"run", "run_speed": move_speed,
		"states": {AIState.WINDUP: &"bite", AIState.CIRCLE: &"lay", AIState.BLINK: &"burrow",
			AIState.EMERGE: &"emerge", AIState.ATTACK: &"charge", AIState.STAGGER: &"stagger",
			AIState.CHASE: &"@loco", AIState.IDLE: &"@loco", AIState.DEAD: &"@dead"},
	}, ArtKit.color("palettes.broodmother.glow")) != null:
		visual.scale = Vector3.ONE * 1.5
		base_visual_scale = visual.scale
		return
	super()


func _apply_presence(s: AIState) -> void:
	var under := s == AIState.BURIED or s == AIState.EMERGE
	set_targetable(not under)
	visual.visible = s != AIState.BURIED


func _present_state(s: AIState) -> void:
	super(s)
	_apply_presence(s)
	if s == AIState.EMERGE:
		_present_emerge()


func _physics_process(delta: float) -> void:
	super(delta)
	if net_puppet or ai_state == AIState.DEAD:
		return
	_tick_runnels(delta)


func _ai_process(delta: float) -> void:
	_charge_cd = maxf(_charge_cd - delta, 0.0)
	_burrow_left -= delta  # count in every state: a bite cycle in melee never starves them
	_lay_left -= delta
	match ai_state:
		AIState.IDLE:
			brake(delta)
			if player != null and distance_to_player() < AGGRO_RANGE * 2.0:
				_enter_state(AIState.CHASE)
				play_fx(&"roar")
		AIState.CHASE:
			face_player(delta, 4.0)
			var dist := distance_to_player()
			if _lay_left <= 0.0 and _brood_count() < BROOD_MAX:
				_lay_left = LAY_EVERY
				_enter_state(AIState.CIRCLE)
				play_fx(&"lay")
			elif _burrow_left <= 0.0:
				_burrow_left = BURROW_EVERY
				_enter_state(AIState.BLINK)
				play_fx(&"dig")
			elif dist <= BITE_RANGE:
				_attack = "bite"
				lock_strike()
				_enter_state(AIState.WINDUP)
				play_fx(&"bite_tell")
			elif _charge_cd <= 0.0 and dist >= CHARGE_MIN and dist <= CHARGE_MAX:
				_attack = "charge"
				_charge_cd = CHARGE_COOLDOWN
				_charge_hit = false
				_charge_dir = dir_to_player()
				visual.rotation.y = atan2(-_charge_dir.x, -_charge_dir.z)
				lock_strike()
				_enter_state(AIState.WINDUP)
				play_fx(&"charge_tell")
			else:
				move_towards(dir_to_player(), move_speed, delta)
		AIState.WINDUP:
			brake(delta)
			if _attack == "bite" and _state_timer >= BITE_WINDUP:
				_enter_state(AIState.RECOVER)
				play_fx(&"bite")
				strike_circle(strike_point(BITE_AHEAD), BITE_RADIUS, BITE_DAMAGE, HitInfo.DamageType.PHYSICAL,
					HitInfo.Weight.HEAVY, 7.0)
			elif _attack == "charge" and _state_timer >= CHARGE_WINDUP:
				_enter_state(AIState.ATTACK)
				play_fx(&"charge")
		AIState.ATTACK:  # the charge down its lane
			velocity.x = _charge_dir.x * CHARGE_SPEED
			velocity.z = _charge_dir.z * CHARGE_SPEED
			_charge_contact()
			var run := (global_position - _strike_origin).dot(_charge_dir)
			if is_on_wall() or _state_timer > 1.6 or run >= CHARGE_MAX:
				velocity.x = 0.0
				velocity.z = 0.0
				_enter_state(AIState.RECOVER)
		AIState.RECOVER:
			brake(delta)
			if _state_timer >= (CHARGE_RECOVER if _attack == "charge" else BITE_RECOVER):
				_enter_state(AIState.CHASE)
		AIState.CIRCLE:  # laying
			brake(delta)
			if _state_timer >= LAY_TIME:
				_lay()
				_enter_state(AIState.CHASE)
		AIState.BLINK:  # digging in
			brake(delta)
			if _state_timer >= DIG_TIME:
				_enter_state(AIState.BURIED)
				_apply_presence(AIState.BURIED)
		AIState.BURIED:  # tunnelling under her prey
			if player != null and is_instance_valid(player):
				var flat := player.global_position - global_position
				flat.y = 0.0
				if flat.length() > 0.8:
					move_towards(flat.normalized(), TUNNEL_SPEED, delta)
				else:
					brake(delta)
			if _state_timer >= TUNNEL_TIME:
				velocity.x = 0.0
				velocity.z = 0.0
				_burst_done = false
				_enter_state(AIState.EMERGE)
				_apply_presence(AIState.EMERGE)
				_present_emerge()
		AIState.EMERGE:
			brake(delta)
			if not _burst_done and _state_timer >= EMERGE_TIME * 0.8:
				_burst_done = true
				strike_circle(global_position, EMERGE_RADIUS, EMERGE_DAMAGE, HitInfo.DamageType.PHYSICAL,
					HitInfo.Weight.HEAVY, 8.0)
				play_fx(&"breach")
			if _state_timer >= EMERGE_TIME:
				_enter_state(AIState.CHASE)
				_apply_presence(AIState.CHASE)
		AIState.STAGGER:
			brake(delta)
			if _state_timer >= 0.0:
				_enter_state(AIState.CHASE)


func _charge_contact() -> void:
	if _charge_hit:
		return
	var here := (global_position - _strike_origin).dot(_charge_dir)
	var zone := ZoneBase.zone_of(self)
	if zone == null:
		return
	for hero in zone.players:
		if hero == null or not is_instance_valid(hero) or hero.health.is_dead:
			continue
		var rel := hero.global_position - _strike_origin
		rel.y = 0.0
		var along := rel.dot(_charge_dir)
		var side := (rel - _charge_dir * along).length()
		if side <= CHARGE_HALF_WIDTH + STRIKE_TOLERANCE and along >= here - 1.2 and along <= here + 2.2:
			_charge_hit = true
			var hit := HitInfo.create(CHARGE_DAMAGE, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.HEAVY, global_position - _charge_dir)
			hit.source_id = get_instance_id()
			hit.knockback = 10.0
			hit.area_center = _strike_origin + _charge_dir * along
			hit.area_radius = CHARGE_HALF_WIDTH + STRIKE_TOLERANCE
			hero.take_hit(hit)


func _brood_count() -> int:
	var n := 0
	for e in EnemyBase.all_enemies:
		if e is CinderBeetle and is_instance_valid(e) and e.ai_state != AIState.DEAD:
			n += 1
	return n


## Authority: a cinder beetle behind her (one per lay, at most BROOD_MAX
## alive); it digs in and hunts at once.
func _lay() -> void:
	var zone := ZoneBase.zone_of(self)
	if zone == null:
		return
	var back := -present_forward()
	for side: float in [1.0]:
		var at := global_position + back * 2.4 + Vector3(back.z, 0.0, -back.x) * side * 1.6
		if arena_rect.has_area():
			var inner := arena_rect.grow(-1.5)
			at.x = clampf(at.x, inner.position.x, inner.end.x)
			at.z = clampf(at.z, inner.position.y, inner.end.y)
		var egg := zone.spawn_by_id("cinder_beetle", zone.ground_point(at + Vector3(0, 1.0, 0), 0.2)) as CinderBeetle
		if egg != null:
			egg.wake()


# --- the lava runnels (below half her health) --------------------------------

func _tick_runnels(delta: float) -> void:
	for i in crust_left.size():
		if crust_left[i] > 0.0:
			crust_left[i] = maxf(crust_left[i] - delta, 0.0)
			if crust_left[i] <= 0.0:
				play_fx(StringName("thaw%d" % i))
	if runnels.is_empty() or (health.current_health > health.max_health * 0.5 and lava == ""):
		return
	_lava_t += delta
	match lava:
		"":
			_lava_left -= delta
			if _lava_left <= 0.0:
				lava = "rise"
				_lava_t = 0.0
				play_fx(&"lava_rise")
		"rise":
			if _lava_t >= RUNNEL_RISE:
				lava = "up"
				_lava_t = 0.0
				_lava_tick = 0.0
		"up":
			_lava_tick -= delta
			if _lava_tick <= 0.0:
				_lava_tick = RUNNEL_TICK
				_lava_bite()
			if _lava_t >= RUNNEL_TIME:
				_end_lava()


func _end_lava() -> void:
	lava = ""
	_lava_t = 0.0
	_lava_left = RUNNEL_EVERY
	play_fx(&"lava_end")


## The runnel a point stands in (-1: none).
func runnel_at(p: Vector3) -> int:
	for i in runnels.size():
		if runnels[i].has_point(Vector2(p.x, p.z)):
			return i
	return -1


func _lava_bite() -> void:
	var zone := ZoneBase.zone_of(self)
	if zone == null:
		return
	for hero in zone.players:
		if hero == null or not is_instance_valid(hero) or hero.health.is_dead:
			continue
		var i := runnel_at(hero.global_position)
		if i < 0 or crust_left[i] > 0.0:
			continue
		var hit := HitInfo.create(RUNNEL_DAMAGE, HitInfo.DamageType.FIRE, HitInfo.Weight.LIGHT, hero.global_position)
		hero.take_hit(hit)


## Authority (a LavaValve): runnel i crusts over for a while.
func crust_runnel(i: int) -> bool:
	if i < 0 or i >= crust_left.size() or ai_state == AIState.DEAD:
		return false
	crust_left[i] = CRUST_TIME
	play_fx(StringName("crust%d" % i))
	return true


## Dead, the runnels drain at once.
func _on_died() -> void:
	if lava != "" and not net_puppet:
		_end_lava()
	super()


# --- presentation ------------------------------------------------------------

func _build_runnels() -> void:
	if runnels.is_empty() or not _planes.is_empty():
		return
	_groove_mat = EnemyBase.flat_material(ArtKit.color("palettes.warrens.lava_crust", Color(0.16, 0.07, 0.05)))
	_crust_mat = EnemyBase.flat_material(ArtKit.color("palettes.warrens.floor.1", Color(0.13, 0.09, 0.07)))
	for r in runnels:
		var plane := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(r.size.x, 0.06, r.size.y)
		plane.mesh = box
		plane.material_override = _groove_mat
		plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		get_tree().current_scene.add_child(plane)
		var y := ZoneBase.ground_under(self, Vector3(r.get_center().x, global_position.y + 2.0, r.get_center().y)).y
		plane.global_position = Vector3(r.get_center().x, y + 0.02, r.get_center().y)
		_planes.append(plane)


func _show_runnel(i: int, look: String) -> void:
	if i < 0 or i >= _planes.size() or not is_instance_valid(_planes[i]):
		return
	match look:
		"lava":
			_planes[i].material_override = WaterChannel.lava_material()
		"crust":
			_planes[i].material_override = _crust_mat
		_:
			_planes[i].material_override = _groove_mat


func _present_emerge() -> void:
	_telegraph = VFX.telegraph_disc(get_tree().current_scene, present_origin(), EMERGE_RADIUS, EMERGE_TIME * 0.8)
	VFX.dodge_dust(get_tree().current_scene, present_origin(), Vector3.UP)
	Sfx.play("chitter", global_position, 0.0, 0.1, 0.5)


func _present_fx(fx: StringName) -> void:
	var scene := get_tree().current_scene
	var s := String(fx)
	if s.begins_with("crust"):
		var ci := s.trim_prefix("crust").to_int()
		if net_puppet and ci < crust_left.size():
			crust_left[ci] = CRUST_TIME
		_show_runnel(ci, "crust")
		VFX.frost_burst(scene, Vector3(runnels[ci].get_center().x, present_origin().y + 0.4, runnels[ci].get_center().y)
			if ci < runnels.size() else present_origin(), 3.0)
		Sfx.play("steam_hiss", global_position, 0.0, 0.05, 0.8)
		return
	if s.begins_with("thaw"):
		var ti := s.trim_prefix("thaw").to_int()
		if net_puppet and ti < crust_left.size():
			crust_left[ti] = 0.0
		_show_runnel(ti, "lava" if lava != "" else "groove")
		return
	match fx:
		&"roar":
			Sfx.play("brood_shriek", global_position, 0.0, 0.1, 1.0)
		&"bite_tell":
			_telegraph = VFX.telegraph_disc(scene, present_origin() + present_forward() * BITE_AHEAD, BITE_RADIUS, BITE_WINDUP)
			Sfx.play("chitter", global_position, -2.0, 0.1, 0.6)
		&"bite":
			VFX.earthbreaker_slam(scene, present_origin() + present_forward() * BITE_AHEAD, BITE_RADIUS)
			Sfx.play("earthbreaker_impact", global_position, -3.0, 0.1, 0.9)
		&"charge_tell":
			_telegraph = VFX.telegraph_lane(scene, present_origin(), present_forward(), CHARGE_MAX, CHARGE_HALF_WIDTH * 2.0,
				CHARGE_WINDUP)
			Sfx.play("brood_shriek", global_position, -2.0, 0.1, 1.2)
		&"charge":
			Sfx.play("earthbreaker_windup", global_position, -2.0, 0.1, 1.4)
		&"dig":
			VFX.dodge_dust(scene, present_origin(), Vector3.UP)
			Sfx.play("earthbreaker_impact", global_position, -6.0, 0.1, 0.6)
		&"breach":
			VFX.earthbreaker_slam(scene, present_origin(), EMERGE_RADIUS)
			VFX.ember_impact(scene, present_origin() + Vector3(0, 0.5, 0))
			Sfx.play("earthbreaker_impact", global_position, 0.0, 0.1, 0.5)
			GameFeel.camera_shake(0.35)
		&"lay":
			VFX.flash(scene, present_origin() + Vector3(0, 1.2, 0) - present_forward() * 2.0,
				ArtKit.color("palettes.broodmother.glow", Color(1.0, 0.6, 0.2)), 1.4, LAY_TIME)
			Sfx.play("brood_shriek", global_position, -6.0, 0.1, 1.5)
		&"lava_rise":
			if net_puppet:
				lava = "rise"
			for i in _planes.size():
				_show_runnel(i, "crust" if i < crust_left.size() and crust_left[i] > 0.0 else "lava")
			Sfx.play("wave_surge", global_position, 2.0, 0.05, 0.5)
			GameFeel.camera_shake(0.2)
		&"lava_end":
			if net_puppet:
				lava = ""
			for i in _planes.size():
				_show_runnel(i, "groove")


func _on_interrupted() -> void:
	if _telegraph != null and is_instance_valid(_telegraph):
		_telegraph.queue_free()


func _exit_tree() -> void:
	super()
	for plane in _planes:
		if is_instance_valid(plane):
			plane.queue_free()
