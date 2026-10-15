class_name InventoryUI
extends HBoxContainer
## Inventory tab of the hero window (`I`). Rig v3 (user 2026-10-14): WoW
## style. Left the paper doll: the hero in 3D (HeroLook in its own world, drag
## to turn) between the seven slot tiles, the weapon below. Right the bag:
## the consumables, a 6x4 icon grid with rarity frames and the bin. An
## instant tooltip shows an item and how equipping it compares (the equipped
## piece beside it); items move by drag and drop (bag -> slot or onto the
## hero = equip, slot -> bag = take off, bag -> bag = reorder, onto the bin =
## discard after asking) or right-click / double-click (equip, take off,
## drink). HeroUI owns the frame, the input lock and the mouse.

const TILE := 60
const ICON := 48  # the 16 px item art at 3x (its 32 px texture at 1.5x keeps whole art pixels)
const HUD_ICON := 40  # HUD icons (consumables, the bin): their 40 px texture 1:1
const COLS := 6
const LEFT_SLOTS: Array[ItemData.Slot] = [ItemData.Slot.HELM, ItemData.Slot.AMULET, ItemData.Slot.CHEST]
const RIGHT_SLOTS: Array[ItemData.Slot] = [ItemData.Slot.GLOVES, ItemData.Slot.RING, ItemData.Slot.BOOTS]
## Empty-slot silhouettes (assets/ui/items/<name>.png), by ItemData.Slot.
const SLOT_ICON: Array[String] = ["weapon", "armor", "relic", "helm", "gloves", "boots", "ring"]
const FRAME_EMPTY := Color(0.24, 0.22, 0.3)
const FILL := Color(0.06, 0.05, 0.09, 0.92)
const GAIN := Color(0.45, 0.9, 0.5)
const LOSS := Color(0.95, 0.4, 0.38)

var player: Player
var hero: HeroUI

var _slot_tiles: Dictionary = {}  # ItemData.Slot -> Tile
var _bag_tiles: Array[Tile] = []
## M10b: the consumables (a row of counted tiles above the grid).
var _bag_box: HBoxContainer
var _bag_title: Label
var _gold_label: Label
var _info: Label
var _doll: DollView
var _tooltip: PanelContainer
var _tip_row: HBoxContainer
var _hovered: Tile = null
var _confirm: Control = null
var _selected: ItemData = null


func setup(p: Player, hero_ui: HeroUI = null) -> void:
	player = p
	hero = hero_ui
	player.equipment.changed.connect(_refresh)
	player.consumables_changed.connect(_refresh)
	player.gold_changed.connect(func(_total: int, _delta: int) -> void: _refresh())
	player.health.health_changed.connect(func(_c: float, _m: float) -> void: _refresh())  # "Health is full"
	_build()
	visible = false
	visibility_changed.connect(_on_visibility_changed)


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

