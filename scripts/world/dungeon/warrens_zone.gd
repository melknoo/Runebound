class_name WarrensZone
extends DungeonZone
## M13: THE EMBER WARRENS behind the gate in the Charwood - old ember mines
## and their smelting halls, soot-black hewn rock and old timber, copper ore
## in the walls, lava in the runnels, hot ember light against the dark
## (layout: tools/worldgen/warrens_layout.py, palette: art_spec "warrens").


func _dungeon_id() -> String:
	return "warrens"


func _floor_role() -> StringName:
	return &"warrens_floor"


func _wall_role() -> StringName:
	return &"warrens_wall"


## Interior: near-black umber, a faint warm top light, smoky haze.
func _zone_look() -> ZoneLook:
	var l := ZoneLook.spire_interior()
	l.background = ArtKit.color("palettes.warrens.background")
	l.ambient_color = ArtKit.color("palettes.warrens.ambient")
	l.ambient_energy = 2.4
	l.fog_color = ArtKit.color("palettes.warrens.fog")
	l.fog_density = 0.022
	l.sun_color = Color(0.85, 0.6, 0.42)
	l.sun_energy = 0.55
	l.split_shadows = Color(0.5, 0.42, 0.4)
	l.split_highlights = Color(0.62, 0.5, 0.38)
	return l


func _light_color() -> Color:
	return ArtKit.color("palettes.warrens.lamp", Color(1.0, 0.7, 0.35))


func _lamp_prop() -> String:
	return "wa_lamp"


## The warrens kit: timber frames on the halls' walls, ore veins along the
## galleries, ember grates in the floors, spouts where the lava runs into a
## wall, slag, coal and ore at the walls' feet (visual only; none on the server).
func _build_dungeon() -> void:
	if Net.has_view() and look != null and look.art_pass:
		DungeonDressing.dress(self, {
			"arch": "wa_timber", "pipe": "wa_ore_vein", "grate": "wa_ember_grate", "sluice": "wa_lava_spout",
			"scatter": [
				{"prop": "wa_slag", "per_m": 0.22, "band": Vector2(0.2, 0.9), "scale": Vector2(0.8, 1.4),
					"cluster": Vector2i(1, 3), "spread": 0.35},
				{"prop": "wa_ore_chunk", "per_m": 0.14, "band": Vector2(0.1, 0.6), "scale": Vector2(0.8, 1.3),
					"cluster": Vector2i(1, 2), "spread": 0.3},
			],
		}, 5329)
	_add_ambience("warrens_rumble_loop" if ResourceLoader.exists("res://assets/sfx/warrens_rumble_loop_01.wav")
		else "spire_drone_loop", Vector3.INF, -13.0)
