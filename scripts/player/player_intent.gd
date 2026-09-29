class_name PlayerIntent
extends RefCounted
## M07b: what a player wants to do this physics tick, filled by an InputSource
## (local keyboard/mouse today, a network peer in the co-op milestone). Player
## consumes only this, never Input directly, so a remote or server-side hero
## runs the same code.

## World-space, flat, normalized movement direction (the source applies the
## camera yaw); ZERO when idle.
var move_dir: Vector3 = Vector3.ZERO
## Action ids pressed this tick (ability ids and "dodge"), in press order.
var pressed: Array[StringName] = []
## M10: ability ids whose key is held down this tick (auto-fire, block).
var held: Array[StringName] = []
## Held this tick: run faster (M08 notes; Player allows it out of combat only).
var sprint: bool = false
## M10: where a source without a camera aims (bots); ZERO = the camera / facing.
var aim_dir: Vector3 = Vector3.ZERO


func clear() -> void:
	move_dir = Vector3.ZERO
	pressed.clear()
	held.clear()
	sprint = false
	aim_dir = Vector3.ZERO