func _build() -> void:
	add_theme_constant_override("separation", 34)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(540, 0)
	left.add_theme_constant_override("separation", 6)
	add_child(left)
	left.add_child(_title(Texts.t("ui.inv.equipment")))
	var doll_row := HBoxContainer.new()
	doll_row.alignment = BoxContainer.ALIGNMENT_CENTER
	doll_row.add_theme_constant_override("separation", 22)
	left.add_child(doll_row)
	doll_row.add_child(_slot_column(LEFT_SLOTS))
	_doll = DollView.new()
	_doll.setup(self)
	doll_row.add_child(_doll)
	doll_row.add_child(_slot_column(RIGHT_SLOTS))
	var weapon_row := HBoxContainer.new()
	weapon_row.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_child(weapon_row)
	weapon_row.add_child(_slot_tile(ItemData.Slot.WEAPON))
	_info = Label.new()
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.add_theme_color_override("font_color", UiTheme.MUTED)
	left.add_child(_info)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(COLS * TILE + (COLS - 1) * 8, 0)
	right.add_theme_constant_override("separation", 10)
	add_child(right)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	right.add_child(head)
	_bag_title = _title("")
	head.add_child(_bag_title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var coin := TextureRect.new()
	coin.texture = Hud.icon(&"coin")
	coin.custom_minimum_size = Vector2(24, 24)
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(coin)
	_gold_label = Label.new()
	_gold_label.add_theme_color_override("font_color", ArtKit.color("color_roles.resonance.hot", Color("#FFD97A")))
	_gold_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_gold_label)
	_bag_box = HBoxContainer.new()
	_bag_box.add_theme_constant_override("separation", 8)
	right.add_child(_bag_box)
	for cid: StringName in Consumables.DEFS:
		var ct := Tile.make(self, &"consumable")
		ct.cid = cid
		ct.icon.texture = Hud.icon(cid)
		ct.icon.custom_minimum_size = Vector2(HUD_ICON, HUD_ICON)
		_bag_box.add_child(ct)
	var grid := GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	right.add_child(grid)
	for i in Equipment.INVENTORY_CAP:
		var t := Tile.make(self, &"bag")
		t.index = i
		grid.add_child(t)
		_bag_tiles.append(t)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	right.add_child(foot)
	var bin := Tile.make(self, &"bin")
	bin.icon.texture = Hud.icon(&"bin")
	bin.icon.custom_minimum_size = Vector2(HUD_ICON, HUD_ICON)
	if bin.icon.texture == null:
		bin.count.text = Texts.t("ui.inv.bin")
		bin.count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bin.count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	foot.add_child(bin)
	var hint := Label.new()
	hint.text = Texts.t("ui.inv.hint")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.add_theme_color_override("font_color", UiTheme.MUTED)
	foot.add_child(hint)

	# The tooltip floats over the whole window (top level: no container layout).
	_tooltip = PanelContainer.new()
	_tooltip.top_level = true
	_tooltip.visible = false
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.z_index = 10
	_tooltip.add_theme_stylebox_override("panel", _panel_style(Color(0.33, 0.62, 0.6)))
	_tip_row = HBoxContainer.new()
	_tip_row.add_theme_constant_override("separation", 14)
	_tip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.add_child(_tip_row)
	add_child(_tooltip)


func _title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UiTheme.font(true))
	label.add_theme_font_size_override("font_size", UiTheme.TITLE)
	label.add_theme_color_override("font_color", ArtKit.color("color_roles.player_accent.body", Color(0.5, 0.85, 0.8)))
	return label


func _slot_column(slots: Array[ItemData.Slot]) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 30)
	for slot in slots:
		col.add_child(_slot_tile(slot))
	return col


func _slot_tile(slot: ItemData.Slot) -> Tile:
	var t := Tile.make(self, &"slot")
	t.slot = slot
	_slot_tiles[slot] = t
	return t


static func _panel_style(border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.04, 0.08, 0.97)
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_content_margin_all(10)
	return sb


# ---------------------------------------------------------------------------
# Refresh
# ---------------------------------------------------------------------------

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
	for slot: ItemData.Slot in _slot_tiles:
		_show_item(_slot_tiles[slot], player.equipment.equipped.get(slot))
	var inv := player.equipment.inventory
	for i in _bag_tiles.size():
		_show_item(_bag_tiles[i], inv[i] if i < inv.size() else null)
	_bag_title.text = Texts.t("ui.inv.bag", [inv.size(), Equipment.INVENTORY_CAP])
	_gold_label.text = str(player.gold)
	for node: Node in _bag_box.get_children():
		var ct := node as Tile
		var n := player.consumable_count(ct.cid)
		ct.count.text = str(n)
		ct.icon.modulate = Color.WHITE if n > 0 else Color(1, 1, 1, 0.35)
		ct.set_frame(Consumables.is_food(ct.cid) and n > 0, n > 0)
	var cls := player.class_data
	_info.text = Texts.t("ui.inv.level_class", [player.progression.level, cls.display_name if cls != null else ""])
	_doll.show_hero(cls, HeroLook.looks_for(player.equipment.equipped, player.helm_hidden()), _blade_override())
	if _hovered != null:
		_show_tooltip(_hovered)


func _blade_override() -> Material:
	var weapon: ItemData = player.equipment.equipped.get(ItemData.Slot.WEAPON)
	if weapon != null and weapon.legendary_id == &"cindermaw":
		return player._cindermaw_material()
	return null


func _show_item(t: Tile, item: ItemData) -> void:
	t.item = item
	if item != null:
		t.icon.texture = UiTheme.item_icon(item)
		t.icon.modulate = Color.WHITE
		t.set_color(ItemData.rarity_color(item.rarity))
	elif t.kind == &"slot":
		t.icon.texture = load(UiTheme.UI_DIR + "items/%s.png" % SLOT_ICON[t.slot]) as Texture2D
		t.icon.modulate = Color(1, 1, 1, 0.16)
		t.set_color(FRAME_EMPTY)
	else:
		t.icon.texture = null
		t.set_color(FRAME_EMPTY)


