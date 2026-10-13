class_name PuzzleInputs
extends Object
## M13b: what a gate, a water channel or a beam waits on, read the same way
## everywhere (it was copied into all three). The layout's `inputs` list is
## AND: every entry must hold. An entry is a puzzle id (`PoiPuzzle.is_active`)
## or `flag:<name>` (a world flag); an entry that is itself a list holds when
## ANY of its entries does (the Stormwatch's split paths: the other wing's
## plate held, or the lever on the far side pulled).


## The layout's raw list as entries (Strings, or Arrays of Strings).
static func parse(raw: Variant) -> Array:
	var out: Array = []
	if not raw is Array:
		return out
	for entry: Variant in raw as Array:
		if entry is Array:
			var any_of: Array[String] = []
			for e: Variant in entry as Array:
				any_of.append(String(e))
			out.append(any_of)
		else:
			out.append(String(entry))
	return out


## Does every entry hold? (An empty list holds.)
static func holds(inputs: Array, puzzles: Dictionary) -> bool:
	for entry: Variant in inputs:
		if not _entry_holds(entry, puzzles):
			return false
	return true


static func _entry_holds(entry: Variant, puzzles: Dictionary) -> bool:
	if entry is Array:
		for e: Variant in entry as Array:
			if _one_holds(String(e), puzzles):
				return true
		return false
	return _one_holds(String(entry), puzzles)


static func _one_holds(input: String, puzzles: Dictionary) -> bool:
	if input.begins_with("flag:"):
		return SaveGame.has_flag(StringName(input.trim_prefix("flag:")))
	var p := puzzles.get(input) as PoiPuzzle
	return p != null and p.is_active()


## Every puzzle id the entries name (flags left out), flat - who to listen to.
static func ids(inputs: Array) -> Array[String]:
	var out: Array[String] = []
	for entry: Variant in inputs:
		var names: Array = entry as Array if entry is Array else [entry]
		for e: Variant in names:
			var s := String(e)
			if not s.begins_with("flag:") and not s in out:
				out.append(s)
	return out
