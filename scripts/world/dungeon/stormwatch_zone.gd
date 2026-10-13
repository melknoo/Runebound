class_name StormwatchZone
extends DungeonZone
## M13b: THE STORMWATCH behind the gate east of the Cinder Flats - a shattered
## rune observatory where stormcallers once bound lightning into runes; cold
## slate, verdigris copper, violet-white lightning against the dark (layout:
## tools/worldgen/stormwatch_layout.py, palette: art_spec "stormwatch"). The
## co-op dungeon: 3-5 heroes, every run fresh, a fallen hero can be revived
## (DungeonRegistry "stormwatch"). Phase 0 is the greybox (the Spire's
## materials, code-built lamps).


func _dungeon_id() -> String:
	return "stormwatch"


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


func _build_dungeon() -> void:
	_add_ambience("spire_drone_loop", Vector3.INF, -13.0)