func _on_visibility_changed() -> void:
	if not visible:
		_hovered = null
		_tooltip.visible = false
		_close_confirm()


# ---------------------------------------------------------------------------
# Tooltip
# ---------------------------------------------------------------------------

func _hover(t: Tile) -> void:
	_hovered = t
	t.set_hot(true)
	_show_tooltip(t)


func _unhover(t: Tile) -> void:
	t.set_hot(false)
	if _hovered == t:
		_hovered = null
		_tooltip.visible = false


## Tests and the playtest capture: pin the tooltip of `item` (bag or slot).
func _select(item: ItemData) -> void:
	_selected = item
	var tiles: Array = _bag_tiles.duplicate()
	tiles.append_array(_slot_tiles.values())
	for t: Tile in tiles:
		if t.item == item:
			_hover(t)
			return


func tooltip_visible() -> bool:
	return _tooltip.visible


func tip_text() -> String:
	var parts: PackedStringArray = []
	for label: Node in _tip_row.find_children("*", "Label", true, false):
		parts.append((label as Label).text)
	return "\n".join(parts)


func _show_tooltip(t: Tile) -> void:
	for child in _tip_row.get_children():
		_tip_row.remove_child(child)
		child.queue_free()
	match t.kind:
		&"consumable":
			_tip_row.add_child(_consumable_panel(t.cid))
		&"bin":
			var box := _column()
			_line(box, Texts.t("ui.inv.bin"), UiTheme.TEXT)
			_line(box, Texts.t("ui.inv.bin_tip"), UiTheme.MUTED, true)
			_tip_row.add_child(box)
		_:
			if t.item == null:
				if t.kind != &"slot":
					_tooltip.visible = false
					return
				var empty := _column()
				_line(empty, Texts.t("ui.inv.empty_slot", [ItemData.slot_title(t.slot)]), UiTheme.MUTED)
				_tip_row.add_child(empty)
			else:
				var worn: ItemData = player.equipment.equipped.get(t.item.slot)
				var against: ItemData = worn if t.kind == &"bag" and worn != null and worn != t.item else null
				_tip_row.add_child(_item_panel(t.item, "", against))
				if against != null:
					_tip_row.add_child(VSeparator.new())
					_tip_row.add_child(_item_panel(against, Texts.t("ui.inv.equipped"), null))
	_tooltip.visible = true
	_tooltip.reset_size()
	_place_tooltip.call_deferred(t)


func _place_tooltip(t: Tile) -> void:
	if not is_instance_valid(t) or not _tooltip.visible:
		return
	var size_now := _tooltip.get_combined_minimum_size()
	_tooltip.size = size_now
	var rect := t.get_global_rect()
	var screen := get_viewport_rect().size
	var pos := Vector2(rect.end.x + 12, rect.position.y)
	if pos.x + size_now.x > screen.x - 8:
		pos.x = rect.position.x - size_now.x - 12
	pos.x = clampf(pos.x, 8, maxf(8, screen.x - size_now.x - 8))
	pos.y = clampf(pos.y, 8, maxf(8, screen.y - size_now.y - 8))
	_tooltip.global_position = pos


func _column() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(270, 0)
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box


func _line(box: VBoxContainer, text: String, color: Color, wrap: bool = false, size: int = 0) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if size > 0:
		label.add_theme_font_size_override("font_size", size)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(270, 0)
	box.add_child(label)
	return label


func _item_panel(item: ItemData, header: String, against: ItemData) -> VBoxContainer:
	var box := _column()
	if header != "":
		_line(box, header, UiTheme.MUTED)
	_line(box, item.title(), ItemData.rarity_color(item.rarity), true, UiTheme.BODY + 4)
	_line(box, "%s - %s" % [ItemData.rarity_title(item.rarity), ItemData.slot_title(item.slot)], Color(0.7, 0.7, 0.75))
	if item.kit != &"":
		_line(box, Texts.t("ui.inv.start_kit"), Color(0.7, 0.7, 0.75))
	else:
		_line(box, Texts.t("ui.inv.item_level", [item.item_level]), Color(0.7, 0.7, 0.75))
	for affix in item.affixes:
		_line(box, "+ " + String(affix["label"]), Color(0.86, 0.86, 0.92), true)
	if item.affixes.is_empty() and item.power_text() == "":
		_line(box, Texts.t("ui.inv.no_stats"), UiTheme.MUTED)
	if item.power_text() != "":
		_line(box, item.power_text(), Color(1.0, 0.6, 0.25), true)
	if against != null:
		var lines := compare_lines(item, against, player)
		if not lines.is_empty():
			_line(box, " ", UiTheme.MUTED)
			_line(box, Texts.t("ui.inv.if_equipped"), UiTheme.TEXT)
			for line: Array in lines:
				_line(box, line[0], line[1], true)
	if header == "":
		var worn: bool = player.equipment.equipped.get(item.slot) == item
		_line(box, Texts.t("ui.inv.right_off" if worn else "ui.inv.right_equip"), UiTheme.MUTED)
	return box


