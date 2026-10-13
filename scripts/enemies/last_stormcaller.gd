class_name LastStormcaller
extends DungeonBoss
## M13b the Stormwatch's end boss (the heart of the storm): the last
## stormcaller, worn by the storm he bound like a coat. Three phases:
##   1  heavy blows of his staff on whoever holds his attention (a disc),
##      and static pulses through the whole hall every few seconds (a ring
##      first) - the tank takes the blows, the healer the pulses
##   2  below 60 % he gathers the thunder (11 s, the grounding coils glow):
##      only a chain of heroes from one coil to the other (each within a
##      link - the coils' distance split by the party, so all but one hero
##      have to stand in it) drains it to the ground - he reels, open to
##      every blow; otherwise the thunderclap strikes the whole hall
##   3  below 30 % his acolytes and a sentinel come, the pulses quicken.
## The coils are the arena's `grounds` (DungeonBuilder builds them); every
## machine draws the chain while he gathers, the authority judges it.

const BLOW_AHEAD := 2.4
const BLOW_RADIUS := 3.0
const BLOW_WINDUP := 1.0
const BLOW_DAMAGE := 34.0
const BLOW_RECOVER := 1.4
const PULSE_EVERY := 9.0
const PULSE_EVERY_LATE := 6.0
const PULSE_WINDUP := 1.2
const PULSE_DAMAGE := 14.0
const CLAP_AT := 0.6
const CLAP_EVERY := 32.0
const CLAP_CHARGE := 11.0
const CLAP_DAMAGE := 60.0
## His mark keeps away: a bolt on it now and then (leaping once within 4 m).
const FAR_BOLT_MIN := 8.0
const FAR_BOLT_EVERY := 4.0
const FAR_BOLT_DAMAGE := 22.0
const GROUND_HOLD := 1.5
const GROUNDED_STUN := 4.0
const GROUNDED_BONUS := 1.5
const ADDS_AT := 0.3
## A link of the chain: the coils' distance split by the party, a little slack.
const LINK_SLACK := 1.06

const RIG_PATH := "res://assets/models/chars/last_stormcaller.glb"

## The grounding coils (the arena's `grounds`).
var grounds: Array[Vector3] = []
var phase: int = 1
## Authority: seconds of the thunder still gathering (> 0: charging).
var clap_left: float = 0.0
## Seconds he still reels after a grounded clap (authority).
var grounded_left: float = 0.0
var _clap_cd: float = 0.0
var _far_bolt_left: float = FAR_BOLT_EVERY
var _pulse_left: float = PULSE_EVERY * 0.7
var _ground_held: float = 0.0
var _adds_called: bool = false
## Every machine: the gathering's end on this machine's clock (the chain's look, bots' places).
var _charge_until: float = -1.0
var _arc_left: float = 0.0
## Tests: claps that struck and that went to ground.
var claps: int = 0
var grounded_claps: int = 0


func _init() -> void:
	super()
	xp_value = 900
	display_name = "The Last Stormcaller"
	max_health = 4800.0
	move_speed = 2.5
	body_color = Color(0.34, 0.33, 0.45)


func _build_body() -> void:
	if _setup_rigged_visual(RIG_PATH, "last_stormcaller", {
		"idle": &"idle", "run": &"glide", "run_speed": move_speed,
		"states": {AIState.WINDUP: &"charge", AIState.RECOVER: &"cast", AIState.CIRCLE: &"gust",
			AIState.ATTACK: &"charge", AIState.STAGGER: &"stagger",
			AIState.CHASE: &"@loco", AIState.IDLE: &"@loco", AIState.DEAD: &"@dead"},
	}, ArtKit.color("palettes.last_stormcaller.glow")) != null:
		visual.scale = Vector3.ONE * 1.25
		base_visual_scale = visual.scale
		return
	super()


