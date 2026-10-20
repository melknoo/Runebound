class_name QuestTracker
extends VBoxContainer
## M14a: the shown quest in the HUD's top-right corner (STORY_DESIGN "The
## campaign"): its title in gold, the current step with its progress, the
## recommended level when the hero is below it, and a hint which key opens the
## journal. Lives in the HUD's root (Hud's own child 0); hidden without a
## running quest or while a camera pan plays (`suppressed`).

const WIDTH := 330.0
const GOLD := Color("#E8B44A")

var qlog: QuestLog = null
var hero: Player = null
## Set by camera pans: hide while true.
var suppressed: bool = false:
	set(v):
		suppressed = v
		refresh()

var _title: Label
var _step: Label
var _level: Label
var _hint: Label
## M14a phase 5: a tutorial line (the prologue's "WASD: walk ...") until the
## next step or hint replaces it.
var _tut: Label
var _tut_key: String = ""
var _tut_actions: Array = []


func _ready() -> void:
	name = "QuestTracker"
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -WIDTH - 24.0
	offset_right = -24.0
	offset_top = 24.0
	offset_bottom = 160.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 2)
	_title = _label(GOLD, true)
	_step = _label(UiTheme.TEXT, false)
	_level = _label(Color("#E07A5F"), false)
	_hint = _label(UiTheme.MUTED, false)
	_tut = _label(Color("#9FF2E6"), false)
	_tut.visible = false
	GameSettings.changed.connect(_on_setting_changed)
	visible = false


func _exit_tree() -> void:
	if GameSettings.changed.is_connected(_on_setting_changed):
		GameSettings.changed.disconnect(_on_setting_changed)


func bind(log_: QuestLog, p: Player) -> void:
	qlog = log_
	hero = p
	if not qlog.changed.is_connected(refresh):
		qlog.changed.connect(refresh)
	if not qlog.step_done.is_connected(_on_step_done):
		qlog.step_done.connect(_on_step_done)
	if hero != null and not hero.progression.leveled_up.is_connected(_on_level):
		hero.progression.leveled_up.connect(_on_level)
	refresh()


func _on_level(_l: int) -> void:
	refresh()


## A step finished: its tutorial line goes (the step's effects may set the next).
func _on_step_done(_q: String, _s: String) -> void:
	set_hint("", [])


## Shows tutorial text `key` formatted with the current keys of `actions`
## ("" clears it).
func set_hint(key: String, actions: Array) -> void:
	_tut_key = key
	_tut_actions = actions.duplicate()
	_render_hint()


func hint_text() -> String:
	return _tut.text if _tut.visible else ""


func _render_hint() -> void:
	if _tut_key == "":
		_tut.text = ""
		_tut.visible = false
		return
	var args: Array = []
	for a: Variant in _tut_actions:
		args.append(InputSetup.key_label(StringName(str(a))))
	_tut.text = Texts.t(_tut_key, args)
	_tut.visible = true


func _on_setting_changed(key: String) -> void:
	if key == "general/language" or key == "keys":
		refresh()
		_render_hint()


## The text the tracker shows now: [title, step] ("" when hidden).
func lines() -> PackedStringArray:
	return PackedStringArray([_title.text, _step.text]) if visible else PackedStringArray()


func refresh() -> void:
	if qlog == null or not qlog.active or suppressed:
		visible = false
		return
	var qid := qlog.shown_quest()
	if qid == "":
		visible = false
		return
	var q := StoryDB.quest(qid)
	var st := qlog.current_step(qid)
	_title.text = Texts.t(str(q.get("title", qid)))
	var step_text := Texts.t(str(st.get("text", "")))
	var prog := qlog.progress(qid)
	if prog.y > 1:
		step_text += "  (%d/%d)" % [prog.x, prog.y]
	_step.text = "- " + step_text
	var lvl := int(q.get("level", 0))
	_level.visible = lvl > 0 and hero != null and hero.progression.level < lvl
	if _level.visible:
		_level.text = Texts.t("ui.tracker.level", [lvl])
	_hint.text = Texts.t("ui.tracker.hint", [InputSetup.key_label(&"journal_toggle")])
	visible = true


func _label(color: Color, title: bool) -> Label:
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(WIDTH, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", UiTheme.OUTLINE)
	l.add_theme_color_override("font_outline_color", UiTheme.INK)
	if title:
		l.add_theme_font_override("font", UiTheme.font(true))
		l.add_theme_font_size_override("font_size", 30)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l
