class_name DruidHero
extends Player
## M11: the root druid, the healer. Thorn Volley (LMB, held for auto-fire)
## fights at mid range; the heals go to the ally under the crosshair, else the
## most wounded ally in reach, else the druid itself (Player.pick_heal_target).
## Sap is a POOL (ClassData.resource_mode): it starts full, every heal spends
## it, and it refills only while a fight is on (user 2026-09-30: no
## regeneration out of combat). Heals on allies travel as HERO_FX with a
## target ref and are applied by the target's owner (HeroFx "ally_*"); the
## Renewal Grove and the Totem of Growth exist on every machine and each one
## looks after the heroes it simulates (like the tank's Warding Rune).

## Thorn Volley: this many thorns, this far apart (degrees), this long in flight.
const THORNS := 3
const THORN_SPREAD := 6.0
const THORN_LIFETIME := 0.75
## Barkskin grows with the druid's level.
const BARK_PER_LEVEL := 2.0
## Below this health share Ashbloom Seed doubles Mending Bloom and Overgrowth
## adds a Regrowth; Nurture (low_heal_pct) works below half.
const LOW_HEALTH := 0.35
const NURTURE_BELOW := 0.5
## Totem of Growth: its damage bonus (%) before talents.
const TOTEM_DAMAGE_PCT := 15.0
## Wild Bloom throws back and roots the enemies this close.
const BLOOM_ENEMY_RADIUS := 5.0
## Briar Burst: Root Grasp bursts again this much later, at half damage.
const BRIAR_DELAY := 1.0
## Rooted Totem: the totem roots enemies this close when it is planted.
const TOTEM_ROOT_RADIUS := 3.0
const TOTEM_ROOT_TIME := 1.5
## Heart of the Grove: grove and totem last this much longer.
const HEART_OF_THE_GROVE := 1.5

## Abilities that go to the heal target (Player.pick_heal_target).
const TARGETED_HEALS: Array[StringName] = [&"mending_bloom", &"barkskin", &"regrowth"]

# Ability tuning: derived caches of `abilities` (the tests read them by name).
var thorn_volley: AbilityData
var mending_bloom: AbilityData
var barkskin: AbilityData
var regrowth: AbilityData
var root_grasp: AbilityData
var renewal_grove: AbilityData
var thornfield: AbilityData
var growth_totem: AbilityData
var wild_bloom: AbilityData


func _load_abilities() -> void:
	super()
	thorn_volley = ability(&"thorn_volley")
	mending_bloom = ability(&"mending_bloom")
	barkskin = ability(&"barkskin")
	regrowth = ability(&"regrowth")
	root_grasp = ability(&"root_grasp")
	renewal_grove = ability(&"renewal_grove")
	thornfield = ability(&"thornfield")
	growth_totem = ability(&"growth_totem")
	wild_bloom = ability(&"wild_bloom")


func _register_actions() -> void:
	super()
	_actions.merge({
		&"thorn_volley": try_thorn_volley,
		&"mending_bloom": try_mending_bloom,
		&"barkskin": try_barkskin,
		&"regrowth": try_regrowth,
		&"root_grasp": try_root_grasp,
		&"renewal_grove": try_renewal_grove,
		&"thornfield": try_thornfield,
		&"growth_totem": try_growth_totem,
		&"wild_bloom": try_wild_bloom,
	})


## The druid rig's clips (tools/modelgen: druid_clips). The quick heals and
## the thorns are upper-body gestures, so the legs keep running; the ground
## abilities (roots, grove, totem, the bloom) take the whole body.
func _anim_profile() -> Dictionary:
	var profile := super()
	(profile["actions"] as Dictionary).merge({&"root_grasp": &"root_grasp", &"renewal_grove": &"grove",
		&"growth_totem": &"totem", &"wild_bloom": &"bloom"})
	(profile["upper"] as Dictionary).merge({&"thorn_volley": &"thorn", &"mending_bloom": &"mend",
		&"barkskin": &"bark", &"regrowth": &"regrowth", &"thornfield": &"thornfield"})
	return profile


func shows_heal_target() -> bool:
	for id in TARGETED_HEALS:
		if can_use(id):
			return true
	return false


## M11 talents: Mending Bloom may cost less Sap.
func resource_cost(id: StringName) -> float:
	var base := super(id)
	if id == &"mending_bloom":
		base = maxf(base - stat(&"mend_cost_reduce"), 0.0)
	return base


