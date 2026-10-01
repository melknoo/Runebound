class_name Consumables
extends RefCounted
## M10b: things a hero carries in the bag and uses up, counted per id
## (Player.consumables) instead of taking an inventory slot. User decision
## 2026-09-30: no regeneration out of combat (waiting would answer every
## fight) - healing between fights comes from consumables. Today there is one,
## the Healing Draught; food follows with the animals of M12. Drunk only from
## the inventory (right-click), by the user's choice: slow on purpose.

const HEALING_DRAUGHT: StringName = &"healing_draught"
## M12 food (user decision 2026-10-01): gathered from ember tuber patches and
## camp cooking pots, sold by Ylva; eaten only out of combat, a hit ends it.
const EMBER_TUBER: StringName = &"ember_tuber"

## id -> definition. heal_pct of the maximum health over `time` seconds; at
## most `cap` in the bag; `price` in gold at Ylva's in Runehold.
const DEFS := {
	&"healing_draught": {
		"name": "Healing Draught",
		"text": "Restores 35 % of your health over 4 s. Right-click to drink.",
		"heal_pct": 0.35, "time": 4.0, "cap": 5, "price": 30,
	},
	# M12: names and texts from the text table (DE/EN)
	&"ember_tuber": {
		"kind": "food", "name": "Ember Tuber", "name_key": "item.ember_tuber.name", "text_key": "item.ember_tuber.text",
		"heal_pct": 0.5, "time": 8.0, "cap": 10, "price": 12,
	},
}

## Chance per kill that a hero's personal loot holds a draught, by enemy kind.
const KILL_CHANCE := {&"trash": 0.05, &"brute": 0.15, &"elite": 0.3}
## Bosses always leave this many for every hero near the kill.
const BOSS_DRAUGHTS := 2
## Chance that a chest's purse holds a draught (one per hero).
const CHEST_CHANCE := 0.6


static func has(id: StringName) -> bool:
	return DEFS.has(id)


static func def(id: StringName) -> Dictionary:
	return DEFS.get(id, {})


static func display_name(id: StringName) -> String:
	var d := def(id)
	if d.has("name_key"):
		return Texts.t(str(d["name_key"]))
	return str(d.get("name", String(id)))


## The description shown in the bag (M12: from the text table when it has a key).
static func text(id: StringName) -> String:
	var d := def(id)
	if d.has("text_key"):
		return Texts.t(str(d["text_key"]))
	return str(d.get("text", ""))


## "draught" or (M12) "food".
static func kind(id: StringName) -> String:
	return str(def(id).get("kind", "draught"))


static func is_food(id: StringName) -> bool:
	return kind(id) == "food"


static func cap(id: StringName) -> int:
	return int(def(id).get("cap", 0))


static func price(id: StringName) -> int:
	return int(def(id).get("price", 0))


## Draughts a kill leaves for one hero (its personal roll).
static func roll_kill(enemy: EnemyBase) -> int:
	if enemy is AshveinColossus or enemy is ShatteredVessel:
		return BOSS_DRAUGHTS
	var kind := &"elite" if enemy.is_elite else (&"brute" if enemy is Brute else &"trash")
	return 1 if randf() < float(KILL_CHANCE[kind]) else 0


static func roll_chest() -> int:
	return 1 if randf() < CHEST_CHANCE else 0
