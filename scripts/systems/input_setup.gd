class_name InputSetup
extends Object
## Keyboard layout applied at runtime (user, 2026-09-24): abilities on the
## number row, Q / R kept as alternates, interaction on E. M10: the keys belong
## to the loadout's slots (SLOT_ACTIONS), 4-6 are free again. Done here instead of
## in project.godot on purpose (the editor may be open and would overwrite
## external edits). Mouse buttons, Space and the rest stay as the project
## defines them. Idempotent: each listed action gets exactly these keys.

const KEYS := {
	&"ability_q": [KEY_1, KEY_Q],              # M10 loadout slot 2
	&"ability_e": [KEY_2],                     # slot 3 (E is interaction now)
	&"ability_r": [KEY_3, KEY_R],              # slot 4
	&"interact": [KEY_E],                      # portals, chests, NPCs
	&"talents_toggle": [KEY_N],
	&"hero_character": [KEY_C],                # M07b character sheet tab
	&"loadout_toggle": [KEY_K],                # M10 abilities tab (the loadout)
	&"map_toggle": [KEY_M],                    # M08 zone map
	&"party_cancel": [KEY_X],                  # M09 cancels a party travel countdown
	&"sprint": [KEY_SHIFT],                    # M08 notes: held, out of combat
	&"playtest_toggle": [KEY_J],               # the playtest checklist (PlaytestUI)
}


## M10 loadout: the four free slots in order (RMB, 1, 2, 3); LMB (primary_attack)
## always fires the class's basic attack, Space the dodge.
const SLOT_ACTIONS: Array[StringName] = [&"secondary_ability", &"ability_q", &"ability_e", &"ability_r"]


static func slot_label(slot: int) -> String:
	return key_label(SLOT_ACTIONS[slot]) if slot >= 0 and slot < SLOT_ACTIONS.size() else ""


static func ensure() -> void:
	for action: StringName in KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				InputMap.action_erase_event(action, ev)
		for key: Key in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)


## Label for a HUD slot: the first key of an action ("1", "2", ...). Actions
## the project binds itself (mouse buttons, Space) are read from the InputMap.
static func key_label(action: StringName) -> String:
	var keys: Array = KEYS.get(action, [])
	if not keys.is_empty():
		return OS.get_keycode_string(keys[0])
	if action == &"" or not InputMap.has_action(action):
		return "?"
	for ev in InputMap.action_get_events(action):
		if ev is InputEventMouseButton:
			match (ev as InputEventMouseButton).button_index:
				MOUSE_BUTTON_LEFT: return "LMB"
				MOUSE_BUTTON_RIGHT: return "RMB"
				MOUSE_BUTTON_MIDDLE: return "MMB"
				_: return "M%d" % (ev as InputEventMouseButton).button_index
		if ev is InputEventKey:
			var key := ev as InputEventKey
			var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
			return "SPC" if code == KEY_SPACE else OS.get_keycode_string(code)
	return "?"
