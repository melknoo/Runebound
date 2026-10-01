class_name KeyBindings
extends Object
## M17a: the player's key bindings. Every listed action has up to two
## bindings (a key or a mouse button). The defaults are the InputMap as the
## project and InputSetup leave it, snapshot once at startup; overrides live
## in GameSettings' [keys] section as "key:<physical keycode>" /
## "mouse:<button index>" codes. A key given to one action leaves the action
## that had it (which may end up unbound - the settings show that in red).
## Esc (the menu) and F1 (the debug panel) are not rebindable.

## [group, [[action, name], ...]] in the order the settings list them.
const GROUPS := [
	["Movement", [[&"move_forward", "Move forward"], [&"move_back", "Move back"], [&"move_left", "Move left"],
		[&"move_right", "Move right"], [&"dodge", "Dodge"], [&"sprint", "Sprint (hold, out of combat)"]]],
	["Combat", [[&"primary_attack", "Basic attack"], [&"secondary_ability", "Ability slot 1"],
		[&"ability_q", "Ability slot 2"], [&"ability_e", "Ability slot 3"], [&"ability_r", "Ability slot 4"],
		[&"target_cycle", "Next target"]]],
	["Interface", [[&"interact", "Interact"], [&"inventory_toggle", "Inventory"], [&"hero_character", "Character"],
		[&"talents_toggle", "Talents"], [&"loadout_toggle", "Abilities (loadout)"], [&"map_toggle", "Map"],
		[&"chronicle_toggle", "Chronicle"],
		[&"party_cancel", "Cancel party travel"], [&"zoom_in", "Zoom in"], [&"zoom_out", "Zoom out"],
		[&"playtest_toggle", "Playtest list (developer tools)"]]],
]
const SLOTS := 2
## Codes no action may take: Esc opens the menu, F1 the debug panel.
const RESERVED: Array[String] = ["key:%d" % KEY_ESCAPE, "key:%d" % KEY_F1]

## action -> PackedStringArray of codes, as the game started.
static var _defaults: Dictionary = {}


static func actions() -> Array[StringName]:
	var out: Array[StringName] = []
	for group: Array in GROUPS:
		for entry: Array in group[1]:
			out.append(entry[0])
	return out


static func display_name(action: StringName) -> String:
	for group: Array in GROUPS:
		for entry: Array in group[1]:
			if entry[0] == action:
				return str(entry[1])
	return String(action)


## Remembers the InputMap as the defaults (once; InputSetup.ensure() first).
static func capture_defaults() -> void:
	if not _defaults.is_empty():
		return
	for action in actions():
		_defaults[action] = codes(action)


static func defaults(action: StringName) -> PackedStringArray:
	return _defaults.get(action, PackedStringArray())


## The action's bindings as codes (keys and mouse buttons only, in order).
static func codes(action: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	if not InputMap.has_action(action):
		return out
	for ev in InputMap.action_get_events(action):
		var code := code_of(ev)
		if code != "" and not out.has(code):
			out.append(code)
	return out


## Replaces the action's key and mouse bindings with `list`.
static func set_codes(action: StringName, list: PackedStringArray) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey or ev is InputEventMouseButton:
			InputMap.action_erase_event(action, ev)
	for code in list:
		var ev := event_of(code)
		if ev != null:
			InputMap.action_add_event(action, ev)


## Puts `code` on the action's binding `slot` (0 or 1). Returns the action
## that had it before (&"" when none): that one loses it.
static func bind(action: StringName, slot: int, code: String) -> StringName:
	if code == "" or RESERVED.has(code):
		return &""
	var taken_from: StringName = &""
	for other in actions():
		if other == action:
			continue
		var theirs := codes(other)
		if theirs.has(code):
			theirs.remove_at(theirs.find(code))
			set_codes(other, theirs)
			taken_from = other
	var mine := codes(action)
	if mine.has(code):
		mine.remove_at(mine.find(code))
	if slot < mine.size():
		mine[slot] = code
	else:
		mine.append(code)
	set_codes(action, mine)
	return taken_from


## Removes the action's binding `slot`.
static func clear(action: StringName, slot: int) -> void:
	var mine := codes(action)
	if slot >= 0 and slot < mine.size():
		mine.remove_at(slot)
		set_codes(action, mine)


static func reset_all() -> void:
	for action in actions():
		if _defaults.has(action):
			set_codes(action, _defaults[action])


## The listed actions whose bindings differ from the defaults.
static func overrides() -> Dictionary:
	var out := {}
	for action in actions():
		var now := codes(action)
		if now != defaults(action):
			out[action] = now
	return out


static func is_unbound(action: StringName) -> bool:
	return codes(action).is_empty()


# --- codes and labels ----------------------------------------------------------

static func code_of(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var key := ev as InputEventKey
		var k := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		return "key:%d" % k if k != KEY_NONE else ""
	if ev is InputEventMouseButton:
		return "mouse:%d" % (ev as InputEventMouseButton).button_index
	return ""


static func event_of(code: String) -> InputEvent:
	var kind := code.get_slice(":", 0)
	var value := code.get_slice(":", 1)
	if not value.is_valid_int():
		return null
	match kind:
		"key":
			var ev := InputEventKey.new()
			ev.physical_keycode = int(value) as Key
			return ev
		"mouse":
			var mb := InputEventMouseButton.new()
			mb.button_index = int(value) as MouseButton
			return mb
	return null


## What the player reads: the key as this keyboard layout prints it ("Z" on
## a German keyboard where a US one says "Y"), mouse buttons by name. `short`
## for HUD slots ("SPC", "LMB").
static func label(code: String, short: bool = false) -> String:
	var kind := code.get_slice(":", 0)
	var value := int(code.get_slice(":", 1))
	if kind == "mouse":
		match value:
			MOUSE_BUTTON_LEFT: return "LMB" if short else "Left mouse"
			MOUSE_BUTTON_RIGHT: return "RMB" if short else "Right mouse"
			MOUSE_BUTTON_MIDDLE: return "MMB" if short else "Middle mouse"
			MOUSE_BUTTON_WHEEL_UP: return "WhUp" if short else "Wheel up"
			MOUSE_BUTTON_WHEEL_DOWN: return "WhDn" if short else "Wheel down"
			MOUSE_BUTTON_XBUTTON1: return "M4" if short else "Mouse 4"
			MOUSE_BUTTON_XBUTTON2: return "M5" if short else "Mouse 5"
		return "M%d" % value if short else "Mouse %d" % value
	if kind != "key" or value == KEY_NONE:
		return "?"
	if value == KEY_SPACE:
		return "SPC" if short else "Space"
	var shown := DisplayServer.keyboard_get_label_from_physical(value as Key)
	if shown == KEY_NONE:
		shown = value as Key
	return OS.get_keycode_string(shown)
