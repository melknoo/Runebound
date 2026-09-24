extends Node
## Autoload "SaveGame": versioned JSON persistence for gear and world position.
## Corrupt or missing saves always fall back to a fresh start - never crash.

const VERSION := 2  # v2 (M07): progression; v1 saves migrate on load
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
	_loaded_data = _read_file()
	if _loaded_data.has("zone"):
		current_zone = _loaded_data["zone"]
	flags = _loaded_data.get("flags", {})


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
	current_zone = "res://scenes/hub.tscn"
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


func has_save() -> bool:
	return not _loaded_data.is_empty()


## Re-read the save file from disk (tests use this after switching save_path).
func reload_from_disk() -> void:
	_loaded_data = _read_file()
	if _loaded_data.has("zone"):
		current_zone = _loaded_data["zone"]
	flags = _loaded_data.get("flags", {})


## Restore gear into a freshly spawned player. Called by ZoneBase.
func restore_player(player: Player) -> void:
	if _loaded_data.is_empty():
		return
	for entry: Dictionary in _loaded_data.get("inventory", []):
		player.equipment.inventory.append(ItemData.from_dict(entry))
	for slot_key: String in _loaded_data.get("equipped", {}):
		var item := ItemData.from_dict(_loaded_data["equipped"][slot_key])
		player.equipment.equipped[int(slot_key) as ItemData.Slot] = item
	player.progression.from_dict(_loaded_data.get("progression", {}))
	player.equipment._recompute()
	player.equipment.changed.emit()


func _collect() -> Dictionary:
	var player := _find_player()
	var data := {"version": VERSION, "zone": current_zone, "flags": flags, "inventory": [], "equipped": {}}
	if player != null:
		for item in player.equipment.inventory:
			(data["inventory"] as Array).append(item.to_dict())
		for slot: ItemData.Slot in player.equipment.equipped:
			data["equipped"][str(int(slot))] = (player.equipment.equipped[slot] as ItemData).to_dict()
		data["progression"] = player.progression.to_dict()
	elif _loaded_data.has("progression"):
		data["progression"] = _loaded_data["progression"]  # no player in this scene: keep it
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
	if version != VERSION:
		push_warning("SaveGame: incompatible save version ignored")
		return {}
	return data
