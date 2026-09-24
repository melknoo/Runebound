class_name WaypointRegistry
extends Object
## Every waypoint in the world, for the travel list and fast travel across
## zones: the hub's shrine plus the open zones' layout waypoints (read from
## their baked layout.json, so no zone has to be loaded). Keys are
## "<zone scene basename>:<poi id>"; the hub's is HUB_KEY.

const HUB_KEY := "hub:runehold"
const ZONE_LAYOUTS := {
	"res://scenes/ashen_highlands.tscn": ["res://assets/world/highlands/layout.json", "ASHEN HIGHLANDS"],
}

static var _entries: Array[Dictionary] = []


static func key_for(scene_path: String, poi_id: String) -> String:
	return scene_path.get_file().get_basename() + ":" + poi_id


## [{key, poi, scene, zone, name}] in travel-list order (hub first).
static func all() -> Array[Dictionary]:
	if _entries.is_empty():
		_load()
	return _entries


static func find(key: String) -> Dictionary:
	for e in all():
		if String(e["key"]) == key:
			return e
	return {}


static func _load() -> void:
	_entries.append({"key": HUB_KEY, "poi": "runehold", "scene": "res://scenes/hub.tscn",
		"zone": "RUNEHOLD", "name": "Runehold"})
	for scene_path: String in ZONE_LAYOUTS:
		var info: Array = ZONE_LAYOUTS[scene_path]
		var layout := ZoneLayout.load_from(String(info[0]))
		for poi in layout.by_type("waypoint"):
			var pid := String(poi.get("id", ""))
			_entries.append({"key": key_for(scene_path, pid), "poi": pid, "scene": scene_path,
				"zone": String(info[1]), "name": String(poi.get("name", pid))})


static func clear() -> void:
	_entries.clear()