## The heal a support ability of `base` gives with this hero's gear and
## talents (Nurture adds to a target below half health).
func heal_amount(base: float, target: Player = null) -> float:
	var pct := stat(&"heal_pct")
	if target != null and _health_share(target) < NURTURE_BELOW:
		pct += stat(&"low_heal_pct")
	return base * (1.0 + pct / 100.0)


static func _health_share(p: Player) -> float:
	return p.health.current_health / maxf(p.health.max_health, 1.0)


## Sends a heal to `target` (this hero, a bot, or another player's hero): the
## look plays everywhere, the target's owner applies it (HeroFx "ally_heal").
func heal_ally(target: Player, amount: float) -> void:
	var zone := ZoneBase.zone_of(self)
	if zone == null or target == null:
		return
	hero_fx(&"ally_heal", [zone.hero_ref(target), amount])


func _hot_ally(target: Player, total: float, duration: float) -> void:
	var zone := ZoneBase.zone_of(self)
	if zone != null and target != null:
		hero_fx(&"ally_hot", [zone.hero_ref(target), &"regrowth", total, duration])


## Faces a chosen ally for the cast (itself: the aim).
func _face_ally(target: Player) -> void:
	if target == null or target == self:
		_hold_aim()
		return
	var to := target.global_position - global_position
	to.y = 0.0
	if to.length() > 0.1:
		_visual.rotation.y = atan2(-to.x, -to.z)
		_aim_hold_until = Time.get_ticks_msec() + AIM_HOLD_MSEC


## True when `id` can be paid for now (else a denied click).
func _pay(id: StringName) -> bool:
	var cost := resource_cost(id)
	if resonance < cost:
		ui_denied()
		return false
	spend_resonance(cost)
	return true


func _ready_for(id: StringName) -> bool:
	return knows(id) and state == State.MOVE and not _on_cooldown(id)


## The ground under the aim, at most `reach` away (the camera's aim point;
## without a camera - a bot - the enemy nearest the aim line, else `reach`
## along it).
func _ground_aim(reach: float) -> Vector3:
	var exclude: Array[RID] = [get_rid()]
	var aim_point := camera_rig.get_aim_point(exclude) if camera_rig != null else _bot_aim_point(reach)
	var offset := Vector3(aim_point.x - global_position.x, 0.0, aim_point.z - global_position.z)
	if offset.length() > reach:
		offset = offset.normalized() * reach
	return ZoneBase.ground_under(self, global_position + offset, 0.02)


func _bot_aim_point(reach: float) -> Vector3:
	var aim := aim_direction()
	aim.y = 0.0
	aim = aim.normalized() if aim.length() > 0.01 else facing()
	var best: EnemyBase = null
	var best_off := 2.5
	for e in EnemyBase.all_enemies:
		if not is_instance_valid(e) or e.ai_state == EnemyBase.AIState.DEAD:
			continue
		var rel := e.global_position - global_position
		rel.y = 0.0
		var along := rel.dot(aim)
		if along < 0.0 or along > reach:
			continue
		var off := (rel - aim * along).length()
		if off < best_off:
			best_off = off
			best = e
	return best.global_position if best != null else global_position + aim * reach


func _root_duration(base: float) -> float:
	return base + stat(&"root_duration")


# ---------------------------------------------------------------------------
# Thorn Volley (basic attack, auto-fire while held)
# ---------------------------------------------------------------------------

func thorn_count() -> int:
	return THORNS + (1 if has_power(&"splinter") else 0) + (2 if has_power(&"thornmothers_crown") else 0)


func try_thorn_volley() -> bool:
	if not _ready_for(&"thorn_volley"):
		return false
	_set_cooldown(&"thorn_volley", thorn_volley.cooldown)
	_hold_aim()
	var aim := aim_direction()
	var dirs: Array = []
	var n := thorn_count()
	for i in n:
		dirs.append(aim.rotated(Vector3.UP, deg_to_rad((i - (n - 1) * 0.5) * THORN_SPREAD)))
	var from := muzzle_position()
	for dir: Vector3 in dirs:
		var thorn := SpellBolt.new()
		thorn.color_role = "nature"
		thorn.lifetime = THORN_LIFETIME
		thorn.setup(thorn_volley, dir, self)
		thorn.position = from  # before add_child, like every projectile
		get_tree().current_scene.add_child(thorn)
	mark_combat()
	hero_fx(&"thorn_volley", [from, dirs])  # puppets fly visual copies
	cooldowns_changed.emit()
	action_started.emit(&"thorn_volley")
	return true


