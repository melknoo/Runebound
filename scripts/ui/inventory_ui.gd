class_name InventoryUI
extends HBoxContainer
## Inventory tab of the hero window (`I`): equipped slots | inventory list |
## detail + compare pane. M07b: a page inside HeroUI, which owns the frame,
## the input lock and the mouse; `toggle()` still opens/closes it. M10b: the
## consumables sit above the bag list (counted, no slot); right-click drinks.

var player: Player
var hero: HeroUI

var _equip_column: VBoxContainer
var _list_column: VBoxContainer
var _list_box: VBoxContainer
var _bag_box: VBoxContainer
var _detail: VBoxContainer
var _selected: ItemData = null
var _selected_consumable: StringName = &""


func setup(p: Player, hero_ui: HeroUI = null) -> void:
	player = p
	hero = hero_ui
	player.equipment.changed.connect(_refresh)
	player.consumables_changed.connect(_refresh)
	player.health.health_changed.connect(func(_c: float, _m: float) -> void: _refresh())  # "Health is full"
	_build()
	visible = false


func _build() -> void:
	add_theme_constant_override("separation", 18)
	var columns := self

	_equip_column = _column(columns, "EQUIPPED", 230)
	_list_column = _column(columns, "INVENTORY", 320)
	_bag_box = VBoxContainer.new()  # M10b: consumables, above the gear
	_bag_box.add_theme_constant_override("separation", 4)
	_list_column.add_child(_bag_box)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(320, 390)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_column.add_child(scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list_box)
	_detail = _column(columns, "DETAILS", 320)


func _column(parent: Control, title: String, width: float) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(width, 0)
	col.add_theme_constant_override("separation", 6)
	parent.add_child(col)
	var label := Label.new()
	label.text = title
	label.add_theme_font_override("font", UiTheme.font(true))
	label.add_theme_font_size_override("font_size", UiTheme.TITLE)
	label.add_theme_color_override("font_color", ArtKit.color("color_roles.player_accent.body", Color(0.5, 0.85, 0.8)))
	col.add_child(label)
	return col


## Opens the hero window on this tab, or closes it when this tab is showing.
func toggle() -> void:
	if hero != null:
		hero.toggle_tab(HeroUI.Tab.INVENTORY)
	else:
		visible = not visible
		refresh()


func refresh() -> void:
	_refresh()


func _refresh() -> void:
	if not visible:
		return
	# Equipped column: all 7 slots in body order.
	for child in _equip_column.get_children().slice(1):
		child.queue_free()
	for slot: ItemData.Slot in ItemData.SLOT_ORDER:
		var item: ItemData = player.equipment.equipped.get(slot)
		var btn := Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if item != null:
			btn.text = "%s: %s" % [ItemData.slot_name(slot), item.display_name]
			btn.icon = UiTheme.item_icon(item)
			btn.add_theme_color_override("font_color", ItemData.rarity_color(item.rarity))
			btn.pressed.connect(_select.bind(item))
			btn.tooltip_text = "Right-click: take off"
			btn.gui_input.connect(_on_right_click.bind(func() -> void: _unequip(slot)))
		else:
			btn.text = "%s: —" % ItemData.slot_name(slot)
			btn.disabled = true
		_equip_column.add_child(btn)

	# Inventory list.
	var title := _list_column.get_child(0) as Label
	title.text = "INVENTORY (%d/%d)" % [player.equipment.inventory.size(), Equipment.INVENTORY_CAP]
	for child in _bag_box.get_children():
		child.queue_free()
	for cid: StringName in Consumables.DEFS:
		var count := player.consumable_count(cid)
		var bag_btn := Button.new()
		bag_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		bag_btn.text = "%s  %d/%d" % [Consumables.display_name(cid), count, Consumables.cap(cid)]
		bag_btn.icon = Hud.icon(cid)
		var tone := ArtKit.color("palettes.burnt_forest.ember.2", Color("#D86A2C")) if Consumables.is_food(cid) \
			else ArtKit.color("color_roles.health.hot", Color("#FF9C9C"))
		bag_btn.add_theme_color_override("font_color", tone if count > 0 else UiTheme.MUTED)
		bag_btn.tooltip_text = "Right-click: eat" if Consumables.is_food(cid) else "Right-click: drink"
		bag_btn.pressed.connect(_select_consumable.bind(cid))
		bag_btn.gui_input.connect(_on_right_click.bind(func() -> void: _drink(cid)))
		_bag_box.add_child(bag_btn)
	for child in _list_box.get_children():
		child.queue_free()
	for item in player.equipment.inventory:
		var btn := Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.text = item.display_name
		btn.icon = UiTheme.item_icon(item)
		btn.add_theme_color_override("font_color", ItemData.rarity_color(item.rarity))
		btn.pressed.connect(_select.bind(item))
		btn.tooltip_text = "Right-click: equip"
		btn.gui_input.connect(_on_right_click.bind(func() -> void: _equip(item)))
		_list_box.add_child(btn)

	_render_detail()


func _select(item: ItemData) -> void:
	_selected = item
	_selected_consumable = &""
	_render_detail()


func _select_consumable(cid: StringName) -> void:
	_selected = null
	_selected_consumable = cid
	_render_detail()


