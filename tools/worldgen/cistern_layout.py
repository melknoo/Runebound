"""RUNEBOUND — the Hollow Cistern dungeon layout (M13).

The single source of truth for the Cistern's rooms, doors and points of
interest; `dungeon_bake.py` turns it into assets/world/hollow_cistern/
layout.json + map.png, which CisternZone reads at runtime.

Coordinates are world metres on XZ: +x east, +z south (Godot). The way runs
as a ring:
  * the inlet (south) - west into the sluice hall, whose flooded channel
    blocks the way north until two valves drain it (a causeway shows); the
    pump chamber is a branch (a block onto a plate, a latching plate, a
    bonus chest behind bars)
  * north over the frost channel (a frost crystal, an ice anchor: a floe for
    12 s), up a slope to the mirror gallery (a light and two crystals open
    the way on)
  * the antechamber (a rune), the settling basin (the mid-boss), the undertow
    run south (sluice blades; a cracked wall hides the vault)
  * the vault (secret, roofed): the big puzzle - ice to the far bank, a light
    led over the water twice, a latching plate and a block on a plate - opens
    the tome room
  * the Maw's threshold (a rune; its lever opens the shortcut to the inlet),
    the heart of the cistern (the end boss) and the way out behind it.

Rooms stand 2 m apart (the wall); a connector cuts a doorway through that
gap. Channels are sunken water across a room. Every id carries the prefix
"ci_" (SaveGame keys are flat). Rules: see dungeon_bake.py.
"""

