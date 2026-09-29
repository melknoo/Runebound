class_name ClassData
extends Resource
## M07b: a playable class as data (docs/TECHNICAL_ARCHITECTURE.md, "Multi-class
## seams"). Lists which abilities the class has, which of them a fresh
## character knows, its talent branches and its rig. M10: behaviour lives in
## the class's hero script (scripts/player/classes/, `extends Player`);
## Player.create(class_data) instantiates it.

const CLASS_DIR := "res://resources/classes/"
const DEFAULT_ID: StringName = &"runebreaker"

@export var id: StringName = &""
@export var display_name: String = ""
## M10: the co-op role in a word ("Tank", "Damage", "Healer").
@export var role: String = ""
@export_multiline var description: String = ""
## M10: the hero script (extends Player) with this class's ability code.
@export var hero_script: Script = null
## Every ability of the class (basic attack first, then the pool in trainer order).
@export var abilities: Array[AbilityData] = []
## M10: the fixed LMB ability; every other ability goes into a free slot.
@export var basic_attack: StringName = &""
## Ability ids a fresh character starts with (the rest are learned).
@export var starting_abilities: Array[StringName] = []
## Talent branch display names and colour roles, indexed by TalentData.Branch.
@export var talent_branches: Array[String] = ["Storm", "Ember", "Runic Warden"]
@export var talent_colors: Array[String] = ["lightning", "fire", "frost"]
@export var rig_path: String = ""
@export var material_id: String = ""
## M10: a tint over the body atlas while a class borrows another class's rig.
@export var body_tint: Color = Color.WHITE
## Health at level 1 before gear (M10: the tank is sturdier, the caster frailer).
@export var base_max_hp: float = 100.0
## The class resource (Runebreaker: Resonance, Elementalist: Aether) and the
## art_spec colour role of its HUD bar and rig glow.
@export var resource_label: String = "Resonance"
@export var resource_color_role: String = "resonance"
@export var max_resource: float = 100.0
## M10 bots: how far from its target this class likes to fight.
@export var preferred_range: float = 1.4
## M10: the Runehold trainer of this class and where to find them.
@export var trainer_name: String = ""
@export var trainer_spot_hint: String = ""

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
