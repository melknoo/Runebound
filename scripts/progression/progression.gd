class_name Progression
extends Node
## M07 character progression (docs/PROGRESSION_DESIGN.md): XP and levels up to
## LEVEL_CAP, one talent point per level, respec at any time. Feeds the same
## hook points as equipment: Player.stat() sums both, Player.has_power()
## checks both. Talent data: resources/talents/ (tools/talents/).

signal xp_changed(xp: int, needed: int, level: int)
signal leveled_up(level: int)
signal talents_changed

const LEVEL_CAP := 25
const HP_PER_LEVEL := 6.0
const DAMAGE_PCT_PER_LEVEL := 2.0
const TALENT_DIR := "res://resources/talents/"

var level: int = 1
var xp: int = 0  # progress into the current level
var ranks: Dictionary = {}  # talent id (StringName) -> rank
## M07b: the class whose tree this character spends points in (Player sets it).
var class_id: StringName = ClassData.DEFAULT_ID

var _stats: Dictionary = {}
var _powers: Array[StringName] = []

static var _tree: Array[TalentData] = []


## XP needed to go from `lvl` to `lvl + 1`.
static func xp_to_next(lvl: int) -> int:
	return int(round(80.0 * pow(float(lvl), 1.6)))


## Every talent node, ordered by branch, tier, id.
static func tree() -> Array[TalentData]:
	if _tree.is_empty():
		for file in DirAccess.get_files_at(TALENT_DIR):
			var res_name := file.trim_suffix(".remap")  # exported builds list .tres.remap
			if not res_name.ends_with(".tres"):
				continue
			var t := load(TALENT_DIR + res_name) as TalentData
			if t != null:
				_tree.append(t)
		_tree.sort_custom(func(a: TalentData, b: TalentData) -> bool:
			if a.branch != b.branch:
				return a.branch < b.branch
			if a.tier != b.tier:
				return a.tier < b.tier
			return String(a.id) < String(b.id)
		)
	return _tree


## The nodes of one class's tree (M07b), in tree() order.
static func tree_for(cid: StringName) -> Array[TalentData]:
	var out: Array[TalentData] = []
	for t in tree():
		if t.class_id == cid:
			out.append(t)
	return out


static func talent(id: StringName) -> TalentData:
	for t in tree():
		if t.id == id:
			return t
	return null


static func clear_cache() -> void:
	_tree.clear()


func _ready() -> void:
	_recompute()


func add_xp(amount: int) -> void:
	if amount <= 0 or level >= LEVEL_CAP:
		return
	xp += amount
	var gained := 0
	while level < LEVEL_CAP and xp >= xp_to_next(level):
		xp -= xp_to_next(level)
		level += 1
		gained += 1
	if level >= LEVEL_CAP:
		xp = 0
	if gained > 0:
		_recompute()
	xp_changed.emit(xp, xp_to_next(level), level)
	if gained > 0:
		leveled_up.emit(level)
		talents_changed.emit()


func points_total() -> int:
	return level - 1


func points_spent() -> int:
	var total := 0
	for id: StringName in ranks:
		total += int(ranks[id])
	return total


func points_free() -> int:
	return points_total() - points_spent()


func rank(id: StringName) -> int:
	return int(ranks.get(id, 0))


## Points spent in `branch` on tiers strictly below `tier` (what opens a tier).
func spent_below(branch: TalentData.Branch, tier: int) -> int:
	var total := 0
	for id: StringName in ranks:
		var t := talent(id)
		if t != null and t.branch == branch and t.tier < tier:
			total += int(ranks[id])
	return total


func tier_open(t: TalentData) -> bool:
	return spent_below(t.branch, t.tier) >= TalentData.TIER_POINTS[t.tier]


func can_learn(t: TalentData) -> bool:
	return t != null and points_free() > 0 and rank(t.id) < t.max_rank and tier_open(t)


func learn(t: TalentData) -> bool:
	if not can_learn(t):
		return false
	ranks[t.id] = rank(t.id) + 1
	_changed()
	return true


## A rank may go if every higher node of its branch keeps its tier open.
func can_unlearn(t: TalentData) -> bool:
	if t == null or rank(t.id) <= 0:
		return false
	ranks[t.id] = rank(t.id) - 1
	var ok := true
	for id: StringName in ranks:
		var u := talent(id)
		if u != null and int(ranks[id]) > 0 and u.branch == t.branch and u.tier > t.tier and not tier_open(u):
			ok = false
			break
	ranks[t.id] = rank(t.id) + 1
	return ok


func unlearn(t: TalentData) -> bool:
	if not can_unlearn(t):
		return false
	ranks[t.id] = rank(t.id) - 1
	if int(ranks[t.id]) <= 0:
		ranks.erase(t.id)
	_changed()
	return true


func respec() -> void:
	if ranks.is_empty():
		return
	ranks.clear()
	_changed()


## Level bonuses + talent stats for a Player.stat() key (0 when absent).
func stat(key: StringName) -> float:
	return _stats.get(key, 0.0)


func has_power(id: StringName) -> bool:
	return _powers.has(id)


func _changed() -> void:
	_recompute()
	talents_changed.emit()


func _recompute() -> void:
	_stats.clear()
	_powers.clear()
	_stats[&"max_hp"] = HP_PER_LEVEL * (level - 1)
	_stats[&"damage_pct"] = DAMAGE_PCT_PER_LEVEL * (level - 1)
	for id: StringName in ranks:
		var t := talent(id)
		if t == null:
			continue
		var r := int(ranks[id])
		if t.stat != &"":
			_stats[t.stat] = _stats.get(t.stat, 0.0) + t.per_rank * r
		if t.power != &"" and r > 0:
			_powers.append(t.power)


func to_dict() -> Dictionary:
	var talents := {}
	for id: StringName in ranks:
		talents[String(id)] = int(ranks[id])
	return {"level": level, "xp": xp, "talents": talents}


func from_dict(data: Dictionary) -> void:
	level = clampi(int(data.get("level", 1)), 1, LEVEL_CAP)
	xp = maxi(int(data.get("xp", 0)), 0)
	ranks.clear()
	var talents: Dictionary = data.get("talents", {})
	for key: String in talents:
		var t := talent(StringName(key))
		if t != null and t.class_id == class_id:  # another class's nodes never carry over
			ranks[t.id] = clampi(int(talents[key]), 0, t.max_rank)
	# a save from a bigger tree (or a hand edit) never keeps unaffordable ranks
	if points_free() < 0:
		ranks.clear()
	_recompute()
	xp_changed.emit(xp, xp_to_next(level), level)
	talents_changed.emit()
