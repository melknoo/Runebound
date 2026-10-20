class_name StoryCutscene
extends CanvasLayer
## M14a: a short camera pan (STORY_DESIGN "The campaign": the shard strikes,
## the bridge breaks, Sigrun sees the glow, the empty socket). Black bars top
## and bottom, the HUD and the tracker away, the hero still; its own camera
## glides between anchors and looks at one, a line of text under it, small
## effects on cue, an act card at the end. Esc, the interact key or Space
## skip it. It never pauses the world (online the others play on) and plays
## on this machine only. Headless runs (tests, the server) finish at once.
##
## `resources/story/cutscenes.json` = {"cutscenes": {id: {
##   "safe": true (wait until the hero is out of combat),
##   "shots": [{"from": anchor, "to": anchor, "look": anchor, "t": seconds,
##              "say": key, "speaker": npc id}],
##   "fx": [{"t": seconds, "kind": "shard_fall" | "flash" | "shake" | "sfx",
##           "at": anchor, "name": sfx}],
##   "card": {"title": key, "sub": key}, "on_end": [effects]}}}
## An anchor is [x, y, z], or {"at": "hero" | "npc:<id>" | "marker:<id>" |
## "poi:<id>", "offset": [x, y, z], "local": true (offset turns with it)}.

signal finished(id: String)

const BAR_HEIGHT := 92.0
const SAFE_WAIT_MAX := 10.0

var zone: ZoneBase
var id: String = ""
var playing: bool = false

var _data: Dictionary = {}
var _cam: Camera3D = null
var _shot: int = 0
var _shot_t: float = 0.0
var _elapsed: float = 0.0
var _fx_done: Array[int] = []
var _safe_wait: float = -1.0
var _bars: Array[ColorRect] = []
var _speaker: Label
var _line: Label
var _skip_hint: Label


func setup(z: ZoneBase) -> void:
	zone = z
	layer = 15
	name = "StoryCutscene"
	_build()
	visible = false


## Plays camera pan `cut_id`; false when it doesn't exist or one plays.
## `instant` finishes at once (headless runs always do).
func play(cut_id: String, instant: bool = false) -> bool:
	var data := StoryDB.cutscene(cut_id)
	if data.is_empty() or playing:
		return false
	id = cut_id
	_data = data
	playing = true
	if instant or DisplayServer.get_name() == "headless":
		_finish()
		return true
	var hero := zone.player
	if bool(data.get("safe", true)) and hero != null and hero.in_combat():
		_safe_wait = 0.0  # starts once the fight is over
		return true
	_start()
	return true


## Tests: plays it the windowed way even in a headless run.
func play_forced(cut_id: String) -> bool:
	var data := StoryDB.cutscene(cut_id)
	if data.is_empty() or playing:
		return false
	id = cut_id
	_data = data
	playing = true
	_start()
	return true


func _start() -> void:
	_safe_wait = -1.0
	var hero := zone.player
	if hero != null and is_instance_valid(hero):
		hero.input_locked = true
		hero.velocity = Vector3.ZERO
	zone.close_windows()
	if zone.hud != null:
		zone.hud.visible = false
	if zone.quest_tracker != null:
		zone.quest_tracker.suppressed = true
	_cam = Camera3D.new()
	_cam.name = "CutsceneCamera"
	var rig_cam := zone.camera_rig.camera if zone.camera_rig != null else null
	if rig_cam != null:
		_cam.fov = rig_cam.fov
		_cam.far = rig_cam.far
		_cam.near = rig_cam.near
	zone.world.add_child(_cam)
	if rig_cam != null:
		_cam.global_transform = rig_cam.global_transform
	_cam.make_current()
	_shot = 0
	_shot_t = 0.0
	_elapsed = 0.0
	_fx_done.clear()
	visible = true
	_show_line()
	_place(0.0)


