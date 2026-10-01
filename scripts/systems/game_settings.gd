extends Node
## Autoload "GameSettings" (M17a): this machine's settings - volumes, window,
## mouse and camera, comfort, the developer tools - in user://settings.cfg
## next to ClientSettings' [coop] section (every write is load -> set -> save,
## so the sections never overwrite each other). Changes apply at once and
## emit `changed`; readers either ask the typed getters or listen.
## Headless and test runs (smoke, net clients, shots, perf, stress, captures)
## run on the defaults and never read, write or apply the player's file, so
## results never depend on how the dev PC is set up; tests that want a file
## call `use_file()`. Developer tools are on there and with `-- --dev`.

signal changed(key: String)

const PATH := "user://settings.cfg"
## Where the file lives; `use_file()` points tests at a scratch one.
static var path: String = PATH

const DEFAULTS := {
	"audio/master": 1.0, "audio/music": 1.0, "audio/effects": 1.0, "audio/ambience": 1.0, "audio/interface": 1.0,
	"video/window_mode": "windowed", "video/window_size": "1600x900", "video/vsync": true,
	"video/max_fps": 0, "video/show_fps": false,
	"controls/sensitivity": 1.0, "controls/invert_y": false, "controls/zoom_speed": 1.0,
	"gameplay/shake": 1.0, "gameplay/hurt_flash": true, "gameplay/damage_numbers": true,
	"gameplay/pause_on_focus_loss": true, "gameplay/dev_tools": false,
	# M12: the language of the new texts (Texts); "auto" follows the system.
	# Its own section, so the Gameplay tab's Reset leaves it alone.
	"general/language": "auto",
}
## Test runs read the texts in English whatever the dev PC's language is.
const TEST_DEFAULTS := {"general/language": "en"}
## Volume setting -> the buses it scales (on top of Sfx.BUSES' start levels).
const AUDIO_BUSES := {"audio/master": ["Master"], "audio/music": ["Music"], "audio/effects": ["SFX", "Telegraph"],
	"audio/ambience": ["Ambience"], "audio/interface": ["UI"]}
const WINDOW_MODES: Array[String] = ["windowed", "borderless", "fullscreen"]
const WINDOW_SIZES: Array[String] = ["1280x720", "1600x900", "1920x1080", "2560x1440"]
## 0 = no limit.
const FPS_LIMITS: Array[int] = [30, 60, 90, 120, 144, 0]

## Headless and test runs: the defaults, no file, developer tools on, and no
## pause when the window loses focus (a windowed perf run must not stop).
var test_run: bool = false

var _values: Dictionary = {}
## False on headless and test runs until a test calls use_file().
var _persist: bool = false
var _dev_forced: bool = false
var _fps_layer: CanvasLayer
var _fps_label: Label
var _fps_tick: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # the FPS counter keeps counting in a paused menu
	var args := OS.get_cmdline_user_args()
	var is_test := DisplayServer.get_name() == "headless" or SaveGame.is_test_run()
	for arg in args:
		is_test = is_test or arg.begins_with("--net-test")
	test_run = is_test
	_values = _defaults()
	_dev_forced = is_test or "--dev" in args
	_persist = not is_test
	InputSetup.ensure()  # the project's keys, once; then the player's own (KeyBindings)
	KeyBindings.capture_defaults()
	if _persist:
		_read()
		_read_keys()
	apply_all()


## Tests: read and write `file` from now on (a missing file = the defaults).
func use_file(file: String) -> void:
	path = file
	_persist = true
	_values = _defaults()
	KeyBindings.reset_all()
	_read()
	_read_keys()
	apply_all()


## M17a key bindings: writes the bindings that differ from the defaults
## into [keys] (the whole section anew) and tells the labels.
func save_bindings() -> void:
	if _persist:
		var cfg := ConfigFile.new()
		cfg.load(path)
		if cfg.has_section("keys"):
			cfg.erase_section("keys")
		var changed_now := KeyBindings.overrides()
		for action: StringName in changed_now:
			cfg.set_value("keys", String(action), changed_now[action])
		cfg.save(path)
	changed.emit("keys")


func reset_bindings() -> void:
	KeyBindings.reset_all()
	save_bindings()


func _read_keys() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK or not cfg.has_section("keys"):
		return
	var known := KeyBindings.actions()
	for field in cfg.get_section_keys("keys"):
		var action := StringName(field)
		var v: Variant = cfg.get_value("keys", field)
		if known.has(action) and (v is PackedStringArray or v is Array):
			KeyBindings.set_codes(action, PackedStringArray(v))


func value(key: String) -> Variant:
	return _values.get(key, DEFAULTS.get(key))


func set_value(key: String, v: Variant) -> void:
	if not DEFAULTS.has(key):
		push_warning("GameSettings: unknown setting " + key)
		return
	if typeof(v) != typeof(DEFAULTS[key]):
		v = type_convert(v, typeof(DEFAULTS[key]))
	if _values.get(key) == v:
		return
	_values[key] = v
	_apply(key)
	_write(key)
	changed.emit(key)


## Every setting of `section` ("audio", "video", ...) back to its default.
func reset_section(section: String) -> void:
	var defaults := _defaults()
	for key: String in defaults:
		if key.begins_with(section + "/"):
			set_value(key, defaults[key])


