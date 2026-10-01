class_name CarrionVulture
extends EnemyBase
## M12 bone field (the carrion brood): a great bald vulture. It circles high
## over the heroes, out of reach - no target, no hit, only its shadow on the
## ground - until it picks one: its wings go up and a lane on the ground fills
## toward that hero; then it swoops down the lane (whoever is still in it is
## struck) and lands at its end. On the ground it is a target for
## LANDED_TIME - the moment to punish it - then it beats back up into the
## air. Only heavy hits stagger it (that keeps it down a little longer).
## The body never leaves the ground: in the air it only stops colliding (it
## glides over rocks and trunks) and its visual rises to ALTITUDE.

const ALTITUDE := 6.5
const CIRCLE_RADIUS := 7.0
const CIRCLE_TIME := 3.0
const IDLE_RADIUS := 5.0
const AIR_SPEED := 5.5
const DIVE_WINDUP := 1.1
const DIVE_LENGTH := 11.0
const DIVE_WIDTH := 2.4
const DIVE_TIME := 0.45
const DIVE_DAMAGE := 14.0
## It only dives at a hero this far off (room for the lane before and after).
const DIVE_MIN := 4.5
const DIVE_MAX := 9.5
const LANDED_TIME := 2.2
const TAKEOFF_TIME := 0.8
const GROUND_MASK := 0b1000011  # EnemyBase's: world + players + foliage
## The rig is drawn this much larger: a great bird next to the heroes (2.9 m wings).
const SIZE := 1.25

const RIG_PATH := "res://assets/models/chars/carrion_vulture.glb"

var _circle_dir: float = 1.0
var _struck: Array[int] = []
var _lane: MeshInstance3D
var _alt: float = ALTITUDE
var _shadow: Decal


func _init() -> void:
	xp_value = 30
	display_name = Texts.t("enemy.carrion_vulture")
	max_health = 52.0
	move_speed = AIR_SPEED
	body_color = Color(0.46, 0.41, 0.36)
	stagger_resist = true


func _ready() -> void:
	super()
	state_entered.connect(_apply_presence)
	_apply_presence(ai_state)  # in the air from the start (a puppet too)
	_make_shadow()


static func airborne(s: AIState) -> bool:
	return s in [AIState.IDLE, AIState.CHASE, AIState.CIRCLE, AIState.WINDUP, AIState.ATTACK,
		AIState.RETREAT, AIState.RETURN]


## In the air: no target, no hit, no collisions (every machine, from the state).
func _apply_presence(s: AIState) -> void:
	if s == AIState.DEAD:
		return  # the death keeps its own layers; the visual falls (_process)
	var air := airborne(s)
	set_targetable(not air)
	collision_mask = 0 if air else GROUND_MASK


func nameplate_height() -> float:
	return 1.4 * SIZE + _alt


func _build_body() -> void:
	base_visual_scale = Vector3.ONE * SIZE
	visual.scale = base_visual_scale
	if _setup_rigged_visual(RIG_PATH, "carrion_vulture", {
		"idle": &"soar", "run": &"soar", "run_speed": move_speed,
		"states": {AIState.IDLE: &"~soar", AIState.CHASE: &"~soar", AIState.CIRCLE: &"~soar",
			AIState.RETURN: &"~soar", AIState.WINDUP: &"charge", AIState.ATTACK: &"swoop",
			AIState.RECOVER: &"~idle", AIState.RETREAT: &"takeoff", AIState.STAGGER: &"stagger",
			AIState.DEAD: &"@dead"},
	}, ArtKit.color("palettes.carrion_vulture.eyes")) != null:
		return
	var torso := MeshInstance3D.new()  # fallback (and the dedicated server): a body and a wing bar
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.4, 0.15, 0.6)
	mesh.material = flat_material(body_color)
	torso.mesh = mesh
	torso.position = Vector3(0, 0.6, 0)
	visual.add_child(torso)


## The mark on the ground under it: darker and tighter the lower it flies.
func _make_shadow() -> void:
	if not Net.has_view():
		return
	var grad := Gradient.new()
	grad.set_color(0, Color(0.0, 0.0, 0.0, 0.6))
	grad.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 32
	tex.height = 32
	_shadow = Decal.new()
	_shadow.name = "Shadow"
	_shadow.texture_albedo = tex
	_shadow.size = Vector3(2.4, 6.0, 2.4)
	_shadow.position = Vector3(0, 1.0, 0)
	add_child(_shadow)


