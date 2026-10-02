class_name LoadoutTab
extends VBoxContainer
## M10 abilities tab of the hero window (K): the loadout. LMB (the class's
## basic attack) and Space (dodge) are fixed; four free slots (RMB, 1, 2, 3)
## take any learned ability of the class's pool. Click a slot, then an
## ability; right-click a slot empties it. Changes only out of combat (the
## sprint's 3 s rule, Player.loadout_locked_reason).

const SLOT_WIDTH := 250.0

var player: Player
var hero: HeroUI

var _status: Label
var _slot_buttons: Array[Button] = []
var _fixed_row: HBoxContainer
var _pool_box: GridContainer
var _detail_title: Label
var _detail_text: Label
var _selected: int = -1
var _hovered: StringName = &""
var _lock_check: float = 0.0


func setup(p: Player, hero_ui: HeroUI = null) -> void:
	player = p
	hero = hero_ui
	player.loadout_changed.connect(refresh)
	player.abilities_changed.connect(refresh)
	player.progression.talents_changed.connect(refresh)
	_build()
	visible = false


func _build() -> void:
	add_theme_constant_override("separation", 12)
	var head := Label.new()
	head.text = "Your basic attack (LMB) and dodge (SPC) are fixed. Choose four abilities for RMB, 1, 2 and 3:" \
		+ " click a slot, then an ability. Right-click empties a slot."
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.custom_minimum_size = Vector2(1080, 0)
	head.add_theme_color_override("font_color", UiTheme.MUTED)
	add_child(head)
	_status = Label.new()
	add_child(_status)

	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 10)
	add_child(slots)
	for i in Player.LOADOUT_SIZE:
		var btn := _ability_button(SLOT_WIDTH)
		btn.toggle_mode = true
		btn.pressed.connect(_on_slot_pressed.bind(i))
		btn.gui_input.connect(func(event: InputEvent) -> void:
			var mb := event as InputEventMouseButton
			if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
				clear_slot(i)
		)
		btn.mouse_entered.connect(func() -> void:
			_hovered = player.loadout[i] if i < player.loadout.size() else &""
			_render_detail()
		)
		slots.add_child(btn)
		_slot_buttons.append(btn)

	_fixed_row = HBoxContainer.new()
	_fixed_row.add_theme_constant_override("separation", 24)
	add_child(_fixed_row)

	var pool_title := Label.new()
	pool_title.text = "%s ABILITIES" % player.class_data.display_name.to_upper()
	pool_title.add_theme_font_override("font", UiTheme.font(true))
	pool_title.add_theme_font_size_override("font_size", UiTheme.TITLE)
	pool_title.add_theme_color_override("font_color", ArtKit.color("color_roles.player_accent.body", Color(0.5, 0.85, 0.8)))
	add_child(pool_title)
	_pool_box = GridContainer.new()
	_pool_box.columns = 2
	_pool_box.add_theme_constant_override("h_separation", 16)
	_pool_box.add_theme_constant_override("v_separation", 8)
	_pool_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_pool_box)

	_detail_title = Label.new()
	_detail_title.add_theme_color_override("font_color", ArtKit.color("color_roles.resonance.hot"))
	add_child(_detail_title)
	_detail_text = Label.new()
	_detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_text.custom_minimum_size = Vector2(1080, 44)
	add_child(_detail_text)


func _ability_button(width: float) -> Button:
	var btn := Button.new()
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(width, 52)
	btn.expand_icon = false
	btn.focus_mode = Control.FOCUS_NONE
	return btn


## Opens the hero window on this tab, or closes it when this tab is showing.
func toggle() -> void:
	if hero != null:
		hero.toggle_tab(HeroUI.Tab.LOADOUT)


func _process(delta: float) -> void:
	if not visible:
		return
	_lock_check -= delta
	if _lock_check <= 0.0:
		_lock_check = 0.25
		_render_status()


# ---------------------------------------------------------------------------
# Actions (tests call these directly)
# ---------------------------------------------------------------------------

## Puts `id` into slot `slot`. Refused in combat or for unknown abilities
## (a toast says why); true when the loadout changed.
func assign(slot: int, id: StringName) -> bool:
	var reason := player.set_loadout_slot(slot, id)
	if reason != "":
		_deny(reason)
		return false
	Sfx.play_ui("equip", -6.0)
	SaveGame.request_save()
	return true


func clear_slot(slot: int) -> bool:
	if slot < 0 or slot >= player.loadout.size() or player.loadout[slot] == &"":
		return false
	return assign(slot, &"")