func _consumable_panel(cid: StringName) -> VBoxContainer:
	var box := _column()
	var count := player.consumable_count(cid)
	_line(box, Consumables.display_name(cid), ArtKit.color("color_roles.health.hot", Color("#FF9C9C")), false, UiTheme.BODY + 4)
	_line(box, Texts.t("ui.inv.consumable", [count, Consumables.cap(cid)]), Color(0.7, 0.7, 0.75))
	_line(box, Consumables.text(cid), Color(0.86, 0.86, 0.92), true)
	var why := player.consumable_deny_reason(cid)
	if why != "":
		_line(box, why, UiTheme.MUTED, true)
	else:
		_line(box, Texts.t("ui.inv.right_eat" if Consumables.is_food(cid) else "ui.inv.right_drink"), UiTheme.MUTED)
	return box


# ---------------------------------------------------------------------------
# Actions: clicks, drag and drop, discard
# ---------------------------------------------------------------------------

func _tile_input(t: Tile, event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index != MOUSE_BUTTON_RIGHT and not (mb.button_index == MOUSE_BUTTON_LEFT and mb.double_click):
		return
	match t.kind:
		&"bag":
			if t.item != null:
				_equip(t.item)
		&"slot":
			if t.item != null:
				_unequip(t.slot)
		&"consumable":
			_drink(t.cid)


## What a drag from `t` carries (null: nothing to drag); tests drop it by hand.
func _drag_payload(t: Tile) -> Variant:
	if t.item == null or not (t.kind == &"bag" or t.kind == &"slot"):
		return null
	return {"inv_item": t.item, "from": t.kind}


func _drag_data(t: Tile) -> Variant:
	var payload: Variant = _drag_payload(t)
	if payload == null:
		return null
	var preview := TextureRect.new()
	preview.texture = t.icon.texture
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.size = Vector2(ICON, ICON)
	preview.position = -preview.size * 0.5
	preview.modulate.a = 0.85
	var holder := Control.new()
	holder.add_child(preview)
	t.set_drag_preview(holder)
	_tooltip.visible = false
	return payload


func _can_drop(t: Tile, data: Variant) -> bool:
	if not (data is Dictionary) or not (data as Dictionary).has("inv_item"):
		return false
	var item := data["inv_item"] as ItemData
	var from: StringName = data["from"]
	match t.kind:
		&"slot":
			return from == &"bag" and int(item.slot) == t.slot
		&"bag":
			return true
		&"bin":
			return from == &"bag"
	return false


func _drop(t: Tile, data: Variant) -> void:
	var item := data["inv_item"] as ItemData
	var from: StringName = data["from"]
	match t.kind:
		&"slot":
			_equip(item)
		&"bag":
			if from == &"slot":
				_unequip(item.slot)
			else:
				player.equipment.move(item, t.index)
				SaveGame.request_save()
		&"bin":
			_ask_discard(item)


func _can_drop_on_hero(data: Variant) -> bool:
	return data is Dictionary and (data as Dictionary).get("from", &"") == &"bag"


func _drop_on_hero(data: Variant) -> void:
	_equip(data["inv_item"] as ItemData)


func _ask_discard(item: ItemData) -> void:
	_close_confirm()
	var shade := ColorRect.new()
	shade.top_level = true
	shade.z_index = 20
	shade.color = Color(0.02, 0.01, 0.04, 0.55)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.position = Vector2.ZERO
	shade.size = get_viewport_rect().size
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(LOSS))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	var ask := Label.new()
	ask.text = Texts.t("ui.inv.discard_ask", [item.title()])
	ask.add_theme_color_override("font_color", ItemData.rarity_color(item.rarity))
	ask.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(ask)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	var yes := Button.new()
	yes.text = Texts.t("ui.inv.discard_yes")
	yes.pressed.connect(func() -> void:
		player.equipment.discard(item)
		SaveGame.request_save()
		_close_confirm()
	)
	row.add_child(yes)
	var no := Button.new()
	no.text = Texts.t("ui.inv.discard_no")
	no.pressed.connect(_close_confirm)
	row.add_child(no)
	shade.add_child(panel)
	add_child(shade)
	_confirm = shade
	var place := func() -> void:
		if is_instance_valid(panel):
			panel.position = (shade.size - panel.get_combined_minimum_size()) * 0.5
	place.call_deferred()
	no.grab_focus.call_deferred()


