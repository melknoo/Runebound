class_name ClientSettings
extends Object
## M09: per-machine client settings (user://settings.cfg), kept out of the
## save: the co-op server (picked from ServerList, or an address of your own),
## the name shown to the party and (M09b) the invite code for each server.

const PATH := "user://settings.cfg"
## Where they live; tests point it at a file of their own.
static var path: String = PATH


static func get_value(key: String, fallback: String) -> String:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return fallback
	return str(cfg.get_value("coop", key, fallback))


static func set_value(key: String, value: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)  # a missing file just starts empty
	cfg.set_value("coop", key, value)
	cfg.save(path)


## The invite code last used for `address` ("" = none yet).
static func get_invite(address: String) -> String:
	return str(_invites().get(_server_key(address), ""))


static func set_invite(address: String, code: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)
	var codes := _invites()
	codes[_server_key(address)] = code
	cfg.set_value("coop", "invites", codes)
	cfg.save(path)


static func _invites() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return {}
	var v: Variant = cfg.get_value("coop", "invites", {})
	return v if v is Dictionary else {}


static func _server_key(address: String) -> String:
	return address.strip_edges().to_lower()
