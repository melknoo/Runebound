class_name AffixPool
extends Object
## Affix definitions. Numeric affixes stay chunky enough to feel; behavioral
## affixes change how an ability works (the interesting drops).
## def: { id, template ("%d" gets the rolled value), stat, min, max,
##        slots: Array[ItemData.Slot], weight }

const DEFS: Array[Dictionary] = [
	# --- numeric, all slots unless noted ---
	{"id": &"damage_pct", "template": "+%d%% damage", "stat": &"damage_pct",
		"min": 12.0, "max": 20.0, "slots": [ItemData.Slot.WEAPON, ItemData.Slot.RELIC], "weight": 10},
	{"id": &"max_hp", "template": "+%d maximum health", "stat": &"max_hp",
		"min": 20.0, "max": 35.0, "slots": [ItemData.Slot.ARMOR, ItemData.Slot.RELIC], "weight": 10},
	{"id": &"cooldown_pct", "template": "%d%% cooldown reduction", "stat": &"cooldown_pct",
		"min": 10.0, "max": 20.0, "slots": [ItemData.Slot.RELIC, ItemData.Slot.ARMOR], "weight": 7},
	{"id": &"resonance_pct", "template": "+%d%% Resonance gained", "stat": &"resonance_pct",
		"min": 20.0, "max": 35.0, "slots": [ItemData.Slot.WEAPON, ItemData.Slot.RELIC], "weight": 8},
	{"id": &"move_pct", "template": "+%d%% movement speed", "stat": &"move_pct",
		"min": 8.0, "max": 12.0, "slots": [ItemData.Slot.ARMOR], "weight": 8},
	{"id": &"crit_pct", "template": "+%d%% critical chance", "stat": &"crit_pct",
		"min": 4.0, "max": 7.0, "slots": [ItemData.Slot.WEAPON], "weight": 7},
	# --- behavioral (fixed values, the value is the mechanic) ---
	{"id": &"ember_pierce", "template": "Ember Lance pierces %d additional enemy", "stat": &"ember_pierce",
		"min": 1.0, "max": 1.0, "slots": [ItemData.Slot.WEAPON, ItemData.Slot.RELIC], "weight": 5},
	{"id": &"chain_jumps", "template": "Chain Spark jumps to %d additional enemy", "stat": &"chain_jumps",
		"min": 1.0, "max": 1.0, "slots": [ItemData.Slot.WEAPON, ItemData.Slot.RELIC], "weight": 5},
	{"id": &"cleave_radius_pct", "template": "+%d%% Rune Cleave area", "stat": &"cleave_radius_pct",
		"min": 35.0, "max": 35.0, "slots": [ItemData.Slot.WEAPON], "weight": 5},
	{"id": &"dodge_cd_pct", "template": "%d%% dodge cooldown reduction", "stat": &"dodge_cd_pct",
		"min": 30.0, "max": 30.0, "slots": [ItemData.Slot.ARMOR], "weight": 5},
	{"id": &"eb_cost_reduce", "template": "Earthbreaker costs %d less Resonance", "stat": &"eb_cost_reduce",
		"min": 15.0, "max": 15.0, "slots": [ItemData.Slot.RELIC], "weight": 5},
	{"id": &"rune_arm_reduce", "template": "Fracture Rune arms 0.4s faster", "stat": &"rune_arm_reduce",
		"min": 0.4, "max": 0.4, "slots": [ItemData.Slot.RELIC], "weight": 5},
]

const LEGENDARIES: Array[Dictionary] = [
	{"id": &"cindermaw", "name": "Cindermaw", "slot": ItemData.Slot.WEAPON,
		"text": "Burning enemies struck by Ember Lance erupt, scorching nearby enemies."},
	{"id": &"conductors_oath", "name": "Conductor's Oath", "slot": ItemData.Slot.RELIC,
		"text": "Enemies struck by Chain Spark become Conductors. Lightning damage arcs between Conductors."},
	{"id": &"glacier_heart", "name": "Glacier Heart", "slot": ItemData.Slot.ARMOR,
		"text": "Earthbreaker leaves a field of frost that Chills enemies."},
]


static func defs_for_slot(slot: ItemData.Slot) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for def in DEFS:
		if slot in (def["slots"] as Array):
			out.append(def)
	return out


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
