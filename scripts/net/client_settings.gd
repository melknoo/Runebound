class_name ClientSettings
extends Object
## M09: per-machine client settings (user://settings.cfg), kept out of the
## save: the last co-op server address, the name shown to the party and (M09b)
## the invite code for each server.

const PATH := "user://settings.cfg"


static func get_value(key: String, fallback: String) -> String:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return fallback
	return str(cfg.get_value("coop", key, fallback))


static func set_value(key: String, value: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)  # a missing file just starts empty
	cfg.set_value("coop", key, value)
	cfg.save(PATH)


## The invite code last used for `address` ("" = none yet).
static func get_invite(address: String) -> String:
	return str(_invites().get(_server_key(address), ""))


static func set_invite(address: String, code: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	var codes := _invites()
	codes[_server_key(address)] = code
	cfg.set_value("coop", "invites", codes)
	cfg.save(PATH)


static func _invites() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return {}
	var v: Variant = cfg.get_value("coop", "invites", {})
	return v if v is Dictionary else {}


static func _server_key(address: String) -> String:
	return address.strip_edges().to_lower()
