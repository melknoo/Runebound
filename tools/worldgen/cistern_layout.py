"""RUNEBOUND — the Hollow Cistern dungeon layout (M13).

The single source of truth for the Cistern's rooms, doors and points of
interest; `dungeon_bake.py` turns it into assets/world/hollow_cistern/
layout.json + map.png, which CisternZone reads at runtime.

Coordinates are world metres on XZ: +x east, +z south (Godot). The way runs
as a ring: from the inlet (south) west into the sluice hall, north over the
frost channel and up to the mirror gallery, east through the settling basin
(the mid-boss), south down the undertow run (a trap) to the Maw's threshold,
whose lever opens the shortcut back to the inlet; the boss waits east of
it. A cracked wall in the undertow run hides the vault with the big puzzle
and, behind it, the tome.

Rooms stand 2 m apart (the wall); a connector cuts a doorway through that
gap. Every id carries the prefix "ci_" (SaveGame keys are flat). Rules: see
dungeon_bake.py.
"""

LAYOUT = {
    "id": "hollow_cistern",
    "prefix": "ci_",
    "entry": "ci_inlet",
    "map_palette": "spire",
    "wall_h": 7.0,
    "rooms": [
        {"id": "ci_inlet", "rect": [-10, 30, 10, 50], "floor": 0.0, "tags": ["entry"],
         "name_key": "area.ci_inlet"},
        {"id": "ci_c1", "rect": [-28, 37, -12, 43], "floor": 0.0, "wall_h": 6.0},
        {"id": "ci_sluice", "rect": [-60, 22, -30, 52], "floor": 0.0, "name_key": "area.ci_sluice"},
        {"id": "ci_pump", "rect": [-84, 26, -62, 48], "floor": 0.0, "name_key": "area.ci_pump"},
        {"id": "ci_frost", "rect": [-60, -6, -30, 20], "floor": 0.0, "name_key": "area.ci_frost"},
        {"id": "ci_c3", "rect": [-48, -22, -42, -8], "wall_h": 6.0,
         "slope": {"axis": "z", "span": [-21, -9], "y": [2.0, 0.0]}},
        {"id": "ci_mirror", "rect": [-64, -52, -26, -24], "floor": 2.0, "name_key": "area.ci_mirror"},
        {"id": "ci_ante", "rect": [-24, -44, -8, -32], "floor": 2.0, "wall_h": 6.0},
        {"id": "ci_basin", "rect": [-6, -56, 26, -24], "floor": 2.0, "wall_h": 9.0,
         "name_key": "area.ci_basin"},
        {"id": "ci_run_n", "rect": [28, -43, 48, -37], "floor": 2.0, "wall_h": 6.0},
        {"id": "ci_run", "rect": [50, -46, 56, 16], "wall_h": 6.0, "name_key": "area.ci_run",
         "slope": {"axis": "z", "span": [-2, 12], "y": [2.0, 0.0]}},
        {"id": "ci_vault", "rect": [58, -30, 80, -8], "floor": 2.0, "tags": ["secret", "roofed"],
         "name_key": "area.ci_vault"},
        {"id": "ci_tome_room", "rect": [58, -50, 72, -32], "floor": 2.0, "tags": ["secret", "roofed"]},
        {"id": "ci_threshold", "rect": [44, 18, 64, 40], "floor": 0.0, "name_key": "area.ci_threshold"},
        {"id": "ci_c4", "rect": [12, 33, 42, 39], "floor": 0.0, "wall_h": 6.0},
        {"id": "ci_heart", "rect": [66, 10, 100, 46], "floor": 0.0, "wall_h": 9.0, "tags": ["arena"],
         "name_key": "area.ci_heart"},
    ],
    "connectors": [
        {"id": "ci_d_inlet_c1", "a": "ci_inlet", "b": "ci_c1", "at": [-11, 40], "width": 5.0},
        {"id": "ci_d_c1_sluice", "a": "ci_c1", "b": "ci_sluice", "at": [-29, 40], "width": 5.0},
        {"id": "ci_d_sluice_pump", "a": "ci_sluice", "b": "ci_pump", "at": [-61, 37], "width": 5.0},
        {"id": "ci_d_sluice_frost", "a": "ci_sluice", "b": "ci_frost", "at": [-45, 21], "width": 6.0,
         "kind": "gate"},
        {"id": "ci_d_frost_c3", "a": "ci_frost", "b": "ci_c3", "at": [-45, -7], "width": 5.0},
        {"id": "ci_d_c3_mirror", "a": "ci_c3", "b": "ci_mirror", "at": [-45, -23], "width": 5.0},
        {"id": "ci_d_mirror_ante", "a": "ci_mirror", "b": "ci_ante", "at": [-25, -38], "width": 5.0,
         "kind": "gate"},
        {"id": "ci_d_ante_basin", "a": "ci_ante", "b": "ci_basin", "at": [-7, -38], "width": 5.0},
        {"id": "ci_d_basin_run", "a": "ci_basin", "b": "ci_run_n", "at": [27, -40], "width": 5.0,
         "kind": "gate", "inputs": ["flag:ci_keeper_down"]},
        {"id": "ci_d_run_n_run", "a": "ci_run_n", "b": "ci_run", "at": [49, -40], "width": 5.0},
        {"id": "ci_d_run_vault", "a": "ci_run", "b": "ci_vault", "at": [57, -19], "width": 4.0,
         "kind": "secret"},
        {"id": "ci_d_vault_tome", "a": "ci_vault", "b": "ci_tome_room", "at": [65, -31], "width": 4.0,
         "kind": "gate"},
        {"id": "ci_d_run_threshold", "a": "ci_run", "b": "ci_threshold", "at": [53, 17], "width": 5.0},
        {"id": "ci_d_threshold_heart", "a": "ci_threshold", "b": "ci_heart", "at": [65, 29], "width": 6.0},
        {"id": "ci_d_inlet_c4", "a": "ci_inlet", "b": "ci_c4", "at": [11, 36], "width": 5.0},
        {"id": "ci_d_c4_threshold", "a": "ci_c4", "b": "ci_threshold", "at": [43, 36], "width": 5.0,
         "kind": "shortcut"},
    ],
    "pois": [
        {"id": "ci_exit", "type": "portal", "pos": [0, 47], "yaw": 3.14159, "dest": "highlands",
         "arrival": "dungeon_e", "label": "ASHEN HIGHLANDS"},
        {"id": "ci_camp_sluice", "type": "camp", "pos": [-45, 34], "radius": 10.0,
         "composition": ["rusher", "rusher", "caster"],
         "spots": [[-48, 31], [-42, 31], [-45, 37]]},
        {"id": "ci_camp_mirror", "type": "camp", "pos": [-45, -38], "radius": 11.0,
         "composition": ["rusher", "caster", "warden"],
         "spots": [[-49, -35], [-41, -35], [-45, -42]]},
        # the mid-boss (the Bloated Keeper from phase 5; the arena placeholder until then)
        {"id": "ci_arena_keeper", "type": "arena", "pos": [10, -40], "boss": "dungeon_boss",
         "flag": "ci_keeper_down", "trigger": 9.0, "reward": "mid"},
        {"id": "ci_rune_ante", "type": "rune", "pos": [-16, -42], "yaw": 0.0},
        {"id": "ci_rune_threshold", "type": "rune", "pos": [47, 21], "yaw": 0.0},
        # the end boss (the Deepmaw from phase 5) and the way out behind it
        {"id": "ci_arena_deepmaw", "type": "arena", "pos": [83, 28], "boss": "dungeon_boss",
         "flag": "ci_deepmaw_down", "trigger": 10.0, "reward": "end"},
        {"id": "ci_exit_heart", "type": "portal", "pos": [96, 28], "yaw": -1.5708, "dest": "highlands",
         "arrival": "dungeon_e", "label": "ASHEN HIGHLANDS", "unlock_flag": "ci_deepmaw_down"},
        {"id": "ci_camp_threshold", "type": "camp", "pos": [54, 29], "radius": 8.0,
         "composition": ["warden", "caster"],
         "spots": [[51, 27], [57, 31]]},
        {"id": "ci_chest_pump", "type": "chest", "pos": [-79, 37], "yaw": 1.5708, "rarity_bias": 1},
        {"id": "ci_chest_vault", "type": "chest", "pos": [76, -19], "yaw": -1.5708, "rarity_bias": 1},
    ],
}