## The defaults this run starts from (test runs: English texts).
func _defaults() -> Dictionary:
	var out := DEFAULTS.duplicate()
	if test_run:
		out.merge(TEST_DEFAULTS, true)
	return out


func _exit_tree() -> void:
	Texts.shutdown()


# --- typed getters for the hot paths ---------------------------------------

func mouse_sensitivity() -> float:
	return float(value("controls/sensitivity"))


func invert_y() -> bool:
	return bool(value("controls/invert_y"))


func zoom_speed() -> float:
	return float(value("controls/zoom_speed"))


func shake() -> float:
	return float(value("gameplay/shake"))


func hurt_flash() -> bool:
	return bool(value("gameplay/hurt_flash"))


func pause_on_focus_loss() -> bool:
	return bool(value("gameplay/pause_on_focus_loss"))


## F1 debug panel, the J playtest list and its line on the title screen.
func dev_tools() -> bool:
	return _dev_forced or bool(value("gameplay/dev_tools"))


# --- applying ----------------------------------------------------------------

func apply_all() -> void:
	for key: String in DEFAULTS:
		_apply(key)


func _apply(key: String) -> void:
	if AUDIO_BUSES.has(key):
		_apply_volume(key)
	elif key.begins_with("video/"):
		_apply_video(key)
	elif key == "gameplay/damage_numbers":
		GameFeel.damage_numbers_enabled = bool(value(key))
	elif key == "general/language":
		Texts.set_language(str(value(key)))


## A volume of 1 keeps the bus at its mix level, 0 mutes it.
func _apply_volume(key: String) -> void:
	var v := clampf(float(value(key)), 0.0, 1.0)
	for bus_name: String in AUDIO_BUSES[key]:
		var i := AudioServer.get_bus_index(bus_name)
		if i < 0:
			continue
		AudioServer.set_bus_mute(i, v <= 0.001)
		AudioServer.set_bus_volume_db(i, bus_level(bus_name) + linear_to_db(maxf(v, 0.001)))


## The bus's mix level at a volume of 100 % (Sfx.BUSES; Master is 0 dB).
static func bus_level(bus_name: String) -> float:
	return float(Sfx.BUSES.get(bus_name, 0.0))


func _apply_video(key: String) -> void:
	if key == "video/show_fps":
		_show_fps(bool(value(key)))
		return
	if not _persist or DisplayServer.get_name() == "headless":
		return  # test runs keep the window the harness asked for
	match key:
		"video/window_mode", "video/window_size":
			var mode := str(value("video/window_mode"))
			match mode:
				"fullscreen":
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
				"borderless":
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
				_:
					if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
						DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
					_apply_window_size()
		"video/vsync":
			DisplayServer.window_set_vsync_mode(
				DisplayServer.VSYNC_ENABLED if bool(value(key)) else DisplayServer.VSYNC_DISABLED)
		"video/max_fps":
			Engine.max_fps = maxi(int(value(key)), 0)


func _apply_window_size() -> void:
	var size := parse_size(str(value("video/window_size")))
	if size == Vector2i.ZERO:
		return
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	size = Vector2i(mini(size.x, usable.size.x), mini(size.y, usable.size.y))
	if DisplayServer.window_get_size() == size:
		return
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(usable.position + (usable.size - size) / 2)


## "1600x900" -> Vector2i(1600, 900); anything else -> zero.
static func parse_size(text: String) -> Vector2i:
	var parts := text.split("x")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))


func _show_fps(on: bool) -> void:
	if on and _fps_layer == null:
		_fps_layer = CanvasLayer.new()
		_fps_layer.layer = 30
		add_child(_fps_layer)
		_fps_label = Label.new()
		_fps_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_fps_label.offset_left = -150
		_fps_label.offset_top = 6
		_fps_label.offset_right = -10
		_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_fps_label.add_theme_font_override("font", UiTheme.font())
		_fps_label.add_theme_font_size_override("font_size", UiTheme.BODY)
		_fps_label.add_theme_color_override("font_color", UiTheme.MUTED)
		_fps_label.add_theme_color_override("font_outline_color", UiTheme.INK)
		_fps_label.add_theme_constant_override("outline_size", UiTheme.OUTLINE)
		_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fps_layer.add_child(_fps_label)
	if _fps_layer != null:
		_fps_layer.visible = on


func _process(delta: float) -> void:
	if _fps_layer == null or not _fps_layer.visible:
		return
	_fps_tick -= delta
	if _fps_tick <= 0.0:
		_fps_tick = 0.25
		_fps_label.text = "%d FPS" % roundi(Engine.get_frames_per_second())


# --- the file --------------------------------------------------------------

func _read() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	for key: String in DEFAULTS:
		var section := key.get_slice("/", 0)
		var field := key.get_slice("/", 1)
		if cfg.has_section_key(section, field):
			var v: Variant = cfg.get_value(section, field)
			if typeof(v) == typeof(DEFAULTS[key]) or (typeof(v) in [TYPE_INT, TYPE_FLOAT] and typeof(DEFAULTS[key]) in [TYPE_INT, TYPE_FLOAT]):
				_values[key] = type_convert(v, typeof(DEFAULTS[key]))


func _write(key: String) -> void:
	if not _persist:
		return
	var cfg := ConfigFile.new()
	cfg.load(path)  # a missing file just starts empty; [coop] stays as it is
	cfg.set_value(key.get_slice("/", 0), key.get_slice("/", 1), _values[key])
	cfg.save(path)
