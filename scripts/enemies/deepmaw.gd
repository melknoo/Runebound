class_name Deepmaw
extends DungeonBoss
## M13 the Hollow Cistern's end boss: the great eel-worm under the heart of
## the cistern. It never walks: it rises at one of the room's drains, lunges
## down a lane or spits a fan of cold water, and after a while it sinks and
## rises at another drain (under the floor it cannot be hit). Now and then it
## calls the drowned up through the other drains. Below half its health the
## heart floods: the water rises in the outer ring of the room and nips and
## slows whoever stands in it, until it drains again - but a strike on one of
## the frost pylons in the ring freezes the flood solid for a while (no
## harm, firm ice). The drains, the ring and the pylons come from its arena
## (the layout POI); the authority runs the fight, every machine shows it.

const EMERGE_TIME := 1.0
const UP_TIME := 7.0
const SINK_TIME := 0.6
const UNDER_TIME := 1.4
const LUNGE_WINDUP := 0.9
const LUNGE_LENGTH := 8.0
const LUNGE_WIDTH := 2.4
const LUNGE_DAMAGE := 26.0
const SPIT_WINDUP := 0.7
const SPIT_BOLTS := 3
const SPIT_SPREAD := 0.5
const SPIT_DAMAGE := 12.0
const SPIT_SPEED := 10.0
const ATTACK_GAP := 1.0
const SUMMON_EVERY := 22.0
const FLOOD_EVERY := 18.0
const FLOOD_RISE := 1.5
const FLOOD_TIME := 7.0
const FLOOD_TICK := 0.6
const FLOOD_DAMAGE := 6.0
const FREEZE_TIME := 6.0
const MOUTH_HEIGHT := 2.4

const RIG_PATH := "res://assets/models/chars/deepmaw.glb"

var drains: Array[Vector3] = []
var inner: Rect2 = Rect2()
var _drain_index: int = -1  # none yet: it first rises at the drain nearest a hero
var _up_left: float = UP_TIME
var _attack_left: float = 1.2
var _next_is_lunge: bool = true
var _summon_left: float = SUMMON_EVERY * 0.6
var _lane_dir: Vector3 = Vector3.FORWARD
## Flood (authority): "" (none), "rise", "up", "frozen"; time in that phase.
var flood: String = ""
var _flood_t: float = 0.0
var _flood_left: float = FLOOD_EVERY * 0.5
var _flood_tick: float = 0.0
var _flood_planes: Array[MeshInstance3D] = []
var _flood_mat: ShaderMaterial
var _ice_mat: StandardMaterial3D


func _init() -> void:
	super()
	xp_value = 800
	display_name = "The Deepmaw"
	max_health = 1300.0
	move_speed = 0.0
	body_color = Color(0.2, 0.32, 0.36)
	immobile = true


## The arena's drains and safe middle (authority and puppets alike).
func setup_from_poi(poi: Dictionary) -> void:
	drains.clear()
	for d: Array in poi.get("drains", []):
		drains.append(Vector3(float(d[0]), float(poi.get("y", 0.0)), float(d[1])))
	var r: Array = poi.get("inner", [])
	if r.size() == 4:
		inner = Rect2(float(r[0]), float(r[1]), float(r[2]) - float(r[0]), float(r[3]) - float(r[1]))


func _ready() -> void:
	super()
	if not net_puppet:
		_enter_state(AIState.BURIED)  # under the floor until it rises at a drain
	_apply_presence(ai_state)


func _present_state(s: AIState) -> void:
	super(s)
	_apply_presence(s)


func _apply_presence(s: AIState) -> void:
	var under := s == AIState.BURIED or s == AIState.EMERGE
	set_targetable(not under)
	visual.visible = s != AIState.BURIED


func nameplate_height() -> float:
	return 4.4


