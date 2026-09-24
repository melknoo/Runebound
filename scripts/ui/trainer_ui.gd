class_name TrainerUI
extends CanvasLayer
## M07b trainer panel: the class's TRAINER abilities with level requirement
## and gold price; Learn buys one. Opened by a TrainerNpc, closed with Esc.
## Locks combat input and frees the mouse like the other panels. Also nudges
## the player with a toast when an ability first becomes affordable.

var player: Player

var _root: Control
var _title: Label
var _flavour: Label
var _gold_label: Label
var _rows: VBoxContainer
var _announced: Array[StringName] = []
var _npc: TrainerNpc = null


func setup(p: Player) -> void:
	player = p
	layer = 8
	_build()
	visible = false
	player.progression.leveled_up.connect(func(_level: int) -> void: _maybe_announce())
	player.gold_changed.connect(func(_total: int, delta: int) -> void:
		if delta > 0:
			_maybe_announce()
	)


## Abilities the trainer sells this character, known ones last.
static func offers(p: Player) -> Array[AbilityData]:
	var out := p.class_data.trainer_abilities()
	out.sort_custom(func(a: AbilityData, b: AbilityData) -> bool:
		var ka := p.knows(a.id)
		var kb := p.knows(b.id)
		if ka != kb:
			return not ka
		if a.learn_level != b.learn_level:
			return a.learn_level < b.learn_level
		return a.learn_price < b.learn_price
	)
	return out


## Why `data` can't be bought right now; "" when it can.
static func deny_reason(p: Player, data: AbilityData) -> String:
	if p.knows(data.id):
		return "Learned"
	if p.progression.level < data.learn_level:
		return "Requires level %d" % data.learn_level
	if p.gold < data.learn_price:
		return "Need %d more gold" % (data.learn_price - p.gold)
	return ""


func try_buy(data: AbilityData) -> bool:
	if deny_reason(player, data) != "" or not player.spend_gold(data.learn_price):
		Sfx.play_ui("ui_denied", -8.0)
		return false
	player.learn_ability(data.id)
	Sfx.play_ui("ability_learned", -2.0)
	var scene := get_tree().current_scene
	VFX.flash(scene, player.global_position + Vector3(0, 1.2, 0), ArtKit.color("color_roles.resonance.hot"), 1.8, 0.25)
	VFX.ground_ring(scene, player.global_position, ArtKit.color("color_roles.resonance.body"), 2.6, 0.4)
	var zone := scene as ZoneBase
	if zone != null and zone.hud != null:
		zone.hud.toast("Learned %s  -  %s" % [data.display_name, Hud.key_for(player, data.id)],
			ArtKit.color("color_roles.resonance.hot", Color("#FFD97A")))
	SaveGame.save_now()
	_refresh()
	return true


func open(npc: TrainerNpc, p: Player = null) -> void:
	if p != null:
		player = p
	_npc = npc
	var zone := get_parent() as ZoneBase
	if zone != null and zone.hero_ui != null:
		zone.hero_ui.close()  # one window at a time
	if zone != null and zone.map_ui != null:
		zone.map_ui.close()
	visible = true
	player.input_locked = true
	_refresh()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	if not visible:
		return
	visible = false
	player.input_locked = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"toggle_cursor"):
		close()
		get_viewport().set_input_as_handled()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	UiTheme.apply(_root)
	add_child(_root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.01, 0.04, 0.6)
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(860, 560)
	panel.position = Vector2(-430, -280)
	panel.add_theme_stylebox_override("panel", UiTheme.nine("frame.png", 16, 18))
	_root.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	panel.add_child(body)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 20)
	body.add_child(top)
	_title = Label.new()
	_title.add_theme_font_override("font", UiTheme.font(true))
	_title.add_theme_font_size_override("font_size", UiTheme.TITLE)
	_title.add_theme_color_override("font_color", ArtKit.color("color_roles.resonance.body"))
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	var gold_box := HBoxContainer.new()
	gold_box.add_theme_constant_override("separation", 6)
	top.add_child(gold_box)
	var coin := TextureRect.new()
	coin.texture = Hud.icon(&"coin")
	coin.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	gold_box.add_child(coin)
	_gold_label = Label.new()
	_gold_label.add_theme_color_override("font_color", ArtKit.color("color_roles.resonance.hot", Color("#FFD97A")))
	_gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gold_box.add_child(_gold_label)
	top.add_child(UiTheme.close_button(close))

	_flavour = Label.new()
	_flavour.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_flavour.custom_minimum_size = Vector2(820, 0)
	_flavour.add_theme_color_override("font_color", UiTheme.MUTED)
	body.add_child(_flavour)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	_rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_rows)

	var footer := Label.new()
	footer.text = "[Esc] Leave"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer.add_theme_color_override("font_color", UiTheme.MUTED)
	body.add_child(footer)


func _refresh() -> void:
	if player == null:
		return
	_title.text = (_npc.npc_name if _npc != null else "Trainer").to_upper()
	_flavour.text = _npc.flavour_line() if _npc != null else ""
	_gold_label.text = str(player.gold)
	for child in _rows.get_children():
		child.queue_free()
	for data in offers(player):
		_rows.add_child(_row(data))


func _row(data: AbilityData) -> Control:
	var reason := deny_reason(player, data)
	var known := player.knows(data.id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(44, 44)
	row.add_child(slot)
	var frame := TextureRect.new()
	frame.texture = load(UiTheme.UI_DIR + "slot.png")
	slot.add_child(frame)
	var icon := TextureRect.new()
	icon.texture = Hud.icon(data.id)
	icon.position = Vector2(2, 2)
	icon.modulate = Color(0.55, 0.55, 0.6) if known else Color.WHITE
	slot.add_child(icon)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)
	var name_label := Label.new()
	var element := (HitInfo.DamageType.keys()[data.damage_type] as String).capitalize()
	name_label.text = "%s   %s   [%s]" % [data.display_name, element, Hud.key_for(player, data.id)]
	name_label.add_theme_color_override("font_color", UiTheme.MUTED if known else HitInfo.type_color(data.damage_type))
	text.add_child(name_label)
	var desc := Label.new()
	desc.text = data.description
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(520, 0)
	desc.add_theme_color_override("font_color", UiTheme.MUTED if known else UiTheme.TEXT)
	text.add_child(desc)

	var price := Label.new()
	price.custom_minimum_size = Vector2(150, 0)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	price.text = "Learned" if known else "Level %d  ·  %d gold" % [data.learn_level, data.learn_price]
	price.add_theme_color_override("font_color", UiTheme.MUTED if known else ArtKit.color("color_roles.resonance.hot", Color("#FFD97A")))
	row.add_child(price)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(150, 0)
	btn.text = "Learn" if reason == "" else reason
	btn.disabled = reason != ""
	btn.pressed.connect(func() -> void: try_buy(data))
	row.add_child(btn)
	return row


## Toast once per ability when the trainer could teach it right now (level
## and gold both met) - so the player knows a trip to Runehold pays off.
func _maybe_announce() -> void:
	if player == null or visible:
		return
	for data in player.class_data.trainer_abilities():
		if _announced.has(data.id) or deny_reason(player, data) != "":
			continue
		_announced.append(data.id)
		var zone := get_parent() as ZoneBase
		if zone != null and zone.hud != null:
			zone.hud.toast("Sigrun can teach you %s (%d gold)  -  Runehold" % [data.display_name, data.learn_price],
				ArtKit.color("color_roles.resonance.body", Color("#E8B23A")))
