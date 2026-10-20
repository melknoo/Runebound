class_name JournalUI
extends CanvasLayer
## M14a: the journal (key U, rebindable): every quest this character has, the
## main ones first, then the side ones, then the completed ones. A click shows
## a quest: its act and recommended level, the summary, the steps done and the
## one to do now (with progress), the reward and a [Track] button that puts it
## into the HUD's tracker. Built like the lore window (one window at a time,
## locks the hero, Esc / the key / the X close it).

const PANEL := Vector2(1040, 600)
const GOLD := Color("#E8B44A")

var player: Player
var shown: String = ""

var _root: Control
var _list_box: VBoxContainer
var _title: Label
var _meta: Label
var _body: VBoxContainer
var _track: Button
var _footer: Label


func setup(p: Player) -> void:
	player = p
	layer = 8
	_build()
	visible = false
	GameSettings.changed.connect(_on_setting_changed)


func _exit_tree() -> void:
	if GameSettings.changed.is_connected(_on_setting_changed):
		GameSettings.changed.disconnect(_on_setting_changed)


func qlog() -> QuestLog:
	return QuestLog.of(player)


func open(quest_id: String = "") -> void:
	var zone := get_parent() as ZoneBase
	if zone != null:
		zone.close_windows()
	var q := qlog()
	shown = quest_id if quest_id != "" else (q.shown_quest() if q != null else "")
	if shown == "" and q != null and not q.done.is_empty():
		shown = q.done[q.done.size() - 1]
	_render()
	visible = true
	player.input_locked = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	if not visible:
		return
	visible = false
	player.input_locked = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		var zone := get_parent() as ZoneBase
		if zone != null and zone.debug_overlay != null and zone.debug_overlay._visible:
			return  # the F1 overlay owns the letter keys while it shows
		if not PauseMenu.showing and player != null and not player.input_locked \
				and InputMap.has_action(&"journal_toggle") and event.is_action_pressed(&"journal_toggle"):
			open()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"toggle_cursor") or event.is_action_pressed(&"journal_toggle"):
		close()
		get_viewport().set_input_as_handled()


func _on_setting_changed(key: String) -> void:
	if (key == "general/language" or key == "keys") and visible:
		_render()


## The quest ids the list shows, in order: running main, running side, done.
func listed() -> Array[String]:
	var q := qlog()
	var out: Array[String] = []
	if q == null or not q.active:
		return out
	out.append_array(q.running())
	for i in range(q.done.size() - 1, -1, -1):
		out.append(String(q.done[i]))
	return out


func _render() -> void:
	_footer.text = Texts.t("ui.journal.close", [InputSetup.key_label(&"journal_toggle")])
	_fill_list()
	for child in _body.get_children():
		child.queue_free()
	var q := qlog()
	if shown == "" or q == null:
		_title.text = Texts.t("ui.journal.empty_title")
		_meta.text = Texts.t("ui.journal.title").to_upper()
		_add_text(Texts.t("ui.journal.empty"), UiTheme.TEXT)
		_track.visible = false
		return
	var quest := StoryDB.quest(shown)
	_title.text = Texts.t(str(quest.get("title", shown)))
	var act := int(quest.get("act", 0))
	var parts: Array[String] = [Texts.t("ui.journal.kind." + str(quest.get("kind", "side")))]
	parts.append(Texts.t("ui.journal.prologue") if act == 0 else Texts.t("ui.journal.act", [_roman(act)]))
	if int(quest.get("level", 0)) > 0:
		parts.append(Texts.t("ui.journal.level", [int(quest["level"])]))
	_meta.text = "  ·  ".join(parts).to_upper()
	if quest.has("summary"):
		_add_text(Texts.t(str(quest["summary"])), UiTheme.TEXT)
	var steps: Array = quest.get("steps", [])
	var finished := q.is_done(shown)
	var at := steps.size() if finished else q.step_index(shown)
	for i in mini(at + 1, steps.size()):
		var st: Dictionary = steps[i]
		var line := Texts.t(str(st.get("text", "")))
		if i < at:
			_add_text("x  " + line, UiTheme.MUTED)
		else:
			var prog := q.progress(shown)
			_add_text(">  " + line + ("  (%d/%d)" % [prog.x, prog.y] if prog.y > 1 else ""), GOLD)
	if finished:
		_add_text(Texts.t("ui.journal.finished"), UiTheme.MUTED)
	var reward := reward_text(quest.get("rewards", {}))
	if reward != "":
		_add_text(Texts.t("ui.journal.rewards", [reward]), Color("#9FB4FF"))
	_track.visible = q.is_running(shown)
	_track.text = Texts.t("ui.journal.tracked") if q.shown_quest() == shown else Texts.t("ui.journal.track")
	_track.disabled = q.shown_quest() == shown