LAYOUT = {
    "id": "hollow_cistern",
    "prefix": "ci_",
    "entry": "ci_inlet",
    "map_palette": "cistern",
    "wall_h": 7.0,
    "rooms": [
        {"id": "ci_inlet", "rect": [-10, 30, 10, 50], "floor": 0.0, "tags": ["entry"],
         "name_key": "area.ci_inlet"},
        {"id": "ci_c1", "rect": [-28, 37, -12, 43], "floor": 0.0, "wall_h": 6.0},
        {"id": "ci_sluice", "rect": [-60, 22, -30, 52], "floor": 0.0, "name_key": "area.ci_sluice",
         "channels": [{"id": "ci_ch_sluice", "rect": [-60, 30, -30, 34], "depth": 2.0}]},
        {"id": "ci_pump", "rect": [-84, 26, -62, 48], "floor": 0.0, "name_key": "area.ci_pump"},
        {"id": "ci_pump_alcove", "rect": [-80, 14, -70, 24], "floor": 0.0, "wall_h": 5.0},
        {"id": "ci_frost", "rect": [-60, -6, -30, 20], "floor": 0.0, "name_key": "area.ci_frost",
         "channels": [{"id": "ci_ch_frost", "rect": [-60, 4, -30, 8], "depth": 2.0}]},
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
         "name_key": "area.ci_vault",
         "channels": [{"id": "ci_ch_vault", "rect": [58, -21, 80, -17], "depth": 2.0}]},
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
        {"id": "ci_d_pump_alcove", "a": "ci_pump", "b": "ci_pump_alcove", "at": [-75, 25], "width": 5.0,
         "kind": "gate", "inputs": ["ci_plate_pump_a", "ci_plate_pump_b"]},
        {"id": "ci_d_sluice_frost", "a": "ci_sluice", "b": "ci_frost", "at": [-45, 21], "width": 6.0},
        {"id": "ci_d_frost_c3", "a": "ci_frost", "b": "ci_c3", "at": [-45, -7], "width": 5.0},
        {"id": "ci_d_c3_mirror", "a": "ci_c3", "b": "ci_mirror", "at": [-45, -23], "width": 5.0},
        {"id": "ci_d_mirror_ante", "a": "ci_mirror", "b": "ci_ante", "at": [-25, -38], "width": 5.0,
         "kind": "gate", "inputs": ["ci_light_gallery"]},
        {"id": "ci_d_ante_basin", "a": "ci_ante", "b": "ci_basin", "at": [-7, -38], "width": 5.0},
        {"id": "ci_d_basin_run", "a": "ci_basin", "b": "ci_run_n", "at": [27, -40], "width": 5.0,
         "kind": "gate", "inputs": ["flag:ci_keeper_down"]},
        {"id": "ci_d_run_n_run", "a": "ci_run_n", "b": "ci_run", "at": [49, -40], "width": 5.0},
        {"id": "ci_d_run_vault", "a": "ci_run", "b": "ci_vault", "at": [57, -12], "width": 4.0,
         "kind": "secret"},
        {"id": "ci_d_vault_tome", "a": "ci_vault", "b": "ci_tome_room", "at": [65, -31], "width": 4.0,
         "kind": "gate", "inputs": ["ci_light_vault", "ci_plate_vault_a", "ci_plate_vault_b"]},
        {"id": "ci_d_run_threshold", "a": "ci_run", "b": "ci_threshold", "at": [53, 17], "width": 5.0},
        {"id": "ci_d_threshold_heart", "a": "ci_threshold", "b": "ci_heart", "at": [65, 29], "width": 6.0},
        {"id": "ci_d_inlet_c4", "a": "ci_inlet", "b": "ci_c4", "at": [11, 36], "width": 5.0},
        {"id": "ci_d_c4_threshold", "a": "ci_c4", "b": "ci_threshold", "at": [43, 36], "width": 5.0,
         "kind": "shortcut", "inputs": ["ci_lever_short"]},
    ],
    "pois": [
        # --- the inlet ---
        {"id": "ci_exit", "type": "portal", "pos": [0, 47], "yaw": 3.14159, "dest": "highlands",
         "arrival": "dungeon_e", "label": "ASHEN HIGHLANDS"},
        {"id": "ci_lore_inlet", "type": "lore", "kind": "note", "text": "lore.cistern.keeper_log",
         "pos": [7, 33], "yaw": -0.6},
        # --- the sluice hall: two valves drain the channel, the causeway shows ---
        {"id": "ci_camp_sluice", "type": "camp", "pos": [-45, 42], "radius": 10.0,
         "composition": ["rusher", "rusher", "caster"],
         "spots": [[-48, 39], [-42, 39], [-45, 45]]},
        {"id": "ci_valve_sluice_a", "type": "lever", "pos": [-57, 48], "yaw": 3.14159, "look": "valve"},
        {"id": "ci_valve_sluice_b", "type": "lever", "pos": [-33, 48], "yaw": 3.14159, "look": "valve"},
        {"id": "ci_water_sluice", "type": "water", "pos": [-52, 32], "channel": "ci_ch_sluice",
         "inputs": ["ci_valve_sluice_a", "ci_valve_sluice_b"], "walkways": [[-47, 30, -43, 34]]},
        {"id": "ci_lore_sluice", "type": "lore", "kind": "inscription", "text": "lore.cistern.sluice_plaque",
         "pos": [-36, 25], "yaw": 3.14159},
        # --- the pump chamber (a branch): the block onto plate a, plate b latches ---
        {"id": "ci_block_pump", "type": "block", "pos": [-74, 42], "grid": [-82, 28, -64, 46], "cell": 2.0},
        {"id": "ci_reset_pump", "type": "reset", "pos": [-80, 45], "targets": ["ci_block_pump"]},
        {"id": "ci_plate_pump_a", "type": "plate", "pos": [-74, 32]},
        {"id": "ci_plate_pump_b", "type": "plate", "pos": [-66, 30], "latch": True},
        {"id": "ci_chest_pump", "type": "chest", "pos": [-75, 18], "yaw": 0.0, "rarity_bias": 1},
        # --- the frost channel: a crystal on each bank, an anchor in the water ---
        {"id": "ci_crystal_frost_s", "type": "carrier", "pos": [-38, 14], "element": "frost"},
        {"id": "ci_crystal_frost_n", "type": "carrier", "pos": [-54, 0], "element": "frost"},
        {"id": "ci_ice_frost", "type": "ice", "pos": [-45, 6], "channel": "ci_ch_frost",
         "strip": [-47, 4, -43, 8], "seconds": 12.0},
        {"id": "ci_water_frost", "type": "water", "pos": [-36, 6], "channel": "ci_ch_frost",
         "inputs": [], "walkways": [], "ice": ["ci_ice_frost"]},
        # --- the mirror gallery: east, south at the first crystal, east at the second ---
        {"id": "ci_camp_mirror", "type": "camp", "pos": [-45, -38], "radius": 11.0,
         "composition": ["rusher", "caster", "warden"],
         "spots": [[-49, -35], [-41, -35], [-45, -42]]},
        {"id": "ci_light_gallery", "type": "beam", "pos": [-61, -48], "dir": 2,
         "mirrors": [[-50, -48, 5], [-50, -30, 7]], "receiver": [-29, -30], "targets": [0, 2]},
        {"id": "ci_lore_mason", "type": "lore", "kind": "note", "text": "lore.cistern.mason",
         "pos": [-60, -27], "yaw": 0.4},
        # --- the antechamber and the basin (the mid-boss) ---
        {"id": "ci_rune_ante", "type": "rune", "pos": [-16, -42], "yaw": 0.0},
        {"id": "ci_arena_keeper", "type": "arena", "pos": [10, -40], "boss": "dungeon_boss",
         "flag": "ci_keeper_down", "trigger": 9.0, "reward": "mid"},
        {"id": "ci_lore_keeper", "type": "lore", "kind": "note", "text": "lore.cistern.keeper_last",
         "pos": [22, -27], "yaw": 2.4},
        # --- the undertow run: sluice blades; the cracked wall at z -12 ---
        {"id": "ci_blades_run", "type": "trap", "pos": [53, -30], "look": "blades",
         "lane": [[53, -40], [53, -20]], "strips": 5, "period": 3.0, "damage": 14.0},
        # --- the vault: the big puzzle ---
        {"id": "ci_crystal_vault", "type": "carrier", "pos": [62, -11], "element": "frost"},
        {"id": "ci_crystal_vault_n", "type": "carrier", "pos": [69, -24], "element": "frost"},
        {"id": "ci_ice_vault", "type": "ice", "pos": [70, -19], "channel": "ci_ch_vault",
         "strip": [68, -21, 72, -17], "seconds": 12.0},
        {"id": "ci_water_vault", "type": "water", "pos": [76, -19], "channel": "ci_ch_vault",
         "inputs": [], "walkways": [], "ice": ["ci_ice_vault"]},
        {"id": "ci_light_vault", "type": "beam", "pos": [61, -12], "dir": 4,
         "mirrors": [[61, -27, 0], [77, -27, 6]], "receiver": [77, -12], "targets": [2, 0]},
        {"id": "ci_plate_vault_a", "type": "plate", "pos": [64, -24], "latch": True},
        {"id": "ci_block_vault", "type": "block", "pos": [74, -28], "grid": [62, -29, 79, -25], "cell": 2.0},
        {"id": "ci_plate_vault_b", "type": "plate", "pos": [70, -28]},
        {"id": "ci_reset_vault", "type": "reset", "pos": [78, -23], "targets": ["ci_block_vault"]},
        {"id": "ci_lore_vault", "type": "lore", "kind": "inscription", "text": "lore.cistern.warning",
         "pos": [60, -10], "yaw": 1.5708},
        {"id": "ci_chest_tome", "type": "chest", "pos": [65, -46], "yaw": 0.0, "rarity_bias": 2},
        # --- the threshold, the shortcut's lever, the heart (the end boss) ---
        {"id": "ci_rune_threshold", "type": "rune", "pos": [47, 21], "yaw": 0.0},
        {"id": "ci_lever_short", "type": "lever", "pos": [46, 32], "yaw": 1.5708},
        {"id": "ci_camp_threshold", "type": "camp", "pos": [54, 29], "radius": 8.0,
         "composition": ["warden", "caster"],
         "spots": [[51, 27], [57, 31]]},
        {"id": "ci_arena_deepmaw", "type": "arena", "pos": [83, 28], "boss": "dungeon_boss",
         "flag": "ci_deepmaw_down", "trigger": 10.0, "reward": "end"},
        {"id": "ci_exit_heart", "type": "portal", "pos": [96, 28], "yaw": -1.5708, "dest": "highlands",
         "arrival": "dungeon_e", "label": "ASHEN HIGHLANDS", "unlock_flag": "ci_deepmaw_down"},
    ],
}
