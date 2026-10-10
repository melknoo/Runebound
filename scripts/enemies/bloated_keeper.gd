class_name BloatedKeeper
extends DungeonBoss
## M13 the Hollow Cistern's mid-boss: what came up the settling basin's drain
## wearing a keeper's coat. Swollen with the basin's water it shrugs off most
## of every blow while the basin stands full (a cold splash shows it); pull
## both sluice levers and the basin runs dry for a while - laid bare it takes
## full damage and more, and it drags itself slower. It slams a disc ahead,
## stamps out a ring wave every few seconds (dodge through it), and at two
## thirds and one third of its health it calls the drowned up from the
## basin's corners.

const WET_ARMOR := 0.4
const DRY_BONUS := 1.25
const DRY_SLOW := 0.6
const WAVE_EVERY := 9.0
const WAVE_WINDUP := 0.9
const WAVE_SPEED := 6.0
const WAVE_MAX := 9.0
const WAVE_BAND := 0.8
const WAVE_DAMAGE := 14.0
const SUMMON_AT: Array[float] = [0.66, 0.33]

const RIG_PATH := "res://assets/models/chars/bloated_keeper.glb"

var _wave_left: float = WAVE_EVERY * 0.6
var _wave_t: float = -1.0
var _wave_hit: Array[int] = []
var _summons_done: int = 0
var _was_dry: bool = false


func _init() -> void:
	super()
	xp_value = 300
	display_name = "The Bloated Keeper"
	max_health = 950.0
	move_speed = 2.2
	body_color = Color(0.32, 0.4, 0.4)


func _build_body() -> void:
	if _setup_rigged_visual(RIG_PATH, "bloated_keeper", {
		"idle": &"idle", "run": &"run", "run_speed": move_speed,
		"states": {AIState.WINDUP: &"slam", AIState.CIRCLE: &"stomp", AIState.STAGGER: &"stagger",
			AIState.CHASE: &"@loco", AIState.IDLE: &"@loco", AIState.DEAD: &"@dead"},
	}, ArtKit.color("palettes.bloated_keeper.eyes")) != null:
		visual.scale = Vector3.ONE * 1.15
		base_visual_scale = visual.scale
		return
	super()


## The basin's sluices (the BasinDrain in this arena), or null.
func drain() -> BasinDrain:
	var zone := ZoneBase.zone_of(self)
	if not zone is DungeonZone:
		return null
	for key: String in (zone as DungeonZone).puzzles:
		var d := (zone as DungeonZone).puzzles[key] as BasinDrain
		if d != null and (not arena_rect.has_area() or arena_rect.has_point(Vector2(d.global_position.x, d.global_position.z))):
			return d
	return null


func is_dry() -> bool:
	var d := drain()
	return d != null and d.is_dry()


## Wet, most of a blow runs off; dry, it bites deeper (the authority's copy
## judges; every machine shows the splash).
func take_hit(hit: HitInfo) -> bool:
	if hit != null and targetable and ai_state != AIState.DEAD:
		if is_dry():
			if not net_puppet:
				hit.damage *= DRY_BONUS
		else:
			if not net_puppet:
				hit.damage *= WET_ARMOR
			VFX.frost_burst(get_tree().current_scene, global_position + Vector3(0, 1.2, 0), 0.9)
	return super(hit)


func _physics_process(delta: float) -> void:
	super(delta)
	if net_puppet or ai_state == AIState.DEAD:
		return
	var dry := is_dry()
	if dry != _was_dry:
		_was_dry = dry
		play_fx(&"bared" if dry else &"soaked")
	_tick_wave(delta)
	var share := health.current_health / maxf(health.max_health, 1.0)
	if _summons_done < SUMMON_AT.size() and share <= SUMMON_AT[_summons_done]:
		_summons_done += 1
		_summon()


