class_name DungeonRegistry
extends Object
## M13: every dungeon behind a Highlands gate - its scene, baked layout, gate
## POI, enemy levels and name (a Texts key). A dungeon without a scene keeps
## its gate sealed (the Ember Warrens did until M13 phase 6). `min_party` is
## the heroes needed to enter; the normal dungeons take anyone.
## M13b, the co-op dungeon (the Stormwatch):
##   min_party 3   - a party enters with 3 heroes or more (the gate, travel and
##                   the server check it); inside it may shrink
##   fresh_runs    - every entry is a new run: the world keys with the
##                   layout's prefix are cleared, camps never re-arm in a run
##   level_mode "party", min_level - enemy and loot level = the party's
##                   average level on entry (at least min_level), bosses +1
##   revive        - a fallen hero lies downed and can be revived (ReviveSystem)
##   shards        - storm shards each hero gets per boss, by the arena's
##                   reward kind (the storm trader in Runehold takes them)

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
		"revive": true,  # M13b: the co-op kit's tests (bots revive here too)
	},
	"warrens": {
		"scene": "res://scenes/ember_warrens.tscn",
		"layout": "res://assets/world/ember_warrens",
		"gate": "dungeon_w",
		"exit": "wa_exit",
		"level": 4,
		"boss_level": 5,
		"recommended": 5,
		"name_key": "zone.ember_warrens",
		"min_party": 1,
	},
	"stormwatch": {
		"scene": "res://scenes/stormwatch.tscn",
		"layout": "res://assets/world/stormwatch",
		"gate": "dungeon_se",
		"exit": "sw_exit",
		"prefix": "sw_",
		"level": 7,
		"boss_level": 8,
		"recommended": 7,
		"name_key": "zone.stormwatch",
		"min_party": 3,
		"fresh_runs": true,
		"revive": true,
		"level_mode": "party",
		"min_level": 7,
		"shards": {"mid": 3, "end": 6},  # M13b phase 7: storm shards per hero and boss
	},
}

const HIGHLANDS_SCENE := "res://scenes/ashen_highlands.tscn"


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


## M13b: heroes a party needs to enter this dungeon (1 for every other zone).
static func min_party(id: String) -> int:
	return int(info(id).get("min_party", 1))


## M13b: heroes a party needs to travel to this scene (1 for any non-dungeon).
static func min_party_for_scene(scene_path: String) -> int:
	return min_party(id_for_scene(scene_path))


## M13b: is this a co-op dungeon (more than one hero needed)?
static func is_coop(id: String) -> bool:
	return min_party(id) > 1


## Display name in the current language ("" for an unknown id).
static func title(id: String) -> String:
	var key := String(info(id).get("name_key", ""))
	return Texts.t(key) if key != "" else ""