func _process(delta: float) -> void:
	if not playing:
		return
	if _safe_wait >= 0.0:
		_safe_wait += delta
		var hero := zone.player
		if hero == null or not hero.in_combat() or _safe_wait > SAFE_WAIT_MAX:
			_start()
		return
	if _cam == null:
		return
	_elapsed += delta
	_shot_t += delta
	var fx: Array = _data.get("fx", [])
	for i in fx.size():
		var f: Dictionary = fx[i]
		if not _fx_done.has(i) and _elapsed >= float(f.get("t", 0.0)):
			_fx_done.append(i)
			_play_fx(f)
	var shots: Array = _data.get("shots", [])
	if shots.is_empty():
		_finish()
		return
	var shot: Dictionary = shots[_shot]
	var dur := maxf(float(shot.get("t", 2.0)), 0.05)
	if _shot_t >= dur:
		_shot += 1
		_shot_t = 0.0
		if _shot >= shots.size():
			_finish()
			return
		_show_line()
	_place(clampf(_shot_t / dur, 0.0, 1.0))


## Esc, interact or Space skip (before the pause menu sees Esc).
func _input(event: InputEvent) -> void:
	if not playing or not visible:
		return
	var skip := event.is_action_pressed(&"toggle_cursor") or event.is_action_pressed(&"interact") \
		or (event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo
			and (event as InputEventKey).physical_keycode == KEY_SPACE)
	if skip:
		get_viewport().set_input_as_handled()
		skip_now()


func skip_now() -> void:
	if playing:
		_finish()


func _finish() -> void:
	var was_shown := visible
	playing = false
	_safe_wait = -1.0
	visible = false
	if _cam != null:
		if zone.camera_rig != null and zone.camera_rig.camera != null:
			zone.camera_rig.camera.make_current()
		_cam.queue_free()
		_cam = null
	if zone.hud != null:
		zone.hud.visible = true
	if zone.quest_tracker != null:
		zone.quest_tracker.suppressed = false
	var hero := zone.player
	if was_shown and hero != null and is_instance_valid(hero):
		hero.input_locked = false
	var card: Variant = _data.get("card", {})
	if card is Dictionary and not (card as Dictionary).is_empty() and zone.hud != null:
		var c: Dictionary = card
		zone.hud.title_card(Texts.t(str(c.get("title", ""))), Texts.t(str(c["sub"])) if c.has("sub") else "")
	if hero != null and is_instance_valid(hero):
		var ql := QuestLog.of(hero)
		ql.mark_seen(id)
		StoryEffects.apply(_data.get("on_end", []), hero, ql)
	finished.emit(id)


func _place(k: float) -> void:
	var shots: Array = _data.get("shots", [])
	if _shot >= shots.size():
		return
	var shot: Dictionary = shots[_shot]
	var a := resolve(shot.get("from", {"at": "hero", "offset": [0, 3, 6]}))
	var b := resolve(shot.get("to", shot.get("from", {"at": "hero", "offset": [0, 3, 6]})))
	var e := k * k * (3.0 - 2.0 * k)  # smoothstep
	_cam.global_position = a.lerp(b, e)
	var look := resolve(shot.get("look", {"at": "hero", "offset": [0, 1.4, 0]}))
	if look.distance_to(_cam.global_position) > 0.05:
		_cam.look_at(look, Vector3.UP)


## A world point for an anchor (see the header); the hero's feet when it
## can't be found.
func resolve(anchor: Variant) -> Vector3:
	if anchor is Array and (anchor as Array).size() == 3:
		var v: Array = anchor
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	var d: Dictionary = anchor if anchor is Dictionary else {"at": str(anchor)}
	var at := str(d.get("at", "hero"))
	var base := Vector3.ZERO
	var basis := Basis.IDENTITY
	var node: Node3D = null
	if at == "hero":
		node = zone.player
	elif at.begins_with("npc:") or at.begins_with("marker:"):
		var key := at.get_slice(":", 1)
		for n in get_tree().get_nodes_in_group(&"story_target"):
			if n is Node3D and str(n.get_meta(&"story_id", "")) == key:
				node = n as Node3D
				break
	elif at.begins_with("poi:"):
		var p := zone.poi_position(at.get_slice(":", 1))
		base = p if p != Vector3.INF else Vector3.ZERO
	if node != null and is_instance_valid(node):
		base = node.global_position
		basis = Basis(Vector3.UP, node.global_rotation.y)
	elif at == "hero" or at.begins_with("npc:") or at.begins_with("marker:"):
		base = zone.player.global_position if zone.player != null else Vector3.ZERO
	var off := Vector3.ZERO
	if d.has("offset"):
		var o: Array = d["offset"]
		off = Vector3(float(o[0]), float(o[1]), float(o[2]))
	if bool(d.get("local", false)):
		off = basis * off
	return base + off


