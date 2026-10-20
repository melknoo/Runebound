class_name QuestLog
extends RefCounted
## M14a: one hero's story (STORY_DESIGN "The campaign"): the act, beats (story
## facts that stay true: "legacy", "boss:colossus", "act1_done"), the running
## quests (step index + counter), the finished ones, the tracked quest, the
## camera pans seen, dialogue choices and quests waiting to start. Saved per
## character under `characters[i].story` (SaveGame.character_dict), so it
## travels into co-op sessions: online the world flags are the server's, which
## is why no quest goal ever reads a world flag.
##
## It hangs on the hero as meta (`QuestLog.of(hero)`; player.gd belongs to
## Rig v3). A character without a saved story keeps an inactive log: lab
## heroes, bots, net-test and server-side heroes never start or advance quests.
## Only the local hero's QuestDirector feeds it events; a co-op server just
## reads proxies' logs (StoryBosses).

signal changed
signal quest_started(id: String)
signal step_done(id: String, step: String)
signal quest_done(id: String)

const META := &"quest_log"
const FORMAT := 1

var active: bool = false
var act: int = 0
var beats: PackedStringArray = PackedStringArray()
## quest id -> {"s": step index, "n": counter of the current step}
var quests: Dictionary = {}
var done: PackedStringArray = PackedStringArray()
var tracked: String = ""
var seen: PackedStringArray = PackedStringArray()
var choices: Dictionary = {}
var pending: PackedStringArray = PackedStringArray()

## The hero this log was last used with (rewards, retroactive checks).
var _hero_ref: WeakRef = null


static func of(hero: Object) -> QuestLog:
	if hero == null:
		return null
	if not hero.has_meta(META):
		hero.set_meta(META, QuestLog.new())
	return hero.get_meta(META) as QuestLog


func hero() -> Player:
	return _hero_ref.get_ref() as Player if _hero_ref != null else null


func bind(p: Player) -> void:
	_hero_ref = weakref(p) if p != null else null


# ---------------------------------------------------------------------------
# Save
# ---------------------------------------------------------------------------

## {} for an inactive log (the save then has no `story` key at all).
func to_dict() -> Dictionary:
	if not active:
		return {}
	return {"v": FORMAT, "act": act, "beats": Array(beats), "quests": quests.duplicate(true), "done": Array(done),
		"tracked": tracked, "seen": Array(seen), "choices": choices.duplicate(true), "pending": Array(pending)}


func from_dict(d: Variant) -> void:
	active = d is Dictionary and not (d as Dictionary).is_empty()
	var data: Dictionary = d if d is Dictionary else {}
	act = int(data.get("act", 0))
	beats = PackedStringArray(data.get("beats", []))
	quests = {}
	var q: Variant = data.get("quests", {})
	if q is Dictionary:
		for id: Variant in q:
			var entry: Variant = (q as Dictionary)[id]
			if entry is Dictionary:
				quests[str(id)] = {"s": int((entry as Dictionary).get("s", 0)), "n": int((entry as Dictionary).get("n", 0))}
	done = PackedStringArray(data.get("done", []))
	tracked = str(data.get("tracked", ""))
	seen = PackedStringArray(data.get("seen", []))
	var c: Variant = data.get("choices", {})
	choices = (c as Dictionary).duplicate(true) if c is Dictionary else {}
	pending = PackedStringArray(data.get("pending", []))
	changed.emit()


## A fresh story for a new character (SaveGame.new_character): act 0, the
## prologue waiting.
static func new_story() -> Dictionary:
	return {"v": FORMAT, "act": 0, "pending": ["p_ash_road"]}


## What skipping the prologue gives (a second character at creation, or one
## that goes online first): its level and gold, Act 1 with Sigrun waiting.
const PROLOGUE_LEVEL := 2
const PROLOGUE_GOLD := 40


static func skipped_story() -> Dictionary:
	return {"v": FORMAT, "act": 1, "beats": ["prologue_skipped", "runebound"], "done": ["p_ash_road"],
		"pending": ["a1_call"]}


## The prologue is over without being played (online first): Act 1 begins.
func skip_prologue() -> void:
	if act > 0 or done.has("p_ash_road"):
		return
	var d := skipped_story()
	quests.erase("p_ash_road")
	var at := pending.find("p_ash_road")
	if at >= 0:
		pending.remove_at(at)
	act = int(d["act"])
	for b: Variant in d["beats"]:
		if not beats.has(str(b)):
			beats.append(str(b))
	done.append("p_ash_road")
	for p: Variant in d["pending"]:
		if not pending.has(str(p)):
			pending.append(str(p))
	if tracked == "p_ash_road":
		tracked = ""
	_touched()


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

