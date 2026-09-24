class_name WorldPickup
extends Node3D
## M07b: base for things lying on the ground that a player picks up by walking
## over them (ItemDrop, GoldDrop). Owns the proximity test and the bob/spin of
## `_shape`; subclasses build their shape and implement _try_pickup().

const PICKUP_RANGE := 1.4

## The player this pickup belongs to (the local one today; the killer later).
var player: Player

var _bob_time: float = 0.0
var _shape: Node3D
var _bob_height: float = 0.55
var _bob_amount: float = 0.12
var _spin: float = 1.5


func _process(delta: float) -> void:
	_bob_time += delta
	if _shape != null:
		_shape.position.y = _bob_height + sin(_bob_time * 2.4) * _bob_amount
		_shape.rotate_y(delta * _spin)
	if player == null or not is_instance_valid(player):
		return
	_pickup_motion(delta)
	if player.global_position.distance_to(global_position) <= PICKUP_RANGE:
		_try_pickup()


## Movement towards the player before the pickup range (gold magnet).
func _pickup_motion(_delta: float) -> void:
	pass


## Called every frame while the player stands in range; decide and queue_free.
func _try_pickup() -> void:
	pass
