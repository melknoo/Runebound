class_name DialogueUI
extends CanvasLayer
## M14a: a conversation with an NPC (STORY_DESIGN "Dialogue"): a panel along
## the bottom with the speaker's portrait and name, one line at a time, and the
## hero's answers (keys 1-4 or a click). Lines without answers go on with the
## interact key or Space; Esc ends the talk. Locks the hero while it is open
## and lets go one frame after it closed (otherwise the same key press would
## open the NPC again).
##
## The data is `resources/story/dialogue/<npc>.json`:
##   {"npc": id, "entries": [{"if": cond, "start": node, "topic": bool}],
##    "nodes": {id: {"say": key | "say_pool": [keys], "speaker": npc id,
##                   "effects": [...], "next": id | "options": [{"text": key,
##                   "if": cond, "effects": [...], "next": id | "end": true}],
##                   "end": true}}}
## The first entry whose `if` holds starts the talk. A trainer or a merchant
## only talks when a `topic` entry holds (story to tell); otherwise [E] opens
## its panel straight away (shopping stays one key press).

const PANEL_W := 1120.0
const PANEL_H := 250.0
const GOLD := Color("#E8B44A")
const MAX_OPTIONS := 4

var player: Player
## The talk on show: npc id, node id ("" when closed).
var npc_id: String = ""
var node_id: String = ""
var npc: Node3D = null

var _root: Control
var _portrait: PortraitView
var _name: Label
var _text: Label
var _options: VBoxContainer
var _hint: Label
var _shown_options: Array[Dictionary] = []
var _unlock_at_frame: int = -1
## How often each NPC's say_pool rotated (flavour lines change per visit).
var _visits: Dictionary = {}


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


## The node a talk with `id` would start at now ("" = nothing to say).
## `topics_only`: only entries marked as a topic count (trainers, merchants).
func entry_for(id: String, who: Node3D = null, topics_only: bool = false) -> String:
	var d := StoryDB.dialogue(id)
	var ql := qlog()
	if d.is_empty() or ql == null or not ql.active:
		return ""
	for entry: Variant in d.get("entries", []):
		var e: Dictionary = entry
		if topics_only and not bool(e.get("topic", false)):
			continue
		if StoryCond.check(e.get("if", {}), ql, player, {"npc": who}):
			return str(e.get("start", ""))
	return ""


## Opens a talk with NPC `id` (`who` stands in the world: portrait, panels).
## False when it has nothing to say (the caller does its old thing).
func try_open(id: String, who: Node3D, p: Player = null, topics_only: bool = false) -> bool:
	if p != null:
		player = p
	var start := entry_for(id, who, topics_only)
	if start == "":
		return false
	var zone := get_parent() as ZoneBase
	if zone != null:
		zone.close_windows()
	npc_id = id
	npc = who
	visible = true
	player.input_locked = true
	_unlock_at_frame = -1
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_visits[id] = int(_visits.get(id, -1)) + 1
	_portrait.show_npc(who if who is Npc else null)  # a marker (an inscription) has no face
	_goto(start)
	return true


func close() -> void:
	if not visible:
		return
	visible = false
	npc_id = ""
	node_id = ""
	_portrait.show_npc(null)
	_unlock_at_frame = Engine.get_process_frames() + 1
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	if _unlock_at_frame >= 0 and Engine.get_process_frames() >= _unlock_at_frame:
		_unlock_at_frame = -1
		if player != null and is_instance_valid(player) and not visible:
			player.input_locked = false


## The current line (translated) and answer texts - tests and shots.
func current_text() -> String:
	return _text.text


func option_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for o in _shown_options:
		out.append(Texts.t(str(o.get("text", ""))))
	return out


## Picks answer `i` (0-based) of the line on show.
func choose(i: int) -> void:
	if not visible or i < 0 or i >= _shown_options.size():
		return
	var o := _shown_options[i]
	var who := npc
	StoryEffects.apply(o.get("effects", []), player, qlog(), {"npc": who})
	if not visible:
		_unlock_at_frame = -1  # an effect opened a panel (it closed us): the panel unlocks the hero
		return
	if o.has("next"):
		_goto(str(o["next"]))
	else:
		close()