func has_beat(id: String) -> bool:
	return beats.has(id)


func is_done(id: String) -> bool:
	return done.has(id)


func is_running(id: String) -> bool:
	return quests.has(id)


## The running quest's current step index (-1 when it isn't running).
func step_index(id: String) -> int:
	return int((quests.get(id, {}) as Dictionary).get("s", -1))


func step_id(id: String) -> String:
	return str(StoryDB.step(id, step_index(id)).get("id", ""))


func counter(id: String) -> int:
	return int((quests.get(id, {}) as Dictionary).get("n", 0))


func current_step(id: String) -> Dictionary:
	return StoryDB.step(id, step_index(id))


## Running quests in a stable order: main before side, then file order.
func running() -> Array[String]:
	var out: Array[String] = []
	for kind in ["main", "side"]:
		for id in StoryDB.quest_ids():
			if quests.has(id) and str(StoryDB.quest(id).get("kind", "side")) == kind:
				out.append(id)
	for id: String in quests:  # quests the data no longer knows stay listed last
		if not out.has(id):
			out.append(id)
	return out


## The quest the tracker shows: the tracked one, else the first running main
## quest, else any running one ("" when nothing runs).
func shown_quest() -> String:
	if tracked != "" and quests.has(tracked):
		return tracked
	var all := running()
	return all[0] if not all.is_empty() else ""


func choice(key: String) -> String:
	return str(choices.get(key, ""))


# ---------------------------------------------------------------------------
# Changes
# ---------------------------------------------------------------------------

func add_beat(id: String) -> bool:
	if id == "" or beats.has(id):
		return false
	beats.append(id)
	_touched()
	_recheck_goal_type("beat")
	_recheck_goal_type("boss")
	return true


func set_act(n: int) -> void:
	if n != act:
		act = n
		_touched()


func mark_seen(id: String) -> bool:
	if id == "" or seen.has(id):
		return false
	seen.append(id)
	_touched()
	return true


func set_choice(key: String, value: String) -> void:
	choices[key] = value
	_touched()


func track(id: String) -> void:
	tracked = id if quests.has(id) else ""
	_touched()


## Can quest `id` start now (it exists, isn't running or done, its
## requirements hold)?
func can_start(id: String) -> bool:
	if not active or not StoryDB.has_quest(id) or quests.has(id) or done.has(id):
		return false
	return StoryCond.check(StoryDB.quest(id).get("requires", {}), self, hero())


## Starts quest `id` (or queues it in `pending` while it can't start yet).
## Steps whose goal already holds complete at once (retroactive goals).
func start(id: String, queue_if_blocked: bool = true) -> bool:
	if not active or quests.has(id) or done.has(id):
		return false
	if not can_start(id):
		if queue_if_blocked and not pending.has(id):
			pending.append(id)
			_touched()
		return false
	var at := pending.find(id)
	if at >= 0:
		pending.remove_at(at)
	quests[id] = {"s": 0, "n": 0}
	if tracked == "" or not quests.has(tracked) or str(StoryDB.quest(id).get("kind", "side")) == "main":
		tracked = id
	_touched()
	quest_started.emit(id)
	StoryEffects.apply(StoryDB.quest(id).get("on_start", []), hero(), self)  # a camera pan, a hint
	_check_current(id)
	return true


## Starts every pending quest that can start now.
func flush_pending() -> void:
	if not active:
		return
	for id in Array(pending):
		if can_start(str(id)):
			start(str(id))


## An event the director saw (kill, talk, read ...): counts it for every
## running quest whose current step waits for it.
func event(kind: String, id: String, data: Dictionary = {}) -> void:
	if not active:
		return
	for qid in running():
		if not quests.has(qid):
			continue
		var goal: Dictionary = current_step(qid).get("goal", {})
		if not _matches(goal, kind, id, data):
			continue
		if _retro_count(goal) >= 0:
			_check_current(qid)  # counted from the hero's own records
		else:
			(quests[qid] as Dictionary)["n"] = counter(qid) + 1
			_touched()
			if counter(qid) >= goal_count(goal):
				complete_step(qid)


## Completes the running quest's current step (its effects run, the next
## step starts and is checked at once; past the last step the quest is done).
func complete_step(qid: String) -> void:
	if not quests.has(qid):
		return
	var st := current_step(qid)
	var sid := str(st.get("id", ""))
	var next := step_index(qid) + 1
	quests[qid] = {"s": next, "n": 0}
	_touched()
	step_done.emit(qid, sid)
	StoryEffects.apply(st.get("effects", []), hero(), self)
	if not quests.has(qid):
		return  # an effect finished the quest some other way
	if next >= StoryDB.steps(qid).size():
		_finish(qid)
	else:
		_check_current(qid)


