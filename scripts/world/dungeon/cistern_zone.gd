class_name CisternZone
extends DungeonZone
## M13: THE HOLLOW CISTERN behind the gate on the Ribs of Emberfall - an old,
## half-flooded cistern, cold blue-green stone (layout:
## tools/worldgen/cistern_layout.py). Phase 0: the walkable shell with
## placeholder camps; water, puzzles, its family and bosses follow.


func _dungeon_id() -> String:
	return "cistern"


## Interior: near-black teal, a cold top light, low haze over the water.
func _zone_look() -> ZoneLook:
	var l := ZoneLook.spire_interior()
	l.background = Color(0.025, 0.045, 0.05)
	l.ambient_color = Color(0.19, 0.28, 0.3)
	l.fog_color = Color(0.1, 0.17, 0.19)
	l.sun_color = Color(0.5, 0.72, 0.8)
	l.split_shadows = Color(0.42, 0.5, 0.56)
	l.split_highlights = Color(0.5, 0.58, 0.56)
	return l


func _light_color() -> Color:
	return Color(0.42, 0.82, 0.86)


func _build_dungeon() -> void:
	_add_ambience("spire_drone_loop", Vector3.INF, -16.0)
