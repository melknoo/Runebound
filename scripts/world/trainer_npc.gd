class_name TrainerNpc
extends Npc
## M07b: a Runehold trainer. Talking opens the zone's TrainerUI, which sells
## the TRAINER abilities of `teaches_class` for gold and level. M10: one
## trainer per class (ClassData.trainer_name); a hero of another class is
## pointed to its own. The names and lines are placeholders until M14 gives
## the trainers a story.

const FLAVOUR := {
	&"runebreaker": [
		"Runes don't care how hard you swing. They care that you paid attention. And paid.",
		"Every rune I teach, I earned the same way you will: one scar at a time.",
		"Stand in front. Hold. The ones behind you will do the rest.",
	],
	&"elementalist": [
		"Fire listens to patience. Lightning to nerve. Frost listens to nobody - you'll learn it anyway.",
		"Aether is borrowed, not owned. Spend it before it spends you.",
		"Sigrun teaches walls. I teach what the walls are for.",
	],
	&"druid": [
		"The ash remembers what grew here. I only remind it.",
		"Sap is patient. It won't rise for you while you idle - only when the fight asks for it.",
		"Mend the one in front, and the one in front keeps you standing. That's the whole secret.",
	],
}

## The class whose abilities this trainer teaches (set before add_child).
@export var teaches_class: StringName = ClassData.DEFAULT_ID

var _visit := 0


func _init() -> void:
	prompt_text = "Talk"


func _ready() -> void:
	var cls := ClassData.load_by_id(teaches_class)
	if cls != null and cls.trainer_name != "":
		npc_name = cls.trainer_name
	super()
	interacted.connect(_on_interacted)


## Does this trainer teach `player`'s class?
func teaches(player: Player) -> bool:
	return player != null and player.class_data != null and player.class_data.id == teaches_class


func flavour_line() -> String:
	var lines: Array = FLAVOUR.get(teaches_class, FLAVOUR[ClassData.DEFAULT_ID])
	return str(lines[_visit % lines.size()])


## What this trainer tells a hero of another class (who teaches it instead).
func referral_line(player: Player) -> String:
	var own := player.class_data
	var where := own.trainer_spot_hint if own.trainer_spot_hint != "" else "in Runehold"
	return "I don't teach the %s's way. %s does - %s." % [own.display_name, own.trainer_name, where]


func _on_interacted(player: Player) -> void:
	var zone := get_tree().current_scene as ZoneBase
	if zone == null or zone.trainer_ui == null:
		return
	zone.trainer_ui.open(self, player)
	_visit += 1
