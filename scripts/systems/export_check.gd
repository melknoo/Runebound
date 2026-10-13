extends Node
## A player build checks itself (tools/dist/build_windows.ps1 runs it after
## every export): `Runebound.exe --headless -- --export-check --out=<json>`.
## The title screen hands over to this node. It reads everything an export
## can lose (raw files, imported copies, directory listings, JSON tables),
## then boots the Highlands for a few seconds and counts the errors logged
## on the way. Writes {ok, version, checks: [{name, ok, detail}], errors}
## and quits with 0 (all good) or 1. Also runs from the source tree.
## docs/dev-notes/release-builds.md

const BOOT_SECONDS := 6.0

var _checks: Array[Dictionary] = []
var _log := ErrorLog.new()
var _out := "user://export_check.json"


class ErrorLog extends Logger:
	const KEEP := 40
	var mutex := Mutex.new()
	var lines: Array[String] = []
	## Errors that fail the check: script errors and failed res:// loads.
	var fatal: int = 0

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		var text := "%s (%s:%d %s)" % [rationale if rationale != "" else code, file.get_file(), line, function]
		mutex.lock()
		if error_type == ERROR_TYPE_SCRIPT or text.contains("res://"):
			fatal += 1
		if lines.size() < KEEP:
			lines.append(text)
		mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


func _init() -> void:
	OS.add_logger(_log)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	var exported := OS.has_feature("template")
	_check("version", not exported or (version != "" and version != "dev"), version)

	var terrain := Terrain.load_from(AshenHighlands.LAYOUT_DIR, null)
	var lo := INF
	var hi := -INF
	for h: float in terrain.heights:
		lo = minf(lo, h)
		hi = maxf(hi, h)
	_check("terrain heights", terrain.heights.size() > 0 and hi - lo > 1.0, "%d samples, %.1f..%.1f m" % [terrain.heights.size(), lo, hi])
	terrain.free()

	var biome_names := _files(ArtKit.BIOME_DIR, ".png")
	var bad: Array[String] = []
	for n in biome_names:
		var img := ArtKit.png_image(ArtKit.BIOME_DIR + n)
		if img == null or img.get_width() < 16:
			bad.append(n)
	_check("biome textures", biome_names.size() >= 20 and bad.is_empty(), "%d found, unreadable: %s" % [biome_names.size(), bad])

	var layout := ZoneLayout.load_from(AshenHighlands.LAYOUT_DIR.path_join("layout.json"))
	var mask := layout.biome_image()
	_check("biome mask", mask != null, "" if mask == null else str(mask.get_size()))

	var layouts := 0
	for dir in DirAccess.get_directories_at("res://assets/world"):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/world/%s/layout.json" % dir))
		if parsed is Dictionary:
			layouts += 1
	_check("zone layouts", layouts >= 5, "%d parsed" % layouts)
	Texts.ensure()
	_check("text tables", Texts.keys().size() > 100, "%d keys" % Texts.keys().size())
	_check("server list", not ServerList.all().is_empty(), "%d servers" % ServerList.all().size())
	_check("playtest list", not PlaytestLog.groups().is_empty(), "%d groups" % PlaytestLog.groups().size())
	_check("art spec", not ArtKit.spec().is_empty(), "%d keys" % ArtKit.spec().size())
	_check("classes", ClassData.all().size() >= 3, "%d classes" % ClassData.all().size())
	_check("talents", not Progression.tree().is_empty(), "%d talents" % Progression.tree().size())
	var sounds := (Sfx.get(&"_library") as Dictionary).size()
	_check("sounds", sounds > 20, "%d keys" % sounds)

	var scenes := _files("res://scenes", ".tscn")
	var broken: Array[String] = []
	for s in scenes:
		if not (load("res://scenes/" + s) is PackedScene):
			broken.append(s)
	_check("scenes", scenes.size() >= 8 and broken.is_empty(), "%d found, broken: %s" % [scenes.size(), broken])

	get_tree().change_scene_to_file(DungeonRegistry.HIGHLANDS_SCENE)
	await get_tree().create_timer(BOOT_SECONDS).timeout
	var zone := get_tree().current_scene as ZoneBase
	_check("highlands boot", zone != null and is_instance_valid(zone.player), "" if zone != null else "no zone")

	_finish(version)


## File names in `dir` ending in `ext`, also in a player build (where the
## listing holds `x.png.import` / `x.tscn.remap` instead of the file).
func _files(dir: String, ext: String) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		var fname := f.trim_suffix(".import").trim_suffix(".remap")
		if fname.ends_with(ext) and not out.has(fname):
			out.append(fname)
	return out


func _check(check_name: String, ok: bool, detail: String) -> void:
	_checks.append({"name": check_name, "ok": ok, "detail": detail})
	print("export check: %s %s  %s" % ["ok  " if ok else "FAIL", check_name, detail])


func _finish(version: String) -> void:
	_log.mutex.lock()
	var errors := _log.lines.duplicate()
	var fatal := _log.fatal
	_log.mutex.unlock()
	_check("logged errors", fatal == 0, "%d fatal, %d kept" % [fatal, errors.size()])
	var ok := true
	for c in _checks:
		ok = ok and bool(c["ok"])
	var report := {"ok": ok, "version": version, "exported": OS.has_feature("template"),
		"godot": Engine.get_version_info()["string"], "checks": _checks, "errors": errors}
	var f := FileAccess.open(_out, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "\t"))
		f.close()
	print("export check: %s -> %s" % ["PASSED" if ok else "FAILED", ProjectSettings.globalize_path(_out) if _out.begins_with("user://") else _out])
	OS.remove_logger(_log)
	get_tree().quit(0 if ok else 1)
