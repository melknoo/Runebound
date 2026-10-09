class_name PuzzleLabZone
extends DungeonZone
## M13: the puzzle kit's test dungeon (tools/worldgen/lab_layout.py) - one
## room per mechanism. Tests and the net scenarios use it; no gate leads
## here and it has no title (no discovery XP).


func _dungeon_id() -> String:
	return "lab"


func _zone_look() -> ZoneLook:
	return ZoneLook.spire_interior()