func discard_pending() -> bool:
	return _confirm != null


func _close_confirm() -> void:
	if _confirm != null:
		_confirm.queue_free()
		_confirm = null


## M10b: drink one (or say why not).
func _drink(cid: StringName) -> void:
	var why := player.consumable_deny_reason(cid)
	if why != "" or not player.use_consumable(cid):
		player.ui_denied()
		_toast(why if why != "" else Texts.t("ui.inv.cant_drink"))


func _equip(item: ItemData) -> void:
	if not player.equipment.inventory.has(item):
		return
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
	_toast(Texts.t("ui.inv.full"))


func _toast(text: String) -> void:
	var zone := ZoneBase.zone_of(player)
	if zone != null and zone.hud != null:
		zone.hud.toast(text, UiTheme.MUTED)


## [text, colour] per stat that differs between two items (green = gain).
## Stat names live in StatSheet.STAT_NAMES (shared with the character sheet).
static func compare_lines(candidate: ItemData, current: ItemData, hero_: Player = null) -> Array:
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
		lines.append([StatSheet.stat_text(key, delta, hero_), GAIN if delta > 0.0 else LOSS])
	if candidate.legendary_id != current.legendary_id:
		if candidate.legendary_id != &"":
			lines.append(["+ legendary power: " + candidate.title(), Color(1.0, 0.6, 0.25)])
		if current.legendary_id != &"":
			lines.append(["- loses legendary power: " + current.title(), LOSS])
	return lines


# ---------------------------------------------------------------------------
# One square: an equipment slot, a bag cell, a consumable or the bin
# ---------------------------------------------------------------------------

class Tile extends PanelContainer:
	var ui: InventoryUI
	var kind: StringName = &"bag"  # &"slot", &"bag", &"consumable", &"bin"
	var slot: int = -1
	var index: int = -1
	var cid: StringName = &""
	var item: ItemData = null
	var icon: TextureRect
	var count: Label
	var _style: StyleBoxFlat
	var _color: Color = InventoryUI.FRAME_EMPTY
	var _hot: bool = false

	static func make(owner: InventoryUI, tile_kind: StringName) -> Tile:
		var t := Tile.new()
		t.ui = owner
		t.kind = tile_kind
		t.custom_minimum_size = Vector2(InventoryUI.TILE, InventoryUI.TILE)
		t.mouse_filter = Control.MOUSE_FILTER_STOP
		t._style = StyleBoxFlat.new()
		t._style.bg_color = InventoryUI.FILL
		t._style.set_border_width_all(2)
		t.add_theme_stylebox_override("panel", t._style)
		t.icon = TextureRect.new()
		t.icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		t.icon.custom_minimum_size = Vector2(InventoryUI.ICON, InventoryUI.ICON)
		t.icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		t.icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		t.icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t.add_child(t.icon)
		t.count = Label.new()
		t.count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		t.count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		t.count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t.add_child(t.count)
		t.set_color(InventoryUI.FRAME_EMPTY)
		t.mouse_entered.connect(func() -> void: owner._hover(t))
		t.mouse_exited.connect(func() -> void: owner._unhover(t))
		t.gui_input.connect(func(event: InputEvent) -> void: owner._tile_input(t, event))
		return t

	func set_color(c: Color) -> void:
		_color = c
		_paint()

	func set_hot(hot: bool) -> void:
		_hot = hot
		_paint()

	## Consumables: warm frame for food, red for draughts; dim when empty.
	func set_frame(food: bool, stocked: bool) -> void:
		var tone := ArtKit.color("palettes.burnt_forest.ember.2", Color("#D86A2C")) if food \
			else ArtKit.color("color_roles.health.hot", Color("#FF9C9C"))
		set_color(tone if stocked else InventoryUI.FRAME_EMPTY)

	func _paint() -> void:
		_style.border_color = _color.lightened(0.35) if _hot else _color
		_style.bg_color = InventoryUI.FILL.lightened(0.08) if _hot else InventoryUI.FILL

	func _get_drag_data(_at_position: Vector2) -> Variant:
		return ui._drag_data(self)

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return ui._can_drop(self, data)

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		ui._drop(self, data)


