class_name ClientSettings
extends Object
## M09: per-machine client settings (user://settings.cfg), kept out of the
## save: the last co-op server address and the name shown to the party.

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