func _build_body() -> void:
	if _setup_rigged_visual(RIG_PATH, "deepmaw", {
		"idle": &"idle", "run": &"idle", "run_speed": 1.0,
		"states": {AIState.EMERGE: &"emerge", AIState.WINDUP: &"lunge", AIState.CIRCLE: &"spit",
			AIState.BLINK: &"submerge", AIState.STAGGER: &"stagger", AIState.IDLE: &"@loco",
			AIState.CHASE: &"@loco", AIState.DEAD: &"@dead"},
	}, ArtKit.color("palettes.deepmaw.eyes")) != null:
		visual.scale = Vector3.ONE * 1.6
		base_visual_scale = visual.scale
		return
	var neck := MeshInstance3D.new()  # fallback: a great rearing column
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.45
	mesh.bottom_radius = 0.8
	mesh.height = 3.6
	mesh.material = flat_material(body_color)
	neck.mesh = mesh
	neck.position = Vector3(0, 1.8, 0)
	visual.add_child(neck)


## Never walks home: it moves only by sinking and rising.
func _should_return(_delta: float) -> bool:
	return false


func _physics_process(delta: float) -> void:
	super(delta)
	if net_puppet or ai_state == AIState.DEAD:
		return
	_tick_flood(delta)


func _ai_process(delta: float) -> void:
	brake(delta)
	match ai_state:
		AIState.EMERGE:
			face_player(delta, 6.0)
			if _state_timer >= EMERGE_TIME:
				_up_left = UP_TIME
				_attack_left = 0.8
				_enter_state(AIState.CHASE)
				_apply_presence(AIState.CHASE)
		AIState.IDLE, AIState.CHASE:
			face_player(delta, 4.0)
			_up_left -= delta
			_attack_left -= delta
			_summon_left -= delta
			if _summon_left <= 0.0:
				_summon_left = SUMMON_EVERY
				_summon()
			if _up_left <= 0.0:
				_enter_state(AIState.BLINK)  # sinking
				play_fx(&"sink")
				return
			if _attack_left <= 0.0 and player != null and is_instance_valid(player):
				if _next_is_lunge:
					lock_strike()
					_lane_dir = present_forward()
					_enter_state(AIState.WINDUP)
					play_fx(&"lunge_tell")
				else:
					_enter_state(AIState.CIRCLE)
					play_fx(&"spit_tell")
				_next_is_lunge = not _next_is_lunge
		AIState.WINDUP:
			if _state_timer >= LUNGE_WINDUP:
				_lunge()
				_attack_left = ATTACK_GAP
				_enter_state(AIState.CHASE)
		AIState.CIRCLE:
			face_player(delta, 3.0)
			if _state_timer >= SPIT_WINDUP:
				_spit()
				_attack_left = ATTACK_GAP
				_enter_state(AIState.CHASE)
		AIState.BLINK:
			if _state_timer >= SINK_TIME:
				_enter_state(AIState.BURIED)
				_apply_presence(AIState.BURIED)
		AIState.BURIED:
			if _state_timer >= UNDER_TIME:
				_move_to_next_drain()
				_enter_state(AIState.EMERGE)
				play_fx(&"breach")
				_apply_presence(AIState.EMERGE)
		AIState.STAGGER:
			if _state_timer >= 0.0:
				_enter_state(AIState.CHASE)


func _move_to_next_drain() -> void:
	if drains.size() < 2:
		return
	# rise at the drain nearest a hero (not the one it just left)
	var best := -1
	var best_d := INF
	var zone := ZoneBase.zone_of(self)
	for i in drains.size():
		if i == _drain_index:
			continue
		var d := INF
		if zone != null:
			var hero := zone.nearest_player(drains[i])
			d = hero.global_position.distance_to(drains[i]) if hero != null else randf() * 10.0
		if d < best_d:
			best_d = d
			best = i
	_drain_index = best if best >= 0 else (_drain_index + 1) % drains.size()
	global_position = ZoneBase.ground_under(self, drains[_drain_index], 0.05)


