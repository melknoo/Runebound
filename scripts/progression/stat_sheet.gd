class_name StatSheet
extends RefCounted
## M07b: the numbers the character sheet and the HUD tooltip show, computed
## from the same hooks the game uses (Player.stat, cooldown_for, AbilityData),
## so what the sheet says is what a hit does. All static; no state.

## Display names for every stat key an affix or talent can carry:
## key -> [suffix, name]. Shared by the inventory compare and the sheet.
const STAT_NAMES := {
	&"damage_pct": ["%", " damage"], &"max_hp": ["", " maximum health"],
	&"cooldown_pct": ["%", " cooldown reduction"], &"resonance_pct": ["%", " Resonance gained"],
	&"move_pct": ["%", " movement speed"], &"crit_pct": ["%", " critical chance"],
	&"ember_pierce": ["", " Ember Lance pierce"], &"chain_jumps": ["", " Chain Spark jump"],
	&"cleave_radius_pct": ["%", " Rune Cleave area"], &"dodge_cd_pct": ["%", " dodge cooldown reduction"],
	&"eb_cost_reduce": ["", " Earthbreaker cost reduction"], &"rune_arm_reduce": ["s", " faster rune arming"],
	&"shocked_dmg_pct": ["%", " damage to Shocked enemies"], &"burn_pct": ["%", " Burn damage"],
	&"storm_cd_pct": ["%", " Storm Step cooldown reduction"], &"burning_dmg_pct": ["%", " damage to Burning enemies"],
	&"ember_dmg_pct": ["%", " Ember Lance damage"], &"lightning_res_pct": ["%", " Resonance from lightning"],
}

const LIGHTNING_ABILITIES: Array[StringName] = [&"storm_step", &"chain_spark"]


## Damage of one hit before the crit roll (level and gear %, Ember Lance's own %).
static func effective_damage(p: Player, d: AbilityData) -> float:
	var mult := 1.0 + p.stat(&"damage_pct") / 100.0
	if d.id == &"ember_lance":
		mult *= 1.0 + p.stat(&"ember_dmg_pct") / 100.0
	return d.damage * mult


static func crit_chance(p: Player, d: AbilityData) -> float:
	return clampf(d.crit_chance + p.stat(&"crit_pct") / 100.0, 0.0, 1.0)


## Average damage per hit with the crit chance folded in.
static func expected_damage(p: Player, d: AbilityData) -> float:
	var crit := crit_chance(p, d)
	return effective_damage(p, d) * (1.0 + crit * (d.crit_multiplier - 1.0))


static func effective_cooldown(p: Player, d: AbilityData) -> float:
	return p.cooldown_for(d.id, d.cooldown)


static func cost(p: Player, d: AbilityData) -> float:
	return p.earthbreaker_cost() if d.id == &"earthbreaker" else d.resonance_cost


## Resonance one hit of `d` builds, with the gain bonuses applied.
static func resonance_gain(p: Player, d: AbilityData) -> float:
	var pct := p.stat(&"resonance_pct")
	if LIGHTNING_ABILITIES.has(d.id):
		pct += p.stat(&"lightning_res_pct")
	return d.resonance_gain_per_hit * (1.0 + pct / 100.0)


## Headline damage text of an ability for the tooltip / sheet; "" when it
## deals none.
static func damage_text(p: Player, d: AbilityData) -> String:
	match d.id:
		&"runic_guard":
			return "Barrier %d" % roundi(d.damage + float(p.progression.level))
		&"resonance_burst":
			return "Up to %d damage at full Resonance" % roundi(d.damage * p.max_resource() * (1.0 + p.stat(&"damage_pct") / 100.0))
	if d.damage <= 0.0:
		return ""
	return "Damage %d (avg %d)" % [roundi(effective_damage(p, d)), roundi(expected_damage(p, d))]