# ---------------------------------------------------------------------------
# Mending Bloom (a targeted heal, the start kit)
# ---------------------------------------------------------------------------

func try_mending_bloom() -> bool:
	if not _ready_for(&"mending_bloom"):
		return false
	var target := pick_heal_target()
	if not _pay(&"mending_bloom"):
		return false
	_set_cooldown(&"mending_bloom", mending_bloom.cooldown)
	_face_ally(target)
	var low := _health_share(target) < LOW_HEALTH
	var amount := heal_amount(mending_bloom.heal, target)
	if low and has_power(&"ashbloom_seed"):
		amount *= 2.0  # M11 legendary
	heal_ally(target, amount)
	if low and has_power(&"overgrowth") and regrowth != null:
		_hot_ally(target, heal_amount(regrowth.heal, target), _regrowth_time())
	cooldowns_changed.emit()
	action_started.emit(&"mending_bloom")
	return true


# ---------------------------------------------------------------------------
# Barkskin (a targeted shield)
# ---------------------------------------------------------------------------

func bark_amount() -> float:
	var lvl := progression.level if progression != null else 1
	return (barkskin.heal + BARK_PER_LEVEL * lvl + stat(&"bark_amount")) * (1.0 + stat(&"heal_pct") / 100.0)


func try_barkskin() -> bool:
	if not _ready_for(&"barkskin"):
		return false
	var target := pick_heal_target()
	if not _pay(&"barkskin"):
		return false
	_set_cooldown(&"barkskin", barkskin.cooldown)
	_face_ally(target)
	var zone := ZoneBase.zone_of(self)
	if zone != null:
		hero_fx(&"ally_shield", [zone.hero_ref(target), bark_amount(), barkskin.active])
	cooldowns_changed.emit()
	action_started.emit(&"barkskin")
	return true


# ---------------------------------------------------------------------------
# Regrowth (a targeted heal over time)
# ---------------------------------------------------------------------------

func _regrowth_time() -> float:
	return regrowth.active * (1.0 + stat(&"hot_dur_pct") / 100.0)


func try_regrowth() -> bool:
	if not _ready_for(&"regrowth"):
		return false
	var target := pick_heal_target()
	if not _pay(&"regrowth"):
		return false
	_set_cooldown(&"regrowth", regrowth.cooldown)
	_face_ally(target)
	_hot_ally(target, heal_amount(regrowth.heal, target), _regrowth_time())
	cooldowns_changed.emit()
	action_started.emit(&"regrowth")
	return true


# ---------------------------------------------------------------------------
# Root Grasp (roots burst from the ground at the aim)
# ---------------------------------------------------------------------------

func try_root_grasp() -> bool:
	if not _ready_for(&"root_grasp"):
		return false
	if not _pay(&"root_grasp"):
		return false
	_set_cooldown(&"root_grasp", root_grasp.cooldown)
	var at := _ground_aim(root_grasp.projectile_speed)
	_hold_aim()
	_root_burst(at, 1.0)
	if has_power(&"briar_burst"):
		get_tree().create_timer(BRIAR_DELAY, false).timeout.connect(func() -> void:
			if is_instance_valid(self) and is_inside_tree():
				_root_burst(at, 0.5))
	feel_shake(0.15)
	cooldowns_changed.emit()
	action_started.emit(&"root_grasp")
	return true


func _root_burst(at: Vector3, mult: float) -> void:
	hero_fx(&"root_grasp", [at, root_grasp.aoe_radius])
	for enemy: Node in _query_hurtboxes(at + Vector3(0, 0.8, 0), root_grasp.aoe_radius):
		var hit := roll_ability_hit(root_grasp)
		hit.damage *= mult
		hit.source_position = at
		if enemy.call(&"take_hit", hit) and enemy is EnemyBase:
			(enemy as EnemyBase).status.apply_root(_root_duration(root_grasp.active))


# ---------------------------------------------------------------------------
# Renewal Grove (a healing zone at the aim; exists on every machine)
# ---------------------------------------------------------------------------

func grove_rate() -> float:
	return heal_amount(renewal_grove.heal) * (1.0 + stat(&"grove_heal_pct") / 100.0)


func grove_radius() -> float:
	return renewal_grove.aoe_radius + stat(&"grove_radius")