func _lunge() -> void:
	play_fx(&"lunge")
	var zone := ZoneBase.zone_of(self)
	if zone == null:
		return
	for hero in zone.players:
		if hero == null or not is_instance_valid(hero) or hero.health.is_dead:
			continue
		var rel := hero.global_position - global_position
		rel.y = 0.0
		var along := rel.dot(_lane_dir)
		var side := absf(rel.dot(Vector3(_lane_dir.z, 0.0, -_lane_dir.x)))
		if along >= -0.5 and along <= LUNGE_LENGTH and side <= LUNGE_WIDTH * 0.5 + STRIKE_TOLERANCE:
			var hit := HitInfo.create(LUNGE_DAMAGE, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.HEAVY, global_position)
			hit.knockback = 7.0
			hero.take_hit(hit)


func _spit() -> void:
	play_fx(&"spit")
	if player == null or not is_instance_valid(player):
		return
	var origin := global_position + Vector3(0, MOUTH_HEIGHT, 0) + present_forward() * 1.2
	var aim := (player.global_position + Vector3(0, 1.0, 0) - origin).normalized()
	for k in SPIT_BOLTS:
		var spread := (float(k) - float(SPIT_BOLTS - 1) * 0.5) * SPIT_SPREAD
		var bolt := EnemyBolt.new()
		bolt.setup(aim.rotated(Vector3.UP, spread), SPIT_SPEED, SPIT_DAMAGE)
		bolt.shooter_id = get_instance_id()
		bolt.position = origin
		get_tree().current_scene.add_child(bolt)


func _summon() -> void:
	var zone := ZoneBase.zone_of(self)
	if zone == null or drains.size() < 2:
		return
	play_fx(&"roar")
	var spawned := 0
	for i in drains.size():
		if i == _drain_index or spawned >= 2:
			continue
		spawned += 1
		var add := zone.spawn_by_id("drowned_thrall", zone.ground_point(drains[i] + Vector3(0, 1.0, 0), 0.2))
		VFX.frost_burst(get_tree().current_scene, add.global_position, 1.6)


# --- the flood (below half its health) -------------------------------------

func _tick_flood(delta: float) -> void:
	if health.current_health > health.max_health * 0.5 and flood == "":
		return
	_flood_t += delta
	match flood:
		"":
			_flood_left -= delta
			if _flood_left <= 0.0:
				flood = "rise"
				_flood_t = 0.0
				play_fx(&"flood_rise")
		"rise":
			if _flood_t >= FLOOD_RISE:
				flood = "up"
				_flood_t = 0.0
				_flood_tick = 0.0
				play_fx(&"flood")
		"up":
			_flood_tick -= delta
			if _flood_tick <= 0.0:
				_flood_tick = FLOOD_TICK
				_flood_bite()
			if _flood_t >= FLOOD_TIME:
				_end_flood()
		"frozen":
			if _flood_t >= FREEZE_TIME:
				_end_flood()


func _end_flood() -> void:
	flood = ""
	_flood_t = 0.0
	_flood_left = FLOOD_EVERY
	play_fx(&"flood_end")


## Dead, the heart drains at once (the risen or frozen flood with it).
func _on_died() -> void:
	if flood != "" and not net_puppet:
		_end_flood()
	super()


## Is a point in the flooded ring (the arena outside the safe middle)?
func in_ring(p: Vector3) -> bool:
	var q := Vector2(p.x, p.z)
	return arena_rect.has_point(q) and inner.has_area() and not inner.has_point(q)


func _flood_bite() -> void:
	var zone := ZoneBase.zone_of(self)
	if zone == null:
		return
	for hero in zone.players:
		if hero == null or not is_instance_valid(hero) or hero.health.is_dead or not in_ring(hero.global_position):
			continue
		var hit := HitInfo.create(FLOOD_DAMAGE, HitInfo.DamageType.FROST, HitInfo.Weight.LIGHT, hero.global_position)
		hit.applies_chill = true
		hero.take_hit(hit)


