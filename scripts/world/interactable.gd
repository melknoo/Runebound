class_name Interactable
extends Node3D
## M12: the shared base of things a hero uses with [E] - lore objects, the
## rune shards, gather nodes, ghosts (and the M12 puzzles, shrines and the
## tome after them). Subclasses say what the prompt reads (`prompt_text`,
## "" = none), whether this hero may use it (`can_interact`) and what happens
## (`interact`). Only the local hero uses things here: each machine reads its
## own lore and gathers its own food; world-changing ones (puzzles) ask the
## server themselves. Ticks only within TICK_RANGE of the local hero.

const TICK_RANGE := 20.0

## Reach of the prompt (metres from this node's origin).
@export var reach: float = 2.4
## Height of the prompt above the origin.
@export var prompt_height: float = 1.4
## The layout id this thing was built from (save keys, tests, the map).
var id: String = ""

var _prompt: InteractPrompt


func _ready() -> void:
	_prompt = InteractPrompt.create(self, prompt_height)


## What the prompt says for `hero` ("" hides it).
func prompt_text(_hero: Player) -> String:
	return ""


func can_interact(_hero: Player) -> bool:
	return true


func interact(_hero: Player) -> void:
	pass


func _process(_delta: float) -> void:
	var zone := ZoneBase.zone_of(self)
	var hero := zone.player if zone != null else null
	if hero == null or not is_instance_valid(hero):
		_prompt.update(false, "")
		return
	var d := global_position.distance_to(hero.global_position)
	if d > TICK_RANGE or not is_visible_in_tree():  # M12: a hidden one (the priest before the curse lifts) waits
		if _prompt.visible:
			_prompt.update(false, "")
		return
	var text := prompt_text(hero) if d <= reach else ""
	_prompt.update(text != "" and can_interact(hero), text)
	if _prompt.pressed(hero):
		interact(hero)


## Tests and scripted runs: use it as `hero` would with [E] (no prompt needed).
func use_by(hero: Player) -> void:
	if can_interact(hero) and prompt_text(hero) != "":
		interact(hero)
