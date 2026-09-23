class_name ItemGenerator
extends Object
## Rolls complete items: rarity → affix count → affixes → name.

const PREFIXES := ["Ashen", "Runic", "Storm-Kissed", "Duskforged", "Emberlit",
	"Hollow", "Warden's", "Shattered", "Gale", "Deepstone"]
const WEAPON_NOUNS := ["Blade", "Cleaver", "Edge", "Fang", "Riftbrand"]
const ARMOR_NOUNS := ["Cuirass", "Bulwark", "Shell", "Plating", "Aegis"]
const RELIC_NOUNS := ["Sigil", "Idol", "Talisman", "Focus", "Runestone"]
const SUFFIXES := ["of Echoes", "of the Highlands", "of Sparks", "of Cinders",
	"of the Spire", "of Resonance", "of the Long Dusk", ""]


## rarity_bias: 0 = normal enemy, 1 = brute, 2 = elite (min RARE).
static func generate(rarity_bias: int = 0) -> ItemData:
	var item := ItemData.new()
	item.slot = randi() % 3 as ItemData.Slot
	item.rarity = _roll_rarity(rarity_bias)
	if item.rarity == ItemData.Rarity.LEGENDARY:
		return _make_legendary(item)
	var affix_count := 0
	match item.rarity:
		ItemData.Rarity.MAGIC:
			affix_count = 1
		ItemData.Rarity.RARE:
			affix_count = 2 + (randi() % 2)
	_roll_affixes(item, affix_count)
	item.display_name = _roll_name(item.slot)
	return item


static func generate_legendary() -> ItemData:
	var item := ItemData.new()
	item.rarity = ItemData.Rarity.LEGENDARY
	return _make_legendary(item)


static func _make_legendary(item: ItemData) -> ItemData:
	var def: Dictionary = AffixPool.LEGENDARIES.pick_random()
	item.slot = def["slot"]
	item.display_name = def["name"]
	item.legendary_id = def["id"]
	item.legendary_text = def["text"]
	_roll_affixes(item, 2)
	return item


static func _roll_rarity(bias: int) -> ItemData.Rarity:
	var roll := randf()
	match bias:
		2:  # elite: rare or better
			return ItemData.Rarity.LEGENDARY if roll < 0.25 else ItemData.Rarity.RARE
		1:  # brute
			if roll < 0.06:
				return ItemData.Rarity.LEGENDARY
			if roll < 0.4:
				return ItemData.Rarity.RARE
			if roll < 0.8:
				return ItemData.Rarity.MAGIC
			return ItemData.Rarity.COMMON
		_:
			if roll < 0.02:
				return ItemData.Rarity.LEGENDARY
			if roll < 0.15:
				return ItemData.Rarity.RARE
			if roll < 0.5:
				return ItemData.Rarity.MAGIC
			return ItemData.Rarity.COMMON


static func _roll_affixes(item: ItemData, count: int) -> void:
	var pool := AffixPool.defs_for_slot(item.slot)
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
		ItemData.Slot.ARMOR:
			noun = ARMOR_NOUNS.pick_random()
		ItemData.Slot.RELIC:
			noun = RELIC_NOUNS.pick_random()
		_:
			noun = WEAPON_NOUNS.pick_random()
	var name := "%s %s" % [PREFIXES.pick_random(), noun]
	var suffix: String = SUFFIXES.pick_random()
	if suffix != "":
		name += " " + suffix
	return name
