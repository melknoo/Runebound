class_name LocalInputSource
extends InputSource
## The local player's keyboard and mouse -> PlayerIntent. Ability keys come
## from each AbilityData.input_action (InputSetup binds them at runtime);
## movement is rotated into the camera's flat basis here, so Player never
## needs to know where the input came from.


func poll(intent: PlayerIntent, player: Player) -> void:
	if player.input_locked:
		return
	if Input.is_action_just_pressed(&"dodge"):
		intent.pressed.append(&"dodge")
	for data in player.class_data.abilities:
		if data == null or data.input_action == &"" or not InputMap.has_action(data.input_action):
			continue
		if Input.is_action_just_pressed(data.input_action):
			intent.pressed.append(data.id)
	var raw := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	if raw != Vector2.ZERO and player.camera_rig != null:
		intent.move_dir = (player.camera_rig.get_flat_basis() * Vector3(raw.x, 0, raw.y)).normalized()
