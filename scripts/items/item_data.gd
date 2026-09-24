class_name ItemData
extends Resource
## One generated item instance: slot, rarity, affixes, optional legendary power.
## Affix entries: { "id": StringName, "label": String, "stat": StringName,
## "value": float } — `stat` keys are interpreted by Equipment/Player.

## 7 equipment slots (user, 2026-09-24). The first three keep their old
## values (ARMOR -> CHEST, RELIC -> AMULET), so saves need no conversion.
enum Slot { WEAPON, CHEST, AMULET, HELM, GLOVES, BOOTS, RING }
const SLOT_COUNT := 7
## Display / equip order in the inventory.
const SLOT_ORDER: Array[Slot] = [Slot.WEAPON, Slot.HELM, Slot.CHEST, Slot.GLOVES, Slot.BOOTS, Slot.AMULET, Slot.RING]
enum Rarity { COMMON, MAGIC, RARE, LEGENDARY }

var slot: Slot = Slot.WEAPON
var rarity: Rarity = Rarity.COMMON
var display_name: String = ""
var affixes: Array[Dictionary] = []
var legendary_id: StringName = &""
var legendary_text: String = ""
## M07: level of the source that dropped it; scales the numeric affixes.
var item_level: int = 1


func to_dict() -> Dictionary:
	var affix_list: Array = []
	for affix in affixes:
		affix_list.append({
			"id": String(affix["id"]),
			"label": affix["label"],
			"stat": String(affix["stat"]),
			"value": affix["value"],
		})
	return {
		"slot": slot,
		"rarity": rarity,
		"name": display_name,
		"affixes": affix_list,
		"legendary_id": String(legendary_id),
		"legendary_text": legendary_text,
		"item_level": item_level,
	}


static func from_dict(data: Dictionary) -> ItemData:
	var item := ItemData.new()
	item.slot = int(data.get("slot", 0)) as Slot
	item.rarity = int(data.get("rarity", 0)) as Rarity
	item.display_name = data.get("name", "Unknown Item")
	item.legendary_id = StringName(data.get("legendary_id", ""))
	item.legendary_text = data.get("legendary_text", "")
	item.item_level = int(data.get("item_level", 1))
	for affix: Dictionary in data.get("affixes", []):
		item.affixes.append({
			"id": StringName(affix.get("id", "")),
			"label": String(affix.get("label", "")),
			"stat": StringName(affix.get("stat", "")),
			"value": float(affix.get("value", 0.0)),
		})
	return item


static func rarity_color(r: Rarity) -> Color:
	match r:
		Rarity.MAGIC:
			return Color(0.45, 0.65, 1.0)
		Rarity.RARE:
			return Color(1.0, 0.85, 0.35)
		Rarity.LEGENDARY:
			return Color(1.0, 0.55, 0.2)
		_:
			return Color(0.8, 0.8, 0.8)


static func rarity_name(r: Rarity) -> String:
	match r:
		Rarity.MAGIC:
			return "Magic"
		Rarity.RARE:
			return "Rare"
		Rarity.LEGENDARY:
			return "Legendary"
		_:
			return "Common"


static func slot_name(s: Slot) -> String:
	match s:
		Slot.CHEST:
			return "Chest"
		Slot.AMULET:
			return "Amulet"
		Slot.HELM:
			return "Helm"
		Slot.GLOVES:
			return "Gloves"
		Slot.BOOTS:
			return "Boots"
		Slot.RING:
			return "Ring"
		_:
			return "Weapon"
