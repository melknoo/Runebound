extends Node
## Frame-by-frame telemetry for Ember Lance pierce. Not part of CI.

func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var lab: CombatLab = (load("res://scenes/combat_lab.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(lab)
	get_tree().current_scene = lab
	for i in 5:
		await get_tree().physics_frame
	lab.kill_all_enemies()
	for i in 20:
		await get_tree().physics_frame

	var player := lab.player
	player.global_position = Vector3(0, 0.2, 6)
	await get_tree().physics_frame

	var pierce_item := ItemData.new()
	pierce_item.slot = ItemData.Slot.WEAPON
	pierce_item.display_name = "Piercer"
	pierce_item.affixes = [{"id": &"ember_pierce", "label": "pierce", "stat": &"ember_pierce", "value": 1.0}]
	player.equipment.add_item(pierce_item)
	player.equipment.equip(pierce_item)
	print("stat ember_pierce = ", player.equipment.stat(&"ember_pierce"))
	print("player facing: ", player.facing(), " pos: ", player.global_position)

	var front := MeleeRusher.new()
	var back := MeleeRusher.new()
	for pair in [[front, 4.0], [back, 7.0]]:
		var e: EnemyBase = pair[0]
		lab.enemies_root.add_child(e)
		e.player = player
		e.global_position = player.global_position + player.facing() * (pair[1] as float)
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("front: ", front.global_position, "  back: ", back.global_position)
	print("aim_dir: ", player.aim_direction())
	print("try_ember: ", player.try_ember())

	var proj: EmberLanceProjectile = null
	for i in 70:
		await get_tree().physics_frame
		if proj == null:
			for child in lab.get_children():
				if child is EmberLanceProjectile:
					proj = child
			if proj != null:
				print("frame %d: spawned %s pierces=%d" % [i, proj.global_position, proj._pierces_left])
		elif is_instance_valid(proj):
			print("frame %d: %s pierces=%d fronthp=%.0f backhp=%.0f" % [i, proj.global_position, proj._pierces_left,
				front.health.current_health if is_instance_valid(front) else -1.0,
				back.health.current_health if is_instance_valid(back) else -1.0])
		else:
			print("frame %d: gone. front=%.0f back=%.0f" % [i,
				front.health.current_health if is_instance_valid(front) else -1.0,
				back.health.current_health if is_instance_valid(back) else -1.0])
			break
	get_tree().quit(0)
