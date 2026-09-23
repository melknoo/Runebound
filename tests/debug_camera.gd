extends Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var lab: CombatLab = (load("res://scenes/combat_lab.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(lab)
	get_tree().current_scene = lab
	for i in 30:
		await get_tree().physics_frame
	var rig := lab.camera_rig
	print("rig pos: ", rig.global_position)
	print("player pos: ", lab.player.global_position)
	print("spring len: ", rig.spring.spring_length, "  hit len: ", rig.spring.get_hit_length())
	print("spring global: ", rig.spring.global_position, " basis z: ", rig.spring.global_transform.basis.z)
	print("camera global: ", rig.camera.global_position)
	print("camera local: ", rig.camera.position)
	print("pitch: ", rig._pitch, " yaw: ", rig._yaw)
	get_tree().quit(0)
