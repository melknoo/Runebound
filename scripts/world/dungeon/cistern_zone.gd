class_name CisternZone
extends DungeonZone
## M13: THE HOLLOW CISTERN behind the gate on the Ribs of Emberfall - an old,
## half-flooded cistern, cold wet blue-green stone with algae in the joints,
## dark water, pale phosphor lamps (layout: tools/worldgen/cistern_layout.py,
## palette: art_spec "cistern").


func _dungeon_id() -> String:
	return "cistern"


func _floor_role() -> StringName:
	return &"cistern_floor"


func _wall_role() -> StringName:
	return &"cistern_wall"


## Interior: near-black teal, a faint cold top light, low haze over the water.
func _zone_look() -> ZoneLook:
	var l := ZoneLook.spire_interior()
	l.background = ArtKit.color("palettes.cistern.background")
	l.ambient_color = ArtKit.color("palettes.cistern.ambient")
	l.ambient_energy = 1.7
	l.fog_color = ArtKit.color("palettes.cistern.fog")
	l.fog_density = 0.026
	l.sun_color = Color(0.55, 0.75, 0.82)
	l.sun_energy = 0.6
	l.split_shadows = Color(0.42, 0.5, 0.56)
	l.split_highlights = Color(0.5, 0.58, 0.56)
	return l


func _light_color() -> Color:
	return ArtKit.color("palettes.cistern.lamp", Color(0.62, 0.9, 0.88))


func _lamp_prop() -> String:
	return "ci_lamp"


## The cistern kit: arches on the halls' walls, pipes in the corridors, drain
## grates, sluice frames where the channels meet the walls, algae and fallen
## stones at the walls' feet (visual only; none on the server).
func _build_dungeon() -> void:
	if Net.has_view() and look != null and look.art_pass:
		DungeonDressing.dress(self, {
			"arch": "ci_wall_arch", "pipe": "ci_pipe", "grate": "ci_grate", "sluice": "ci_sluice_gate",
			"scatter": [
				{"prop": "ci_rubble", "per_m": 0.22, "band": Vector2(0.2, 0.9), "scale": Vector2(0.8, 1.4),
					"cluster": Vector2i(1, 3), "spread": 0.35},
				{"prop": "ci_moss_tuft", "per_m": 0.3, "band": Vector2(0.1, 0.6), "scale": Vector2(0.8, 1.5),
					"cluster": Vector2i(1, 3), "spread": 0.3},
			],
		}, 4211)
	_add_ambience("cistern_drip_loop" if ResourceLoader.exists("res://assets/sfx/cistern_drip_loop_01.wav")
		else "spire_drone_loop", Vector3.INF, -14.0)