func setup_from_poi(poi: Dictionary) -> void:
	grounds.clear()
	for g: Array in poi.get("grounds", []):
		grounds.append(Vector3(float(g[0]), float(poi.get("y", 0.0)), float(g[1])))  # the arena's floor (not in the tree yet)


func party_count() -> int:
	var zone := ZoneBase.zone_of(self)
	return maxi(zone.party_size(), 1) if zone != null else 1


## A link of the chain between the coils for the party there is now.
func link_length() -> float:
	if grounds.size() < 2:
		return 0.0
	return grounds[0].distance_to(grounds[1]) / float(maxi(party_count(), 2)) * LINK_SLACK


func is_gathering() -> bool:
	return Time.get_ticks_msec() / 1000.0 < _charge_until


## M13b bots: while he gathers, the places of the chain between the coils
## (as many as the party has heroes besides the one holding him).
func bot_stations(leader: Player) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not is_gathering() or grounds.size() < 2 or leader == null:
		return out
	var k := maxi(party_count() - 1, 1)
	for i in k:
		out.append({"pos": grounds[0].lerp(grounds[1], float(i + 1) / float(k + 1)), "pull": -1})
	return out


func take_hit(hit: HitInfo) -> bool:
	if hit != null and grounded_left > 0.0 and not net_puppet and ai_state != AIState.DEAD:
		hit.damage *= GROUNDED_BONUS
	return super(hit)


func _physics_process(delta: float) -> void:
	super(delta)
	if net_puppet or ai_state == AIState.DEAD:
		return
	var frac := health.current_health / maxf(health.max_health, 1.0)
	if phase == 1 and frac <= CLAP_AT:
		phase = 2
		_clap_cd = 3.0
	if phase == 2 and frac <= ADDS_AT:
		phase = 3
	if phase == 3 and not _adds_called:
		_adds_called = true
		_call_adds()
	grounded_left = maxf(grounded_left - delta, 0.0)


func _process(delta: float) -> void:
	if not is_gathering() or not Net.has_view() or grounds.size() < 2:
		return
	_arc_left -= delta
	if _arc_left > 0.0:
		return
	_arc_left = 0.18
	var zone := ZoneBase.zone_of(self)
	if zone == null:
		return
	var t := ChainPuzzle.trace(zone.party(), grounds[0], grounds[1], link_length())
	var parent: Dictionary = t["parent"]
	var lift := Vector3(0, 1.2, 0)
	for h: Player in t["connected"]:
		var by: Variant = parent.get(h.get_instance_id())
		var from := grounds[0] + Vector3(0, 2.6, 0) if by == null or not is_instance_valid(by) else (by as Player).global_position + lift
		VFX.lightning_arc(get_tree().current_scene, from, h.global_position + lift, Color(0.85, 0.8, 1.0))
	if bool(t["closed"]):
		var chain: Array = t["chain"]
		if not chain.is_empty() and is_instance_valid(chain.back()):
			VFX.lightning_arc(get_tree().current_scene, (chain.back() as Player).global_position + lift,
				grounds[1] + Vector3(0, 2.6, 0), Color(1.0, 0.97, 0.85))