# ---------------------------------------------------------------------------
# The hero in 3D (its own small world; half resolution, nearest = the pixel look)
# ---------------------------------------------------------------------------

class DollView extends SubViewportContainer:
	var ui: InventoryUI
	var look: HeroLook = null
	var class_id: StringName = &""
	var _vp: SubViewport
	var _pivot: Node3D
	var _model: Node3D = null
	var _anim: AnimationPlayer = null
	var _turning: bool = false

	func setup(owner: InventoryUI) -> void:
		ui = owner
		custom_minimum_size = Vector2(270, 330)
		stretch = true
		stretch_shrink = 2
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		mouse_filter = Control.MOUSE_FILTER_STOP
		tooltip_text = Texts.t("ui.inv.turn")
		_vp = SubViewport.new()
		_vp.own_world_3d = true
		_vp.transparent_bg = true
		_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
		add_child(_vp)
		var env := WorldEnvironment.new()
		var e := Environment.new()
		e.background_mode = Environment.BG_CLEAR_COLOR
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.62, 0.56, 0.7)
		e.ambient_light_energy = 0.9
		env.environment = e
		_vp.add_child(env)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-38.0, 28.0, 0.0)
		sun.light_energy = 1.25
		_vp.add_child(sun)
		var cam := Camera3D.new()
		cam.fov = 30.0
		var eye := Vector3(0.0, 1.15, 4.6)
		cam.transform = Transform3D(Basis.looking_at(Vector3(0.0, 0.98, 0.0) - eye, Vector3.UP), eye)
		_vp.add_child(cam)
		_pivot = Node3D.new()
		_pivot.rotation.y = PI - 0.35  # rigs face -Z in game: turn the front (three-quarter) to the camera
		_vp.add_child(_pivot)

	## The hero of `cls` in `looks` (legacy classes: their rig, dressed plain).
	func show_hero(cls: ClassData, looks: Dictionary, blade: Material) -> void:
		if cls == null:
			return
		if cls.id != class_id or _model == null:
			_clear()
			class_id = cls.id
			var glow := ArtKit.color("color_roles.%s.body" % cls.resource_color_role, Color("#3CBEB4"))
			look = HeroLook.create(_pivot, cls.id, glow, 1.2)
			if look != null:
				_model = look.model
			else:
				var scene := ArtKit.rig_scene(cls.rig_path)
				if scene == null:
					return
				_model = scene.instantiate() as Node3D
				_model.rotation.y = PI
				_pivot.add_child(_model)
				ArtKit.dress_rig(_model, cls.material_id if cls.material_id != "" else "runebreaker", cls.body_tint, glow, 1.2)
			var anims := _model.find_children("*", "AnimationPlayer", true, false)
			_anim = anims[0] as AnimationPlayer if not anims.is_empty() else null
			if _anim != null and _anim.has_animation(&"idle"):
				_anim.play(&"idle")
				_anim.animation_finished.connect(func(_clip: StringName) -> void:
					if _anim != null:
						_anim.play(&"idle")
				)
		if look != null:
			look.apply(looks)
			look.set_blade_material(blade)

	func _clear() -> void:
		if look != null:
			look.release()
		elif _model != null:
			for mi: Node in _model.find_children("*", "MeshInstance3D", true, false):
				var mesh := mi as MeshInstance3D
				for i in mesh.get_surface_override_material_count():
					mesh.set_surface_override_material(i, null)
		if _model != null:
			_model.get_parent().remove_child(_model)
			_model.queue_free()
		look = null
		_model = null
		_anim = null

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
			_turning = mb.pressed
		var mm := event as InputEventMouseMotion
		if mm != null and _turning:
			_pivot.rotation.y += mm.relative.x * 0.015

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return ui._can_drop_on_hero(data)

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		ui._drop_on_hero(data)

	func _exit_tree() -> void:
		_clear()
