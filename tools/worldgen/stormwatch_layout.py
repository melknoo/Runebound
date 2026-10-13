"""RUNEBOUND — the Stormwatch, the co-op dungeon (M13b).

The single source of truth for the Stormwatch's rooms, doors and points of
interest; `dungeon_bake.py` turns it into assets/world/stormwatch/
layout.json + map.png, which StormwatchZone reads at runtime.

A shattered rune observatory in the eastern rim mountains where stormcallers
once bound lightning into runes. For 3-5 heroes (DungeonRegistry min_party):
every run is fresh, a fallen hero can be revived, the puzzles want several
heroes at once (ROADMAP M13b, the user's decisions of 2026-10-13).

Coordinates are world metres on XZ: +x east, +z south (Godot). The way runs
as a ring:
  * the forecourt (south, the way out) - north into the coil hall:
    three coils far apart, struck within one window, open the way on
  * the crossing forks into the archive (west) and the turbine hall (east):
    split paths, each wing opens the other wing's way to the bridge
  * the bridge (a rune), the hall of the Sworn (mid-boss 1), a ramp up east
    into the plate hall (plates held at once), the gale hall (mid-boss 2)
  * a ramp down to the landing (a rune; its lever opens the gallery's
    shortcut back into the coil hall), the conductor hall (a lightning
    chain of heroes) and the heart of the storm (the end boss), the way out
    behind it
  * a cracked wall at the bridge's west end hides the orrery (the big
    puzzle) and the tome room behind it.

Rooms stand 2 m apart (the wall); a connector cuts a doorway through that
gap. Every id carries the prefix "sw_" (SaveGame keys are flat; a fresh run
clears every key with it). Rules: see dungeon_bake.py.
Phase 0 is the greybox: the rooms, the doors, placeholder camps and arena
wardens; the co-op puzzles, the storm family and the bosses follow.
"""