func _ai_process(delta: float) -> void:
	var speed := move_speed * (DRY_SLOW if is_dry() else 1.0)
	_wave_left -= delta  # counts in every state: a slam cycle in melee never starves the wave
	match ai_state:
		AIState.IDLE:
			brake(delta)
			if player != null and distance_to_player() < AGGRO_RANGE * 2.0:
				_enter_state(AIState.CHASE)
		AIState.CHASE:
			face_player(delta, 3.5)
			move_towards(dir_to_player(), speed, delta)
			if _wave_left <= 0.0:
				_wave_left = WAVE_EVERY
				_enter_state(AIState.CIRCLE)  # the stamp's windup
				play_fx(&"stamp")
			elif distance_to_player() <= ATTACK_RANGE:
				lock_strike()
				_enter_state(AIState.WINDUP)
				_present_windup()
		AIState.CIRCLE:
			brake(delta)
			if _state_timer >= WAVE_WINDUP:
				_wave_t = 0.0
				_wave_hit.clear()
				play_fx(&"wave")
				_enter_state(AIState.RECOVER)
		AIState.WINDUP:
			brake(delta)
			if _state_timer >= WINDUP_TIME:
				_enter_state(AIState.RECOVER)
				play_fx(&"slam")
				strike_circle(strike_point(SLAM_AHEAD), SLAM_RADIUS, SLAM_DAMAGE, HitInfo.DamageType.PHYSICAL,
					HitInfo.Weight.HEAVY, 8.0)
		AIState.RECOVER:
			brake(delta)
			if _state_timer >= RECOVER_TIME:
				_enter_state(AIState.CHASE)
		AIState.STAGGER:
			brake(delta)
			if _state_timer >= 0.0:
				_enter_state(AIState.CHASE)


## Authority: the ring runs out from where it stamped; each hero once.
func _tick_wave(delta: float) -> void:
	if _wave_t < 0.0:
		return
	_wave_t += delta
	var r := _wave_t * WAVE_SPEED
	if r > WAVE_MAX:
		_wave_t = -1.0
		return
	var zone := ZoneBase.zone_of(self)
	if zone == null:
		return
	for hero in zone.players:
		if hero == null or not is_instance_valid(hero) or hero.health.is_dead or _wave_hit.has(hero.get_instance_id()):
			continue
		var flat := Vector2(hero.global_position.x - global_position.x, hero.global_position.z - global_position.z)
		if absf(flat.length() - r) <= WAVE_BAND and absf(hero.global_position.y - global_position.y) < 1.5:
			_wave_hit.append(hero.get_instance_id())
			var hit := HitInfo.create(WAVE_DAMAGE, HitInfo.DamageType.FROST, HitInfo.Weight.MEDIUM, global_position)
			hit.knockback = 5.0
			hero.take_hit(hit)


func _summon() -> void:
	var zone := ZoneBase.zone_of(self)
	if zone == null or not arena_rect.has_area():
		return
	play_fx(&"roar")
	var inner := arena_rect.grow(-3.0)
	for corner: Vector2 in [inner.position, inner.end]:
		var add := zone.spawn_by_id("drowned_thrall", zone.ground_point(Vector3(corner.x, global_position.y + 1.0, corner.y), 0.2))
		VFX.frost_burst(get_tree().current_scene, add.global_position, 1.6)


func _present_fx(fx: StringName) -> void:
	var scene := get_tree().current_scene
	match fx:
		&"slam":
			super(fx)
		&"stamp":
			VFX.telegraph_disc(scene, present_origin(), 2.0, WAVE_WINDUP)
			Sfx.play("earthbreaker_windup", global_position, -4.0, 0.1, 0.6)
		&"wave":
			VFX.ground_ring(scene, present_origin(), ArtKit.color("palettes.cistern.water_hi", Color(0.4, 0.8, 0.85)),
				WAVE_MAX, WAVE_MAX / WAVE_SPEED)
			Sfx.play("wave_surge", global_position, -2.0, 0.05, 1.0)
			GameFeel.camera_shake(0.25)
		&"bared":
			VFX.frost_burst(scene, present_origin() + Vector3(0, 1.0, 0), 2.2)
			Sfx.play("deep_roar", global_position, -4.0, 0.1, 1.25)
		&"soaked":
			Sfx.play("water_splash", global_position, -6.0, 0.1, 0.7)
		&"roar":
			Sfx.play("deep_roar", global_position, -2.0, 0.1, 1.0)
