class_name Galebinder
extends DungeonBoss
## M13b the Stormwatch's second mid-boss (the gale hall): the Circle's
## weather-keeper, carried on the wind he bound. He keeps his distance and
## throws blades of wind down a lane at whoever holds his attention (a lane
## marks it; it throws a hero back); every few seconds he gathers a gust
## and blows everyone near him away (a ring grows on the floor first); at
## three quarters, half and a quarter of his health a wave of gale wraiths
## comes - one for every hero.

const KEEP_MIN := 7.0
const KEEP_MAX := 11.0
const BLADE_EVERY := 2.6
const BLADE_WINDUP := 0.8
const BLADE_LENGTH := 13.0
const BLADE_HALF_WIDTH := 0.9
const BLADE_DAMAGE := 15.0
const GUST_EVERY := 15.0
const GUST_WINDUP := 1.1
const GUST_RADIUS := 7.0
const GUST_DAMAGE := 6.0
const GUST_PUSH := 14.0
const WAVES: Array[float] = [0.75, 0.5, 0.25]
const GALE_RECOVER := 0.8

const RIG_PATH := "res://assets/models/chars/galebinder.glb"

var _blade_left: float = 1.5
var _gust_left: float = GUST_EVERY * 0.6
var _waves_done: int = 0
## Tests: wraiths called so far.
var wraiths_called: int = 0


func _init() -> void:
	super()
	xp_value = 450
	display_name = "The Galebinder"
	max_health = 950.0
	move_speed = 2.9
	body_color = Color(0.4, 0.42, 0.55)


func _build_body() -> void:
	if _setup_rigged_visual(RIG_PATH, "galebinder", {
		"idle": &"idle", "run": &"glide", "run_speed": move_speed,
		"states": {AIState.WINDUP: &"charge", AIState.RECOVER: &"cast", AIState.CIRCLE: &"gust", AIState.STAGGER: &"stagger",
			AIState.CHASE: &"@loco", AIState.IDLE: &"@loco", AIState.RETREAT: &"@loco", AIState.DEAD: &"@dead"},
	}, ArtKit.color("palettes.galebinder.glow")) != null:
		visual.scale = Vector3.ONE * 1.1
		base_visual_scale = visual.scale
		return
	super()


func party_count() -> int:
	var zone := ZoneBase.zone_of(self)
	return maxi(zone.party_size(), 1) if zone != null else 1


func _physics_process(delta: float) -> void:
	super(delta)
	if net_puppet or ai_state == AIState.DEAD:
		return
	while _waves_done < WAVES.size() and health.current_health <= health.max_health * WAVES[_waves_done]:
		_waves_done += 1
		_call_wraiths()


func _ai_process(delta: float) -> void:
	_blade_left -= delta  # both count in every state
	_gust_left -= delta
	match ai_state:
		AIState.IDLE:
			brake(delta)
			if player != null and distance_to_player() < AGGRO_RANGE * 2.0:
				_enter_state(AIState.CHASE)
		AIState.CHASE, AIState.RETREAT:
			face_player(delta, 5.0)
			var dist := distance_to_player()
			if dist < KEEP_MIN:
				move_towards(-dir_to_player(), move_speed, delta)
			elif dist > KEEP_MAX:
				move_towards(dir_to_player(), move_speed, delta)
			else:
				brake(delta)
			if _gust_left <= 0.0 and _heroes_near(GUST_RADIUS) > 0:
				_gust_left = GUST_EVERY
				lock_strike()
				_enter_state(AIState.CIRCLE)
				play_fx(&"gust_tell")
			elif _blade_left <= 0.0 and player != null and is_instance_valid(player):
				_blade_left = BLADE_EVERY
				lock_strike()
				_enter_state(AIState.WINDUP)
				play_fx(&"blade_tell")
		AIState.WINDUP:
			brake(delta)
			if _state_timer >= BLADE_WINDUP:
				play_fx(&"blade")
				strike_lane(_strike_origin, _strike_forward, BLADE_LENGTH, BLADE_HALF_WIDTH, BLADE_DAMAGE,
					HitInfo.DamageType.PHYSICAL, HitInfo.Weight.HEAVY, 9.0)
				_enter_state(AIState.RECOVER)
		AIState.CIRCLE:  # gathering the gust
			brake(delta)
			if _state_timer >= GUST_WINDUP:
				play_fx(&"gust")
				strike_circle(_strike_origin, GUST_RADIUS, GUST_DAMAGE, HitInfo.DamageType.PHYSICAL,
					HitInfo.Weight.HEAVY, GUST_PUSH)
				_enter_state(AIState.RECOVER)
		AIState.RECOVER:
			brake(delta)
			if _state_timer >= GALE_RECOVER:
				_enter_state(AIState.CHASE)
		AIState.STAGGER:
			brake(delta)
			if _state_timer >= 0.0:
				_enter_state(AIState.CHASE)


func _heroes_near(radius: float) -> int:
	return heroes_in_circle(global_position, radius).size()


## Authority: a wave of wraiths at the hall's edges, one for every hero.
func _call_wraiths() -> void:
	var zone := ZoneBase.zone_of(self)
	if zone == null or not arena_rect.has_area():
		return
	play_fx(&"call")
	var inner := arena_rect.grow(-3.0)
	var count := clampi(party_count(), 1, 5)
	for i in count:
		var a := TAU * float(i) / float(count) + float(_waves_done)
		var at := Vector2(inner.get_center().x + cos(a) * inner.size.x * 0.45, inner.get_center().y + sin(a) * inner.size.y * 0.45)
		var add := zone.spawn_by_id("gale_wraith", zone.ground_point(Vector3(at.x, global_position.y + 1.0, at.y), 0.2))
		VFX.flash(get_tree().current_scene, add.global_position + Vector3(0, 1.0, 0), Color(0.85, 0.88, 1.0), 1.0, 0.2)
		wraiths_called += 1


func _present_windup() -> void:
	pass  # the blade's lane comes with its fx (its windup is no slam)


func _present_fx(fx: StringName) -> void:
	var scene := get_tree().current_scene
	match fx:
		&"blade_tell":
			_telegraph_disc = VFX.telegraph_lane(scene, present_origin(), present_forward(), BLADE_LENGTH,
				BLADE_HALF_WIDTH * 2.0, BLADE_WINDUP)
			Sfx.play("gale_gust", global_position, -10.0, 0.1, 1.3)
		&"blade":
			Sfx.play("gale_gust", global_position, -3.0, 0.1, 1.6)
		&"gust_tell":
			_telegraph_disc = VFX.telegraph_disc(scene, present_origin(), GUST_RADIUS, GUST_WINDUP)
			Sfx.play("gale_gust", global_position, -8.0, 0.05, 0.6)
		&"gust":
			VFX.ground_ring(scene, present_origin(), Color(0.85, 0.88, 1.0), GUST_RADIUS, 0.4)
			Sfx.play("gale_gust", global_position, 0.0, 0.05, 0.8)
			GameFeel.camera_shake(0.2)
		&"call":
			Sfx.play("wraith_shriek", global_position, -2.0, 0.1, 0.7)
