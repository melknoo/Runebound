extends Node
## Automated playtest: drives the player through every combat beat and
## saves screenshots to captures/ for visual review of feel, VFX and the
## three art-style candidates. Added by CombatLab when run with `-- --capture`.

var lab: CombatLab
var _shot_index: int = 0


func _ready() -> void:
	lab = get_parent() as CombatLab
	# Pickups trigger saves — keep capture runs off the real save file.
	SaveGame.save_path = "user://capture_save.json"
	SaveGame.wipe()
	_run.call_deferred()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var dir := ProjectSettings.globalize_path("res://captures")
	DirAccess.make_dir_recursive_absolute(dir)
	_shot_index += 1
	var path := "%s/%02d_%s.png" % [dir, _shot_index, name]
	img.save_png(path)
	print("capture: ", path)


func _clear_and_place(enemy: EnemyBase, offset: Vector3) -> void:
	for child in lab.enemies_root.get_children():
		child.free()
	lab.enemies_root.add_child(enemy)
	enemy.player = lab.player
	enemy.global_position = lab.player.global_position + offset


func _aim_camera(yaw: float, pitch: float) -> void:
	lab.camera_rig._yaw = yaw
	lab.camera_rig._pitch = pitch


## Back to arena center facing -Z: keeps every section's framing clean.
func _recenter() -> void:
	lab.player.global_position = Vector3(0, 0.2, 6)
	lab.player.velocity = Vector3.ZERO
	_aim_camera(0.0, -0.35)


