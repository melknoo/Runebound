class_name MerchantNpc
extends Npc
## M10b: Ylva Ashbrew in Runehold sells consumables for gold (prices in
## Consumables.DEFS). Talking opens the zone's TrainerUI in its shop view (the
## same panel, so every other window closes it the same way). Name and lines
## are placeholders until M14 gives Runehold its people.

const FLAVOUR := [
	"Ashroot, emberleaf, a spoon of honey. Drink it slow - it works slow.",
	"Sigrun's warriors come back bleeding, Maren's come back singed. Both pay.",
	"No brew brings back the dead. That's the shrine's business, not mine.",
]

## What she sells (Consumables ids, in shelf order).
@export var sells: Array[StringName] = [Consumables.HEALING_DRAUGHT, Consumables.EMBER_TUBER]  # M12: food too

var _visit := 0


func _init() -> void:
	npc_name = "Ylva Ashbrew"
	prompt_text = "Trade"


func _ready() -> void:
	super()
	interacted.connect(_on_interacted)


func flavour_line() -> String:
	return str(FLAVOUR[_visit % FLAVOUR.size()])


func _on_interacted(player: Player) -> void:
	var zone := get_tree().current_scene as ZoneBase
	if zone == null or zone.trainer_ui == null:
		return
	zone.trainer_ui.open(self, player)
	_visit += 1
