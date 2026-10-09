class_name DungeonRegistry
extends Object
## M13: every dungeon behind a Highlands gate - its scene, baked layout, gate
## POI, enemy levels and name (a Texts key). A dungeon without a scene keeps
## its gate sealed (the Ember Warrens until they are built). `min_party` is
## the seam for the M13b co-op dungeon (heroes needed to enter); the normal
## dungeons take anyone.

const DUNGEONS := {
	"cistern": {
		"scene": "res://scenes/hollow_cistern.tscn",
		"layout": "res://assets/world/hollow_cistern",
		"gate": "dungeon_e",
		"exit": "ci_exit",
		"level": 3,
		"boss_level": 4,
		"recommended": 4,
		"name_key": "zone.hollow_cistern",
		"min_party": 1,
	},
	# the puzzle kit's test dungeon (tests only; no gate leads here)
	"lab": {
		"scene": "res://scenes/puzzle_lab.tscn",
		"layout": "res://assets/world/puzzle_lab",
		"gate": "",
		"exit": "lab_exit",
		"level": 1,
		"boss_level": 2,
		"recommended": 1,
		"name_key": "",
		"min_party": 1,
	},
	"warrens": {
		"scene": "",
		"layout": "",
		"gate": "dungeon_w",
		"exit": "wa_exit",
		"level": 4,
		"boss_level": 5,
		"recommended": 5,
		"name_key": "zone.ember_warrens",
		"min_party": 1,
	},
}


static func info(id: String) -> Dictionary:
	return DUNGEONS.get(id, {})


## The dungeon whose scene this is ("" for any other zone).
static func id_for_scene(scene_path: String) -> String:
	for id: String in DUNGEONS:
		if String(DUNGEONS[id]["scene"]) == scene_path and scene_path != "":
			return id
	return ""


## True when the dungeon can be entered (its scene exists).
static func is_open(id: String) -> bool:
	var scene := String(info(id).get("scene", ""))
	return scene != "" and ResourceLoader.exists(scene)


## Display name in the current language ("" for an unknown id).
static func title(id: String) -> String:
	var key := String(info(id).get("name_key", ""))
	return Texts.t(key) if key != "" else ""
