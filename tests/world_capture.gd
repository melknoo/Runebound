extends Node
## World-zone screenshot run (`run_godot.ps1 worldcapture`): boots in the hub,
## shoots its beats, travels to the highlands and shoots the region + boss.
## ZoneBase attaches this to every zone when --worldcapture is passed, so each
## instance only runs the sequence matching its zone type.

var zone: ZoneBase
var _shot_index_base: int = 0


func _ready() -> void:
	zone = get_parent() as ZoneBase
	if zone is HubZone:
		_run_hub.call_deferred()
	elif zone is AshenHighlands:
		_run_highlands.call_deferred()
	elif zone is SpireZone:
		_run_spire.call_deferred()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var dir := ProjectSettings.globalize_path("res://captures_world")
	DirAccess.make_dir_recursive_absolute(dir)
	img.save_png("%s/%s.png" % [dir, name])
	print("capture: ", name)


func _aim(yaw: float, pitch: float) -> void:
	zone.camera_rig._yaw = yaw
	zone.camera_rig._pitch = pitch


func _run_hub() -> void:
	# Never touch the real save from capture runs (boss kills set flags).
	SaveGame.save_path = "user://capture_save.json"
	SaveGame.wipe()
	zone.player.god_mode = true
	await _wait(0.8)
	_aim(0.0, -0.25)
	await _wait(0.3)
	await _shot("01_hub_spawn")
	# Campfire close-up.
	zone.player.global_position = Vector3(2.5, 0.2, 1)
	_aim(0.6, -0.3)
	await _wait(0.4)
	await _shot("02_hub_campfire")
	# Portal.
	zone.player.global_position = Vector3(0, 0.2, -9)
	_aim(0.0, -0.2)
	await _wait(0.4)
	await _shot("03_hub_portal")
	await _wait(0.3)
	zone.travel_to("res://scenes/ashen_highlands.tscn")


func _run_highlands() -> void:
	zone.player.god_mode = true
	await _wait(0.8)
	_aim(0.0, -0.18)
	await _shot("04_highlands_vista")
	# First camp fight.
	zone.player.global_position = Vector3(0, 0.2, 20)
	await _wait(1.2)
	await _shot("05_highlands_camp")
	# Chest.
	var chest: TreasureChest = null
	for child in zone.world.get_children():
		if child is TreasureChest:
			chest = child
			break
	zone.player.global_position = chest.global_position + Vector3(0, 0.2, 3.5)
	chest.open(zone)  # M07: chests open on the interact key
	_aim(0.0, -0.3)
	await _wait(0.8)
	await _shot("06_chest_loot")
	# Boss: telegraphed charge + boss bar.
	var highlands := zone as AshenHighlands
	zone.player.global_position = Vector3(0, 0.2, -18)
	_aim(0.0, -0.15)
	await _wait(1.0)
	await _shot("07_boss_arena")
	# Wait for a charge telegraph (boss decides on range/cooldown).
	for i in 100:
		await _wait(0.1)
		if highlands.boss != null and highlands.boss.ai_state == EnemyBase.AIState.WINDUP \
				and highlands.boss._attack_kind == "charge":
			break
	await _wait(0.35)
	await _shot("08_boss_charge_telegraph")
	# Enrage.
	if highlands.boss != null:
		highlands.boss.take_hit(HitInfo.create(320.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, Vector3.ZERO))
		await _wait(0.5)
		await _shot("09_boss_enraged")
		highlands.boss.take_hit(HitInfo.create(99999.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, Vector3.ZERO))
		await _wait(1.0)
		_aim(0.0, -0.25)
		await _shot("10_boss_defeated_portal")
	await _wait(0.5)
	zone.travel_to("res://scenes/shattered_spire.tscn")


func _run_spire() -> void:
	var spire := zone as SpireZone
	zone.player.god_mode = true
	await _wait(0.8)
	_aim(0.0, -0.15)
	await _shot("11_spire_entry")
	# Gallery verticality.
	zone.player.global_position = Vector3(0, 0.2, 6)
	await _wait(1.0)
	await _shot("12_spire_gallery")
	# Warden block feedback.
	var warden := HollowWarden.new()
	zone.enemies_root.add_child(warden)
	warden.player = zone.player
	warden.global_position = zone.player.global_position + zone.player.facing() * 3.0
	await _wait(0.4)
	warden.visual.rotation.y = zone.player._visual.rotation.y + PI
	zone.player.try_melee()
	await _wait(0.2)
	await _shot("13_warden_block")
	warden.take_hit(HitInfo.create(9999.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, warden.global_position))
	await _wait(0.6)
	# Boss phase 1: runes + slam. Clear dragged-along camp enemies first so
	# the shots frame the boss, not an elite in the camera.
	zone.kill_all_enemies()
	await _wait(0.8)
	zone.player.global_position = Vector3(0, 0.2, -20)
	_aim(0.0, -0.12)
	await _wait(1.2)
	if spire.boss != null:
		# The vault camp re-triggers on the teleport — clear everything but
		# the boss so the shots stay framed on him.
		for child in zone.enemies_root.get_children():
			if child != spire.boss:
				child.free()
		await _wait(0.3)
		spire.boss._rune_timer = 0.0
		await _wait(0.9)
		await _shot("14_vessel_phase1_runes")
		# Shatter transition.
		spire.boss.take_hit(HitInfo.create(760.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, Vector3.ZERO))
		await _wait(0.4)
		await _shot("15_vessel_shatter")
		await _wait(1.2)
		# Phase 2: blink + fan.
		spire.boss._blink_timer = 0.0
		spire.boss._fan_timer = 0.1
		await _wait(0.5)
		await _shot("16_vessel_phase2")
		spire.boss._ring_timer = 0.0
		await _wait(1.2)
		await _shot("17_vessel_hazard_ring")
		spire.boss.take_hit(HitInfo.create(99999.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, Vector3.ZERO))
		await _wait(1.2)
		_aim(0.0, -0.25)
		await _shot("18_vessel_defeated")
	print("world capture complete")
	get_tree().quit(0)
