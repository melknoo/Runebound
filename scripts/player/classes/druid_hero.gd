class_name DruidHero
extends Player
## M11: the root druid, the healer. Thorn Volley (LMB, held for auto-fire)
## fights at mid range; the heals go to the ally under the crosshair, else the
## most wounded ally in reach, else the druid itself (Player.pick_heal_target).
## Sap is a POOL (ClassData.resource_mode): it starts full, every heal spends
## it, and it refills only while a fight is on (user 2026-09-30: no
## regeneration out of combat). Heals on allies travel as HERO_FX with a
## target ref and are applied by the target's owner (HeroFx "ally_*").

## Thorn Volley: this many thorns, this far apart (degrees), this long in flight.
const THORNS := 3
const THORN_SPREAD := 6.0
const THORN_LIFETIME := 0.75

# Ability tuning: derived caches of `abilities` (the tests read them by name).
var thorn_volley: AbilityData
var mending_bloom: AbilityData


func _load_abilities() -> void:
	super()
	thorn_volley = ability(&"thorn_volley")
	mending_bloom = ability(&"mending_bloom")


func _register_actions() -> void:
	super()
	_actions.merge({
		&"thorn_volley": try_thorn_volley,
		&"mending_bloom": try_mending_bloom,
	})


## Until the druid rig exists (M11 phase 3) it borrows the Elementalist's
## clips: the thorns throw like a Rune Bolt, a heal reaches out like a spark.
func _anim_profile() -> Dictionary:
	var profile := super()
	(profile["upper"] as Dictionary).merge({&"thorn_volley": &"bolt", &"mending_bloom": &"chain_spark"})
	return profile


## Abilities that go to the heal target (Player.pick_heal_target).
const TARGETED_HEALS: Array[StringName] = [&"mending_bloom", &"barkskin", &"regrowth"]


func shows_heal_target() -> bool:
	for id in TARGETED_HEALS:
		if can_use(id):
			return true
	return false


## The heal a support ability of `base` gives with this hero's gear and talents.
func heal_amount(base: float) -> float:
	return base * (1.0 + stat(&"heal_pct") / 100.0)


## Sends a heal to `target` (this hero, a bot, or another player's hero): the
## look plays everywhere, the target's owner applies it (HeroFx "ally_heal").
func heal_ally(target: Player, amount: float) -> void:
	var zone := ZoneBase.zone_of(self)
	if zone == null or target == null:
		return
	hero_fx(&"ally_heal", [zone.hero_ref(target), amount])


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


# ---------------------------------------------------------------------------
# Thorn Volley (basic attack, auto-fire while held)
# ---------------------------------------------------------------------------

func try_thorn_volley() -> bool:
	if not knows(&"thorn_volley") or state != State.MOVE or _on_cooldown(&"thorn_volley"):
		return false
	_set_cooldown(&"thorn_volley", thorn_volley.cooldown)
	_hold_aim()
	var aim := aim_direction()
	var dirs: Array = []
	for i in THORNS:
		dirs.append(aim.rotated(Vector3.UP, deg_to_rad((i - (THORNS - 1) * 0.5) * THORN_SPREAD)))
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
	if not knows(&"mending_bloom") or state != State.MOVE or _on_cooldown(&"mending_bloom"):
		return false
	var target := pick_heal_target()
	if not _pay(&"mending_bloom"):
		return false
	_set_cooldown(&"mending_bloom", mending_bloom.cooldown)
	_face_ally(target)
	heal_ally(target, heal_amount(mending_bloom.heal))
	cooldowns_changed.emit()
	action_started.emit(&"mending_bloom")
	return true
