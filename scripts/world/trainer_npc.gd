class_name TrainerNpc
extends Npc
## M07b: Sigrun Runewright, the Runehold trainer. Talking opens the zone's
## TrainerUI, which sells the class's TRAINER abilities for gold and level.
## The name and lines are placeholders until M11 gives her a story.

const FLAVOUR: Array[String] = [
	"Runes don't care how hard you swing. They care that you paid attention. And paid.",
	"Every rune I teach, I earned the same way you will: one scar at a time.",
	"Gold buys the lesson. The Highlands will test whether you listened.",
]

var _visit := 0


func _init() -> void:
	npc_name = "Sigrun Runewright"
	prompt_text = "Talk"


func _ready() -> void:
	super()
	interacted.connect(_on_interacted)


func flavour_line() -> String:
	return FLAVOUR[_visit % FLAVOUR.size()]


func _on_interacted(player: Player) -> void:
	var zone := get_tree().current_scene as ZoneBase
	if zone == null or zone.trainer_ui == null:
		return
	zone.trainer_ui.open(self, player)
	_visit += 1