## Authority (a FloodPylon was struck): the risen flood freezes solid.
func freeze_flood() -> bool:
	if flood != "up" and flood != "rise":
		return false
	flood = "frozen"
	_flood_t = 0.0
	play_fx(&"freeze")
	return true


func _present_fx(fx: StringName) -> void:
	var scene := get_tree().current_scene
	match fx:
		&"lunge_tell":
			VFX.telegraph_lane(scene, present_origin(), present_forward(), LUNGE_LENGTH, LUNGE_WIDTH, LUNGE_WINDUP)
			Sfx.play("earthbreaker_windup", global_position, -4.0, 0.1, 0.5)
		&"lunge":
			VFX.earthbreaker_slam(scene, present_origin() + present_forward() * LUNGE_LENGTH * 0.6, 2.0)
			Sfx.play("earthbreaker_impact", global_position, -2.0, 0.1, 0.6)
			GameFeel.camera_shake(0.3)
		&"spit_tell":
			VFX.flash(scene, present_origin() + Vector3(0, MOUTH_HEIGHT, 0) + present_forward(),
				ArtKit.color("palettes.deepmaw.eyes", Color(0.6, 1.0, 0.9)), 1.4, SPIT_WINDUP)
			Sfx.play("caster_charge", global_position, -3.0, 0.1, 0.5)
		&"spit":
			Sfx.play("bolt_fire", global_position, -2.0, 0.1, 0.5)
		&"breach":
			VFX.frost_burst(scene, present_origin() + Vector3(0, 0.4, 0), 3.0)
			Sfx.play("water_splash", global_position, 0.0, 0.1, 0.6)
			GameFeel.camera_shake(0.15)
		&"sink":
			Sfx.play("water_splash", global_position, -4.0, 0.1, 0.5)
		&"roar":
			Sfx.play("deep_roar", global_position, 0.0, 0.1, 0.8)
		&"flood_rise":
			_show_flood(true, false)
			Sfx.play("wave_surge", global_position, 2.0, 0.05, 0.7)
		&"flood":
			GameFeel.camera_shake(0.2)
		&"freeze":
			_show_flood(true, true)
			VFX.frost_burst(scene, present_origin(), 6.0)
			Sfx.play("frost_nova", global_position, 2.0, 0.05, 1.2)
		&"flood_end":
			_show_flood(false, false)


## The flood's water (or ice) over the ring, on every machine.
func _show_flood(on: bool, frozen: bool) -> void:
	if not inner.has_area() or not arena_rect.has_area():
		return
	if _flood_planes.is_empty():
		_flood_mat = ShaderMaterial.new()
		_flood_mat.shader = WaterChannel.WATER_SHADER
		_flood_mat.set_shader_parameter(&"deep", ArtKit.color("palettes.cistern.water", Color(0.07, 0.2, 0.24)))
		_ice_mat = EnemyBase.flat_material(Color(0.78, 0.92, 1.0), true, 0.35)
		var y := ZoneBase.ground_under(self, Vector3(arena_rect.get_center().x, global_position.y + 2.0, arena_rect.get_center().y)).y
		for part in DungeonBuilder.subtract(arena_rect, [inner] as Array[Rect2]):
			var plane := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(part.size.x, 0.08, part.size.y)
			plane.mesh = box
			plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			get_tree().current_scene.add_child(plane)
			plane.global_position = Vector3(part.get_center().x, y - 0.3, part.get_center().y)
			plane.set_meta(&"floor_y", y)
			_flood_planes.append(plane)
	for plane in _flood_planes:
		if not is_instance_valid(plane):
			continue
		plane.material_override = _ice_mat if frozen else _flood_mat
		var floor_y := float(plane.get_meta(&"floor_y", 0.0))
		var tw := plane.create_tween()
		tw.tween_property(plane, "global_position:y", floor_y + (0.12 if on else -0.3), FLOOD_RISE if on and not frozen else 0.6)


func _exit_tree() -> void:
	super()
	for plane in _flood_planes:
		if is_instance_valid(plane):
			plane.queue_free()
