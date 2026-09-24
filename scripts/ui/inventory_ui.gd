class_name InventoryUI
extends HBoxContainer
## Inventory tab of the hero window (`I`): equipped slots | inventory list |
## detail + compare pane. M07b: a page inside HeroUI, which owns the frame,
## the input lock and the mouse; `toggle()` still opens/closes it.

var player: Player
var hero: HeroUI

var _equip_column: VBoxContainer
var _list_column: VBoxContainer
var _list_box: VBoxContainer
var _detail: VBoxContainer
var _selected: ItemData = null


func setup(p: Player, hero_ui: HeroUI = null) -> void:
	player = p
	hero = hero_ui
	player.equipment.changed.connect(_refresh)
	_build()
	visible = false


func _build() -> void:
	add_theme_constant_override("separation", 18)
	var columns := self

	_equip_column = _column(columns, "EQUIPPED", 230)
	_list_column = _column(columns, "INVENTORY", 320)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(320, 440)
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
		else:
			btn.text = "%s: —" % ItemData.slot_name(slot)
			btn.disabled = true
		_equip_column.add_child(btn)

	# Inventory list.
	var title := _list_column.get_child(0) as Label
	title.text = "INVENTORY (%d/%d)" % [player.equipment.inventory.size(), Equipment.INVENTORY_CAP]
	for child in _list_box.get_children():
		child.queue_free()
	for item in player.equipment.inventory:
		var btn := Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.text = item.display_name
		btn.icon = UiTheme.item_icon(item)
		btn.add_theme_color_override("font_color", ItemData.rarity_color(item.rarity))
		btn.pressed.connect(_select.bind(item))
		_list_box.add_child(btn)

	_render_detail()


func _select(item: ItemData) -> void:
	_selected = item
	_render_detail()


func _render_detail() -> void:
	for child in _detail.get_children().slice(1):
		child.queue_free()
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
		for line: Array in compare_lines(item, equipped_same):
			_add_detail_label(line[0], line[1])

	if in_inventory:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_detail.add_child(row)
		var equip_btn := Button.new()
		equip_btn.text = "Equip"
		equip_btn.pressed.connect(func() -> void:
			player.equipment.equip(item)
			Sfx.play_ui("equip", -4.0)
			_selected = item
		)
		row.add_child(equip_btn)
		var drop_btn := Button.new()
		drop_btn.text = "Discard"
		drop_btn.pressed.connect(func() -> void:
			player.equipment.discard(item)
			_selected = null
		)
		row.add_child(drop_btn)


## [text, colour] per stat that differs between two items (green = gain).
## Stat names live in StatSheet.STAT_NAMES (shared with the character sheet).
static func compare_lines(candidate: ItemData, current: ItemData) -> Array:
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
		lines.append([StatSheet.stat_text(key, delta), Color(0.45, 0.9, 0.5) if delta > 0.0 else Color(0.95, 0.4, 0.38)])
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