## A pool ability was clicked: into the selected slot, else the first free
## one, else the hint to pick a slot.
func pick(id: StringName) -> bool:
	if not player.knows(id):
		_deny("Not learned yet")
		return false
	var slot := _selected
	if slot < 0:
		slot = player.loadout.find(&"")
	if slot < 0:
		_deny("Click a slot first")
		return false
	var ok := assign(slot, id)
	if ok:
		_selected = -1
	return ok


func _on_slot_pressed(i: int) -> void:
	_selected = -1 if _selected == i else i
	refresh()


func _deny(reason: String) -> void:
	Sfx.play_ui("ui_denied", -8.0)
	_status.text = reason
	_status.add_theme_color_override("font_color", Color("#E08A7A"))
	_lock_check = 1.5  # keep the reason up for a moment
	var zone := ZoneBase.zone_of(player)
	if zone != null and zone.hud != null:
		zone.hud.toast(reason, UiTheme.MUTED)


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

func refresh() -> void:
	if player == null:
		return
	for i in _slot_buttons.size():
		var btn := _slot_buttons[i]
		var id: StringName = player.loadout[i] if i < player.loadout.size() else &""
		var data := player.ability(id)
		btn.icon = Hud.icon(id) if id != &"" else null
		btn.text = "%s   %s" % [InputSetup.slot_label(i), data.title() if data != null else "(empty)"]
		btn.set_pressed_no_signal(i == _selected)
		btn.add_theme_color_override("font_color", UiTheme.TEXT if data != null else UiTheme.MUTED)
	for child in _fixed_row.get_children():
		child.queue_free()
	for fixed: Array in [["LMB", player.basic_attack()], ["SPC", &"dodge"]]:
		var label := Label.new()
		var fixed_data := player.ability(fixed[1])
		label.text = "%s  %s  (fixed)" % [fixed[0], fixed_data.title() if fixed_data != null else "Dodge"]
		label.add_theme_color_override("font_color", UiTheme.MUTED)
		_fixed_row.add_child(label)
	for child in _pool_box.get_children():
		child.queue_free()
	for data in player.pool():
		_pool_box.add_child(_pool_entry(data))
	_render_status()
	_render_detail()


func _pool_entry(data: AbilityData) -> Button:
	var btn := _ability_button(530.0)
	btn.icon = Hud.icon(data.id)
	var known := player.knows(data.id)
	var slot := player.slot_of(data.id)
	var where := ""
	if slot >= 0:
		where = "in slot %s" % InputSetup.slot_label(slot)
	elif known:
		where = "learned"
	elif data.unlock == AbilityData.Unlock.TALENT:
		where = "talent"
	elif data.unlock == AbilityData.Unlock.TOME:
		where = Texts.t("ui.loadout.tome")  # M12
	else:
		where = "trainer: level %d, %d gold" % [data.learn_level, data.learn_price]
	btn.text = "%s   -   %s" % [data.title(), where]
	btn.disabled = not known
	var color := HitInfo.type_color(data.damage_type) if known else UiTheme.MUTED
	btn.add_theme_color_override("font_color", color)
	btn.add_theme_color_override("font_disabled_color", Color(0.45, 0.43, 0.5))
	btn.pressed.connect(func() -> void: pick(data.id))
	btn.mouse_entered.connect(func() -> void:
		_hovered = data.id
		_render_detail()
	)
	return btn


func _render_status() -> void:
	if _lock_check > 0.3:
		return  # a refusal is showing
	var locked := player.loadout_locked_reason()
	if locked != "":
		_status.text = "In combat: the loadout can change %.0f s after the last hit." % Player.SPRINT_COMBAT_LOCK
		_status.add_theme_color_override("font_color", Color("#E08A7A"))
	elif _selected >= 0:
		_status.text = "Slot %s selected: click an ability for it." % InputSetup.slot_label(_selected)
		_status.add_theme_color_override("font_color", ArtKit.color("color_roles.player_accent.hot"))
	else:
		_status.text = ""


func _render_detail() -> void:
	var data := player.ability(_hovered) if _hovered != &"" else null
	if data == null:
		_detail_title.text = ""
		_detail_text.text = "Hover an ability for details. New abilities come from the trainer and the talent tree."
		return
	_detail_title.text = data.title()
	var parts: PackedStringArray = [data.summary()]
	var dmg := StatSheet.damage_text(player, data)
	if dmg != "":
		parts.append(dmg)
	var cost := player.resource_cost(data.id)
	if cost > 0.0:
		parts.append("Costs %d %s" % [roundi(cost), player.class_data.resource_label])
	if data.cooldown > 0.0:
		parts.append("Cooldown %.1f s" % StatSheet.effective_cooldown(player, data))
	_detail_text.text = "   ".join(parts)
