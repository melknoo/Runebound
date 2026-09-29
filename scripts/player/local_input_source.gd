class_name LocalInputSource
extends InputSource
## The local player's keyboard and mouse -> PlayerIntent. M10: keys belong to
## loadout slots, not abilities: LMB fires the class's basic attack, RMB / 1 /
## 2 / 3 whatever sits in the four free slots (InputSetup.SLOT_ACTIONS), Space
## dodges. Movement is rotated into the camera's flat basis here, so Player
## never needs to know where the input came from.


func poll(intent: PlayerIntent, player: Player) -> void:
	if player.input_locked:
		return
	if Input.is_action_just_pressed(&"dodge"):
		intent.pressed.append(&"dodge")
	_read(intent, &"primary_attack", player.basic_attack())
	for i in mini(player.loadout.size(), InputSetup.SLOT_ACTIONS.size()):
		_read(intent, InputSetup.SLOT_ACTIONS[i], player.loadout[i])
	intent.sprint = InputMap.has_action(&"sprint") and Input.is_action_pressed(&"sprint")
	var raw := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	if raw != Vector2.ZERO and player.camera_rig != null:
		intent.move_dir = (player.camera_rig.get_flat_basis() * Vector3(raw.x, 0, raw.y)).normalized()


static func _read(intent: PlayerIntent, action: StringName, id: StringName) -> void:
	if id == &"" or not InputMap.has_action(action):
		return
	if Input.is_action_just_pressed(action):
		intent.pressed.append(id)
	if Input.is_action_pressed(action):
		intent.held.append(id)
