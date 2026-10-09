"""RUNEBOUND — the puzzle lab (M13): a test dungeon for the puzzle kit.

Never reachable in play (no gate leads here); the smoke test and the net
scenarios use it so they stay stable while the real dungeons change. One
room per mechanism, wired in a chain: the hub's lever opens the way east,
two plates (one for the block, one latching) open the beam room, the beam
opens the water room, two valves drain its channel so the causeway shows,
and the corridor behind it holds the shortcut's lever back to the hub. The
hub's west wall is cracked: a hidden room with a chest.
"""

LAYOUT = {
    "id": "puzzle_lab",
    "prefix": "lab_",
    "entry": "lab_entry",
    "map_palette": "spire",
    "wall_h": 6.0,
    "rooms": [
        {"id": "lab_entry", "rect": [-10, 20, 10, 40], "floor": 0.0, "tags": ["entry"]},
        {"id": "lab_c1", "rect": [-3, 4, 3, 18], "floor": 0.0},
        {"id": "lab_hub", "rect": [-14, -16, 14, 2], "floor": 0.0},
        {"id": "lab_hidden", "rect": [-36, -14, -16, 0], "floor": 0.0, "tags": ["secret", "roofed"]},
        {"id": "lab_c2", "rect": [16, -10, 30, -4], "floor": 0.0},
        {"id": "lab_plates", "rect": [32, -20, 56, 4], "floor": 0.0},
        {"id": "lab_beam", "rect": [32, -46, 56, -22], "floor": 0.0},
        {"id": "lab_water", "rect": [6, -46, 30, -22], "floor": 0.0,
         "channels": [{"id": "lab_ch", "rect": [6, -38, 30, -34], "depth": 2.0}]},
        {"id": "lab_c3", "rect": [-2, -46, 4, -18], "floor": 0.0},
    ],
    "connectors": [
        {"id": "lab_d_entry_c1", "a": "lab_entry", "b": "lab_c1", "at": [0, 19], "width": 5.0},
        {"id": "lab_d_c1_hub", "a": "lab_c1", "b": "lab_hub", "at": [0, 3], "width": 5.0},
        {"id": "lab_d_hub_hidden", "a": "lab_hub", "b": "lab_hidden", "at": [-15, -7], "width": 4.0,
         "kind": "secret"},
        {"id": "lab_d_hub_c2", "a": "lab_hub", "b": "lab_c2", "at": [15, -7], "width": 5.0,
         "kind": "gate", "inputs": ["lab_lever"]},
        {"id": "lab_d_c2_plates", "a": "lab_c2", "b": "lab_plates", "at": [31, -7], "width": 5.0},
        {"id": "lab_d_plates_beam", "a": "lab_plates", "b": "lab_beam", "at": [44, -21], "width": 5.0,
         "kind": "gate", "inputs": ["lab_plate_a", "lab_plate_b"]},
        {"id": "lab_d_beam_water", "a": "lab_beam", "b": "lab_water", "at": [31, -28], "width": 5.0,
         "kind": "gate", "inputs": ["lab_light"]},
        {"id": "lab_d_water_c3", "a": "lab_water", "b": "lab_c3", "at": [5, -42], "width": 4.0},
        {"id": "lab_d_c3_hub", "a": "lab_c3", "b": "lab_hub", "at": [1, -17], "width": 4.0,
         "kind": "shortcut", "inputs": ["lab_lever_short"]},
    ],
    "pois": [
        {"id": "lab_exit", "type": "portal", "pos": [0, 37], "yaw": 3.14159, "dest": "hub", "label": "RUNEHOLD"},
        {"id": "lab_lever", "type": "lever", "pos": [10, -12], "yaw": -1.5708},
        {"id": "lab_chest_hidden", "type": "chest", "pos": [-26, -7], "yaw": 1.5708, "rarity_bias": 1},
        # a block onto plate a (five steps north), plate b latches under a hero
        {"id": "lab_block", "type": "block", "pos": [40, -4], "grid": [34, -18, 54, 2], "cell": 2.0},
        {"id": "lab_block_reset", "type": "reset", "pos": [36, 0], "targets": ["lab_block"]},
        {"id": "lab_plate_a", "type": "plate", "pos": [40, -14]},
        {"id": "lab_plate_b", "type": "plate", "pos": [50, 0], "latch": True},
        # the light: east from the source, south at the first mirror, west at the second
        {"id": "lab_light", "type": "beam", "pos": [34, -44], "dir": 2,
         "mirrors": [[50, -44, 3], [50, -26, 1]], "receiver": [34, -26], "targets": [0, 6]},
        {"id": "lab_valve_a", "type": "lever", "pos": [10, -26], "yaw": 3.14159, "look": "valve"},
        {"id": "lab_valve_b", "type": "lever", "pos": [26, -24], "yaw": 3.14159, "look": "valve"},
        {"id": "lab_water_ch", "type": "water", "pos": [18, -36], "channel": "lab_ch",
         "inputs": ["lab_valve_a", "lab_valve_b"], "walkways": [[16, -38, 20, -34]]},
        {"id": "lab_lever_short", "type": "lever", "pos": [1, -22], "yaw": 0.0},
    ],
}
