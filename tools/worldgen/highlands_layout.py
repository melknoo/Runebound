"""RUNEBOUND — Ashen Highlands open-zone layout (M08).

The single source of truth for the open Highlands: terrain shape (base
relief, ridges, plateaus, rim), routes, level bands, named areas and every
point of interest. `bake.py` turns it into the heightmap, the path mask, the
map image and `layout.json`, which the zone script reads at runtime.

Coordinates are world metres on XZ: +x east, +z south (Godot). The zone is
384 x 384 m centred on the origin; the outer 24 m rise into border mountains.

Rules encoded here (and asserted by the bake):
  * a point of interest roughly every 50–80 m along each route
  * camps >= 45 m apart, no camp within 40 m of the spawn
  * every combat POI sits on a flat pad (max slope < 3 deg)
  * route grade <= grade_max (about 24 deg)
"""

LAYOUT = {
    "id": "ashen_highlands",
    "size_m": 384,
    "resolution": 385,
    "origin": [-192, -192],
    "height_max": 80.0,
    "seed": 2608,
    # Rolling ash relief: lower in the south, climbing toward the north
    # plateau; fbm octaves as (cells across the zone, weight).
    "base": {
        "south_y": 6.0,
        "north_y": 22.0,
        "noise_octaves": [[3, 0.55], [7, 0.3], [15, 0.15]],
        "amplitude": 9.0,
    },
    # Gaussian ridges a -> b (height above base, full width). Routes carve
    # passes through them; passes are where ambushes wait.
    "ridges": [
        {"a": [-78, 118], "b": [-32, 142], "height": 7.0, "width": 16.0},   # south funnel, west
        {"a": [32, 142], "b": [78, 118], "height": 7.0, "width": 16.0},     # south funnel, east
        {"a": [-72, 28], "b": [12, 46], "height": 6.0, "width": 14.0},      # crossroads ridge (ambush_1 pass)
        {"a": [-44, -64], "b": [52, -82], "height": 9.0, "width": 16.0},    # north pass ridge (ambush_2 pass)
        {"a": [98, -140], "b": [112, 12], "height": 12.0, "width": 22.0},   # Emberfall Ridge (east)
        {"a": [-152, -104], "b": [-118, -146], "height": 10.0, "width": 18.0},
        {"a": [-160, 60], "b": [-126, 96], "height": 8.0, "width": 16.0},   # Westreach shoulder
        {"a": [40, 60], "b": [58, 20], "height": 5.0, "width": 12.0},       # cinder flats spur
    ],
    "plateaus": [
        {"pos": [0, -140], "radius": 56.0, "height": 10.0, "blend": 26.0},  # Colossus plateau
        {"pos": [-96, -100], "radius": 30.0, "height": 5.0, "blend": 18.0},  # Northreach shelf
    ],
    "rim": {"start_m": 176.0, "height": 36.0},
    # Test feature for the smoke test: an asymmetric bump in the south-east,
    # off every route (north/south and east/west orientation of the bake).
    "test_bump": {"pos": [140, 156], "height": 6.0, "radius": 9.0},
    # Routes: polylines the bake grades and carves; the path mask draws them.
    "routes": [
        {"id": "main", "width": 3.2, "grade_max": 0.45,
         "points": [[0, 170], [0, 150], [-12, 122], [-24, 96], [-30, 64], [-26, 36], [-8, 12],
                    [6, -14], [18, -42], [10, -72], [0, -96], [0, -118], [0, -132]]},
        {"id": "east_loop", "width": 2.8, "grade_max": 0.45,
         "points": [[-12, 122], [16, 112], [52, 96], [74, 66], [78, 30], [66, -4], [44, -30], [18, -42]]},
        {"id": "west_detour", "width": 2.8, "grade_max": 0.45,
         "points": [[-30, 64], [-62, 58], [-90, 40], [-104, 4], [-92, -34], [-64, -58], [-30, -78], [0, -96]]},
        {"id": "far_east", "width": 2.6, "grade_max": 0.5,
         "points": [[66, -4], [104, -22], [126, -56], [108, -96], [70, -118], [34, -124], [0, -118]]},
        {"id": "far_west", "width": 2.6, "grade_max": 0.5,
         "points": [[-104, 4], [-132, -30], [-138, -76], [-110, -116], [-70, -136], [-30, -134], [0, -132]]},
        {"id": "spur_se", "width": 2.2, "grade_max": 0.5,
         "points": [[52, 96], [84, 124], [116, 144]]},
        {"id": "spur_sw", "width": 2.2, "grade_max": 0.5,
         "points": [[-62, 58], [-96, 88], [-118, 116]]},
        {"id": "spur_dungeon_e", "width": 2.2, "grade_max": 0.6,
         "points": [[126, -56], [148, -62]]},
        {"id": "spur_dungeon_w", "width": 2.2, "grade_max": 0.6,
         "points": [[-132, -30], [-152, -28]]},
        {"id": "spur_hidden", "width": 1.8, "grade_max": 0.5,
         "points": [[-30, -78], [-52, -100]]},
        # A straight 25-degree test ramp for the smoke test (east of the spawn).
        {"id": "test_slope", "width": 4.0, "grade_max": 0.47, "test_grade": 0.466,
         "points": [[40, 176], [40, 146]]},
    ],
    # Enemy level per 48 m cell; row 0 = north (z -192..-144), col 0 = west.
    "bands": {
        "cell_m": 48,
        "grid": [
            [3, 3, 3, 3, 3, 3, 3, 3],
            [3, 3, 3, 3, 3, 3, 3, 3],
            [3, 3, 3, 3, 3, 3, 3, 3],
            [2, 2, 2, 2, 2, 2, 3, 3],
            [2, 2, 2, 2, 2, 2, 3, 3],
            [1, 1, 1, 1, 1, 1, 1, 1],
            [1, 1, 1, 1, 1, 1, 1, 1],
            [1, 1, 1, 1, 1, 1, 1, 1],
        ],
    },
    # Named areas: a subtitle when a hero first walks in (per visit).
    "areas": [
        {"id": "ashford", "name": "Ashford Slopes", "pos": [0, 140], "radius": 70},
        {"id": "crossroads", "name": "The Crossroads", "pos": [-30, 50], "radius": 60},
        {"id": "cinder_flats", "name": "Cinder Flats", "pos": [70, 40], "radius": 70},
        {"id": "westreach", "name": "Westreach", "pos": [-110, 10], "radius": 70},
        {"id": "emberfall", "name": "Emberfall Ridge", "pos": [95, -80], "radius": 80},
        {"id": "northreach", "name": "Northreach", "pos": [-80, -110], "radius": 80},
        {"id": "colossus_gate", "name": "Colossus Gate", "pos": [0, -130], "radius": 50},
    ],
    # Points of interest. `pad` = flat radius baked into the terrain.
    "pois": [
        {"id": "spawn", "type": "spawn", "pos": [0, 160], "yaw": 3.1416, "pad": 8},
        {"id": "gate_south", "type": "portal", "pos": [0, 174], "yaw": 3.1416, "pad": 5,
         "dest": "hub", "label": "RUNEHOLD", "arrival": "gate_highlands"},
        {"id": "wp_ashford", "type": "waypoint", "pos": [10, 152], "yaw": 0.0, "pad": 5,
         "name": "Ashford Shrine"},
        {"id": "camp_1", "type": "camp", "pos": [-12, 108], "yaw": 0.0, "pad": 11, "radius": 12.0,
         "composition": ["rusher", "rusher"], "banners": 2},
        {"id": "chest_south", "type": "chest", "pos": [-46, 132], "yaw": 0.4, "pad": 3, "rarity_bias": 0},
        {"id": "camp_2", "type": "camp", "pos": [34, 98], "yaw": 0.0, "pad": 11, "radius": 12.0,
         "composition": ["rusher", "caster", "rusher"], "banners": 2},
        {"id": "grove", "type": "landmark", "pos": [62, 122], "yaw": 0.0, "pad": 0, "prop": "charred_grove"},
        {"id": "ruin_1", "type": "ruin", "pos": [-118, 116], "yaw": 0.5, "pad": 11, "walls": 5,
         "chest": True, "rarity_bias": 0, "ambush": ["assassin", "assassin"]},
        {"id": "monolith_w", "type": "landmark", "pos": [-60, 64], "yaw": 0.26, "pad": 3, "prop": "rune_monolith"},
        {"id": "wp_crossroads", "type": "waypoint", "pos": [-46, 66], "yaw": 0.0, "pad": 5,
         "name": "Crossroads Cairn"},
        {"id": "ambush_1", "type": "ambush", "pos": [-26, 36], "yaw": 0.0, "pad": 4, "radius": 7.0,
         "composition": ["rusher", "rusher", "assassin"]},
        {"id": "camp_3", "type": "camp", "pos": [-90, 40], "yaw": 0.0, "pad": 11, "radius": 12.0,
         "composition": ["assassin", "assassin", "caster"], "banners": 2},
        {"id": "ruin_2", "type": "ruin", "pos": [-108, 2], "yaw": 1.1, "pad": 11, "walls": 4,
         "chest": True, "rarity_bias": 1, "ambush": []},
        {"id": "camp_4", "type": "camp", "pos": [-8, 10], "yaw": 0.0, "pad": 11, "radius": 12.0,
         "composition": ["brute", "rusher", "caster"], "banners": 3},
        {"id": "camp_5", "type": "camp", "pos": [74, 66], "yaw": 0.0, "pad": 11, "radius": 12.0,
         "composition": ["rusher", "rusher", "caster"], "banners": 2},
        {"id": "chest_se", "type": "chest", "pos": [118, 146], "yaw": 2.4, "pad": 3, "rarity_bias": 1},
        {"id": "grove_se", "type": "landmark", "pos": [94, 130], "yaw": 0.0, "pad": 0, "prop": "charred_grove"},
        {"id": "wp_eastwatch", "type": "waypoint", "pos": [80, 28], "yaw": 0.0, "pad": 5,
         "name": "Eastwatch Shrine"},
        {"id": "camp_6", "type": "camp", "pos": [66, -6], "yaw": 0.0, "pad": 11, "radius": 12.0,
         "composition": ["elite", "rusher", "rusher"], "banners": 3},
        {"id": "monolith_e", "type": "landmark", "pos": [46, -30], "yaw": -0.35, "pad": 3, "prop": "rune_monolith"},
        {"id": "dungeon_e", "type": "dungeon", "pos": [148, -62], "yaw": 1.5708, "pad": 7,
         "label": "HOLLOW CISTERN", "pad_from": [126, -56]},
        {"id": "patrol_east", "type": "elite_patrol", "pos": [104, -22], "yaw": 0.0, "pad": 0,
         "patrol": [[104, -22], [126, -56], [108, -96], [70, -118]],
         "composition": ["elite", "rusher", "rusher"], "wake_radius": 55.0},
        {"id": "bone_field", "type": "landmark", "pos": [108, -96], "yaw": 0.0, "pad": 0, "prop": "bone_field"},
        {"id": "camp_7", "type": "camp", "pos": [70, -118], "yaw": 0.0, "pad": 11, "radius": 12.0,
         "composition": ["brute", "assassin", "caster", "rusher"], "banners": 3},
        {"id": "ambush_2", "type": "ambush", "pos": [10, -72], "yaw": 0.0, "pad": 4, "radius": 7.0,
         "composition": ["assassin", "assassin"]},
        {"id": "wp_northreach", "type": "waypoint", "pos": [-32, -80], "yaw": 0.0, "pad": 5,
         "name": "Northreach Shrine"},
        {"id": "chest_hidden", "type": "chest", "pos": [-52, -100], "yaw": 1.0, "pad": 3, "rarity_bias": 1},
        {"id": "ruin_3", "type": "ruin", "pos": [-138, -76], "yaw": 2.0, "pad": 11, "walls": 6,
         "chest": True, "rarity_bias": 1, "ambush": ["assassin", "assassin", "caster"]},
        {"id": "dungeon_w", "type": "dungeon", "pos": [-152, -28], "yaw": -1.5708, "pad": 7,
         "label": "EMBER WARRENS", "pad_from": [-132, -30]},
        {"id": "camp_8", "type": "camp", "pos": [-70, -136], "yaw": 0.0, "pad": 11, "radius": 12.0,
         "composition": ["brute", "rusher", "rusher", "caster"], "banners": 3},
        {"id": "wp_gate", "type": "waypoint", "pos": [22, -110], "yaw": 0.0, "pad": 5,
         "name": "Colossus Gate Shrine"},
        {"id": "arena", "type": "arena", "pos": [0, -142], "yaw": 0.0, "pad": 18, "radius": 16.0,
         "boss_offset": [0, -8], "trigger_offset": [0, 4], "trigger_radius": 12.0,
         "portals": [
             {"id": "gate_north", "pos": [-4, -156], "dest": "hub", "label": "RUNEHOLD", "arrival": "gate_highlands"},
             {"id": "gate_spire", "pos": [4, -156], "dest": "spire", "label": "THE SHATTERED SPIRE", "arrival": ""},
         ]},
    ],
}