## The interact key / Space on a line without answers.
func advance() -> void:
	if not visible or not _shown_options.is_empty():
		return
	var node := _node(node_id)
	if node.has("next"):
		_goto(str(node["next"]))
	else:
		close()


func _node(id: String) -> Dictionary:
	return (StoryDB.dialogue(npc_id).get("nodes", {}) as Dictionary).get(id, {}) as Dictionary


func _goto(id: String) -> void:
	var node := _node(id)
	if node.is_empty():
		close()
		return
	node_id = id
	StoryEffects.apply(node.get("effects", []), player, qlog(), {"npc": npc})
	if not visible:
		_unlock_at_frame = -1
		return
	_render()


func _render() -> void:
	var node := _node(node_id)
	var speaker := str(node.get("speaker", npc_id))
	_name.text = speaker_name(speaker)
	var key := str(node.get("say", ""))
	if node.has("say_pool"):
		var pool: Array = node["say_pool"]
		key = str(pool[int(_visits.get(npc_id, 0)) % maxi(pool.size(), 1)]) if not pool.is_empty() else ""
	_text.text = Texts.t(key) if key != "" else ""
	for child in _options.get_children():
		child.queue_free()
	_shown_options.clear()
	var ql := qlog()
	for opt: Variant in node.get("options", []):
		var o: Dictionary = opt
		if _shown_options.size() >= MAX_OPTIONS:
			break
		if StoryCond.check(o.get("if", {}), ql, player, {"npc": npc}):
			_shown_options.append(o)
	for i in _shown_options.size():
		var b := Button.new()
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.text = "%d.  %s" % [i + 1, Texts.t(str(_shown_options[i].get("text", "")))]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 34)
		var idx := i
		b.pressed.connect(func() -> void: choose(idx))
		_options.add_child(b)
	_hint.text = Texts.t("ui.dialogue.choose") if not _shown_options.is_empty() \
		else Texts.t("ui.dialogue.next", [InputSetup.key_label(&"interact")])


## A speaker's shown name: npcs.json's name key, else the id.
static func speaker_name(id: String) -> String:
	var n := StoryDB.npc(id)
	return Texts.t(str(n["name"])) if n.has("name") else id.capitalize()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"toggle_cursor"):
		close()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"interact") or (event is InputEventKey and (event as InputEventKey).pressed
			and not (event as InputEventKey).echo and (event as InputEventKey).physical_keycode == KEY_SPACE):
		advance()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var k := (event as InputEventKey).physical_keycode
		if k >= KEY_1 and k <= KEY_4:
			choose(k - KEY_1)
			get_viewport().set_input_as_handled()


func _on_setting_changed(key: String) -> void:
	if (key == "general/language" or key == "keys") and visible:
		_render()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.apply(_root)
	add_child(_root)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.offset_left = -PANEL_W * 0.5
	panel.offset_right = PANEL_W * 0.5
	panel.offset_top = -PANEL_H - 36.0
	panel.offset_bottom = -36.0
	panel.add_theme_stylebox_override("panel", UiTheme.nine("frame.png", 16, 18))
	_root.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)
	_portrait = PortraitView.new()
	_portrait.custom_minimum_size = Vector2(196, 196)
	_portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_portrait)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	row.add_child(col)
	_name = Label.new()
	_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_name.add_theme_font_override("font", UiTheme.font(true))
	_name.add_theme_font_size_override("font_size", 34)
	_name.add_theme_color_override("font_color", GOLD)
	col.add_child(_name)
	_text = Label.new()
	_text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.add_theme_color_override("font_color", UiTheme.TEXT)
	_text.add_theme_constant_override("line_spacing", 6)
	col.add_child(_text)
	_options = VBoxContainer.new()
	_options.add_theme_constant_override("separation", 4)
	col.add_child(_options)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)
	_hint = UiTheme.caption("")
	_hint.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(_hint)
