class_name TrainerNpc
extends Npc
## M07b: a Runehold trainer. Talking opens the zone's TrainerUI, which sells
## the TRAINER abilities of `teaches_class` for gold and level. M10: one
## trainer per class (ClassData.trainer_name); a hero of another class is
## pointed to its own. M14a: each trainer is a story NPC too - [E] opens its
## dialogue while it has a topic to tell (resources/story/dialogue/<id>.json),
## otherwise the panel straight away; its flavour lines are in the text table.

## The trainer of each class in the story's data (npcs.json, dialogue).
const STORY_IDS := {&"runebreaker": "sigrun", &"elementalist": "maren", &"druid": "hild"}
const FLAVOUR_LINES := 3

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
	add_to_group(&"story_npc")  # M14a: dialogue badges, quest markers
	add_to_group(&"story_target")
	set_meta(&"story_id", story_id())
	interacted.connect(_on_interacted)


## M14a: this trainer's id in the story's data.
func story_id() -> String:
	return str(STORY_IDS.get(teaches_class, "sigrun"))


## Does this trainer teach `player`'s class?
func teaches(player: Player) -> bool:
	return player != null and player.class_data != null and player.class_data.id == teaches_class


func flavour_line() -> String:
	return Texts.t("dlg.%s.flavour.%d" % [story_id(), _visit % FLAVOUR_LINES])


## What this trainer tells a hero of another class (who teaches it instead).
func referral_line(player: Player) -> String:
	var own := player.class_data
	var where := own.trainer_spot_hint if own.trainer_spot_hint != "" else "in Runehold"
	return "I don't teach the %s's way. %s does - %s." % [own.display_name, own.trainer_name, where]


func _on_interacted(player: Player) -> void:
	var zone := get_tree().current_scene as ZoneBase
	if zone != null and zone.dialogue_ui != null and zone.dialogue_ui.try_open(story_id(), self, player, true):
		return  # M14a: a story topic first; "Teach me" opens the panel from there
	open_panel(player)


## The trainer panel (also the dialogue's "Teach me").
func open_panel(player: Player) -> void:
	var zone := get_tree().current_scene as ZoneBase
	if zone == null or zone.trainer_ui == null:
		return
	zone.trainer_ui.open(self, player)
	_visit += 1