func _process(delta: float) -> void:
	var want := ALTITUDE if airborne(ai_state) else 0.0
	var rate := 4.0
	match ai_state:
		AIState.ATTACK:
			want = 0.3
			rate = ALTITUDE / DIVE_TIME
		AIState.RETREAT:
			rate = ALTITUDE / TAKEOFF_TIME
		AIState.RECOVER, AIState.STAGGER, AIState.DEAD:
			rate = 20.0
	_alt = move_toward(_alt, want, rate * delta)
	visual.position.y = _alt
	if _shadow != null:
		var low := 1.0 - _alt / ALTITUDE
		_shadow.modulate = Color(1, 1, 1, 0.45 + 0.4 * low)
		_shadow.size = Vector3.ONE * (2.6 - 0.8 * low) + Vector3(0, 3.4, 0)
		_shadow.visible = ai_state != AIState.DEAD


func _physics_process(delta: float) -> void:
	super(delta)
	if not net_puppet and collision_mask == 0 and is_inside_tree():
		# in the air the body glides along the ground (no collisions to stand on)
		var zone := ZoneBase.zone_of(self)
		if zone != null:  # the heightmap where there is one, else the floor under it (labs, halls)
			global_position.y = zone.ground_y(global_position) if zone.terrain != null else zone.ground_point(global_position).y
		velocity.y = 0.0


## Soaring over its home is not straying from it.
func _should_return(delta: float) -> bool:
	if ai_state == AIState.IDLE:
		return global_position.distance_to(home) > leash
	return super(delta)


func _ai_process(delta: float) -> void:
	match ai_state:
		AIState.IDLE:
			var centre := home if home != Vector3.INF else global_position + Vector3(IDLE_RADIUS, 0, 0)
			_fly_ring(centre, IDLE_RADIUS, AIR_SPEED * 0.5, delta)
			if distance_to_player() < AGGRO_RANGE:
				_enter_state(AIState.CHASE)
		AIState.CHASE:
			var dir := dir_to_player()
			_face(dir, delta)
			move_towards(dir, AIR_SPEED, delta)
			if distance_to_player() <= CIRCLE_RADIUS + 1.5:
				_enter_state(AIState.CIRCLE)
				_circle_dir = 1.0 if randf() < 0.5 else -1.0
		AIState.CIRCLE:
			if player == null or not is_instance_valid(player):
				_enter_state(AIState.IDLE)
				return
			_fly_ring(player.global_position, CIRCLE_RADIUS, AIR_SPEED, delta)
			if distance_to_player() > CIRCLE_RADIUS + 6.0:
				_enter_state(AIState.CHASE)
			elif _state_timer >= CIRCLE_TIME:
				if _lane_clear():
					_start_dive()
				else:
					_state_timer = CIRCLE_TIME - 0.6  # circle on, try again
		AIState.WINDUP:
			brake(delta)  # hanging over its lane, facing locked
			if _state_timer >= DIVE_WINDUP:
				_struck.clear()
				_enter_state(AIState.ATTACK)
		AIState.ATTACK:
			var speed := DIVE_LENGTH / DIVE_TIME
			velocity.x = _strike_forward.x * speed
			velocity.z = _strike_forward.z * speed
			_strike_passed(minf(_state_timer, DIVE_TIME) * speed)
			if _state_timer >= DIVE_TIME:
				velocity.x = 0.0
				velocity.z = 0.0
				_enter_state(AIState.RECOVER)
				play_fx(&"land")
		AIState.RECOVER:
			brake(delta)
			if _state_timer >= LANDED_TIME:
				_enter_state(AIState.RETREAT)
				_present_takeoff()
		AIState.RETREAT:
			brake(delta)
			if _state_timer >= TAKEOFF_TIME:
				_enter_state(AIState.CIRCLE)
		AIState.STAGGER:
			brake(delta)
			if _state_timer >= 0.0:
				_enter_state(AIState.RETREAT)
				_present_takeoff()