func _ai_process(delta: float) -> void:
	if clap_left <= 0.0:
		_pulse_left -= delta  # the pulses rest while he gathers the thunder
	_clap_cd -= delta
	_far_bolt_left -= delta
	if ai_state == AIState.CHASE and _far_bolt_left <= 0.0 and player != null and is_instance_valid(player) \
			and distance_to_player() > FAR_BOLT_MIN:
		_far_bolt_left = FAR_BOLT_EVERY
		play_fx(&"far_bolt")
		StormStrike.cast(self, player.global_position, 1.6, 0.9, FAR_BOLT_DAMAGE, 4.0, 12.0, 1, get_instance_id())
	match ai_state:
		AIState.IDLE:
			brake(delta)
			if player != null and distance_to_player() < AGGRO_RANGE * 2.0:
				_enter_state(AIState.CHASE)
		AIState.CHASE:
			face_player(delta, 3.5)
			if phase >= 2 and _clap_cd <= 0.0 and grounds.size() >= 2:
				_clap_cd = CLAP_EVERY
				clap_left = CLAP_CHARGE
				_ground_held = 0.0
				lock_strike()
				_enter_state(AIState.ATTACK)
				play_fx(&"clap_charge")
			elif _pulse_left <= 0.0:
				_pulse_left = PULSE_EVERY_LATE if phase >= 3 else PULSE_EVERY
				lock_strike()
				_enter_state(AIState.CIRCLE)
				play_fx(&"pulse_tell")
			elif distance_to_player() <= BLOW_AHEAD + BLOW_RADIUS * 0.6:
				lock_strike()
				_enter_state(AIState.WINDUP)
			else:
				move_towards(dir_to_player(), move_speed, delta)
		AIState.WINDUP:
			brake(delta)
			if _state_timer >= BLOW_WINDUP:
				play_fx(&"blow")
				strike_circle(strike_point(BLOW_AHEAD), BLOW_RADIUS, BLOW_DAMAGE, HitInfo.DamageType.LIGHTNING,
					HitInfo.Weight.HEAVY, 7.0)
				_enter_state(AIState.RECOVER)
		AIState.CIRCLE:  # a static pulse through the hall
			brake(delta)
			if _state_timer >= PULSE_WINDUP:
				play_fx(&"pulse")
				_hit_hall(PULSE_DAMAGE, 0.0)
				_enter_state(AIState.RECOVER)
		AIState.ATTACK:  # gathering the thunder
			brake(delta)
			clap_left -= delta
			if _chain_closed():
				_ground_held += delta
				if _ground_held >= GROUND_HOLD:
					clap_left = 0.0
					grounded_claps += 1
					grounded_left = GROUNDED_STUN
					play_fx(&"grounded")
					_enter_state(AIState.RECOVER)
					return
			else:
				_ground_held = 0.0
			if clap_left <= 0.0:
				clap_left = 0.0
				claps += 1
				play_fx(&"clap")
				_hit_hall(CLAP_DAMAGE, 9.0)
				_enter_state(AIState.RECOVER)
		AIState.RECOVER:
			brake(delta)
			if _state_timer >= BLOW_RECOVER and grounded_left <= 0.0:
				_enter_state(AIState.CHASE)
		AIState.STAGGER:
			brake(delta)
			if _state_timer >= 0.0:
				_enter_state(AIState.CHASE)


## Authority: is the chain of heroes from coil to coil closed right now?
func _chain_closed() -> bool:
	var zone := ZoneBase.zone_of(self)
	if zone == null or grounds.size() < 2:
		return false
	return bool(ChainPuzzle.trace(zone.party(), grounds[0], grounds[1], link_length())["closed"])


## Authority: every living hero in his hall takes it.
func _hit_hall(damage: float, knockback: float) -> void:
	var zone := ZoneBase.zone_of(self)
	if zone == null:
		return
	for hero in zone.party():
		if hero.health.is_dead:
			continue
		var p := Vector2(hero.global_position.x, hero.global_position.z)
		if arena_rect.has_area() and not arena_rect.grow(1.0).has_point(p):
			continue
		var hit := HitInfo.create(damage, HitInfo.DamageType.LIGHTNING, HitInfo.Weight.HEAVY, global_position)
		hit.knockback = knockback
		hit.area_center = hero.global_position
		hit.area_radius = 2.0
		hit.source_id = get_instance_id()
		hero.take_hit(hit)