func try_renewal_grove() -> bool:
	if not _ready_for(&"renewal_grove"):
		return false
	if not _pay(&"renewal_grove"):
		return false
	_set_cooldown(&"renewal_grove", renewal_grove.cooldown)
	var at := _ground_aim(renewal_grove.projectile_speed)
	_hold_aim()
	var duration := renewal_grove.active * (HEART_OF_THE_GROVE if has_power(&"heart_of_the_grove") else 1.0)
	hero_fx(&"renewal_grove", [at, grove_radius(), duration, grove_rate(), has_power(&"heartwood_idol"),
		has_power(&"green_tide")])
	cooldowns_changed.emit()
	action_started.emit(&"renewal_grove")
	return true


# ---------------------------------------------------------------------------
# Thornfield (a patch of thorns at the aim that bites and hinders)
# ---------------------------------------------------------------------------

func try_thornfield() -> bool:
	if not _ready_for(&"thornfield"):
		return false
	if not _pay(&"thornfield"):
		return false
	_set_cooldown(&"thornfield", thornfield.cooldown)
	var at := _ground_aim(thornfield.projectile_speed)
	_hold_aim()
	var field := ThornField.new()
	field.setup(thornfield, self)
	field.radius = thornfield.aoe_radius + stat(&"thornfield_radius")
	field.duration = thornfield.active
	field.position = at
	get_tree().current_scene.add_child(field)
	hero_fx(&"thornfield", [at, field.radius, field.duration])  # puppets raise a visual copy
	cooldowns_changed.emit()
	action_started.emit(&"thornfield")
	return true


# ---------------------------------------------------------------------------
# Totem of Growth (a totem at the feet: damage for allies near, small heals)
# ---------------------------------------------------------------------------

func totem_damage_pct() -> float:
	return TOTEM_DAMAGE_PCT + stat(&"totem_dmg_pct")


func try_growth_totem() -> bool:
	if not _ready_for(&"growth_totem"):
		return false
	if not _pay(&"growth_totem"):
		return false
	_set_cooldown(&"growth_totem", growth_totem.cooldown)
	var at := ZoneBase.ground_under(self, global_position + facing() * 1.2, 0.02)
	var duration := growth_totem.active * (HEART_OF_THE_GROVE if has_power(&"heart_of_the_grove") else 1.0)
	hero_fx(&"growth_totem", [at, growth_totem.aoe_radius, duration, totem_damage_pct(), heal_amount(growth_totem.heal)])
	if has_power(&"rooted_totem"):
		for e in EnemyBase.all_enemies:
			if is_instance_valid(e) and e.ai_state != EnemyBase.AIState.DEAD \
					and e.global_position.distance_to(at) <= TOTEM_ROOT_RADIUS:
				e.status.apply_root(_root_duration(TOTEM_ROOT_TIME))
	cooldowns_changed.emit()
	action_started.emit(&"growth_totem")
	return true


# ---------------------------------------------------------------------------
# Wild Bloom (the great heal: every ally near, enemies thrown back and rooted)
# ---------------------------------------------------------------------------

func try_wild_bloom() -> bool:
	if not _ready_for(&"wild_bloom"):
		return false
	if not _pay(&"wild_bloom"):
		return false
	_set_cooldown(&"wild_bloom", wild_bloom.cooldown)
	var pos := global_position
	var zone := ZoneBase.zone_of(self)
	hero_fx(&"wild_bloom", [pos, wild_bloom.aoe_radius])
	if zone != null:
		for ally in zone.players_within(pos, wild_bloom.aoe_radius):
			var amount := heal_amount(ally.health.max_health * wild_bloom.heal / 100.0, ally)
			heal_ally(ally, amount)
			if has_power(&"lifebloom"):
				hero_fx(&"ally_shield", [zone.hero_ref(ally), amount * 0.2, 5.0])
	var hits := _query_hurtboxes(pos + Vector3(0, 0.8, 0), BLOOM_ENEMY_RADIUS)
	for enemy: Node in hits:
		var hit := roll_ability_hit(wild_bloom)
		hit.source_position = pos
		if enemy.call(&"take_hit", hit) and enemy is EnemyBase:
			(enemy as EnemyBase).status.apply_root(_root_duration(wild_bloom.active))
	feel_shake(0.3)
	cooldowns_changed.emit()
	action_started.emit(&"wild_bloom")
	return true
