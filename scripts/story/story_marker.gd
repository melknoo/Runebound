class_name StoryMarker
extends Interactable
## M14a: a place the story wants looked at (the empty socket in the Spire, a
## cord by the graves): [E] "Look" counts an `interact` goal and, when the
## marker has a dialogue file of its own (resources/story/dialogue/<id>.json),
## opens it (the inscription, the hero's thoughts). Placed by the
## QuestDirector from stage.json on this machine only; a hidden one waits.
## Optionally shows a story prop (`prop` in its stage entry, an ArtKit model).

var story_id: String = ""
var stage: Dictionary = {}
var shown: bool = true


static func create(entry: Dictionary) -> StoryMarker:
	var m := StoryMarker.new()
	m.story_id = str(entry.get("marker", ""))
	m.id = m.story_id
	m.name = "StoryMarker_" + m.story_id
	m.stage = entry
	m.reach = float(entry.get("reach", 2.4))
	m.prompt_height = float(entry.get("prompt_height", 1.3))
	return m


func _ready() -> void:
	super()
	add_to_group(&"story_target")
	set_meta(&"story_id", story_id)


func set_shown(on: bool) -> void:
	shown = on
	visible = on


func prompt_text(_hero: Player) -> String:
	return Texts.t(str(stage.get("prompt", "ui.prompt.inspect"))) if shown else ""


func interact(hero: Player) -> void:
	var zone := ZoneBase.zone_of(self)
	QuestLog.of(hero).event("interact", story_id)
	if zone != null and zone.dialogue_ui != null and not StoryDB.dialogue(story_id).is_empty():
		zone.dialogue_ui.try_open(story_id, self, hero)