## Authority: his acolytes (one fewer than the heroes) and a sentinel.
func _call_adds() -> void:
	var zone := ZoneBase.zone_of(self)
	if zone == null or not arena_rect.has_area():
		return
	play_fx(&"roar")
	var inner := arena_rect.grow(-3.0)
	var corners: Array[Vector2] = [inner.position, Vector2(inner.end.x, inner.position.y), inner.end,
		Vector2(inner.position.x, inner.end.y)]
	var ids: Array[String] = ["coil_sentinel"]
	for i in clampi(party_count() - 1, 1, 4):
		ids.append("storm_acolyte")
	for i in ids.size():
		var c := corners[i % corners.size()]
		var add := zone.spawn_by_id(ids[i], zone.ground_point(Vector3(c.x, global_position.y + 1.0, c.y), 0.2))
		VFX.flash(get_tree().current_scene, add.global_position + Vector3(0, 1.0, 0), Color(0.78, 0.7, 1.0), 1.2, 0.2)


func _present_windup() -> void:
	_telegraph_disc = VFX.telegraph_disc(get_tree().current_scene, present_origin() + present_forward() * BLOW_AHEAD,
		BLOW_RADIUS, BLOW_WINDUP)
	Sfx.play("caster_charge", global_position, -4.0, 0.1, 0.6)


func _present_fx(fx: StringName) -> void:
	var scene := get_tree().current_scene
	var zone := ZoneBase.zone_of(self)
	match fx:
		&"blow":
			var at := present_origin() + present_forward() * BLOW_AHEAD
			VFX.lightning_arc(scene, at + Vector3(0, 3.5, 0), at, Color(0.85, 0.8, 1.0))
			VFX.earthbreaker_slam(scene, at, BLOW_RADIUS)
			Sfx.play("storm_bolt", at, -2.0, 0.1, 0.8)
			GameFeel.camera_shake(0.25)
		&"pulse_tell":
			if arena_rect.has_area():
				_telegraph_disc = VFX.telegraph_disc(scene, present_origin(), maxf(arena_rect.size.x, arena_rect.size.y) * 0.5, PULSE_WINDUP)
			Sfx.play("coil_charge", global_position, -6.0, 0.05, 1.4)
		&"pulse":
			VFX.ground_ring(scene, present_origin(), Color(0.78, 0.7, 1.0), maxf(arena_rect.size.x, arena_rect.size.y) * 0.5, 0.4)
			Sfx.play("coil_discharge", global_position, -2.0, 0.08, 0.8)
		&"clap_charge":
			_charge_until = Time.get_ticks_msec() / 1000.0 + CLAP_CHARGE
			for g in grounds:
				VFX.flash(scene, g + Vector3(0, 2.6, 0), Color(0.85, 0.8, 1.0), 1.4, CLAP_CHARGE)
			Sfx.play("coil_charge", global_position, 0.0, 0.0, 0.5)
			if zone != null and zone.hud != null:
				zone.hud.toast(Texts.t("ui.storm.clap"), Color(0.78, 0.7, 1.0))
		&"grounded":
			_charge_until = -1.0
			for g in grounds:
				VFX.light_pop(scene, g + Vector3(0, 2.6, 0), Color(0.9, 0.86, 1.0), 4.0, 9.0, 0.4)
			Sfx.play("storm_bolt", global_position, 0.0, 0.05, 0.6)
			if zone != null and zone.hud != null:
				zone.hud.toast(Texts.t("ui.storm.grounded"), Color(0.78, 0.7, 1.0))
		&"clap":
			_charge_until = -1.0
			VFX.flash(scene, present_origin() + Vector3(0, 3.0, 0), Color(0.95, 0.92, 1.0), 6.0, 0.25)
			Sfx.play("storm_bolt", global_position, 4.0, 0.0, 0.5)
			Sfx.play("boss_roar", global_position, -2.0, 0.1, 0.7)
			GameFeel.camera_shake(0.6)
		&"far_bolt":
			VFX.flash(scene, present_origin() + Vector3(0, 3.0, 0), Color(0.85, 0.8, 1.0), 1.0, 0.3)
		&"roar":
			Sfx.play("boss_roar", global_position, -2.0, 0.1, 0.9)
