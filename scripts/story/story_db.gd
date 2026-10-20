class_name StoryDB
extends Object
## M14a: the story's data (STORY_DESIGN "The campaign"), read once from JSON
## under res://resources/story/: quests/*.json ({"quests": [...]}), dialogue
## per NPC (dialogue/<npc>.json), npcs.json, stage.json and cutscenes.json.
## Texts live in the text table (resources/i18n/story/), the files here hold
## only ids, keys and structure. `problems()` checks every reference (tests).

const DIR := "res://resources/story"

## Goal types a quest step may use (QuestLog evaluates them).
const GOALS: Array[String] = ["talk", "kill", "boss", "collect", "read", "reach", "enter", "interact", "level",
	"beat", "attune"]

static var _quests: Dictionary = {}       # id -> quest dict
static var _quest_order: Array[String] = []
static var _dialogue: Dictionary = {}     # npc id -> dialogue dict
static var _npcs: Dictionary = {}         # npc id -> npc dict
static var _stage: Array = []             # stage entries
static var _cutscenes: Dictionary = {}    # id -> cutscene dict
static var _loaded: bool = false
static var _load_errors: Array[String] = []


static func ensure() -> void:
	if _loaded:
		return
	_loaded = true
	_quests = {}
	_quest_order = []
	_dialogue = {}
	_npcs = {}
	_stage = []
	_cutscenes = {}
	_load_errors = []
	for file in _json_files(DIR + "/quests"):
		var data := _read(file)
		for q: Variant in data.get("quests", []):
			if q is Dictionary and str((q as Dictionary).get("id", "")) != "":
				var qid := str((q as Dictionary)["id"])
				if _quests.has(qid):
					_load_errors.append("quest %s twice (%s)" % [qid, file])
				_quests[qid] = q
				_quest_order.append(qid)
	for file in _json_files(DIR + "/dialogue"):
		var d := _read(file)
		var npc := str(d.get("npc", file.get_file().get_basename()))
		_dialogue[npc] = d
	_npcs = _read(DIR + "/npcs.json").get("npcs", {}) as Dictionary
	_stage = _read(DIR + "/stage.json").get("stage", []) as Array
	_cutscenes = _read(DIR + "/cutscenes.json").get("cutscenes", {}) as Dictionary


## Tests: a quest that exists for this run only (reload() drops it).
static func add_test_quest(q: Dictionary) -> void:
	ensure()
	var qid := str(q.get("id", ""))
	if not _quests.has(qid):
		_quest_order.append(qid)
	_quests[qid] = q


## Forget everything (tests that swap data; a language switch never needs it).
static func reload() -> void:
	_loaded = false
	ensure()


static func quest(id: String) -> Dictionary:
	ensure()
	return _quests.get(id, {}) as Dictionary


static func has_quest(id: String) -> bool:
	ensure()
	return _quests.has(id)


## Every quest id in file order (the journal sorts by act and kind itself).
static func quest_ids() -> Array[String]:
	ensure()
	return _quest_order.duplicate()


static func steps(id: String) -> Array:
	return quest(id).get("steps", []) as Array


static func step(id: String, index: int) -> Dictionary:
	var all := steps(id)
	return all[index] as Dictionary if index >= 0 and index < all.size() else {}


static func dialogue(npc: String) -> Dictionary:
	ensure()
	return _dialogue.get(npc, {}) as Dictionary


static func npc(id: String) -> Dictionary:
	ensure()
	return _npcs.get(id, {}) as Dictionary


static func npc_ids() -> Array:
	ensure()
	return _npcs.keys()


static func stage() -> Array:
	ensure()
	return _stage


static func cutscene(id: String) -> Dictionary:
	ensure()
	return _cutscenes.get(id, {}) as Dictionary


static func cutscene_ids() -> Array:
	ensure()
	return _cutscenes.keys()


## Every text key the story data names (tests: each one exists in DE and EN).
static func text_keys() -> Array[String]:
	ensure()
	var out: Array[String] = []
	for qid: String in _quests:
		var q: Dictionary = _quests[qid]
		for k in ["title", "summary"]:
			if q.has(k):
				out.append(str(q[k]))
		for s: Variant in q.get("steps", []):
			if s is Dictionary and (s as Dictionary).has("text"):
				out.append(str((s as Dictionary)["text"]))
	for npc_id: Variant in _dialogue:
		var nodes: Dictionary = (_dialogue[npc_id] as Dictionary).get("nodes", {})
		for nid: Variant in nodes:
			var node: Dictionary = nodes[nid]
			if node.has("say"):
				out.append(str(node["say"]))
			for k: Variant in node.get("say_pool", []):
				out.append(str(k))
			for opt: Variant in node.get("options", []):
				if opt is Dictionary and (opt as Dictionary).has("text"):
					out.append(str((opt as Dictionary)["text"]))
	for nid: Variant in _npcs:
		var n: Dictionary = _npcs[nid]
		if n.has("name"):
			out.append(str(n["name"]))
	for cid: Variant in _cutscenes:
		var c: Dictionary = _cutscenes[cid]
		for shot: Variant in c.get("shots", []):
			if shot is Dictionary and (shot as Dictionary).has("say"):
				out.append(str((shot as Dictionary)["say"]))
		var card: Variant = c.get("card", {})
		if card is Dictionary:
			for k in ["title", "sub"]:
				if (card as Dictionary).has(k):
					out.append(str((card as Dictionary)[k]))
	return out


