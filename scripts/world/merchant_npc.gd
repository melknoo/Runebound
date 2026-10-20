class_name MerchantNpc
extends Npc
## M10b: Ylva Ashbrew in Runehold sells consumables for gold (prices in
## Consumables.DEFS). Talking opens the zone's TrainerUI in its shop view (the
## same panel, so every other window closes it the same way). M14a: a story
## NPC too (`ylva`): [E] opens her dialogue while she has a topic, otherwise
## the shop; her flavour lines are in the text table.

const STORY_ID := "ylva"
const FLAVOUR_LINES := 3

## What she sells (Consumables ids, in shelf order).
@export var sells: Array[StringName] = [Consumables.HEALING_DRAUGHT, Consumables.EMBER_TUBER]  # M12: food too

var _visit := 0


func _init() -> void:
	npc_name = "Ylva Ashbrew"
	prompt_text = "Trade"


func _ready() -> void:
	super()
	add_to_group(&"story_npc")
	add_to_group(&"story_target")
	set_meta(&"story_id", STORY_ID)
	interacted.connect(_on_interacted)


func flavour_line() -> String:
	return Texts.t("dlg.%s.flavour.%d" % [STORY_ID, _visit % FLAVOUR_LINES])


func _on_interacted(player: Player) -> void:
	var zone := get_tree().current_scene as ZoneBase
	if zone != null and zone.dialogue_ui != null and zone.dialogue_ui.try_open(STORY_ID, self, player, true):
		return  # M14a: a story topic first
	open_panel(player)


## The shop (also the dialogue's "Show me your wares").
func open_panel(player: Player) -> void:
	var zone := get_tree().current_scene as ZoneBase
	if zone == null or zone.trainer_ui == null:
		return
	zone.trainer_ui.open(self, player)
	_visit += 1
