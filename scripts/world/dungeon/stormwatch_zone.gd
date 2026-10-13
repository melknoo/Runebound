class_name StormwatchZone
extends DungeonZone
## M13b: THE STORMWATCH behind the gate east of the Cinder Flats - a shattered
## rune observatory where stormcallers once bound lightning into runes; cold
## slate, verdigris copper, violet-white lightning against the dark (layout:
## tools/worldgen/stormwatch_layout.py, palette: art_spec "stormwatch"). The
## co-op dungeon: 3-5 heroes, every run fresh, a fallen hero can be revived
## (DungeonRegistry "stormwatch").


func _dungeon_id() -> String:
	return "stormwatch"


func _floor_role() -> StringName:
	return &"stormwatch_floor"


func _wall_role() -> StringName:
	return &"stormwatch_wall"


## Interior: blue-black slate, a cold faint top light, a violet haze.
func _zone_look() -> ZoneLook:
	var l := ZoneLook.spire_interior()
	l.background = ArtKit.color("palettes.stormwatch.background")
	l.ambient_color = ArtKit.color("palettes.stormwatch.ambient")
	l.ambient_energy = 2.4
	l.fog_color = ArtKit.color("palettes.stormwatch.fog")
	l.fog_density = 0.02
	l.sun_color = Color(0.62, 0.66, 0.9)
	l.sun_energy = 0.5
	l.split_shadows = Color(0.4, 0.42, 0.52)
	l.split_highlights = Color(0.58, 0.56, 0.7)
	return l


func _light_color() -> Color:
	return ArtKit.color("palettes.stormwatch.lamp", Color(0.78, 0.75, 1.0))


func _lamp_prop() -> String:
	return "sw_lamp"


## The stormwatch kit: slate arches with a lightning rod on the halls'
## walls, copper cables on insulators along the galleries, grounding grates
## in the floors, split slate and broken instruments at the walls' feet
## (visual only; none on the server).
func _build_dungeon() -> void:
	if Net.has_view() and look != null and look.art_pass:
		DungeonDressing.dress(self, {
			"arch": "sw_arch", "pipe": "sw_cable", "grate": "sw_grate",
			"scatter": [
				{"prop": "sw_rubble", "per_m": 0.2, "band": Vector2(0.2, 0.9), "scale": Vector2(0.8, 1.4),
					"cluster": Vector2i(1, 3), "spread": 0.35},
				{"prop": "sw_shard", "per_m": 0.08, "band": Vector2(0.1, 0.6), "scale": Vector2(0.9, 1.3),
					"cluster": Vector2i(1, 2), "spread": 0.3},
			],
		}, 7417)
	_add_ambience("stormwatch_wind_loop" if ResourceLoader.exists("res://assets/sfx/stormwatch_wind_loop_01.wav")
		else "spire_drone_loop", Vector3.INF, -12.0)
