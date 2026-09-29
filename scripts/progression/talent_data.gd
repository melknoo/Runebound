class_name TalentData
extends Resource
## One talent node (M07). Data only: numeric nodes add `per_rank` x rank to a
## stat the player's hook points already read (Player.stat), behavior nodes
## grant a power id the ability code checks (Player.has_power). Tuning a
## node is a .tres edit in resources/talents/.

## A column of the class's tree (0-2); the names and colours are the class's
## (ClassData.talent_branches / talent_colors). The enum names are the
## Runebreaker-era labels, kept so the .tres files stay valid.
enum Branch { STORM, EMBER, WARDEN }

@export var id: StringName
@export var display_name: String
## M07b: the class whose tree this node belongs to (Progression.tree_for).
@export var class_id: StringName = &"runebreaker"
@export var branch: Branch = Branch.STORM
## 0 = opens at 0 points in the branch, 1 at 3, 2 at 6, 3 (capstone) at 10.
@export_range(0, 3) var tier: int = 0
@export_range(1, 5) var max_rank: int = 1
## Numeric effect: stat key (e.g. &"crit_pct") and its value per rank.
@export var stat: StringName = &""
@export var per_rank: float = 0.0
## Behavior effect: power id checked by the ability code (e.g. &"split_lance").
@export var power: StringName = &""
## "{value}" is replaced by per_rank x rank (or per rank before learning).
@export_multiline var description: String = ""

const TIER_POINTS: Array[int] = [0, 3, 6, 10]


func describe(rank: int) -> String:
	var shown := per_rank * maxi(rank, 1)
	var value := str(int(shown)) if is_equal_approx(shown, roundf(shown)) else "%.1f" % shown
	return description.replace("{value}", value)
