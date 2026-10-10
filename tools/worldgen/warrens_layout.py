"""RUNEBOUND — the Ember Warrens dungeon layout (M13).

The single source of truth for the Warrens' rooms, doors and points of
interest; `dungeon_bake.py` turns it into assets/world/ember_warrens/
layout.json + map.png, which WarrensZone reads at runtime.

Coordinates are world metres on XZ: +x east, +z south (Godot). The way runs
as a ring through old ember mines and their smelting halls:
  * the adit (south) - north through a gallery into the rail hall: an ore
    cart pushed along its rail onto a plate holds the kiln gate open; the
    ore store is a branch (two carts on crossing rails, both onto plates,
    open an alcove with a bonus chest)
  * the kiln hall: an ember bowl and four kilns to light within 20 s (or a
    fire spell) open the way east, up a ramp to the spark shaft
  * the spark shaft (raised): a storm coil and four copper posts struck in
    order lift the gate down to the collapse gallery, whose floor falls
    away row by row over a lava pit
  * the landing (a rune), the smelting hall (the mid-boss), the jet run west
    (fire jets in rhythm; a cracked wall hides the mould room)
  * the mould room (secret, roofed): the big puzzle - three crucibles heated
    (the ember bowl), the tipping lever pulled, the chutes turned until the
    melt runs into the mould - opens the tome room
  * the threshold (a rune; its lever opens the shortcut to the adit), the
    brood hall (the end boss) and the way out behind it.

Rooms stand 2 m apart (the wall); a connector cuts a doorway through that
gap. Channels are sunken lava (kind "lava") across a flat room. Every id
carries the prefix "wa_" (SaveGame keys are flat). Rules: see dungeon_bake.py.
Enemies are placeholders (raiders) until the Ember Brood comes (phase 7).
"""

