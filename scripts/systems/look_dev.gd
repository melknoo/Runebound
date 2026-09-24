class_name LookDev
extends Object
## Registry of switchable look-development options (outline, texel density,
## stepped animation, ...). Systems register a handler per key; shot lists and
## the look-dev debug key apply settings through here, so captures and live
## play compare exactly the same variants.

static var settings: Dictionary = {}
static var _handlers: Dictionary = {}  # StringName -> Callable(value)


static func register(key: StringName, handler: Callable, default_value: Variant) -> void:
	_handlers[key] = handler
	if not settings.has(key):
		settings[key] = _cli_value(key, default_value)
	handler.call(settings[key])


## `-- --look=key:value` sets a start value (debugging, captures, perf A/B).
static func _cli_value(key: StringName, default_value: Variant) -> Variant:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--look=" + String(key) + ":"):
			var raw := arg.get_slice(":", 1)
			if raw == "true" or raw == "false":
				return raw == "true"
			return raw
	return default_value


## Shutdown: drop handlers (lambdas may capture GPU resources).
static func clear() -> void:
	_handlers.clear()


static func get_value(key: StringName, fallback: Variant = null) -> Variant:
	return settings.get(key, fallback)


## Applies every key in `look`; unknown keys are reported, not fatal, so shot
## lists can be written before the system that consumes a key exists.
static func apply(look: Dictionary) -> void:
	for key: Variant in look:
		var k := StringName(str(key))
		settings[k] = look[key]
		if _handlers.has(k):
			var handler: Callable = _handlers[k]
			if handler.is_valid():
				handler.call(look[key])
		else:
			print("LookDev: no handler for '%s' (stored)" % k)
