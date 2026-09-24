class_name CharacterTab
extends HBoxContainer
## M07b character sheet (hero window, key C): the hero's core numbers, one
## row per known ability with the effective damage the game would roll, and
## defence / gear. Every number comes from StatSheet.

const GRID_HEADERS: Array[String] = ["Ability", "Damage", "Avg", "Crit", "Cooldown", "Cost", "Gain"]

var player: Player

var _hero_box: VBoxContainer
var _grid: GridContainer
var _notes_box: VBoxContainer
var _defence_box: VBoxContainer
var _gear_box: VBoxContainer


func setup(p: Player) -> void:
	player = p
	add_theme_constant_override("separation", 18)
	_build()
	player.equipment.changed.connect(refresh)
	player.progression.talents_changed.connect(refresh)
	player.abilities_changed.connect(refresh)
	player.health_changed.connect(func(_c: float, _m: float) -> void: refresh())
	player.resonance_changed.connect(func(_c: float, _m: float) -> void: refresh())
	player.progression.xp_changed.connect(func(_xp: int, _needed: int, _level: int) -> void: refresh())
	player.gold_changed.connect(func(_total: int, _delta: int) -> void: refresh())


func _build() -> void:
	var left := _column("HERO", 300)
	_hero_box = VBoxContainer.new()
	_hero_box.add_theme_constant_override("separation", 2)
	left.add_child(_hero_box)

	var mid := _column("ABILITIES", 520)
	_grid = GridContainer.new()
	_grid.columns = GRID_HEADERS.size()
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 2)
	mid.add_child(_grid)
	_notes_box = VBoxContainer.new()
	_notes_box.add_theme_constant_override("separation", 0)
	mid.add_child(_notes_box)

	var right := _column("DEFENCE & GEAR", 250)
	_defence_box = VBoxContainer.new()
	_defence_box.add_theme_constant_override("separation", 2)
	right.add_child(_defence_box)
	var gear_title := Label.new()
	gear_title.text = "EQUIPPED"
	gear_title.add_theme_color_override("font_color", UiTheme.MUTED)
	right.add_child(gear_title)
	_gear_box = VBoxContainer.new()
	_gear_box.add_theme_constant_override("separation", 2)
	right.add_child(_gear_box)


func _column(title: String, width: float) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(width, 0)
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var label := Label.new()
	label.text = title
	label.add_theme_font_override("font", UiTheme.font(true))
	label.add_theme_font_size_override("font_size", UiTheme.TITLE)
	label.add_theme_color_override("font_color", ArtKit.color("color_roles.player_accent.body", Color(0.5, 0.85, 0.8)))
	col.add_child(label)
	return col


## Rebuilds every column from the current numbers (only while showing).
func refresh() -> void:
	if player == null or not visible:
		return
	var hero_rows: Array = [[player.class_data.display_name, ""]]
	hero_rows.append_array(StatSheet.core_rows(player))
	_fill_pairs(_hero_box, hero_rows)
	_fill_grid()
	_fill_pairs(_defence_box, StatSheet.defence_rows(player))
	for child in _gear_box.get_children():
		child.queue_free()
	for slot: ItemData.Slot in ItemData.SLOT_ORDER:
		var item: ItemData = player.equipment.equipped.get(slot)
		var label := Label.new()
		if item != null:
			label.text = "%s: %s" % [ItemData.slot_name(slot), item.display_name]
			label.add_theme_color_override("font_color", ItemData.rarity_color(item.rarity))
		else:
			label.text = "%s: —" % ItemData.slot_name(slot)
			label.add_theme_color_override("font_color", UiTheme.MUTED)
		_gear_box.add_child(label)


func _fill_pairs(box: VBoxContainer, rows: Array) -> void:
	for child in box.get_children():
		child.queue_free()
	for row: Array in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		box.add_child(line)
		var key := Label.new()
		key.text = String(row[0])
		key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		key.add_theme_color_override("font_color", UiTheme.MUTED if String(row[1]) != "" else ArtKit.color("color_roles.resonance.hot", Color("#FFD97A")))
		line.add_child(key)
		var value := Label.new()
		value.text = String(row[1])
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(value)


func _fill_grid() -> void:
	for child in _grid.get_children():
		child.queue_free()
	for child in _notes_box.get_children():
		child.queue_free()
	for h in GRID_HEADERS:
		var head := Label.new()
		head.text = h
		head.add_theme_color_override("font_color", UiTheme.MUTED)
		_grid.add_child(head)
	var rows := StatSheet.ability_rows(player)
	for r: Dictionary in rows:
		var type_color := HitInfo.type_color(r["type"] as HitInfo.DamageType)
		var is_guard: bool = r["id"] == &"runic_guard"
		var is_burst: bool = r["id"] == &"resonance_burst"
		var cells: Array[String] = [
			"%s  [%s]" % [r["name"], r["key"]],
			("barrier %d" % roundi(float(r["base"]) + float(player.progression.level))) if is_guard
				else (("%.1f / pt" % float(r["base"])) if is_burst else "%d" % roundi(float(r["damage"]))),
			"-" if is_guard or is_burst else "%d" % roundi(float(r["avg"])),
			"-" if is_guard else "%d%%" % roundi(float(r["crit"]) * 100.0),
			("%.1f s" % float(r["cooldown"])) if float(r["cooldown"]) > 0.0 else "-",
			("%d" % roundi(float(r["cost"]))) if float(r["cost"]) > 0.0 else ("all" if is_burst else "-"),
			("+%d" % roundi(float(r["gain"]))) if float(r["gain"]) > 0.0 else "-",
		]
		for i in cells.size():
			var cell := Label.new()
			cell.text = cells[i]
			if i == 0:
				cell.add_theme_color_override("font_color", type_color)
			elif i > 0:
				cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			_grid.add_child(cell)
	for r: Dictionary in rows:
		var notes: Array[String] = r["notes"]
		if notes.is_empty():
			continue
		var line := Label.new()
		line.text = "%s: %s" % [r["name"], "  ·  ".join(notes)]
		line.add_theme_color_override("font_color", UiTheme.MUTED)
		_notes_box.add_child(line)