## Everything wrong with the data: unknown goal types, references to quests,
## NPCs, dialogue nodes or cutscenes that don't exist, missing texts.
static func problems() -> Array[String]:
	ensure()
	var out: Array[String] = _load_errors.duplicate()
	for qid: String in _quests:
		var q: Dictionary = _quests[qid]
		var st: Array = q.get("steps", [])
		if st.is_empty():
			out.append("quest %s has no steps" % qid)
		for s: Variant in st:
			if s is not Dictionary:
				out.append("quest %s: a step is not an object" % qid)
				continue
			var goal: Dictionary = (s as Dictionary).get("goal", {})
			if not str(goal.get("type", "")) in GOALS:
				out.append("quest %s step %s: unknown goal '%s'" % [qid, (s as Dictionary).get("id", "?"), goal.get("type", "")])
			if str(goal.get("type", "")) == "talk" and not _npcs.has(str(goal.get("npc", ""))):
				out.append("quest %s: talk to unknown npc %s" % [qid, goal.get("npc", "")])
		for req: Variant in (q.get("requires", {}) as Dictionary).get("done", []):
			if not _quests.has(str(req)):
				out.append("quest %s requires unknown quest %s" % [qid, req])
		out.append_array(effect_problems(q.get("on_done", []), "quest " + qid))
	for npc_id: Variant in _dialogue:
		var d: Dictionary = _dialogue[npc_id]
		var nodes: Dictionary = d.get("nodes", {})
		if not _npcs.has(str(npc_id)) and not _marker_ids().has(str(npc_id)):
			out.append("dialogue for unknown npc or marker %s" % npc_id)
		for entry: Variant in d.get("entries", []):
			var start := str((entry as Dictionary).get("start", ""))
			if not nodes.has(start):
				out.append("dialogue %s: entry starts at unknown node %s" % [npc_id, start])
		for nid: Variant in nodes:
			var node: Dictionary = nodes[nid]
			var where := "dialogue %s.%s" % [npc_id, nid]
			if not node.has("say") and not node.has("say_pool"):
				out.append(where + " says nothing")
			if node.has("next") and not nodes.has(str(node["next"])):
				out.append(where + " -> unknown node " + str(node["next"]))
			out.append_array(effect_problems(node.get("effects", []), where))
			var opts: Array = node.get("options", [])
			if opts.is_empty() and not node.has("next") and not bool(node.get("end", false)):
				out.append(where + " is a dead end (no next, no options, no end)")
			for opt: Variant in opts:
				var o: Dictionary = opt
				if o.has("next") and not nodes.has(str(o["next"])):
					out.append(where + " option -> unknown node " + str(o["next"]))
				if not o.has("next") and not bool(o.get("end", false)):
					out.append(where + " option leads nowhere")
				out.append_array(effect_problems(o.get("effects", []), where))
	for entry: Variant in _stage:
		var e: Dictionary = entry
		if e.has("npc") and not _npcs.has(str(e["npc"])):
			out.append("stage %s: unknown npc %s" % [e.get("id", "?"), e["npc"]])
	for cid: Variant in _cutscenes:
		out.append_array(effect_problems((_cutscenes[cid] as Dictionary).get("on_end", []), "cutscene " + str(cid)))
	for key in text_keys():
		if not Texts.has(key):
			out.append("missing text " + key)
	return out


static func effect_problems(effects: Variant, where: String) -> Array[String]:
	var out: Array[String] = []
	if effects is not Array:
		return out
	for eff: Variant in effects:
		if eff is not Dictionary:
			out.append(where + ": an effect is not an object")
			continue
		var e: Dictionary = eff
		if e.has("start") and not _quests.has(str(e["start"])):
			out.append(where + ": starts unknown quest " + str(e["start"]))
		if e.has("cutscene") and not _cutscenes.has(str(e["cutscene"])):
			out.append(where + ": plays unknown cutscene " + str(e["cutscene"]))
		if not StoryEffects.KINDS.has(e.keys()[0] if not e.is_empty() else ""):
			out.append(where + ": unknown effect " + str(e.keys()))
	return out


## Ids of the stage's story markers (a marker may have a dialogue file).
static func _marker_ids() -> Array[String]:
	var out: Array[String] = []
	for entry: Variant in _stage:
		if entry is Dictionary and (entry as Dictionary).has("marker"):
			out.append(str((entry as Dictionary)["marker"]))
	return out


## Tests: a dialogue that exists for this run only (reload() drops it).
static func add_test_dialogue(id: String, d: Dictionary) -> void:
	ensure()
	_dialogue[id] = d


## Tests: an NPC that exists for this run only.
static func add_test_npc(id: String, d: Dictionary) -> void:
	ensure()
	_npcs[id] = d


static func _json_files(dir: String) -> Array[String]:
	var out: Array[String] = []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".json") and not f.begins_with("_"):
			out.append(dir + "/" + f)
	out.sort()
	return out


static func _read(file: String) -> Dictionary:
	if not FileAccess.file_exists(file):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
	if data is not Dictionary:
		_load_errors.append("%s is not a JSON object" % file)
		return {}
	return data as Dictionary
