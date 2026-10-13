class_name Stormsworn
extends DungeonBoss
## M13b the Stormwatch's first mid-boss (the hall of the Sworn): the
## Circle's oathbound guardian, still standing her watch, her halberd
## charged. A tank's test: she brings her halberd down three times in a row
## on whoever holds her attention (a disc ahead each time - block, parry or
## step out); every few seconds she calls the dome's lightning on heroes of
## the party (one for every two), and each bolt leaps from hero to hero
## standing within 5 m - spread out. At half health her acolytes come (one
## fewer than the heroes).

const STRIKE_AHEAD := 2.2
const STRIKE_RADIUS := 2.4
const STRIKE_WINDUP := 0.6
const STRIKE_DAMAGE := 18.0
const COMBO := 3
const COMBO_RECOVER := 1.8
const CHAIN_EVERY := 13.0
const CALL_TIME := 0.7
const BOLT_RADIUS := 1.4
const BOLT_DELAY := 1.1
const BOLT_DAMAGE := 14.0
const LEAP_RANGE := 5.0
const LEAP_DAMAGE := 12.0
const SUMMON_AT := 0.5

const RIG_PATH := "res://assets/models/chars/stormsworn.glb"

var _combo_left: int = 0
var _chain_left: float = CHAIN_EVERY * 0.5
var _summoned: bool = false
## Tests: the bolts of her last call and how many acolytes she called.
var last_bolts: Array[StormStrike] = []
var acolytes_called: int = 0


func _init() -> void:
	super()
	xp_value = 450
	display_name = "The Stormsworn"
	max_health = 1100.0
	move_speed = 2.7
	body_color = Color(0.3, 0.3, 0.38)


func _build_body() -> void:
	if _setup_rigged_visual(RIG_PATH, "stormsworn", {
		"idle": &"idle", "run": &"run", "run_speed": move_speed,
		"states": {AIState.WINDUP: &"strike", AIState.CIRCLE: &"call", AIState.STAGGER: &"stagger",
			AIState.CHASE: &"@loco", AIState.IDLE: &"@loco", AIState.DEAD: &"@dead"},
	}, ArtKit.color("palettes.stormsworn.glow")) != null:
		visual.scale = Vector3.ONE * 1.15
		base_visual_scale = visual.scale
		return
	super()


## How many heroes fight her (the mechanics grow with the party).
func party_count() -> int:
	var zone := ZoneBase.zone_of(self)
	return maxi(zone.party_size(), 1) if zone != null else 1


func _physics_process(delta: float) -> void:
	super(delta)
	if net_puppet or ai_state == AIState.DEAD:
		return
	if not _summoned and health.current_health <= health.max_health * SUMMON_AT:
		_summoned = true
		_summon()


func _ai_process(delta: float) -> void:
	_chain_left -= delta  # counts in every state: a combo never starves the call
	match ai_state:
		AIState.IDLE:
			brake(delta)
			if player != null and distance_to_player() < AGGRO_RANGE * 2.0:
				_enter_state(AIState.CHASE)
		AIState.CHASE:
			face_player(delta, 4.0)
			if _chain_left <= 0.0:
				_chain_left = CHAIN_EVERY
				lock_strike()
				_enter_state(AIState.CIRCLE)
				play_fx(&"call")
			elif distance_to_player() <= STRIKE_AHEAD + STRIKE_RADIUS * 0.6:
				_combo_left = COMBO
				lock_strike()
				_enter_state(AIState.WINDUP)
			else:
				move_towards(dir_to_player(), move_speed, delta)
		AIState.WINDUP:
			brake(delta)
			if _state_timer >= STRIKE_WINDUP:
				play_fx(&"strike")
				strike_circle(strike_point(STRIKE_AHEAD), STRIKE_RADIUS, STRIKE_DAMAGE, HitInfo.DamageType.LIGHTNING,
					HitInfo.Weight.HEAVY, 5.0)
				_combo_left -= 1
				if _combo_left > 0:
					face_player(1.0, 30.0)  # turns to her mark again between blows
					lock_strike()
					_enter_state(AIState.WINDUP)
				else:
					_enter_state(AIState.RECOVER)
		AIState.CIRCLE:  # calling the dome's lightning
			brake(delta)
			if _state_timer >= CALL_TIME:
				_call_lightning()
				_enter_state(AIState.CHASE)
		AIState.RECOVER:
			brake(delta)
			if _state_timer >= COMBO_RECOVER:
				_enter_state(AIState.CHASE)
		AIState.STAGGER:
			brake(delta)
			if _state_timer >= 0.0:
				_enter_state(AIState.CHASE)