LAYOUT = {
    "id": "stormwatch",
    "prefix": "sw_",
    "entry": "sw_forecourt",
    "map_palette": "stormwatch",
    "wall_h": 8.0,
    "rooms": [
        {"id": "sw_forecourt", "rect": [-12, 40, 12, 62], "floor": 0.0, "tags": ["entry"],
         "name_key": "area.sw_forecourt"},
        {"id": "sw_c1", "rect": [-3, 26, 3, 38], "floor": 0.0, "wall_h": 6.0},
        {"id": "sw_coils", "rect": [-20, -10, 20, 24], "floor": 0.0, "wall_h": 10.0, "name_key": "area.sw_coils"},
        {"id": "sw_c2", "rect": [-3, -26, 3, -12], "floor": 0.0, "wall_h": 6.0},
        {"id": "sw_crossing", "rect": [-20, -44, 20, -28], "floor": 0.0, "name_key": "area.sw_crossing"},
        {"id": "sw_archive", "rect": [-46, -64, -22, -26], "floor": 0.0, "wall_h": 9.0,
         "name_key": "area.sw_archive"},
        {"id": "sw_turbines", "rect": [22, -64, 46, -26], "floor": 0.0, "wall_h": 9.0,
         "name_key": "area.sw_turbines"},
        {"id": "sw_bridge", "rect": [-46, -84, 46, -66], "floor": 0.0, "wall_h": 10.0,
         "name_key": "area.sw_bridge"},
        {"id": "sw_sworn", "rect": [-20, -124, 20, -86], "floor": 0.0, "wall_h": 11.0, "tags": ["arena"],
         "name_key": "area.sw_sworn"},
        {"id": "sw_c3", "rect": [22, -110, 40, -102], "wall_h": 6.0,
         "slope": {"axis": "x", "span": [23, 39], "y": [0.0, 4.0]}},
        {"id": "sw_plates", "rect": [42, -124, 74, -88], "floor": 4.0, "wall_h": 9.0, "name_key": "area.sw_plates"},
        {"id": "sw_c4", "rect": [56, -86, 62, -62], "floor": 4.0, "wall_h": 6.0},
        {"id": "sw_gale", "rect": [50, -60, 88, -22], "floor": 4.0, "wall_h": 12.0, "tags": ["arena"],
         "name_key": "area.sw_gale"},
        {"id": "sw_c5", "rect": [64, -20, 72, -4], "wall_h": 6.0,
         "slope": {"axis": "z", "span": [-19, -5], "y": [4.0, 0.0]}},
        {"id": "sw_landing", "rect": [54, -2, 82, 20], "floor": 0.0, "name_key": "area.sw_landing"},
        {"id": "sw_gallery", "rect": [22, 4, 52, 10], "floor": 0.0, "wall_h": 6.0},
        {"id": "sw_conductors", "rect": [84, -4, 112, 24], "floor": 0.0, "wall_h": 10.0,
         "name_key": "area.sw_conductors"},
        {"id": "sw_heart", "rect": [74, 26, 122, 70], "floor": 0.0, "wall_h": 14.0, "tags": ["arena"],
         "name_key": "area.sw_heart"},
        {"id": "sw_orrery", "rect": [-78, -88, -48, -60], "floor": 0.0, "wall_h": 10.0, "tags": ["secret", "roofed"],
         "name_key": "area.sw_orrery"},
        {"id": "sw_tome_room", "rect": [-72, -106, -56, -90], "floor": 0.0, "tags": ["secret", "roofed"]},
    ],
    "connectors": [
        {"id": "sw_d_fore_c1", "a": "sw_forecourt", "b": "sw_c1", "at": [0, 39], "width": 5.0},
        {"id": "sw_d_c1_coils", "a": "sw_c1", "b": "sw_coils", "at": [0, 25], "width": 5.0},
        {"id": "sw_d_coils_c2", "a": "sw_coils", "b": "sw_c2", "at": [0, -11], "width": 5.0},
        {"id": "sw_d_c2_crossing", "a": "sw_c2", "b": "sw_crossing", "at": [0, -27], "width": 5.0},
        {"id": "sw_d_crossing_archive", "a": "sw_crossing", "b": "sw_archive", "at": [-21, -36], "width": 5.0},
        {"id": "sw_d_crossing_turbines", "a": "sw_crossing", "b": "sw_turbines", "at": [21, -36], "width": 5.0},
        {"id": "sw_d_archive_bridge", "a": "sw_archive", "b": "sw_bridge", "at": [-34, -65], "width": 5.0},
        {"id": "sw_d_turbines_bridge", "a": "sw_turbines", "b": "sw_bridge", "at": [34, -65], "width": 5.0},
        {"id": "sw_d_bridge_sworn", "a": "sw_bridge", "b": "sw_sworn", "at": [0, -85], "width": 6.0},
        {"id": "sw_d_sworn_c3", "a": "sw_sworn", "b": "sw_c3", "at": [21, -106], "width": 5.0,
         "kind": "gate", "inputs": ["flag:sw_sworn_down"]},
        {"id": "sw_d_c3_plates", "a": "sw_c3", "b": "sw_plates", "at": [41, -106], "width": 5.0},
        {"id": "sw_d_plates_c4", "a": "sw_plates", "b": "sw_c4", "at": [59, -87], "width": 5.0},
        {"id": "sw_d_c4_gale", "a": "sw_c4", "b": "sw_gale", "at": [59, -61], "width": 5.0},
        {"id": "sw_d_gale_c5", "a": "sw_gale", "b": "sw_c5", "at": [68, -21], "width": 5.0,
         "kind": "gate", "inputs": ["flag:sw_gale_down"]},
        {"id": "sw_d_c5_landing", "a": "sw_c5", "b": "sw_landing", "at": [68, -3], "width": 5.0},
        {"id": "sw_d_landing_gallery", "a": "sw_landing", "b": "sw_gallery", "at": [53, 7], "width": 4.0},
        {"id": "sw_d_gallery_coils", "a": "sw_gallery", "b": "sw_coils", "at": [21, 7], "width": 4.0,
         "kind": "shortcut", "inputs": ["sw_lever_short"]},
        {"id": "sw_d_landing_conductors", "a": "sw_landing", "b": "sw_conductors", "at": [83, 9], "width": 5.0},
        {"id": "sw_d_conductors_heart", "a": "sw_conductors", "b": "sw_heart", "at": [98, 25], "width": 6.0},
        {"id": "sw_d_bridge_orrery", "a": "sw_bridge", "b": "sw_orrery", "at": [-47, -75], "width": 4.0,
         "kind": "secret"},
        {"id": "sw_d_orrery_tome", "a": "sw_orrery", "b": "sw_tome_room", "at": [-64, -89], "width": 4.0},
    ],
    "pois": [
        # --- the forecourt: the way out ---
        {"id": "sw_exit", "type": "portal", "pos": [0, 59], "yaw": 3.14159, "dest": "highlands",
         "arrival": "dungeon_se", "label": "ASHEN HIGHLANDS"},
        # --- the coil hall ---
        {"id": "sw_camp_coils", "type": "camp", "pos": [0, 4], "radius": 10.0,
         "composition": ["rusher", "caster", "rusher"], "spots": [[-4, 2], [4, 2], [0, -2]]},
        # --- the wings ---
        {"id": "sw_camp_archive", "type": "camp", "pos": [-34, -45], "radius": 8.0,
         "composition": ["caster", "rusher"], "spots": [[-37, -47], [-31, -43]]},
        {"id": "sw_chest_archive", "type": "chest", "pos": [-42, -30], "yaw": 0.0, "rarity_bias": 1},
        {"id": "sw_camp_turbines", "type": "camp", "pos": [34, -45], "radius": 8.0,
         "composition": ["rusher", "caster"], "spots": [[31, -47], [37, -43]]},
        # --- the bridge (a rune) and the hall of the Sworn (mid-boss 1) ---
        {"id": "sw_rune_bridge", "type": "rune", "pos": [0, -70], "yaw": 0.0},
        {"id": "sw_camp_bridge", "type": "camp", "pos": [30, -75], "radius": 7.0,
         "composition": ["warden", "caster"], "spots": [[27, -77], [33, -73]]},
        {"id": "sw_arena_sworn", "type": "arena", "pos": [0, -105], "boss": "dungeon_boss",
         "flag": "sw_sworn_down", "trigger": 9.0, "reward": "mid"},
        # --- the plate hall (a rune) and the gale hall (mid-boss 2) ---
        {"id": "sw_camp_plates", "type": "camp", "pos": [58, -110], "radius": 8.0,
         "composition": ["warden", "rusher", "caster"], "spots": [[54, -112], [62, -112], [58, -106]]},
        {"id": "sw_rune_plates", "type": "rune", "pos": [58, -92], "yaw": 0.0},
        {"id": "sw_arena_gale", "type": "arena", "pos": [69, -41], "boss": "dungeon_boss",
         "flag": "sw_gale_down", "trigger": 9.0, "reward": "mid"},
        # --- the landing (a rune, the shortcut's lever) ---
        {"id": "sw_rune_landing", "type": "rune", "pos": [64, 6], "yaw": 0.0},
        {"id": "sw_lever_short", "type": "lever", "pos": [57, 14], "yaw": 1.5708},
        # --- the conductor hall and the heart of the storm (the end boss) ---
        {"id": "sw_camp_conductors", "type": "camp", "pos": [98, 10], "radius": 8.0,
         "composition": ["warden", "caster", "caster"], "spots": [[94, 8], [102, 8], [98, 14]]},
        {"id": "sw_arena_caller", "type": "arena", "pos": [98, 46], "boss": "dungeon_boss",
         "flag": "sw_caller_down", "trigger": 10.0, "reward": "end"},
        {"id": "sw_exit_heart", "type": "portal", "pos": [98, 67], "yaw": 3.14159, "dest": "highlands",
         "arrival": "dungeon_se", "label": "ASHEN HIGHLANDS", "unlock_flag": "sw_caller_down"},
        # --- the orrery and the tome room (secret) ---
        {"id": "sw_chest_tome", "type": "chest", "pos": [-64, -96], "yaw": 0.0, "rarity_bias": 2},
    ],
}