static func reward_text(r: Variant) -> String:
	if r is not Dictionary:
		return ""
	var d: Dictionary = r
	var parts: Array[String] = []
	if int(d.get("xp", 0)) > 0:
		parts.append(Texts.t("ui.reward.xp", [int(d["xp"])]))
	if int(d.get("gold", 0)) > 0:
		parts.append(Texts.t("ui.reward.gold", [int(d["gold"])]))
	if int(d.get("draughts", 0)) > 0:
		parts.append(Texts.t("ui.reward.draughts", [int(d["draughts"])]))
	for spec: Variant in d.get("items", []):
		var legendary := spec is Dictionary and bool((spec as Dictionary).get("legendary", false))
		parts.append(Texts.t("ui.reward.legendary" if legendary else "ui.reward.item"))
	return ", ".join(parts)


static func _roman(n: int) -> String:
	return ["0", "I", "II", "III", "IV", "V"][clampi(n, 0, 5)]


func _fill_list() -> void:
	for child in _list_box.get_children():
		child.queue_free()
	var q := qlog()
	if q == null or not q.active:
		return
	var groups := [["ui.journal.main", q.running().filter(func(id: String) -> bool:
			return str(StoryDB.quest(id).get("kind", "side")) == "main")],
		["ui.journal.side", q.running().filter(func(id: String) -> bool:
			return str(StoryDB.quest(id).get("kind", "side")) != "main")],
		["ui.journal.done", Array(q.done).duplicate()]]
	(groups[2][1] as Array).reverse()
	for g: Array in groups:
		var ids: Array = g[1]
		if ids.is_empty():
			continue
		var head := UiTheme.caption(Texts.t(str(g[0])).to_upper())
		head.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		head.add_theme_color_override("font_color", GOLD)
		_list_box.add_child(head)
		for id: Variant in ids:
			var qid := str(id)
			var b := Button.new()
			b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			b.text = Texts.t(str(StoryDB.quest(qid).get("title", qid)))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.toggle_mode = true
			b.button_pressed = qid == shown
			b.clip_text = true
			b.custom_minimum_size = Vector2(290, 36)
			b.pressed.connect(func() -> void:
				shown = qid
				_render()
			)
			_list_box.add_child(b)


func _add_text(text: String, color: Color) -> void:
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("line_spacing", 6)
	l.text = text
	_body.add_child(l)


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiTheme.apply(_root)
	add_child(_root)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.01, 0.04, 0.6)
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -PANEL.x * 0.5
	panel.offset_top = -PANEL.y * 0.5
	panel.offset_right = PANEL.x * 0.5
	panel.offset_bottom = PANEL.y * 0.5
	panel.add_theme_stylebox_override("panel", UiTheme.nine("frame.png", 16, 18))
	_root.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	panel.add_child(body)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	body.add_child(top)
	var heads := VBoxContainer.new()
	heads.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heads.add_theme_constant_override("separation", 2)
	top.add_child(heads)
	_meta = UiTheme.caption("")
	_meta.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	heads.add_child(_meta)
	_title = Label.new()
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_title.add_theme_font_override("font", UiTheme.font(true))
	_title.add_theme_font_size_override("font_size", UiTheme.TITLE)
	_title.add_theme_color_override("font_color", GOLD)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heads.add_child(_title)
	top.add_child(UiTheme.close_button(close))

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(columns)
	var list_scroll := ScrollContainer.new()
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.custom_minimum_size = Vector2(310, 0)
	columns.add_child(list_scroll)
	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 4)
	list_scroll.add_child(_list_box)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	columns.add_child(right)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(scroll)
	var gutter := MarginContainer.new()
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_theme_constant_override("margin_right", 22)
	scroll.add_child(gutter)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	gutter.add_child(_body)
	_track = Button.new()
	_track.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_track.size_flags_horizontal = Control.SIZE_SHRINK_END
	_track.custom_minimum_size = Vector2(180, 40)
	_track.pressed.connect(func() -> void:
		var q := qlog()
		if q != null:
			q.track(shown)
		_render()
	)
	right.add_child(_track)

	_footer = UiTheme.caption("")
	_footer.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	body.add_child(_footer)