## How many events a goal needs.
static func goal_count(goal: Dictionary) -> int:
	if goal.has("count"):
		return maxi(int(goal["count"]), 1)
	var ids: Array = goal.get("ids", [])
	return maxi(ids.size(), 1)


## Progress of the running quest's current step as [have, need].
func progress(qid: String) -> Vector2i:
	var goal: Dictionary = current_step(qid).get("goal", {})
	var need := goal_count(goal)
	var retro := _retro_count(goal)
	var have := retro if retro >= 0 else counter(qid)
	return Vector2i(mini(have, need), need)


func _finish(qid: String) -> void:
	quests.erase(qid)
	if not done.has(qid):
		done.append(qid)
	if tracked == qid:
		tracked = ""
	_touched()
	var q := StoryDB.quest(qid)
	var rewards: Variant = q.get("rewards", {})
	if rewards is Dictionary and not (rewards as Dictionary).is_empty():
		StoryEffects.apply([{"give": rewards}], hero(), self)
	quest_done.emit(qid)
	StoryEffects.apply(q.get("on_done", []), hero(), self)
	if tracked == "":
		tracked = shown_quest()
	flush_pending()


## Re-checks the current step of `qid` against the hero's own records.
func _check_current(qid: String) -> void:
	if not quests.has(qid):
		return
	var goal: Dictionary = current_step(qid).get("goal", {})
	var have := _retro_count(goal)
	if have >= 0 and have >= goal_count(goal):
		complete_step(qid)


## Re-checks every running quest whose current step has a goal of `type`.
func _recheck_goal_type(type: String) -> void:
	for qid in running():
		if str((current_step(qid).get("goal", {}) as Dictionary).get("type", "")) == type:
			_check_current(qid)


## Re-checks every running quest (after a restore, a level, a chronicle entry).
func recheck_all() -> void:
	if not active:
		return
	for qid in running():
		_check_current(qid)
	flush_pending()


## For goals the hero's records answer by themselves (collect, read, level,
## beat, boss, attune): how many already hold; -1 for counted goals.
func _retro_count(goal: Dictionary) -> int:
	var h := hero()
	match str(goal.get("type", "")):
		"beat":
			return 1 if has_beat(str(goal.get("id", ""))) else 0
		"boss":
			return 1 if has_beat("boss:" + str(goal.get("enemy", ""))) else 0
		"level":
			return 1 if h != null and h.progression.level >= int(goal.get("min", 1)) else 0
		"collect":
			return _count_in(h.collected if h != null else PackedStringArray(), goal)
		"read":
			return _count_in(h.lore_read if h != null else PackedStringArray(), goal)
		"attune":
			return 1 if h != null and h.discovered_waypoints.has(str(goal.get("waypoint", ""))) else 0
	return -1


static func _count_in(have: PackedStringArray, goal: Dictionary) -> int:
	var n := 0
	var ids: Array = goal.get("ids", [])
	var prefix := str(goal.get("prefix", ""))
	for entry in have:
		if (not ids.is_empty() and ids.has(String(entry))) or (prefix != "" and String(entry).begins_with(prefix)):
			n += 1
	return n


static func _matches(goal: Dictionary, kind: String, id: String, data: Dictionary) -> bool:
	var type := str(goal.get("type", ""))
	if type != kind:
		# records-based goals re-check on their own events
		return (type == "collect" and kind == "collect") or (type == "read" and kind == "read") \
			or (type == "level" and kind == "level") or (type == "attune" and kind == "attune") \
			or (type == "boss" and kind == "beat") or (type == "beat" and kind == "beat")
	if goal.has("zone") and data.has("zone") and str(goal["zone"]) != str(data["zone"]):
		return false
	match type:
		"talk":
			return str(goal.get("npc", "")) == id
		"kill":
			var enemies: Array = goal.get("enemies", [])
			if not enemies.is_empty() and not enemies.has(id):
				return false
			if goal.has("area") and str(goal["area"]) != str(data.get("area", "")):
				return false
			return not bool(goal.get("elite", false)) or bool(data.get("elite", false))
		"reach":
			return str(goal.get("poi", goal.get("marker", goal.get("area", "")))) == id
		"enter":
			return str(goal.get("zone", "")) == id
		"interact":
			return str(goal.get("marker", "")) == id
	return true


func _touched() -> void:
	changed.emit()
	if hero() != null:
		SaveGame.request_save()