## M10b: drink one (or say why not).
func _drink(cid: StringName) -> void:
	var why := player.consumable_deny_reason(cid)
	if why != "" or not player.use_consumable(cid):
		player.ui_denied()
		var zone := ZoneBase.zone_of(player)
		if zone != null and zone.hud != null:
			zone.hud.toast(why if why != "" else "Can't drink now", UiTheme.MUTED)
		return
	_selected_consumable = cid


func _render_detail() -> void:
	for child in _detail.get_children().slice(1):
		child.queue_free()
	if _selected_consumable != &"":
		_render_consumable(_selected_consumable)
		return
	if _selected == null:
		return
	var item := _selected
	_add_detail_label(item.display_name, ItemData.rarity_color(item.rarity))
	_add_detail_label("%s · %s · Item Level %d" % [ItemData.rarity_name(item.rarity), ItemData.slot_name(item.slot),
		item.item_level], Color(0.7, 0.7, 0.75))
	for affix in item.affixes:
		_add_detail_label("· " + String(affix["label"]), Color(0.85, 0.85, 0.9))
	if item.legendary_text != "":
		_add_detail_label(item.legendary_text, Color(1.0, 0.6, 0.25), true)

	var in_inventory := player.equipment.inventory.has(item)
	var equipped_same: ItemData = player.equipment.equipped.get(item.slot)
	if in_inventory and equipped_same != null and equipped_same != item:
		_add_detail_label(" ", Color.WHITE)
		_add_detail_label("Currently equipped: " + equipped_same.display_name,
			ItemData.rarity_color(equipped_same.rarity))
		for affix in equipped_same.affixes:
			_add_detail_label("· " + String(affix["label"]), Color(0.55, 0.55, 0.6))
		# M07 compare: what equipping this would change, stat by stat.
		for line: Array in compare_lines(item, equipped_same, player):
			_add_detail_label(line[0], line[1])

	if in_inventory:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_detail.add_child(row)
		var equip_btn := Button.new()
		equip_btn.text = "Equip"
		equip_btn.pressed.connect(func() -> void: _equip(item))
		row.add_child(equip_btn)
		var drop_btn := Button.new()
		drop_btn.text = "Discard"
		drop_btn.pressed.connect(func() -> void:
			player.equipment.discard(item)
			SaveGame.request_save()
			_selected = null
		)
		row.add_child(drop_btn)
	elif player.equipment.equipped.get(item.slot) == item:
		# M08 notes (user 2026-09-28): gear can come off again.
		var off_btn := Button.new()
		off_btn.text = "Unequip"
		off_btn.pressed.connect(func() -> void: _unequip(item.slot))
		_detail.add_child(off_btn)


func _render_consumable(cid: StringName) -> void:
	var count := player.consumable_count(cid)
	_add_detail_label(Consumables.display_name(cid), ArtKit.color("color_roles.health.hot", Color("#FF9C9C")))
	_add_detail_label("Consumable · %d/%d in the bag" % [count, Consumables.cap(cid)], Color(0.7, 0.7, 0.75))
	_add_detail_label(Consumables.text(cid), Color(0.85, 0.85, 0.9), true)
	var why := player.consumable_deny_reason(cid)
	var drink_btn := Button.new()
	drink_btn.text = ("Eat" if Consumables.is_food(cid) else "Drink") if why == "" else why
	drink_btn.disabled = why != ""
	drink_btn.pressed.connect(func() -> void: _drink(cid))
	_detail.add_child(drink_btn)


func _equip(item: ItemData) -> void:
	player.equipment.equip(item)
	Sfx.play_ui("equip", -4.0)
	SaveGame.request_save()
	_selected = item


## Into the bag, or a "full" note (the item stays on).
func _unequip(slot: ItemData.Slot) -> void:
	var item: ItemData = player.equipment.equipped.get(slot)
	if player.equipment.unequip(slot):
		Sfx.play_ui("equip", -8.0)
		SaveGame.request_save()
		_selected = item
		return
	player.ui_denied()
	var zone := ZoneBase.zone_of(player)
	if zone != null and zone.hud != null:
		zone.hud.toast("Inventory full", UiTheme.MUTED)


func _on_right_click(event: InputEvent, action: Callable) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
		action.call()


## [text, colour] per stat that differs between two items (green = gain).
## Stat names live in StatSheet.STAT_NAMES (shared with the character sheet).
static func compare_lines(candidate: ItemData, current: ItemData, hero: Player = null) -> Array:
	var totals := {}
	for affix in candidate.affixes:
		totals[affix["stat"]] = float(totals.get(affix["stat"], 0.0)) + float(affix["value"])
	for affix in current.affixes:
		totals[affix["stat"]] = float(totals.get(affix["stat"], 0.0)) - float(affix["value"])
	var lines := []
	for key: StringName in totals:
		var delta := float(totals[key])
		if absf(delta) < 0.01:
			continue
		lines.append([StatSheet.stat_text(key, delta, hero), Color(0.45, 0.9, 0.5) if delta > 0.0 else Color(0.95, 0.4, 0.38)])
	if candidate.legendary_id != current.legendary_id:
		if candidate.legendary_id != &"":
			lines.append(["+ legendary power: " + candidate.display_name, Color(1.0, 0.6, 0.25)])
		if current.legendary_id != &"":
			lines.append(["- loses legendary power: " + current.display_name, Color(0.95, 0.4, 0.38)])
	return lines


func _add_detail_label(text: String, color: Color, wrap: bool = false) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(300, 0)
	_detail.add_child(label)
