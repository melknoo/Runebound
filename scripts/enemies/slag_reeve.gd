class_name SlagReeve
extends DungeonBoss
## M13 the Ember Warrens' mid-boss: the smelting hall's old reeve, grown
## into the slag of his own furnaces. Hot, his crust turns most of every
## blow (a spark shows it). Two quench troughs stand in the hall: pull a
## trough's chain while he stands beside it and the water bursts over him -
## the crust cracks and goes dark for a while: he takes full damage and
## more, and drags himself slower, until the heat comes back. He slams his
## ladle-hammer down ahead, spews slag in a fan (burning ground) every few
## seconds, and at half health calls two kiln imps out of the furnaces.

const HOT_ARMOR := 0.4
const COOLED_BONUS := 1.3
const COOLED_SLOW := 0.7
const COOL_TIME := 14.0
const QUENCH_RADIUS := 6.0
const SPEW_EVERY := 12.0
const SPEW_WINDUP := 0.9
const SPEW_LUMPS := 3
const SPEW_SPREAD := 0.45
const SPEW_DIST := 6.0
const SUMMON_AT := 0.5
## His hammer: slower to recover than the placeholder's slam (the opening).
const HAMMER_DAMAGE := 20.0
const HAMMER_RECOVER := 1.9

const RIG_PATH := "res://assets/models/chars/slag_reeve.glb"

## Authority: seconds of cooled crust left (> 0: laid bare).
var cooled_left: float = 0.0
var _spew_left: float = SPEW_EVERY * 0.6
var _summoned: bool = false
var _was_cooled: bool = false


func _init() -> void:
	super()
	xp_value = 400
	display_name = "The Slag Reeve"
	max_health = 800.0
	move_speed = 2.3
	body_color = Color(0.25, 0.2, 0.17)


func _build_body() -> void:
	if _setup_rigged_visual(RIG_PATH, "slag_reeve", {
		"idle": &"idle", "run": &"run", "run_speed": move_speed,
		"states": {AIState.WINDUP: &"slam", AIState.CIRCLE: &"spew", AIState.STAGGER: &"stagger",
			AIState.CHASE: &"@loco", AIState.IDLE: &"@loco", AIState.DEAD: &"@dead"},
	}, ArtKit.color("palettes.slag_reeve.glow")) != null:
		visual.scale = Vector3.ONE * 1.2
		base_visual_scale = visual.scale
		return
	super()


## Is the crust cracked right now? (A puppet learns it from the fx.)
func is_cooled() -> bool:
	return cooled_left > 0.0


## Authority (a QuenchTrough's chain): the water bursts over him if he
## stands beside the trough at `at`. Returns whether it cooled him.
func quench(at: Vector3) -> bool:
	if ai_state == AIState.DEAD:
		return false
	var flat := global_position - at
	flat.y = 0.0
	if flat.length() > QUENCH_RADIUS:
		return false
	cooled_left = COOL_TIME
	return true


## Hot, most of a blow glances off; cooled, it bites deeper (the
## authority's copy judges; every machine shows the spark).
func take_hit(hit: HitInfo) -> bool:
	if hit != null and targetable and ai_state != AIState.DEAD:
		if is_cooled():
			if not net_puppet:
				hit.damage *= COOLED_BONUS
		else:
			if not net_puppet:
				hit.damage *= HOT_ARMOR
			VFX.flash(get_tree().current_scene, global_position + Vector3(0, 1.6, 0), Color(1.0, 0.6, 0.25), 0.7, 0.1)
	return super(hit)


func _physics_process(delta: float) -> void:
	super(delta)
	if net_puppet or ai_state == AIState.DEAD:
		return
	cooled_left = maxf(cooled_left - delta, 0.0)
	var cooled := is_cooled()
	if cooled != _was_cooled:
		_was_cooled = cooled
		play_fx(&"quenched" if cooled else &"reheat")
	if not _summoned and health.current_health <= health.max_health * SUMMON_AT:
		_summoned = true
		_summon()


