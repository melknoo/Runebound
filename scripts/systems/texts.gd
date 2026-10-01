class_name Texts
extends Object
## M12: the text table, German and English (STORY_DESIGN "Languages"). Every
## new player-facing text from M12 on is a dotted key (`lore.village.grave_1`)
## in a JSON table under resources/i18n/ ({key: {"en": ..., "de": ...}}),
## loaded at runtime into one Translation per language and registered with
## the TranslationServer, so Labels showing a key translate themselves (and
## again when the language changes) and code calls `Texts.t(key, args)`.
## JSON, not CSV: Godot imports every .csv itself and writes .translation
## files next to it. The keys are dotted ids, so they never match the older
## English UI text, which stays as it is until M14. A missing German line
## falls back to the English one; a missing key shows the key (the smoke test
## checks every key has both).

const FILES: Array[String] = ["res://resources/i18n/m12_ui.json", "res://resources/i18n/m12_lore.json"]
const LANGUAGES: Array[String] = ["en", "de"]

## key -> {"en": text, "de": text}
static var _table: Dictionary = {}
static var _translations: Array[Translation] = []
static var _loaded: bool = false
static var _language: String = "en"


## Loads the tables once and registers the translations.
static func ensure() -> void:
	if _loaded:
		return
	_loaded = true
	_table = {}
	for file in FILES:
		if not FileAccess.file_exists(file):
			push_warning("Texts: missing table " + file)
			continue
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
		if not data is Dictionary:
			push_error("Texts: %s is not a JSON object" % file)
			continue
		for key: String in data:
			if key.begins_with("_"):
				continue  # comments
			var entry: Variant = data[key]
			if entry is Dictionary:
				_table[key] = entry
	for lang in LANGUAGES:
		var tr_res := Translation.new()
		tr_res.locale = lang
		for key: String in _table:
			var entry: Dictionary = _table[key]
			var text := str(entry.get(lang, ""))
			if text == "":
				text = str(entry.get("en", key))
			tr_res.add_message(key, text)
		TranslationServer.add_translation(tr_res)
		_translations.append(tr_res)


## Drops the translations (GameSettings' _exit_tree; statics holding
## resources crash the process on quit otherwise).
static func shutdown() -> void:
	for tr_res in _translations:
		TranslationServer.remove_translation(tr_res)
	_translations.clear()
	_table = {}
	_loaded = false


## "auto" follows the system language (German -> "de", anything else "en").
static func resolve(setting: String) -> String:
	if setting in LANGUAGES:
		return setting
	return "de" if OS.get_locale_language() == "de" else "en"


static func set_language(setting: String) -> void:
	ensure()
	_language = resolve(setting)
	TranslationServer.set_locale(_language)


## The language the texts show in now ("en" or "de").
static func language() -> String:
	return _language


## `key` in the current language, formatted with `args` when given.
static func t(key: String, args: Array = []) -> String:
	ensure()
	var text := String(TranslationServer.translate(StringName(key)))
	return text % args if not args.is_empty() else text


## `key` in one language, without switching (tests, the chronicle).
static func in_language(key: String, lang: String) -> String:
	ensure()
	var entry: Dictionary = _table.get(key, {})
	var text := str(entry.get(lang, ""))
	return text if text != "" else str(entry.get("en", key))


static func has(key: String) -> bool:
	ensure()
	return _table.has(key)


static func keys() -> Array:
	ensure()
	return _table.keys()


## Keys missing a language (tests: every key has both).
static func incomplete() -> Array[String]:
	ensure()
	var out: Array[String] = []
	for key: String in _table:
		var entry: Dictionary = _table[key]
		for lang in LANGUAGES:
			if str(entry.get(lang, "")).strip_edges() == "":
				out.append("%s (%s)" % [key, lang])
	return out
