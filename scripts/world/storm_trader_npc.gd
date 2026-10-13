class_name StormTraderNpc
extends Npc
## M13b: Tova Stormward in Runehold trades storm shards (the Stormwatch's
## bosses give them) for the storm legendaries - two per class, sold only
## here (AffixPool.STORM_LEGENDARIES). Talking opens the zone's TrainerUI in
## her shelf view. Her lines are in the player's language; name and rig are
## placeholders until M14 gives Runehold its people.

const LINES := ["ui.storm_trader.line.0", "ui.storm_trader.line.1", "ui.storm_trader.line.2"]

var _visit := 0


func _init() -> void:
	npc_name = "Tova Stormward"
	prompt_text = Texts.t("ui.storm_trader.prompt")


func _ready() -> void:
	super()
	interacted.connect(_on_interacted)


func flavour_line() -> String:
	return Texts.t(LINES[_visit % LINES.size()])


func _on_interacted(player: Player) -> void:
	var zone := get_tree().current_scene as ZoneBase
	if zone == null or zone.trainer_ui == null:
		return
	zone.trainer_ui.open(self, player)
	_visit += 1
