"""RUNEBOUND — the prologue's zone, "The Ash Road" (M14a phase 5).

A night road from the edge of Ashwick down to Runehold (STORY_DESIGN "The
campaign", the prologue beat sheet): one S-shaped road in a valley between
two long ridges, a gorge across it with a bridge (the zone builds the bridge
and the walls along the gorge's rims; the road stops at a pad on each edge,
so the grading never fills the gorge), the Reeve's toll gate at the north end
and the gate to Runehold behind it. `bake.py ash_road` writes
assets/world/ash_road/.

Coordinates as in the Highlands: world metres on XZ, +x east, +z south; the
zone is 256 x 256 m around the origin, the outer 16 m rise into mountains.
"""

LAYOUT = {
    "id": "ash_road",
    "size_m": 256,
    "resolution": 257,
    "origin": [-128, -128],
    "height_max": 80.0,
    "seed": 1410,
    "base": {
        "south_y": 18.0,
        "north_y": 24.0,
        "noise_octaves": [[3, 0.55], [7, 0.3], [15, 0.15]],
        "amplitude": 4.0,
    },
    # The valley walls (long ridges east and west of the road) and the gorge
    # (a negative ridge across the road between the two bridge pads).
    "ridges": [
        {"a": [-62, 120], "b": [-58, -120], "height": 18.0, "width": 34.0},
        {"a": [62, 120], "b": [60, -120], "height": 18.0, "width": 34.0},
        {"a": [-80, -40], "b": [80, -40], "height": -14.0, "width": 13.0},
    ],
    "plateaus": [],
    "rim": {"start_m": 112.0, "height": 30.0},
    "routes": [
        {"id": "road_south", "width": 3.2, "grade_max": 0.45,
         "points": [[0, 104], [-6, 86], [-18, 66], [-28, 46], [-30, 28], [-20, 12], [0, 2], [16, -8],
                    [18, -18], [8, -24], [0, -27]]},
        {"id": "road_north", "width": 3.2, "grade_max": 0.45,
         "points": [[0, -53], [2, -62], [10, -72], [8, -88], [2, -98], [0, -106]]},
    ],
    # Level 1 everywhere (the prologue's enemies).
    "bands": {"cell_m": 32, "grid": [[1] * 8 for _ in range(8)]},
    "areas": [
        {"id": "camp", "name": "The Last Camp", "name_key": "area.ash_camp", "pos": [0, 100], "radius": 18},
        {"id": "clearing", "name": "The Clearing", "name_key": "area.ash_clearing", "pos": [-30, 28], "radius": 14},
        {"id": "gorge", "name": "The Gorge", "name_key": "area.ash_gorge", "pos": [0, -40], "radius": 24},
        {"id": "toll", "name": "The Toll Gate", "name_key": "area.ash_toll", "pos": [8, -80], "radius": 18},
    ],
    "biomes": [],
    "pois": [
        {"id": "spawn", "type": "spawn", "pos": [0, 100], "yaw": 3.1416, "pad": 9},
        # P1: the refugees' last camp
        {"id": "vig_camp", "type": "vignette", "kind": "abandoned_camp", "pos": [12, 104], "yaw": 0.4, "pad": 0},
        {"id": "vig_cart_camp", "type": "vignette", "kind": "cart", "pos": [-9, 96], "yaw": -0.5, "pad": 0},
        # P2: the dead come up behind the camp
        {"id": "ambush_dead", "type": "ambush", "pos": [-22, 58], "yaw": 0.0, "pad": 5, "radius": 8.0,
         "composition": ["grave_shambler", "grave_shambler", "grave_shambler"], "respawn_min": 9999.0},
        # P3: the clearing where the shard falls
        {"id": "clearing", "type": "story", "pos": [-30, 28], "yaw": 0.0, "pad": 8},
        {"id": "vig_fallen_road", "type": "vignette", "kind": "fallen", "pos": [-40, 20], "yaw": 1.2, "pad": 0},
        # P4: raiders at the bend; the supply cart with a draught behind them
        {"id": "ambush_raiders", "type": "ambush", "pos": [12, -6], "yaw": 0.0, "pad": 6, "radius": 9.0,
         "composition": ["rusher", "rusher", "caster"], "respawn_min": 9999.0},
        {"id": "cart", "type": "story", "pos": [26, -14], "yaw": 0.0, "pad": 4},
        # P5: the bridge over the gorge (built by the zone between the pads)
        {"id": "bridge_s", "type": "story", "pos": [0, -27], "yaw": 0.0, "pad": 5},
        {"id": "bridge_n", "type": "story", "pos": [0, -53], "yaw": 0.0, "pad": 5},
        # P6: the Reeve's toll gate
        {"id": "toll", "type": "story", "pos": [8, -80], "yaw": 0.0, "pad": 14},
        {"id": "vig_barricade_toll", "type": "vignette", "kind": "barricade", "pos": [-6, -92], "yaw": 0.2, "pad": 0},
        # P7: the gate to Runehold
        {"id": "gate_north", "type": "portal", "pos": [0, -108], "yaw": 0.0, "pad": 5,
         "dest": "hub", "label": "RUNEHOLD", "arrival": ""},
    ],
}