## Behaviour notes for an ability: reach, extra targets, held talents and
## legendary powers that change it.
static func notes(p: Player, d: AbilityData) -> Array[String]:
	var out: Array[String] = []
	match d.id:
		&"rune_cleave":
			out.append("Reach %.1f m" % (1.5 * (1.0 + p.stat(&"cleave_radius_pct") / 100.0)))
		&"ember_lance":
			var pierce := int(p.stat(&"ember_pierce"))
			if pierce > 0:
				out.append("Pierces %d" % pierce)
			if p.has_power(&"split_lance"):
				out.append("Split Lance")
			if p.has_power(&"phoenix_burst"):
				out.append("Phoenix Burst")
			if p.has_power(&"cindermaw"):
				out.append("Cindermaw")
		&"earthbreaker":
			out.append("Area %.0f m" % d.aoe_radius)
			if p.has_power(&"molten_core"):
				out.append("Molten Core")
			if p.has_power(&"glacier_heart"):
				out.append("Glacier Heart")
		&"storm_step":
			if p.has_power(&"overload"):
				out.append("Overload")
			if p.has_power(&"eye_of_the_storm"):
				out.append("Eye of the Storm")
		&"chain_spark":
			out.append("%d targets (+1 vs Shocked)" % (3 + int(p.stat(&"chain_jumps"))))
			if p.has_power(&"thunderclap"):
				out.append("Thunderclap")
			if p.has_power(&"conductors_oath"):
				out.append("Conductor's Oath")
		&"fracture_rune":
			out.append("Arms in %.1f s" % maxf(FractureRune.ARM_TIME - p.stat(&"rune_arm_reduce"), 0.5))
			out.append("Area %.0f m" % d.aoe_radius)
		&"runic_guard":
			out.append("Lasts %.0f s" % d.active)
			if p.has_power(&"glacial_bulwark"):
				out.append("Glacial Bulwark")
		&"resonance_burst":
			out.append("%.1f damage per Resonance, area %.0f m" % [d.damage, d.aoe_radius])
	return out


## One row per ability the character knows, in class order.
static func ability_rows(p: Player) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for d in p.class_data.abilities:
		if d == null or not p.knows(d.id):
			continue
		rows.append({
			"id": d.id, "name": d.display_name, "key": Hud.key_for(p, d.id), "type": d.damage_type,
			"base": d.damage, "damage": effective_damage(p, d), "avg": expected_damage(p, d),
			"crit": crit_chance(p, d), "cooldown": effective_cooldown(p, d), "cost": cost(p, d),
			"gain": resonance_gain(p, d), "notes": notes(p, d),
		})
	return rows


## [label, value] pairs: the hero's core numbers.
static func core_rows(p: Player) -> Array[Array]:
	var prog := p.progression
	return [
		["Level", "%d  (%d / %d XP)" % [prog.level, prog.xp, Progression.xp_to_next(prog.level)]
			if prog.level < Progression.LEVEL_CAP else "%d  (cap)" % prog.level],
		["Health", "%d / %d" % [roundi(p.health.current_health), roundi(p.health.max_health)]],
		["Barrier", "%d" % roundi(p.barrier)],
		[p.class_data.resource_label, "%d / %d   (+%d%% gained)" % [roundi(p.resonance), roundi(p.max_resource()), roundi(p.stat(&"resonance_pct"))]],
		["Damage", "+%d%%" % roundi(p.stat(&"damage_pct"))],
		["Critical chance", "+%d%%" % roundi(p.stat(&"crit_pct"))],
		["Cooldowns", "-%d%%" % roundi(minf(p.stat(&"cooldown_pct"), 65.0))],
		["Movement", "+%d%%" % roundi(p.stat(&"move_pct"))],
		["Gold", str(p.gold)],
	]


## [label, value] pairs: defence and utility.
static func defence_rows(p: Player) -> Array[Array]:
	var rows: Array[Array] = [
		["Dodge cooldown", "%.2f s" % p.cooldown_for(&"dodge", Player.DODGE_COOLDOWN)],
		["Dodge i-frames", "%.2f s" % Player.DODGE_IFRAMES],
		["Burn damage", "+%d%%" % roundi(p.stat(&"burn_pct"))],
		["vs Shocked", "+%d%%" % roundi(p.stat(&"shocked_dmg_pct"))],
		["vs Burning", "+%d%%" % roundi(p.stat(&"burning_dmg_pct"))],
	]
	if p.has_power(&"unbroken"):
		rows.append(["Unbroken", "%d barrier on a dodged hit" % roundi(Player.UNBROKEN_BARRIER)])
	return rows


## "+15% damage" style text for a stat delta or total.
static func stat_text(key: StringName, value: float) -> String:
	var fmt: Array = STAT_NAMES.get(key, ["", " " + String(key)])
	var amount := ("%+.1f" % value) if absf(value) < 1.0 else ("%+d" % roundi(value))
	return amount + fmt[0] + fmt[1]