LAYOUT = {
    "id": "ember_warrens",
    "prefix": "wa_",
    "entry": "wa_adit",
    "map_palette": "warrens",
    "wall_h": 7.0,
    "rooms": [
        {"id": "wa_adit", "rect": [-10, 30, 10, 50], "floor": 0.0, "tags": ["entry"],
         "name_key": "area.wa_adit"},
        {"id": "wa_c1", "rect": [-3, 12, 3, 28], "floor": 0.0, "wall_h": 6.0},
        {"id": "wa_rails", "rect": [-16, -16, 16, 10], "floor": 0.0, "name_key": "area.wa_rails"},
        {"id": "wa_store", "rect": [-40, -12, -18, 6], "floor": 0.0, "name_key": "area.wa_store"},
        {"id": "wa_store_alcove", "rect": [-36, 8, -26, 18], "floor": 0.0, "wall_h": 5.0},
        {"id": "wa_kilns", "rect": [-18, -54, 18, -18], "floor": 0.0, "wall_h": 9.0, "name_key": "area.wa_kilns",
         "channels": [{"id": "wa_ch_kilns", "rect": [-18, -54, 18, -51], "depth": 1.5, "kind": "lava"}]},
        {"id": "wa_c2", "rect": [20, -39, 36, -33], "wall_h": 6.0,
         "slope": {"axis": "x", "span": [21, 35], "y": [0.0, 3.0]}},
        {"id": "wa_shaft", "rect": [38, -58, 62, -26], "floor": 3.0, "wall_h": 10.0, "name_key": "area.wa_shaft"},
        {"id": "wa_c3", "rect": [46, -24, 54, -12], "wall_h": 6.0,
         "slope": {"axis": "z", "span": [-23, -13], "y": [3.0, 0.0]}},
        {"id": "wa_collapse", "rect": [44, -10, 56, 12], "floor": 0.0, "wall_h": 6.0, "name_key": "area.wa_collapse",
         "channels": [{"id": "wa_pit", "rect": [44, -6, 56, 10], "depth": 3.0, "kind": "lava"}]},
        {"id": "wa_landing", "rect": [40, 14, 60, 30], "floor": 0.0, "wall_h": 6.0},
        {"id": "wa_smelter", "rect": [62, 4, 96, 38], "floor": 0.0, "wall_h": 9.0, "tags": ["arena"],
         "name_key": "area.wa_smelter"},
        {"id": "wa_jets", "rect": [34, 40, 70, 48], "floor": 0.0, "wall_h": 6.0, "name_key": "area.wa_jets"},
        {"id": "wa_mould", "rect": [40, 50, 64, 74], "floor": 0.0, "tags": ["secret", "roofed"],
         "name_key": "area.wa_mould"},
        {"id": "wa_tome_room", "rect": [40, 76, 56, 90], "floor": 0.0, "tags": ["secret", "roofed"]},
        {"id": "wa_threshold", "rect": [12, 34, 32, 56], "floor": 0.0, "name_key": "area.wa_threshold"},
        {"id": "wa_heart", "rect": [2, 58, 38, 92], "floor": 0.0, "wall_h": 9.0, "tags": ["arena"],
         "name_key": "area.wa_heart"},
    ],
    "connectors": [
        {"id": "wa_d_adit_c1", "a": "wa_adit", "b": "wa_c1", "at": [0, 29], "width": 5.0},
        {"id": "wa_d_c1_rails", "a": "wa_c1", "b": "wa_rails", "at": [0, 11], "width": 5.0},
        {"id": "wa_d_rails_store", "a": "wa_rails", "b": "wa_store", "at": [-17, -3], "width": 5.0},
        {"id": "wa_d_store_alcove", "a": "wa_store", "b": "wa_store_alcove", "at": [-31, 7], "width": 5.0,
         "kind": "gate", "inputs": ["wa_plate_store_a", "wa_plate_store_b"]},
        {"id": "wa_d_rails_kilns", "a": "wa_rails", "b": "wa_kilns", "at": [0, -17], "width": 6.0,
         "kind": "gate", "inputs": ["wa_plate_rails"]},
        {"id": "wa_d_kilns_c2", "a": "wa_kilns", "b": "wa_c2", "at": [19, -36], "width": 5.0,
         "kind": "gate", "inputs": ["wa_kilns_fire"]},
        {"id": "wa_d_c2_shaft", "a": "wa_c2", "b": "wa_shaft", "at": [37, -36], "width": 5.0},
        {"id": "wa_d_shaft_c3", "a": "wa_shaft", "b": "wa_c3", "at": [50, -25], "width": 5.0,
         "kind": "gate", "inputs": ["wa_posts"]},
        {"id": "wa_d_c3_collapse", "a": "wa_c3", "b": "wa_collapse", "at": [50, -11], "width": 5.0},
        {"id": "wa_d_collapse_landing", "a": "wa_collapse", "b": "wa_landing", "at": [50, 13], "width": 5.0},
        {"id": "wa_d_landing_smelter", "a": "wa_landing", "b": "wa_smelter", "at": [61, 22], "width": 5.0},
        {"id": "wa_d_smelter_jets", "a": "wa_smelter", "b": "wa_jets", "at": [66, 39], "width": 5.0,
         "kind": "gate", "inputs": ["flag:wa_reeve_down"]},
        {"id": "wa_d_jets_mould", "a": "wa_jets", "b": "wa_mould", "at": [52, 49], "width": 4.0,
         "kind": "secret"},
        {"id": "wa_d_mould_tome", "a": "wa_mould", "b": "wa_tome_room", "at": [48, 75], "width": 4.0,
         "kind": "gate", "inputs": ["wa_melt"]},
        {"id": "wa_d_jets_threshold", "a": "wa_jets", "b": "wa_threshold", "at": [33, 44], "width": 5.0},
        {"id": "wa_d_threshold_heart", "a": "wa_threshold", "b": "wa_heart", "at": [22, 57], "width": 6.0},
        {"id": "wa_d_threshold_adit", "a": "wa_threshold", "b": "wa_adit", "at": [11, 40], "width": 5.0,
         "kind": "shortcut", "inputs": ["wa_lever_short"]},
    ],
    "pois": [
        # --- the adit ---
        {"id": "wa_exit", "type": "portal", "pos": [0, 47], "yaw": 3.14159, "dest": "highlands",
         "arrival": "dungeon_w", "label": "ASHEN HIGHLANDS"},
        {"id": "wa_lore_adit", "type": "lore", "kind": "note", "text": "lore.warrens.foreman_log",
         "pos": [7, 33], "yaw": -0.6},
        # --- the rail hall: the cart along its rail onto the plate holds the kiln gate ---
        {"id": "wa_camp_rails", "type": "camp", "pos": [6, -4], "radius": 9.0,
         "composition": ["rusher", "rusher", "caster"],
         "spots": [[3, -7], [9, -7], [6, -1]]},
        {"id": "wa_cart_rails", "type": "block", "look": "cart", "pos": [-11, 6], "grid": [-12, -14, -10, 8],
         "cell": 2.0},
        {"id": "wa_plate_rails", "type": "plate", "pos": [-11, -12]},
        {"id": "wa_reset_rails", "type": "reset", "pos": [-14, 8], "targets": ["wa_cart_rails"]},
        # --- the ore store (a branch): cart b off the crossing first, then cart a through ---
        {"id": "wa_cart_store_a", "type": "block", "look": "cart", "pos": [-36, -8], "grid": [-38, -9, -21, -7],
         "cell": 2.0},
        {"id": "wa_cart_store_b", "type": "block", "look": "cart", "pos": [-29, -8], "grid": [-30, -10, -28, 4],
         "cell": 2.0},
        {"id": "wa_plate_store_a", "type": "plate", "pos": [-22, -8]},
        {"id": "wa_plate_store_b", "type": "plate", "pos": [-29, 2]},
        {"id": "wa_reset_store", "type": "reset", "pos": [-38, 4], "targets": ["wa_cart_store_a", "wa_cart_store_b"]},
        {"id": "wa_chest_store", "type": "chest", "pos": [-31, 14], "yaw": 0.0, "rarity_bias": 1},
        # --- the kiln hall: an ember bowl, four kilns lit within 20 s ---
        {"id": "wa_bowl_kilns", "type": "carrier", "pos": [0, -36], "element": "fire"},
        {"id": "wa_kilns_fire", "type": "element", "pos": [0, -36], "element": "fire", "window": 20.0,
         "targets": [[-12, -46], [12, -46], [12, -24], [-12, -24]]},
        {"id": "wa_lava_kilns", "type": "water", "pos": [0, -52.5], "channel": "wa_ch_kilns",
         "inputs": [], "walkways": []},
        {"id": "wa_camp_kilns", "type": "camp", "pos": [0, -41], "radius": 9.0,
         "composition": ["rusher", "caster", "rusher"],
         "spots": [[-5, -43], [5, -43], [0, -46]]},
        {"id": "wa_lore_kilns", "type": "lore", "kind": "note", "text": "lore.warrens.smelter_note",
         "pos": [-15, -21], "yaw": 0.6},
        # --- the spark shaft: a storm coil, four copper posts struck in order ---
        {"id": "wa_coil", "type": "carrier", "pos": [44, -32], "element": "storm"},
        {"id": "wa_posts", "type": "element", "pos": [50, -42], "element": "storm", "window": 8.0,
         "ordered": True, "targets": [[42, -50], [50, -54], [58, -48], [56, -32]]},
        {"id": "wa_camp_shaft", "type": "camp", "pos": [50, -42], "radius": 8.0,
         "composition": ["rusher", "caster"], "spots": [[47, -44], [53, -40]]},
        {"id": "wa_lore_shaft", "type": "lore", "kind": "inscription", "text": "lore.warrens.lift_plaque",
         "pos": [40, -28], "yaw": 1.5708},
        # --- the collapse gallery: rows over the lava pit ---
        {"id": "wa_collapse_pit", "type": "collapse", "pos": [50, 2], "channel": "wa_pit",
         "rows": 4, "period": 4.0, "down": 1.5, "back": [50, -8], "damage": 16.0},
        # --- the landing and the smelting hall (the mid-boss) ---
        {"id": "wa_rune_landing", "type": "rune", "pos": [50, 26], "yaw": 0.0},
        {"id": "wa_arena_reeve", "type": "arena", "pos": [79, 21], "boss": "dungeon_boss",
         "flag": "wa_reeve_down", "trigger": 9.0, "reward": "mid"},
        {"id": "wa_lore_reeve", "type": "lore", "kind": "note", "text": "lore.warrens.reeve_hint",
         "pos": [65, 7], "yaw": 0.8},
        # --- the jet run: fire jets in rhythm; the cracked wall at x 52 ---
        {"id": "wa_jets_run", "type": "trap", "pos": [51, 44], "look": "jets",
         "lane": [[62, 44], [40, 44]], "strips": 6, "period": 3.0, "damage": 16.0},
        # --- the mould room: the big puzzle ---
        {"id": "wa_bowl_mould", "type": "carrier", "pos": [44, 56], "element": "fire"},
        {"id": "wa_crucibles", "type": "element", "pos": [52, 69], "element": "fire", "window": 20.0,
         "targets": [[46, 70], [52, 70], [58, 70]]},
        {"id": "wa_lever_tip", "type": "lever", "pos": [44, 66], "yaw": 1.5708},
        {"id": "wa_melt", "type": "beam", "look": "melt", "pos": [52, 67], "dir": 4,
         "mirrors": [[52, 56, 6], [60, 56, 4]], "receiver": [60, 62],
         "inputs": ["wa_crucibles", "wa_lever_tip"]},
        {"id": "wa_lore_mould", "type": "lore", "kind": "inscription", "text": "lore.warrens.mould_words",
         "pos": [42, 52], "yaw": 1.5708},
        {"id": "wa_chest_tome", "type": "chest", "pos": [48, 86], "yaw": 0.0, "rarity_bias": 2},
        # --- the threshold, the shortcut's lever, the brood hall (the end boss) ---
        {"id": "wa_rune_threshold", "type": "rune", "pos": [15, 37], "yaw": 0.0},
        {"id": "wa_lever_short", "type": "lever", "pos": [14, 46], "yaw": 1.5708},
        {"id": "wa_camp_threshold", "type": "camp", "pos": [24, 46], "radius": 7.0,
         "composition": ["rusher", "caster"], "spots": [[21, 44], [27, 48]]},
        {"id": "wa_lore_threshold", "type": "lore", "kind": "note", "text": "lore.warrens.last_note",
         "pos": [29, 37], "yaw": 2.4},
        {"id": "wa_arena_mother", "type": "arena", "pos": [20, 75], "boss": "dungeon_boss",
         "flag": "wa_mother_down", "trigger": 10.0, "reward": "end"},
        {"id": "wa_exit_heart", "type": "portal", "pos": [20, 89], "yaw": 3.14159, "dest": "highlands",
         "arrival": "dungeon_w", "label": "ASHEN HIGHLANDS", "unlock_flag": "wa_mother_down"},
    ],
}
