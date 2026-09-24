extends Node
## Autoload "SaveGame": versioned JSON persistence for gear and world position.
## Corrupt or missing saves always fall back to a fresh start - never crash.
##
## v4 (M08) layout, see docs/PROGRESSION_DESIGN.md:
##   {version, world: {zone, flags, camps: {id: {cleared_at}}},
##    characters: [{class_id, known_abilities, gold, inventory, equipped, progression,
##                  waypoints, map_discovered}],
##    active}
## `world` is what a co-op server will own; `characters` stay with the player.

const VERSION := 4  # v2 (M07): progression; v3 (M07b): world/characters split; v4 (M08): camps, waypoints, map
const DEBOUNCE := 2.0
## Command-line flags (after `--`) that mark an automated capture/perf run.
const TEST_RUN_FLAGS: Array[String] = ["--capture", "--worldcapture", "--shots", "--perf", "--stress"]
const TEST_SAVE_PATH := "user://capture_save.json"
const TEST_RUN_SEED := 1207

## Overridable so tests can run against a scratch file without touching
## the real save.
var save_path: String = "user://runebound_save.json"
var current_zone: String = "res://scenes/hub.tscn"
var flags: Dictionary = {}  # persistent world state, e.g. bosses defeated
## M08: cleared camps by id -> {"cleared_at": unix seconds}; they re-arm later.
var camps: Dictionary = {}
## Index into `characters` of the character being played.
var active: int = 0

var _pending_save: bool = false
var _debounce_left: float = 0.0
var _loaded_data: Dictionary = {}


