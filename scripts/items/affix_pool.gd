class_name AffixPool
extends Object
## Affix definitions. Numeric affixes stay chunky enough to feel; behavioral
## affixes change how an ability works (the interesting drops).
## def: { id, template ("%d" gets the rolled value), stat, min, max,
##        slots: Array[ItemData.Slot], weight }

const DEFS: Array[Dictionary] = [
	# --- numeric, all slots unless noted ---
	{"id": &"damage_pct", "template": "+%d%% damage", "stat": &"damage_pct",
		"min": 12.0, "max": 20.0, "slots": [ItemData.Slot.WEAPON, ItemData.Slot.AMULET, ItemData.Slot.RING], "weight": 10},
	{"id": &"max_hp", "template": "+%d maximum health", "stat": &"max_hp",
		"min": 20.0, "max": 35.0, "slots": [ItemData.Slot.CHEST, ItemData.Slot.HELM, ItemData.Slot.AMULET], "weight": 10},
	{"id": &"cooldown_pct", "template": "%d%% cooldown reduction", "stat": &"cooldown_pct",
		"min": 10.0, "max": 20.0, "slots": [ItemData.Slot.AMULET, ItemData.Slot.HELM, ItemData.Slot.CHEST], "weight": 7},
	{"id": &"resonance_pct", "template": "+%d%% Resonance gained", "stat": &"resonance_pct",
		"min": 20.0, "max": 35.0, "slots": [ItemData.Slot.WEAPON, ItemData.Slot.AMULET, ItemData.Slot.GLOVES, ItemData.Slot.CHEST], "weight": 8},
	{"id": &"move_pct", "template": "+%d%% movement speed", "stat": &"move_pct",
		"min": 8.0, "max": 12.0, "slots": [ItemData.Slot.BOOTS], "weight": 8},
	{"id": &"crit_pct", "template": "+%d%% critical chance", "stat": &"crit_pct",
		"min": 4.0, "max": 7.0, "slots": [ItemData.Slot.WEAPON, ItemData.Slot.GLOVES, ItemData.Slot.RING], "weight": 7},
	# --- behavioral (fixed values, the value is the mechanic) ---
	{"id": &"ember_pierce", "class": &"runebreaker", "template": "Ember Lance pierces %d additional enemy", "stat": &"ember_pierce",
		"min": 1.0, "max": 1.0, "slots": [ItemData.Slot.WEAPON, ItemData.Slot.AMULET], "weight": 5},
	{"id": &"chain_jumps", "class": &"runebreaker", "template": "Chain Spark jumps to %d additional enemy", "stat": &"chain_jumps",
		"min": 1.0, "max": 1.0, "slots": [ItemData.Slot.WEAPON, ItemData.Slot.RING], "weight": 5},
	{"id": &"cleave_radius_pct", "class": &"runebreaker", "template": "+%d%% Rune Cleave area", "stat": &"cleave_radius_pct",
		"min": 35.0, "max": 35.0, "slots": [ItemData.Slot.WEAPON, ItemData.Slot.GLOVES], "weight": 5},
	{"id": &"dodge_cd_pct", "template": "%d%% dodge cooldown reduction", "stat": &"dodge_cd_pct",
		"min": 30.0, "max": 30.0, "slots": [ItemData.Slot.BOOTS], "weight": 5},
	{"id": &"eb_cost_reduce", "class": &"runebreaker", "template": "Earthbreaker costs %d less Resonance", "stat": &"eb_cost_reduce",
		"min": 15.0, "max": 15.0, "slots": [ItemData.Slot.AMULET, ItemData.Slot.HELM, ItemData.Slot.CHEST], "weight": 5},
	{"id": &"rune_arm_reduce", "class": &"runebreaker", "template": "Fracture Rune arms 0.4s faster", "stat": &"rune_arm_reduce",
		"min": 0.4, "max": 0.4, "slots": [ItemData.Slot.RING, ItemData.Slot.HELM], "weight": 5},
	# --- M07: affixes on the talent stats (same keys, so items and talents stack) ---
	{"id": &"shocked_dmg_pct", "template": "+%d%% damage to Shocked enemies", "stat": &"shocked_dmg_pct",
		"min": 10.0, "max": 16.0, "slots": [ItemData.Slot.WEAPON, ItemData.Slot.AMULET, ItemData.Slot.GLOVES], "weight": 6},
	{"id": &"burn_pct", "template": "Burn deals +%d%% damage", "stat": &"burn_pct",
		"min": 20.0, "max": 35.0, "slots": [ItemData.Slot.WEAPON, ItemData.Slot.AMULET, ItemData.Slot.RING], "weight": 6},
	{"id": &"storm_cd_pct", "class": &"runebreaker", "template": "Storm Step cooldown -%d%%", "stat": &"storm_cd_pct",
		"min": 10.0, "max": 18.0, "slots": [ItemData.Slot.BOOTS], "weight": 5},
]

## M07 adds three legendaries that grant a talent's behavior (the powers are
## shared with the tree, so the talent and the item never stack twice).
const LEGENDARIES: Array[Dictionary] = [
	{"id": &"cindermaw", "name": "Cindermaw", "class": &"runebreaker", "slot": ItemData.Slot.WEAPON,
		"text": "Burning enemies struck by Ember Lance erupt, scorching nearby enemies."},
	{"id": &"conductors_oath", "name": "Conductor's Oath", "class": &"runebreaker", "slot": ItemData.Slot.AMULET,
		"text": "Enemies struck by Chain Spark become Conductors. Lightning damage arcs between Conductors."},
	{"id": &"glacier_heart", "name": "Glacier Heart", "class": &"runebreaker", "slot": ItemData.Slot.CHEST,
		"text": "Earthbreaker leaves a field of frost that Chills enemies."},
	{"id": &"split_lance", "name": "Forked Ember", "class": &"runebreaker", "slot": ItemData.Slot.WEAPON,
		"text": "Ember Lance splits into two half-damage lances on its first hit."},
	{"id": &"overload", "name": "Stormcaller's Band", "class": &"runebreaker", "slot": ItemData.Slot.RING,
		"text": "Storm Step's end point Shocks every enemy within 2.5 m."},
	{"id": &"molten_core", "name": "Emberheart Plate", "class": &"runebreaker", "slot": ItemData.Slot.CHEST,
		"text": "Earthbreaker sets every enemy it hits ablaze."},
]


## Affixes a slot can roll. M07b: an affix tagged "class" only drops for that
## class (`class_id` empty = everything, for debug drops and tests).
static func defs_for_slot(slot: ItemData.Slot, class_id: StringName = &"") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for def in DEFS:
		if slot in (def["slots"] as Array) and _fits_class(def, class_id):
			out.append(def)
	return out


static func legendaries_for(class_id: StringName = &"") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for def in LEGENDARIES:
		if _fits_class(def, class_id):
			out.append(def)
	return out


static func _fits_class(def: Dictionary, class_id: StringName) -> bool:
	return class_id == &"" or not def.has("class") or def["class"] == class_id


static func roll(def: Dictionary) -> Dictionary:
	var value := randf_range(def["min"], def["max"])
	if def["max"] > 2.0:
		value = roundf(value)  # whole numbers read better on big stats
	var label: String
	if "%d" in String(def["template"]):
		label = String(def["template"]) % int(value)
	else:
		label = String(def["template"])
	return {"id": def["id"], "label": label, "stat": def["stat"], "value": value}
