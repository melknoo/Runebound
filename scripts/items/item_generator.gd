class_name ItemGenerator
extends Object
## Rolls complete items: rarity → affix count → affixes → name.

const PREFIXES := ["Ashen", "Runic", "Storm-Kissed", "Duskforged", "Emberlit",
	"Hollow", "Warden's", "Shattered", "Gale", "Deepstone"]
const WEAPON_NOUNS := ["Blade", "Cleaver", "Edge", "Fang", "Riftbrand"]
const ARMOR_NOUNS := ["Cuirass", "Bulwark", "Shell", "Plating", "Aegis"]
const RELIC_NOUNS := ["Sigil", "Idol", "Talisman", "Focus", "Runestone"]
const HELM_NOUNS := ["Helm", "Visor", "Crown", "Greathelm", "Cowl"]
const GLOVES_NOUNS := ["Gauntlets", "Grips", "Fists", "Handguards"]
const BOOTS_NOUNS := ["Greaves", "Treads", "Striders", "Sabatons"]
const RING_NOUNS := ["Band", "Loop", "Seal", "Circlet"]
const SUFFIXES := ["of Echoes", "of the Highlands", "of Sparks", "of Cinders",
	"of the Spire", "of Resonance", "of the Long Dusk", ""]


## M07 item level: numeric "safe" affixes grow +6 % per level above 1;
## behavioral affixes and cooldown / speed / crit stay fixed (their value is
## the mechanic, or stacking them would break the kit).
const SCALED_STATS: Array[StringName] = [&"damage_pct", &"max_hp", &"resonance_pct"]
const ILVL_SCALE := 0.06


static func apply_item_level(item: ItemData, lvl: int) -> void:
	item.item_level = maxi(lvl, 1)
	if item.item_level <= 1:
		return
	var mult := 1.0 + ILVL_SCALE * (item.item_level - 1)
	for affix in item.affixes:
		if not SCALED_STATS.has(StringName(affix["stat"])):
			continue
		var value := roundf(float(affix["value"]) * mult)
		affix["value"] = value
		for def in AffixPool.DEFS:
			if def["id"] == StringName(affix["id"]) and "%d" in String(def["template"]):
				affix["label"] = String(def["template"]) % int(value)


## rarity_bias: 0 = normal enemy, 1 = brute, 2 = elite (min RARE).
## class_id (M07b): only that class's affixes and legendaries; "" = any.
static func generate(rarity_bias: int = 0, class_id: StringName = &"") -> ItemData:
	var item := ItemData.new()
	item.slot = randi() % ItemData.SLOT_COUNT as ItemData.Slot
	item.rarity = _roll_rarity(rarity_bias)
	if item.rarity == ItemData.Rarity.LEGENDARY:
		if not AffixPool.legendaries_for(class_id).is_empty():
			return _make_legendary(item, class_id)
		item.rarity = ItemData.Rarity.RARE  # no legendary for this class yet
	var affix_count := 0
	match item.rarity:
		ItemData.Rarity.MAGIC:
			affix_count = 1
		ItemData.Rarity.RARE:
			affix_count = 2 + (randi() % 2)
	_roll_affixes(item, affix_count, class_id)
	item.display_name = _roll_name(item.slot)
	return item


static func generate_legendary(class_id: StringName = &"") -> ItemData:
	var item := ItemData.new()
	item.rarity = ItemData.Rarity.LEGENDARY
	return _make_legendary(item, class_id)


static func _make_legendary(item: ItemData, class_id: StringName = &"") -> ItemData:
	var pool := AffixPool.legendaries_for(class_id)
	if pool.is_empty():
		pool = AffixPool.LEGENDARIES
	var def: Dictionary = pool.pick_random()
	item.slot = def["slot"]
	item.display_name = def["name"]
	item.legendary_id = def["id"]
	item.legendary_text = def["text"]
	_roll_affixes(item, 2, class_id)
	return item


# ---------------------------------------------------------------------------
# Loot tuning, all in one place (M08 notes, user 2026-09-28: "fewer drops,
# rare items much rarer"; docs/ITEMIZATION.md). Boss legendaries stay
# guaranteed (the zones hand them out on top).
# ---------------------------------------------------------------------------

## Chance that a kill drops an item, by kind of enemy (was 20 / 60 / 100 %).
const KILL_DROP_CHANCE := {&"trash": 0.08, &"brute": 0.30, &"elite": 0.60}
## Rarity odds by bias, cumulative: [legendary, + rare, + magic]; the rest is
## common. 0 = trash and plain chests, 1 = brutes and the better chests,
## 2 = elites (rare or better).
const RARITY_ODDS := {
	0: [0.003, 0.063, 0.363],  # legendary 0.3 %, rare 6 %, magic 30 %
	1: [0.01, 0.18, 0.63],     # legendary 1 %, rare 17 %, magic 45 %
	2: [0.05, 1.0, 1.0],       # legendary 5 %, rare 95 %
}
## Items a chest gives each hero (was 2-3).
const CHEST_ITEMS := Vector2i(1, 2)

## Tests: >= 0 replaces the next drop rolls (0.0 = always drops).
static var forced_drop_roll: float = -1.0


## Does a kill of this kind (KILL_DROP_CHANCE key) drop an item?
static func kill_drops(kind: StringName) -> bool:
	var roll := forced_drop_roll if forced_drop_roll >= 0.0 else randf()
	return roll < float(KILL_DROP_CHANCE.get(kind, 0.0))


static func chest_item_count() -> int:
	return randi_range(CHEST_ITEMS.x, CHEST_ITEMS.y)


static func _roll_rarity(bias: int) -> ItemData.Rarity:
	var odds: Array = RARITY_ODDS[clampi(bias, 0, 2)]
	var roll := randf()
	if roll < float(odds[0]):
		return ItemData.Rarity.LEGENDARY
	if roll < float(odds[1]):
		return ItemData.Rarity.RARE
	if roll < float(odds[2]):
		return ItemData.Rarity.MAGIC
	return ItemData.Rarity.COMMON


static func _roll_affixes(item: ItemData, count: int, class_id: StringName = &"") -> void:
	var pool := AffixPool.defs_for_slot(item.slot, class_id)
	var picked_ids: Array[StringName] = []
	for i in count:
		var total_weight := 0
		var available: Array[Dictionary] = []
		for def in pool:
			if not picked_ids.has(def["id"]):
				available.append(def)
				total_weight += def["weight"]
		if available.is_empty():
			break
		var roll := randi() % total_weight
		for def in available:
			roll -= def["weight"]
			if roll < 0:
				item.affixes.append(AffixPool.roll(def))
				picked_ids.append(def["id"])
				break


static func _roll_name(slot: ItemData.Slot) -> String:
	var noun: String
	match slot:
		ItemData.Slot.CHEST:
			noun = ARMOR_NOUNS.pick_random()
		ItemData.Slot.AMULET:
			noun = RELIC_NOUNS.pick_random()
		ItemData.Slot.HELM:
			noun = HELM_NOUNS.pick_random()
		ItemData.Slot.GLOVES:
			noun = GLOVES_NOUNS.pick_random()
		ItemData.Slot.BOOTS:
			noun = BOOTS_NOUNS.pick_random()
		ItemData.Slot.RING:
			noun = RING_NOUNS.pick_random()
		_:
			noun = WEAPON_NOUNS.pick_random()
	var name := "%s %s" % [PREFIXES.pick_random(), noun]
	var suffix: String = SUFFIXES.pick_random()
	if suffix != "":
		name += " " + suffix
	return name