func _ready() -> void:
	# Autoloads are ready before the first zone builds, so this is the only
	# place that keeps automated runs off the real save from the very first
	# frame and makes randf()-driven layout (rock yaw, spawn scatter) repeatable
	# for before/after captures.
	var custom_save := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save="):
			custom_save = arg.trim_prefix("--save=")  # debugging: play a copied save
	if custom_save != "":
		save_path = custom_save
	elif is_test_run():
		save_path = TEST_SAVE_PATH
		if FileAccess.file_exists(save_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
		seed(TEST_RUN_SEED)
	reload_from_disk()


static func is_test_run() -> bool:
	for arg in OS.get_cmdline_user_args():
		for flag in TEST_RUN_FLAGS:
			if arg == flag or arg.begins_with(flag + "="):
				return true
	return false


func set_flag(flag: StringName) -> void:
	flags[String(flag)] = true
	save_now()


func has_flag(flag: StringName) -> bool:
	return flags.get(String(flag), false)


## M08 camp persistence (debounced: a cleared camp is not worth a disk hit).
func mark_camp_cleared(camp_id: String, at: float) -> void:
	camps[camp_id] = {"cleared_at": at}
	request_save()


func clear_camp(camp_id: String) -> void:
	if camps.erase(camp_id):
		request_save()


## Unix seconds the camp was cleared at, -1 when it is live.
func camp_cleared_at(camp_id: String) -> float:
	var entry: Variant = camps.get(camp_id)
	if entry is Dictionary:
		return float((entry as Dictionary).get("cleared_at", -1.0))
	return -1.0


func _process(delta: float) -> void:
	if _pending_save:
		_debounce_left -= delta
		if _debounce_left <= 0.0:
			_pending_save = false
			_write_now()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _pending_save:
		_write_now()


## Debounced save - call freely on pickup/equip/discard.
func request_save() -> void:
	_pending_save = true
	_debounce_left = DEBOUNCE


## Immediate save - zone transitions.
func save_now() -> void:
	_pending_save = false
	_write_now()


func wipe() -> void:
	_loaded_data = {}
	flags = {}
	camps = {}
	active = 0
	current_zone = "res://scenes/hub.tscn"
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


func has_save() -> bool:
	return not _loaded_data.is_empty()


## Re-read the save file from disk (tests use this after switching save_path).
func reload_from_disk() -> void:
	_loaded_data = _read_file()
	var world: Dictionary = _loaded_data.get("world", {})
	if world.has("zone"):
		current_zone = world["zone"]
	flags = world.get("flags", {})
	camps = world.get("camps", {})
	active = int(_loaded_data.get("active", 0))


## The saved character being played ({} on a fresh start).
func active_character() -> Dictionary:
	var chars: Array = _loaded_data.get("characters", [])
	if active < 0 or active >= chars.size():
		return {}
	return chars[active] as Dictionary


## Class of the active character; the default class on a fresh start.
func active_class_id() -> StringName:
	return StringName(str(active_character().get("class_id", ClassData.DEFAULT_ID)))


## Restore the active character into a freshly spawned player. Called by ZoneBase.
func restore_player(player: Player) -> void:
	var ch := active_character()
	if ch.is_empty():
		return
	for entry: Dictionary in ch.get("inventory", []):
		player.equipment.inventory.append(ItemData.from_dict(entry))
	for slot_key: String in ch.get("equipped", {}):
		var item := ItemData.from_dict(ch["equipped"][slot_key])
		player.equipment.equipped[int(slot_key) as ItemData.Slot] = item
	player.progression.from_dict(ch.get("progression", {}))
	if ch.has("known_abilities"):
		var known: Array[StringName] = []
		for id in ch["known_abilities"]:
			var sid := StringName(str(id))
			if player.ability(sid) != null and not known.has(sid):
				known.append(sid)
		for sid in player.class_data.starting_abilities:  # the start kit can't be lost
			if not known.has(sid):
				known.append(sid)
		player.known_abilities = known
	player.gold = maxi(int(ch.get("gold", 0)), 0)
	player.equipment._recompute()
	player.equipment.changed.emit()
	player.abilities_changed.emit()
	player.gold_changed.emit(player.gold, 0)


static func character_dict(player: Player) -> Dictionary:
	var ch := {"class_id": String(player.class_data.id), "known_abilities": [], "gold": player.gold,
		"inventory": [], "equipped": {}, "progression": player.progression.to_dict()}
	for id in player.known_abilities:
		(ch["known_abilities"] as Array).append(String(id))
	for item in player.equipment.inventory:
		(ch["inventory"] as Array).append(item.to_dict())
	for slot: ItemData.Slot in player.equipment.equipped:
		ch["equipped"][str(int(slot))] = (player.equipment.equipped[slot] as ItemData).to_dict()
	return ch


func _collect() -> Dictionary:
	var player := _find_player()
	var chars: Array = (_loaded_data.get("characters", []) as Array).duplicate(true)
	if player != null:
		while chars.size() <= active:
			chars.append({})
		chars[active] = character_dict(player)
	# no player in this scene: the loaded characters are kept as they were
	var data := {"version": VERSION, "world": {"zone": current_zone, "flags": flags, "camps": camps},
		"characters": chars, "active": active}
	_loaded_data = data
	return data


func _find_player() -> Player:
	var scene := get_tree().current_scene
	if scene != null and scene.get(&"player") != null:
		return scene.get(&"player") as Player
	return null


func _write_now() -> void:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_warning("SaveGame: cannot write " + save_path)
		return
	file.store_string(JSON.stringify(_collect(), "\t"))
	file.close()


func _read_file() -> Dictionary:
	if not FileAccess.file_exists(save_path):
		return {}
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is not Dictionary:
		push_warning("SaveGame: corrupt save ignored")
		return {}
	var data := parsed as Dictionary
	return migrate(data)


## Brings an older save up to VERSION; unknown versions start fresh.
static func migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("version", -1))
	if version == 1:  # M07: add progression (level 1, no talents); gear and flags kept
		data["progression"] = {"level": 1, "xp": 0, "talents": {}}
		data["version"] = 2
		version = 2
	if version == 2:  # M07b: one Runebreaker with the start kit; the abilities its level had
		# reached are refunded as gold, so the trainer is the first stop (user, 2026-09-24)
		var prog: Dictionary = data.get("progression", {"level": 1, "xp": 0, "talents": {}})
		var level := int(prog.get("level", 1))
		var cls := ClassData.default_class()
		var known: Array = []
		for id in cls.starting_abilities:
			known.append(String(id))
		var refund := 0
		for ability in cls.trainer_abilities():
			if ability.learn_level <= level:
				refund += ability.learn_price
		data = {
			"version": 3,
			"world": {"zone": data.get("zone", "res://scenes/hub.tscn"), "flags": data.get("flags", {})},
			"characters": [{"class_id": String(cls.id), "known_abilities": known, "gold": refund,
				"inventory": data.get("inventory", []), "equipped": data.get("equipped", {}),
				"progression": prog}],
			"active": 0,
		}
		version = 3
	if version == 3:  # M08: camp persistence in the world, waypoints and map discovery per character
		var world3: Dictionary = data.get("world", {})
		world3["camps"] = {}
		data["world"] = world3
		for ch in data.get("characters", []):
			if ch is Dictionary:
				(ch as Dictionary)["waypoints"] = []
				(ch as Dictionary)["map_discovered"] = []
		data["version"] = 4
		version = 4
	if version != VERSION:
		push_warning("SaveGame: incompatible save version ignored")
		return {}
	return data
