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
	&"chronicle_toggle": [KEY_L],              # M12 the chronicle (lore read, shards found)
}


## M10 loadout: the four free slots in order (RMB, 1, 2, 3); LMB (primary_attack)
## always fires the class's basic attack, Space the dodge.
const SLOT_ACTIONS: Array[StringName] = [&"secondary_ability", &"ability_q", &"ability_e", &"ability_r"]


static func slot_label(slot: int) -> String:
	return key_label(SLOT_ACTIONS[slot]) if slot >= 0 and slot < SLOT_ACTIONS.size() else ""


## M17a: applied once per run (GameSettings at startup), so the player's
## own bindings (KeyBindings) stay when a zone loads.
static var _ensured: bool = false


static func ensure() -> void:
	if _ensured:
		return
	_ensured = true
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


## Label for a HUD slot or a prompt: the action's first binding as the
## player has it now ("1", "RMB", "SPC"; M17a: rebindable, in the keyboard
## layout's own letters); "-" when nothing is bound.
static func key_label(action: StringName) -> String:
	if action == &"" or not InputMap.has_action(action):
		return "?"
	var codes := KeyBindings.codes(action)
	return KeyBindings.label(codes[0], true) if not codes.is_empty() else "-"
