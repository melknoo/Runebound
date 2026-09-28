class_name PlaytestLog
extends Object
## The in-game playtest log (user 2026-09-28: "a quest log for everything in
## KNOWN_ISSUES I still have to test, to tick off"). The checklist is data in
## the repo (resources/playtest/checklist.json, built from the open playtest
## points of docs/KNOWN_ISSUES.md); the ticks live per machine in
## user://playtest.json, keyed by item id: {state: open|ok|problem, note, at}.
## Claude reads that file to work the problems off.

const CHECKLIST := "res://resources/playtest/checklist.json"
const OPEN := "open"
const OK := "ok"
const PROBLEM := "problem"

static var state_path := "user://playtest.json"  # tests point it elsewhere
static var _groups: Array = []
static var _state: Dictionary = {}
static var _loaded := false


## [{id, title, items: [{id, title, hint, src}]}] in display order.
static func groups() -> Array:
	_ensure()
	return _groups


static func item_ids() -> Array[String]:
	var out: Array[String] = []
	for g: Dictionary in groups():
		for it: Dictionary in g.get("items", []):
			out.append(str(it.get("id", "")))
	return out


static func state_of(id: String) -> String:
	_ensure()
	return str((_state.get(id, {}) as Dictionary).get("state", OPEN))


static func note_of(id: String) -> String:
	_ensure()
	return str((_state.get(id, {}) as Dictionary).get("note", ""))


## Sets and saves at once (ok / problem / open; the note stays with problems).
static func set_state(id: String, state: String, note: String = "") -> void:
	_ensure()
	if state == OPEN:
		_state.erase(id)
	else:
		_state[id] = {"state": state, "note": note if state == PROBLEM else "",
			"at": Time.get_datetime_string_from_system(false, true)}
	_save()


static func set_note(id: String, note: String) -> void:
	if state_of(id) == PROBLEM:
		set_state(id, PROBLEM, note)


## open -> ok -> problem -> open
static func next_state(state: String) -> String:
	match state:
		OPEN:
			return OK
		OK:
			return PROBLEM
	return OPEN


## {total, ok, problem, open} over the current checklist (ticks of items that
## are no longer listed do not count).
static func counts(group_id: String = "") -> Dictionary:
	var c := {"total": 0, "ok": 0, "problem": 0, "open": 0}
	for g: Dictionary in groups():
		if group_id != "" and str(g.get("id", "")) != group_id:
			continue
		for it: Dictionary in g.get("items", []):
			c["total"] += 1
			c[state_of(str(it.get("id", "")))] += 1
	return c


## Tests: forget what is loaded (after pointing state_path elsewhere).
static func reload() -> void:
	_loaded = false
	_ensure()


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CHECKLIST))
	_groups = (parsed as Dictionary).get("groups", []) if parsed is Dictionary else []
	_state = {}
	if FileAccess.file_exists(state_path):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(state_path))
		if saved is Dictionary:
			_state = (saved as Dictionary).get("items", {}) if (saved as Dictionary).get("items") is Dictionary else {}


static func _save() -> void:
	var f := FileAccess.open(state_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"version": 1, "items": _state}, "\t"))
	f.close()
