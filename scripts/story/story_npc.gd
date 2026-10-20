class_name StoryNpc
extends Npc
## M14a: someone the story places (Edda by the hearth, a deserter at a ruin):
## built by the QuestDirector from `resources/story/stage.json` on this
## machine only (the server builds none; every player talks on their own
## machine). Looks come from `npcs.json` (a class rig, a tint, gear looks);
## talking opens its dialogue. A hidden one (its stage entry's `show_if` /
## `hide_if`) neither draws, collides nor listens.

## npcs.json id; also the dialogue file's name.
var story_id: String = ""
## The stage entry that placed it ({} for a test NPC).
var stage: Dictionary = {}
var shown: bool = true

var _body: StaticBody3D = null


## A story NPC from its npcs.json entry (not yet in the tree).
static func create(id: String) -> StoryNpc:
	var n := StoryNpc.new()
	n.story_id = id
	n.name = "StoryNpc_" + id
	var d := StoryDB.npc(id)
	n.npc_name = str(d.get("name", id))  # a text key: the nameplate translates itself
	n.prompt_text = Texts.t("ui.prompt.talk")
	var rig := str(d.get("rig", "runebreaker"))
	n.rig_path = "res://assets/models/chars/%s.glb" % rig
	n.material_id = rig
	if d.has("tint"):
		n.body_tint = Color(str(d["tint"]))
	if d.has("rune"):
		n.rune_color = Color(str(d["rune"]))
	var looks: Variant = d.get("looks", {})
	if looks is Dictionary:
		n.looks = (looks as Dictionary).duplicate()
	return n


func _ready() -> void:
	super()
	add_to_group(&"story_npc")
	add_to_group(&"story_target")
	set_meta(&"story_id", story_id)
	for child in get_children():
		if child is StaticBody3D:
			_body = child as StaticBody3D
	interacted.connect(_on_interacted)


func set_shown(on: bool) -> void:
	if on == shown:
		return
	shown = on
	visible = on
	if not on:
		_prompt.update(false, "")
	set_process(on)
	if _body != null:
		_body.collision_layer = 0b1 if on else 0


func _on_interacted(player: Player) -> void:
	var zone := ZoneBase.zone_of(self)
	if zone != null and zone.get(&"dialogue_ui") != null:
		zone.dialogue_ui.try_open(story_id, self, player)
