class_name DebugOverlay
extends CanvasLayer
## F1 toggles the panel. Hotkeys work while the panel is open:
## 1 spawn rusher, 2 spawn caster, 3 kill all, H heal, G god mode,
## R reset lab, C reset cooldowns, T stress test, V cycle visual style,
## O character outline (LookDev; on is the Gate-0 look, off for comparison),
## 0 +500 gold, L learn every trainer ability (M07b).

var lab: Node  # CombatLab, untyped to avoid a load cycle

var _panel: PanelContainer
var _info: Label
var _visible: bool = false
var _frame_times: Array[float] = []


func setup(combat_lab: Node) -> void:
	lab = combat_lab
	layer = 10
	_panel = PanelContainer.new()
	_panel.position = Vector2(12, 12)
	add_child(_panel)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 14)
	_panel.add_child(_info)
	_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_toggle"):
		_visible = not _visible
		_panel.visible = _visible
		return
	if not _visible:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_1:
			lab.call(&"spawn_rusher")
		KEY_2:
			lab.call(&"spawn_caster")
		KEY_3:
			lab.call(&"kill_all_enemies")
		KEY_4:
			lab.call(&"spawn_assassin")
		KEY_5:
			lab.call(&"spawn_brute")
		KEY_6:
			lab.call(&"spawn_elite")
		KEY_7:
			lab.call(&"debug_drop_item", false)
		KEY_8:
			lab.call(&"debug_drop_item", true)
		KEY_9:
			lab.call(&"wipe_save")
		KEY_0:
			lab.call(&"debug_add_gold", 500)
		KEY_L:
			(lab.get(&"player") as Player).debug_learn_all()
		KEY_H:
			lab.call(&"heal_player")
		KEY_G:
			lab.call(&"toggle_god_mode")
		KEY_R:
			lab.call(&"reset_lab")
		KEY_C:
			lab.call(&"reset_cooldowns")
		KEY_T:
			lab.call(&"stress_test")
		KEY_V:
			lab.call(&"cycle_style")
		KEY_O:
			LookDev.apply({&"outline": not bool(LookDev.get_value(&"outline", true))})


func _process(delta: float) -> void:
	_frame_times.append(delta)
	if _frame_times.size() > 60:
		_frame_times.pop_front()
	if not _visible:
		return
	var worst := 0.0
	for t in _frame_times:
		worst = maxf(worst, t)
	var player: Player = lab.get(&"player")
	var god_text := "ON" if (player != null and player.god_mode) else "off"
	_info.text = "FPS %d  |  worst frame %.1f ms\nenemies: %d   style: %s   god: %s\n\n[1] rusher  [2] caster  [3] kill all\n[4] assassin  [5] brute  [6] elite\n[7] drop item  [8] drop legendary  [9] fresh start\n[0] +500 gold  [L] learn all abilities\n[H] heal  [G] god  [R] reset  [C] cooldowns\n[T] stress test  [V] style  [I] inventory\n[O] outline %s" % [
		Engine.get_frames_per_second(),
		worst * 1000.0,
		lab.call(&"enemy_count"),
		lab.get(&"style_name"),
		god_text,
		"ON" if bool(LookDev.get_value(&"outline", true)) else "off",
	]
