class_name ClassData
extends Resource
## M07b: a playable class as data (docs/TECHNICAL_ARCHITECTURE.md, "Multi-class
## seams"). Lists which abilities the class has (HUD order), which of them a
## fresh character knows, its talent branch names and its rig. Behavior stays
## in Player; a second class extends Player and supplies its own ClassData.

const CLASS_DIR := "res://resources/classes/"
const DEFAULT_ID: StringName = &"runebreaker"

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
## Every ability of the class, in HUD slot order.
@export var abilities: Array[AbilityData] = []
## Ability ids a fresh character starts with (the rest are learned).
@export var starting_abilities: Array[StringName] = []
## Talent branch display names, indexed by TalentData.Branch.
@export var talent_branches: Array[String] = ["Storm", "Ember", "Runic Warden"]
@export var rig_path: String = ""
@export var material_id: String = ""
## The class resource (Runebreaker: Resonance).
@export var resource_label: String = "Resonance"
@export var max_resource: float = 100.0

static var _all: Array[ClassData] = []


func ability(ability_id: StringName) -> AbilityData:
	for a in abilities:
		if a != null and a.id == ability_id:
			return a
	return null


## Abilities the trainer can teach (unlock == TRAINER), by level then price.
func trainer_abilities() -> Array[AbilityData]:
	var out: Array[AbilityData] = []
	for a in abilities:
		if a != null and a.unlock == AbilityData.Unlock.TRAINER:
			out.append(a)
	out.sort_custom(func(x: AbilityData, y: AbilityData) -> bool:
		if x.learn_level != y.learn_level:
			return x.learn_level < y.learn_level
		return x.learn_price < y.learn_price
	)
	return out


static func all() -> Array[ClassData]:
	if _all.is_empty():
		for file in DirAccess.get_files_at(CLASS_DIR):
			var res_name := file.trim_suffix(".remap")  # exported builds list .tres.remap
			if not res_name.ends_with(".tres"):
				continue
			var c := load(CLASS_DIR + res_name) as ClassData
			if c != null:
				_all.append(c)
		_all.sort_custom(func(a: ClassData, b: ClassData) -> bool: return String(a.id) < String(b.id))
	return _all


static func load_by_id(class_id: StringName) -> ClassData:
	for c in all():
		if c.id == class_id:
			return c
	return null


static func default_class() -> ClassData:
	var c := load_by_id(DEFAULT_ID)
	assert(c != null, "resources/classes/runebreaker.tres missing")
	return c


static func clear_cache() -> void:
	_all.clear()