func _ai_process(delta: float) -> void:
	var speed := move_speed * (COOLED_SLOW if is_cooled() else 1.0)
	_spew_left -= delta  # counts in every state: a slam cycle in melee never starves the spew
	match ai_state:
		AIState.IDLE:
			brake(delta)
			if player != null and distance_to_player() < AGGRO_RANGE * 2.0:
				_enter_state(AIState.CHASE)
		AIState.CHASE:
			face_player(delta, 3.5)
			move_towards(dir_to_player(), speed, delta)
			if _spew_left <= 0.0 and player != null and is_instance_valid(player):
				_spew_left = SPEW_EVERY
				lock_strike()
				_enter_state(AIState.CIRCLE)  # the spew's windup
				play_fx(&"spew_tell")
			elif distance_to_player() <= ATTACK_RANGE:
				lock_strike()
				_enter_state(AIState.WINDUP)
				_present_windup()
		AIState.CIRCLE:
			brake(delta)
			if _state_timer >= SPEW_WINDUP:
				_spew()
				_enter_state(AIState.RECOVER)
		AIState.WINDUP:
			brake(delta)
			if _state_timer >= WINDUP_TIME:
				_enter_state(AIState.RECOVER)
				play_fx(&"slam")
				strike_circle(strike_point(SLAM_AHEAD), SLAM_RADIUS, HAMMER_DAMAGE, HitInfo.DamageType.FIRE,
					HitInfo.Weight.HEAVY, 8.0)
		AIState.RECOVER:
			brake(delta)
			if _state_timer >= HAMMER_RECOVER:
				_enter_state(AIState.CHASE)
		AIState.STAGGER:
			brake(delta)
			if _state_timer >= 0.0:
				_enter_state(AIState.CHASE)


## Authority: a fan of slag lumps ahead (each leaves burning ground).
func _spew() -> void:
	play_fx(&"spew")
	for k in SPEW_LUMPS:
		var a := (float(k) - float(SPEW_LUMPS - 1) * 0.5) * SPEW_SPREAD
		var lump := EmberLump.new()
		lump.from = global_position + Vector3(0, 2.0, 0)
		lump.target = _strike_origin + _strike_forward.rotated(Vector3.UP, a) * SPEW_DIST
		get_tree().current_scene.add_child(lump)


func _summon() -> void:
	var zone := ZoneBase.zone_of(self)
	if zone == null or not arena_rect.has_area():
		return
	play_fx(&"roar")
	var inner := arena_rect.grow(-3.0)
	for corner: Vector2 in [Vector2(inner.position.x, inner.end.y), Vector2(inner.end.x, inner.position.y)]:
		var add := zone.spawn_by_id("kiln_imp", zone.ground_point(Vector3(corner.x, global_position.y + 1.0, corner.y), 0.2))
		VFX.ember_impact(get_tree().current_scene, add.global_position + Vector3(0, 0.4, 0))


func _present_fx(fx: StringName) -> void:
	var scene := get_tree().current_scene
	match fx:
		&"slam":
			var at := present_origin() + present_forward() * SLAM_AHEAD
			VFX.earthbreaker_slam(scene, at, SLAM_RADIUS)
			VFX.ember_impact(scene, at + Vector3(0, 0.3, 0))
			Sfx.play("earthbreaker_impact", at, -3.0, 0.1, 0.75)
			GameFeel.camera_shake(0.3)
		&"spew_tell":
			VFX.flash(scene, present_origin() + Vector3(0, 2.2, 0) + present_forward() * 0.6,
				ArtKit.color("palettes.warrens.lava_hi", Color(1.0, 0.69, 0.25)), 1.2, SPEW_WINDUP)
			Sfx.play("caster_charge", global_position, -3.0, 0.1, 0.6)
		&"spew":
			Sfx.play("ember_cast", global_position, -2.0, 0.1, 0.7)
		&"quenched":
			if net_puppet:
				cooled_left = COOL_TIME  # the puppet's spark follows the server's crust
			VFX.frost_burst(scene, present_origin() + Vector3(0, 1.4, 0), 2.6)
			Sfx.play("steam_hiss", global_position, 0.0, 0.05, 0.9)
			Sfx.play("deep_roar", global_position, -6.0, 0.1, 1.4)
		&"reheat":
			if net_puppet:
				cooled_left = 0.0
			VFX.ember_impact(scene, present_origin() + Vector3(0, 1.2, 0))
			Sfx.play("ember_cast", global_position, -4.0, 0.1, 0.6)
		&"roar":
			Sfx.play("boss_roar", global_position, -2.0, 0.1, 0.8)
