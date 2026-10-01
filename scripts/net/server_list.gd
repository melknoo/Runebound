class_name ServerList
extends Object
## The co-op servers the title screen offers by name (user 2026-10-01: pick
## the Acer from a dropdown, an alias instead of the address, room for more
## servers later). The list is data in the repo (resources/net/servers.json):
## [{id, name, address}]; `address` is anything NetAddress accepts. Entries
## without a name, with an address NetAddress refuses or with a taken id are
## skipped with a warning.

const PATH := "res://resources/net/servers.json"

static var _servers: Array[Dictionary] = []
static var _loaded := false


## [{id, name, address}] in display order.
static func all() -> Array[Dictionary]:
	_ensure()
	return _servers


## The entry with this id ({} = none).
static func by_id(id: String) -> Dictionary:
	for s: Dictionary in all():
		if str(s["id"]) == id:
			return s
	return {}


## The entry whose address is `address` (case and spaces do not matter; {} = none).
static func by_address(address: String) -> Dictionary:
	var want := address.strip_edges().to_lower()
	for s: Dictionary in all():
		if str(s["address"]).to_lower() == want:
			return s
	return {}


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	_servers.clear()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	var rows: Variant = (parsed as Dictionary).get("servers", []) if parsed is Dictionary else []
	if rows is not Array:
		push_warning("ServerList: %s has no \"servers\" list" % PATH)
		return
	var seen: Array[String] = []
	for row: Variant in rows:
		if row is not Dictionary:
			continue
		var id := str((row as Dictionary).get("id", "")).strip_edges()
		var display := str((row as Dictionary).get("name", "")).strip_edges()
		var address := str((row as Dictionary).get("address", "")).strip_edges()
		var check := NetAddress.parse(address, Net.DEFAULT_PORT)
		if id == "" or display == "" or seen.has(id) or String(check["error"]) != "":
			push_warning("ServerList: skipped the entry \"%s\" (%s)" % [display if display != "" else id,
				String(check["error"]) if String(check["error"]) != "" else "no id or name, or a taken id"])
			continue
		seen.append(id)
		_servers.append({"id": id, "name": display, "address": address})
