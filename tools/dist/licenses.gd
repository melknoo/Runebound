extends SceneTree
## Writes LICENSES.txt for a player build (tools/dist/build_windows.ps1):
## the Godot Engine's licence and its third-party notices, as the engine
## itself reports them, then the fonts' OFL texts.
## `godot --headless --path . --script res://tools/dist/licenses.gd -- --out=<file>`

const FONT_LICENSES: Array[String] = ["res://assets/fonts/OFL_PixelifySans.txt",
	"res://assets/fonts/OFL_RuneboundPixel.txt", "res://assets/fonts/OFL_Jacquard24.txt"]
const RULE := "\n\n------------------------------------------------------------------------\n\n"


func _init() -> void:
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	var text := "RUNEBOUND - third-party licences\n\nRUNEBOUND runs on the Godot Engine %s (https://godotengine.org).\n\n" % [
		Engine.get_version_info()["string"]]
	text += Engine.get_license_text()
	text += RULE + "Fonts\n\n"
	for path in FONT_LICENSES:
		text += "%s:\n\n%s\n\n" % [path.get_file().trim_prefix("OFL_").trim_suffix(".txt"), FileAccess.get_file_as_string(path)]
	text += RULE + "Third-party components of the Godot Engine\n\n"
	for info: Dictionary in Engine.get_copyright_info():
		text += "- %s\n" % info["name"]
		for part: Dictionary in info["parts"]:
			for line: String in part["copyright"]:
				text += "    (c) %s\n" % line
			text += "    License: %s\n" % part["license"]
	var licenses: Dictionary = Engine.get_license_info()
	for license_name: String in licenses:
		text += RULE + "License: %s\n\n%s" % [license_name, licenses[license_name]]
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f == null:
		printerr("licenses: cannot write ", out)
		quit(1)
		return
	f.store_string(text.replace("\r\n", "\n").replace("\n", "\r\n"))
	f.close()
	print("licenses: ", out)
	quit(0)