## Authority: a bolt on one hero of every two (at least one, at most three),
## each leaping on to whoever stands within 5 m of a struck hero.
func _call_lightning() -> void:
	var zone := ZoneBase.zone_of(self)
	if zone == null:
		return
	var marks: Array[Player] = []
	for h in zone.party():
		if not h.health.is_dead and (not arena_rect.has_area()
				or arena_rect.grow(2.0).has_point(Vector2(h.global_position.x, h.global_position.z))):
			marks.append(h)
	marks.shuffle()
	var count := clampi(ceili(party_count() / 2.0), 1, 3)
	last_bolts.clear()
	for i in mini(count, marks.size()):
		last_bolts.append(StormStrike.cast(self, marks[i].global_position, BOLT_RADIUS, BOLT_DELAY, BOLT_DAMAGE,
			LEAP_RANGE, LEAP_DAMAGE, -1, get_instance_id()))


## Authority: her acolytes from the hall's corners, one fewer than the heroes.
func _summon() -> void:
	var zone := ZoneBase.zone_of(self)
	if zone == null or not arena_rect.has_area():
		return
	play_fx(&"roar")
	var inner := arena_rect.grow(-3.0)
	var corners: Array[Vector2] = [inner.position, Vector2(inner.end.x, inner.position.y), inner.end,
		Vector2(inner.position.x, inner.end.y)]
	var count := clampi(party_count() - 1, 1, 4)
	for i in count:
		var c := corners[i % corners.size()]
		var add := zone.spawn_by_id("storm_acolyte", zone.ground_point(Vector3(c.x, global_position.y + 1.0, c.y), 0.2))
		VFX.flash(get_tree().current_scene, add.global_position + Vector3(0, 1.0, 0), Color(0.78, 0.7, 1.0), 1.2, 0.2)
		acolytes_called += 1


func _present_state(s: AIState) -> void:
	super(s)


func _present_windup() -> void:
	_telegraph_disc = VFX.telegraph_disc(get_tree().current_scene, present_origin() + present_forward() * STRIKE_AHEAD,
		STRIKE_RADIUS, STRIKE_WINDUP)
	Sfx.play("caster_charge", global_position, -5.0, 0.1, 0.8)


func _present_fx(fx: StringName) -> void:
	var scene := get_tree().current_scene
	match fx:
		&"strike":
			var at := present_origin() + present_forward() * STRIKE_AHEAD
			VFX.lightning_arc(scene, at + Vector3(0, 3.0, 0), at, Color(0.85, 0.8, 1.0))
			VFX.ground_ring(scene, at, Color(0.78, 0.7, 1.0), STRIKE_RADIUS, 0.25)
			Sfx.play("storm_bolt", at, -4.0, 0.1, 1.2)
			GameFeel.camera_shake(0.18)
		&"call":
			VFX.flash(scene, present_origin() + Vector3(0, 3.4, 0), Color(0.85, 0.8, 1.0), 1.6, CALL_TIME)
			Sfx.play("coil_charge", global_position, -2.0, 0.05, 0.8)
		&"roar":
			Sfx.play("boss_roar", global_position, -2.0, 0.1, 1.1)