## Flies a ring of `radius` around `centre` (in the direction it picked), facing where it flies.
func _fly_ring(centre: Vector3, radius: float, speed: float, delta: float) -> void:
	var rel := global_position - centre
	rel.y = 0.0
	if rel.length() < 0.5:
		rel = Vector3(1, 0, 0)
	var out := rel.normalized()
	var tangent := out.cross(Vector3.UP) * _circle_dir
	var dir := (tangent - out * clampf(rel.length() - radius, -1.0, 1.0)).normalized()
	_face(dir, delta)
	move_towards(dir, speed, delta)


func _face(dir: Vector3, delta: float) -> void:
	if dir.length_squared() > 0.001:
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(-dir.x, -dir.z), minf(6.0 * delta, 1.0))


## The lane toward the hero must run over open ground of about one height
## (no wall, no trunk, no drop) - it lands at the far end.
func _lane_clear() -> bool:
	var dist := distance_to_player()
	if dist < DIVE_MIN or dist > DIVE_MAX:
		return false
	var dir := dir_to_player()
	var end := ZoneBase.ground_under(self, global_position + dir * DIVE_LENGTH, 0.0)
	if absf(end.y - global_position.y) > 3.0:
		return false
	var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.0, 0), end + Vector3(0, 1.0, 0),
		0b1 | Grove.FOLIAGE_LAYER)
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()


## Down on the ground as at a dive's end (tests and shots; the AI lands by diving).
func land() -> void:
	_enter_state(AIState.RECOVER)


func _start_dive() -> void:
	var dir := dir_to_player()
	visual.rotation.y = atan2(-dir.x, -dir.z)
	lock_strike()
	_enter_state(AIState.WINDUP)
	_present_windup()


## Strikes every hero the swoop has reached in its lane (each once).
func _strike_passed(travelled: float) -> void:
	var zone := ZoneBase.zone_of(self)
	if zone == null:
		return
	var side := _strike_forward.cross(Vector3.UP)
	for hero in zone.players:
		if not is_instance_valid(hero) or hero.health.is_dead or _struck.has(hero.get_instance_id()):
			continue
		var rel := hero.global_position - _strike_origin
		var along := rel.dot(_strike_forward)
		if along < -0.5 or along > minf(travelled + 0.8, DIVE_LENGTH) or absf(rel.dot(side)) > DIVE_WIDTH * 0.5 + STRIKE_TOLERANCE \
				or absf(rel.y) > STRIKE_HEIGHT:
			continue
		_struck.append(hero.get_instance_id())
		var hit := HitInfo.create(DIVE_DAMAGE, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.MEDIUM, global_position)
		hit.knockback = 3.0
		hit.area_center = _strike_origin + _strike_forward * clampf(along, 0.0, DIVE_LENGTH)
		hit.area_radius = DIVE_WIDTH * 0.5 + STRIKE_TOLERANCE
		hit.source_id = get_instance_id()
		hero.take_hit(hit)
		VFX.melee_impact(get_tree().current_scene, hero.global_position + Vector3(0, 1.0, 0), _strike_forward)


func _present_state(s: AIState) -> void:
	super(s)
	match s:
		AIState.WINDUP:
			_present_windup()
		AIState.RETREAT:
			_present_takeoff()


func _present_windup() -> void:
	_lane = VFX.telegraph_lane(get_tree().current_scene, present_origin(), present_forward(), DIVE_LENGTH,
		DIVE_WIDTH, DIVE_WINDUP)
	Sfx.play("vulture_screech", global_position + Vector3(0, ALTITUDE, 0), -2.0, 0.08)


func _present_takeoff() -> void:
	VFX.dodge_dust(get_tree().current_scene, present_origin(), Vector3.UP)
	Sfx.play("wing_beat", global_position, -4.0, 0.1, 0.8)


func _present_fx(fx: StringName) -> void:
	if fx == &"land":
		var scene := get_tree().current_scene
		VFX.dodge_dust(scene, present_origin(), present_forward())
		VFX.ground_ring(scene, present_origin(), ArtKit.color("palettes.carrion_vulture.ruff.1", Color("#D0C7B6")), 2.0, 0.3)
		Sfx.play("wing_beat", global_position, -6.0, 0.1, 0.6)


func _on_interrupted() -> void:
	if _lane != null and is_instance_valid(_lane):
		_lane.queue_free()