func _run() -> void:
	var player := lab.player
	player.god_mode = true
	await _wait(0.8)
	await _shot("start_view")

	# --- movement + camera sweep ---
	Input.action_press(&"move_forward")
	await _wait(0.5)
	await _shot("run_forward")
	_aim_camera(1.2, -0.4)
	await _wait(0.5)
	await _shot("run_camera_rotated")
	Input.action_release(&"move_forward")
	Input.action_press(&"move_left")
	await _wait(0.4)
	await _shot("strafe")
	Input.action_release(&"move_left")
	await _wait(0.3)

	# --- dodge ---
	_aim_camera(0.0, -0.35)
	Input.action_press(&"move_forward")
	player.try_dodge()
	await _wait(0.12)
	await _shot("dodge_mid")
	Input.action_release(&"move_forward")
	await _wait(0.6)

	# --- melee impact ---
	var punchbag := MeleeRusher.new()
	punchbag.max_health = 5000.0
	_clear_and_place(punchbag, player.facing() * 1.4)
	await _wait(0.2)
	player.try_melee()
	await _wait(0.17)
	await _shot("melee_impact")
	await _wait(0.6)

	# --- ember lance ---
	var ember_target := MeleeRusher.new()
	ember_target.max_health = 5000.0
	var aim_flat := player.aim_direction()
	aim_flat.y = 0.0
	_clear_and_place(ember_target, aim_flat.normalized() * 7.0)
	await _wait(0.2)
	player.try_ember()
	await _wait(0.22)
	await _shot("ember_flight")
	await _wait(0.14)
	await _shot("ember_impact")
	await _wait(0.8)

	# --- earthbreaker ---
	player.gain_resonance(100.0)
	player.reset_cooldowns()
	var eb_bag := MeleeRusher.new()
	eb_bag.max_health = 5000.0
	_clear_and_place(eb_bag, Vector3(2, 0, 1))
	await _wait(0.2)
	player.try_earthbreaker()
	await _wait(0.42)
	await _shot("earthbreaker_windup")
	await _wait(0.22)
	await _shot("earthbreaker_slam")
	await _wait(0.8)

	# --- enemy telegraph ---
	var attacker := MeleeRusher.new()
	attacker.max_health = 5000.0
	_clear_and_place(attacker, player.facing() * 2.2)
	await _wait(0.7)  # let it enter windup
	await _shot("rusher_telegraph")
	await _wait(1.0)

	# --- caster bolt ---
	var caster := RangedCaster.new()
	caster.max_health = 5000.0
	_clear_and_place(caster, Vector3(0, 0, -9))
	await _wait(1.3)
	await _shot("caster_charge")
	await _wait(0.8)
	await _shot("caster_bolt_flight")
	await _wait(0.5)

	# --- storm step ---
	player.reset_cooldowns()
	var dash_bag := MeleeRusher.new()
	dash_bag.max_health = 5000.0
	_clear_and_place(dash_bag, player.facing() * 3.0)
	await _wait(0.2)
	Input.action_press(&"move_forward")
	player.try_storm_step()
	Input.action_release(&"move_forward")
	await _wait(0.25)
	await _shot("storm_step_trail")
	await _wait(0.6)

	# --- chain spark: three targets ---
	_recenter()
	for child in lab.enemies_root.get_children():
		child.free()
	for i in 3:
		var e := MeleeRusher.new()
		e.max_health = 5000.0
		lab.enemies_root.add_child(e)
		e.player = player
		e.global_position = player.global_position + player.facing() * (4.0 + i * 3.5) \
			+ Vector3(i * 1.5 - 1.5, 0, 0)
	await _wait(0.2)
	player.reset_cooldowns()
	player.try_chain_spark()
	await _wait(0.08)
	await _shot("chain_spark_arcs")
	await _wait(0.6)

	# --- fracture rune: armed + detonation ---
	_recenter()
	var rune_bag := MeleeRusher.new()
	rune_bag.max_health = 5000.0
	_clear_and_place(rune_bag, player.facing() * 6.0)
	await _wait(0.2)
	player.reset_cooldowns()
	player.try_fracture_rune()
	await _wait(0.8)
	await _shot("fracture_rune_armed")
	await _wait(0.55)
	await _shot("fracture_rune_detonation")
	await _wait(0.6)

	# --- assassin + brute ---
	_recenter()
	var assa := Assassin.new()
	assa.max_health = 5000.0
	_clear_and_place(assa, player.facing() * 7.0)
	await _wait(1.6)
	await _shot("assassin_circling")
	var brute := Brute.new()
	brute.max_health = 5000.0
	_clear_and_place(brute, player.facing() * 2.2)
	await _wait(1.0)
	await _shot("brute_slam_telegraph")
	await _wait(1.2)

	# --- elite ---
	_recenter()
	for child in lab.enemies_root.get_children():
		child.free()
	lab.spawn_elite(EliteModifier.Kind.EMBERBOUND, player.global_position + player.facing() * 6.0)
	await _wait(2.6)
	await _shot("elite_emberbound")
	lab.targeting.cycle_target()
	await _wait(0.3)
	await _shot("elite_targeted_gold_bar")
	await _wait(0.4)

	# --- loot rarity presentation row ---
	_recenter()
	for child in lab.enemies_root.get_children():
		child.free()
	var rarities: Array[ItemData.Rarity] = [ItemData.Rarity.COMMON, ItemData.Rarity.MAGIC,
		ItemData.Rarity.RARE, ItemData.Rarity.LEGENDARY]
	for i in 4:
		var it: ItemData
		if rarities[i] == ItemData.Rarity.LEGENDARY:
			it = ItemGenerator.generate_legendary()
		else:
			it = ItemGenerator.generate(0)
			it.rarity = rarities[i]
		lab.spawn_item_drop(it, player.global_position + player.facing() * 5.0
			+ Vector3(-4.5 + i * 3.0, 0, 0))
	await _wait(0.6)
	await _shot("loot_rarity_row")

	# --- pickup toast ---
	var toast_item := ItemGenerator.generate(2)
	lab.spawn_item_drop(toast_item, player.global_position + player.facing() * 1.0)
	await _wait(0.5)
	await _shot("pickup_toast")

	# --- inventory panel ---
	for i in 5:
		player.equipment.add_item(ItemGenerator.generate(randi() % 3))
	player.equipment.add_item(ItemGenerator.generate_legendary())
	lab.inventory_ui.toggle()
	await _wait(0.3)
	lab.inventory_ui._select(player.equipment.inventory[player.equipment.inventory.size() - 1])
	await _wait(0.2)
	await _shot("inventory_panel")
	# Ability names only appear as a tooltip while hovering a slot here.
	get_viewport().warp_mouse(lab.hud.slot_rect(&"earthbreaker").get_center())
	await _wait(0.2)
	await _shot("ability_tooltip")
	lab.inventory_ui.toggle()
	await _wait(0.3)

	# --- Cindermaw eruption ---
	_recenter()
	var maw := ItemData.new()
	maw.slot = ItemData.Slot.WEAPON
	maw.rarity = ItemData.Rarity.LEGENDARY
	maw.display_name = "Cindermaw"
	maw.legendary_id = &"cindermaw"
	player.equipment.add_item(maw)
	player.equipment.equip(maw)
	var burn_bag := Brute.new()
	burn_bag.max_health = 9000.0
	var burn_neighbor := Brute.new()
	burn_neighbor.max_health = 9000.0
	_clear_and_place(burn_bag, player.facing() * 5.0)
	lab.enemies_root.add_child(burn_neighbor)
	burn_neighbor.player = player
	burn_neighbor.global_position = player.global_position + player.facing() * 5.0 + Vector3(1.8, 0, 0)
	await _wait(0.2)
	burn_bag.status.apply_burn()
	player.reset_cooldowns()
	player.try_ember()
	await _wait(0.42)
	await _shot("cindermaw_eruption")
	await _wait(0.6)

	# --- Conductor arcs ---
	_recenter()
	var oath := ItemData.new()
	oath.slot = ItemData.Slot.AMULET
	oath.rarity = ItemData.Rarity.LEGENDARY
	oath.display_name = "Conductor's Oath"
	oath.legendary_id = &"conductors_oath"
	player.equipment.add_item(oath)
	player.equipment.equip(oath)
	for child in lab.enemies_root.get_children():
		child.free()
	for i in 3:
		var c := Brute.new()
		c.max_health = 9000.0
		lab.enemies_root.add_child(c)
		c.player = player
		c.global_position = player.global_position + player.facing() * 5.0 \
			+ Vector3(-3.0 + i * 3.0, 0, -i * 1.0)
	await _wait(0.2)
	player.reset_cooldowns()
	player.try_chain_spark()
	await _wait(0.5)
	player.reset_cooldowns()
	player.try_chain_spark()  # lightning on Conductors: arcs everywhere
	await _wait(0.08)
	await _shot("conductor_arcs")
	await _wait(0.6)

	# --- stress scene ---
	lab.stress_test()
	await _wait(1.5)
	await _shot("stress_combat")
	player.gain_resonance(100.0)
	player.reset_cooldowns()
	player.try_earthbreaker()
	await _wait(0.62)
	await _shot("stress_earthbreaker")
	await _wait(1.0)

	# --- style comparison: same standing scene, three render styles ---
	lab.reset_lab()
	await _wait(0.6)
	player.try_ember()
	await _wait(0.2)
	await _shot("style_c_hybrid")
	lab.cycle_style()  # -> B native pixel
	await _wait(0.4)
	player.reset_cooldowns()
	player.try_ember()
	await _wait(0.2)
	await _shot("style_b_native")
	lab.cycle_style()  # -> A low res
	await _wait(0.4)
	player.reset_cooldowns()
	player.try_ember()
	await _wait(0.2)
	await _shot("style_a_lowres")
	lab.cycle_style()  # back to hybrid
	await _wait(0.3)

	print("capture run complete: %d shots" % _shot_index)
	get_tree().quit(0)