func _show_line() -> void:
	var shots: Array = _data.get("shots", [])
	var shot: Dictionary = shots[_shot] if _shot < shots.size() else {}
	var say := str(shot.get("say", ""))
	_line.text = Texts.t(say) if say != "" else ""
	var who := str(shot.get("speaker", ""))
	_speaker.text = DialogueUI.speaker_name(who) if who != "" else ""
	_speaker.visible = _speaker.text != ""


func _play_fx(f: Dictionary) -> void:
	var at := resolve(f.get("at", {"at": "hero"}))
	match str(f.get("kind", "")):
		"shard_fall":
			_shard_fall(at, float(f.get("fall", 1.1)))
		"flash":
			VFX.flash(zone.world, at + Vector3(0, 1.2, 0), ArtKit.color("color_roles.player_accent.hot", Color("#9FF2E6")), 2.2, 0.3)
			VFX.light_pop(zone.world, at + Vector3(0, 1.5, 0), ArtKit.color("color_roles.player_accent.hot", Color("#9FF2E6")), 4.0, 8.0, 0.5)
		"shake":
			if zone.camera_rig != null:
				zone.camera_rig.add_trauma(float(f.get("amount", 0.5)))
		"sfx":
			Sfx.play_ui(str(f.get("name", "shatter_burst")), float(f.get("db", -4.0)))


## A rune shard falls burning out of the sky onto `at`: flash, light, sound.
func _shard_fall(at: Vector3, fall: float) -> void:
	var shard := PoiBuilder.prop(zone, "rune_shard", at + Vector3(0, 26, 0), randf() * TAU, 1.6) if PoiBuilder.has_art(zone) else null
	var teal := ArtKit.color("color_roles.player_accent.hot", Color("#9FF2E6"))
	if shard != null:
		var tw := shard.create_tween()
		tw.tween_property(shard, "global_position", at + Vector3(0, 0.4, 0), fall).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_callback(func() -> void:
			VFX.flash(zone.world, at + Vector3(0, 0.8, 0), teal, 3.0, 0.35)
			VFX.light_pop(zone.world, at + Vector3(0, 1.2, 0), teal, 6.0, 10.0, 0.6)
			VFX.ground_ring(zone.world, at, teal, 4.0, 0.5)
			Sfx.play_ui("shatter_burst", -2.0)
			if zone.camera_rig != null:
				zone.camera_rig.add_trauma(0.6)
			shard.queue_free())


func _build() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.apply(root)
	add_child(root)
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0, 1)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if top:
			bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
			bar.offset_bottom = BAR_HEIGHT
		else:
			bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
			bar.offset_top = -BAR_HEIGHT
		root.add_child(bar)
		_bars.append(bar)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	box.offset_top = -BAR_HEIGHT + 8.0
	box.offset_bottom = -8.0
	box.offset_left = 120.0
	box.offset_right = -120.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	root.add_child(box)
	_speaker = Label.new()
	_speaker.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_speaker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speaker.add_theme_color_override("font_color", Color("#E8B44A"))
	box.add_child(_speaker)
	_line = Label.new()
	_line.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.add_theme_color_override("font_color", UiTheme.TEXT)
	box.add_child(_line)
	_skip_hint = UiTheme.caption("")
	_skip_hint.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_skip_hint.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_skip_hint.offset_left = -360.0
	_skip_hint.offset_right = -24.0
	_skip_hint.offset_top = BAR_HEIGHT * 0.5 - 12.0
	_skip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_skip_hint.text = ""
	root.add_child(_skip_hint)
	visibility_changed.connect(func() -> void:
		if visible:
			_skip_hint.text = Texts.t("ui.cutscene.skip", [InputSetup.key_label(&"interact")]))
