extends Node
## Headless smoke test: boots the Combat Lab and exercises every M01 system.
## Run: godot --headless --path . res://tests/smoke_test.tscn
## (a scene, not a --script MainLoop: autoloads must be active)

var _failures: Array[String] = []
var lab: CombatLab


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok: " + label)
	else:
		_failures.append(label)
		printerr("  FAIL: " + label)


func _wait_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _run() -> void:
	print("== RUNEBOUND smoke test ==")
	# Hermetic save: never touch the real user save from tests.
	SaveGame.save_path = "user://smoke_test_save.json"
	SaveGame.wipe()
	var packed: PackedScene = load("res://scenes/combat_lab.tscn")
	_check(packed != null, "combat_lab.tscn loads")
	var scene := packed.instantiate()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	lab = scene as CombatLab
	await _wait_frames(5)

	_check(lab != null, "CombatLab script attached")
	_check(lab.player != null, "player spawned")
	_check(lab.camera_rig != null, "camera rig spawned")
	_check(lab.enemy_count() == 3, "initial enemies spawned (3)")
	var sfx := get_node("/root/Sfx")
	_check(bool(sfx.call(&"has_sound", "swing")), "sfx library loaded (swing)")
	_check(bool(sfx.call(&"has_sound", "ember_impact")), "sfx library loaded (ember_impact)")

	var player := lab.player

	# --- movement ---
	var start_pos := player.global_position
	Input.action_press(&"move_forward")
	await _wait_frames(30)
	Input.action_release(&"move_forward")
	_check(player.global_position.distance_to(start_pos) > 1.5, "WASD movement moves player")
	await _wait_frames(10)
	_check(player.velocity.length() < 0.5, "player decelerates to stop")

	# --- dodge ---
	var dodge_start := player.global_position
	var dodged := player.try_dodge()
	_check(dodged, "dodge starts")
	_check(player.health.invulnerable, "dodge grants i-frames")
	await _wait_frames(25)
	_check(player.state == Player.State.MOVE, "dodge returns to MOVE")
	_check(player.global_position.distance_to(dodge_start) > 1.5, "dodge covers distance")
	_check(not player.try_dodge(), "dodge respects cooldown")

	# --- melee vs enemy ---
	lab.kill_all_enemies()
	await _wait_frames(20)
	_check(lab.enemy_count() == 0, "kill_all clears enemies")
	var rusher := MeleeRusher.new()
	lab.enemies_root.add_child(rusher)
	rusher.player = player
	rusher.global_position = player.global_position + player.facing() * 1.3
	await _wait_frames(2)
	var rusher_hp := rusher.health.current_health
	_check(player.try_melee(), "melee starts")
	await _wait_frames(35)
	_check(rusher.health.current_health < rusher_hp, "melee damages enemy in range")
	_check(player.resonance > 0.0, "melee generates Resonance")
	_check(player.state == Player.State.MOVE, "melee recovers to MOVE")

	# --- tab targeting ---
	_check(lab.targeting.current == null, "no target before Tab is pressed")
	lab.targeting.cycle_target()
	_check(lab.targeting.current == rusher, "tab selects enemy near aim")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(lab.targeting._name_label.visible and lab.targeting._name_label.text == "Cinder Marauder",
		"target name plate shows the enemy name")
	var hud_names := lab.hud.ability_names()
	_check(hud_names.size() == 7 and hud_names.has("Fracture Rune") and hud_names.has("Dodge"),
		"HUD shows all 7 ability names")
	lab.targeting.cycle_target()
	_check(lab.targeting.current == rusher, "tab cycle wraps with single candidate")
	var to_target := rusher.global_position - player.global_position
	var facing_dot := player.facing().dot(Vector3(to_target.x, 0, to_target.z).normalized())
	_check(facing_dot > 0.9, "melee faced the enemy")
	# Second candidate: spawn another enemy nearby, Tab must move to it.
	var second := MeleeRusher.new()
	lab.enemies_root.add_child(second)
	second.player = player
	second.global_position = player.global_position + player.facing() * 4.0 + Vector3(1.5, 0, 0)
	await _wait_frames(2)
	lab.targeting.cycle_target()
	_check(lab.targeting.current == second, "tab cycles to the next candidate")
	second.take_hit(HitInfo.create(9999.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, player.global_position))
	await get_tree().process_frame
	await get_tree().process_frame
	_check(lab.targeting.current == null, "target drops on death")
	# Regression: Tab with a hard-freed target must not error (input events
	# can arrive before _process re-validates the held target).
	var freed_target := MeleeRusher.new()
	lab.enemies_root.add_child(freed_target)
	freed_target.player = player
	freed_target.global_position = player.global_position + player.facing() * 3.0
	await _wait_frames(2)
	lab.targeting.cycle_target()
	freed_target.free()
	lab.targeting.cycle_target()
	var safe := lab.targeting.current == null or is_instance_valid(lab.targeting.current)
	_check(safe, "tab after hard-freed target is safe")

	# --- ember lance ---
	lab.kill_all_enemies()
	await _wait_frames(20)
	var target := MeleeRusher.new()
	lab.enemies_root.add_child(target)
	target.player = player
	# Place directly on the camera aim line so the projectile connects.
	var aim_dir := player.aim_direction()
	target.global_position = player.global_position + aim_dir * 6.0 - Vector3(0, aim_dir.y * 6.0, 0)
	await _wait_frames(2)
	var target_hp := target.health.current_health
	_check(player.try_ember(), "ember lance casts")
	_check(not player.try_ember(), "ember lance respects cooldown")
	await _wait_frames(60)
	var ember_hit := not is_instance_valid(target) or target.health.current_health < target_hp
	_check(ember_hit, "ember lance projectile hits")

	# --- burn dot ---
	if not is_instance_valid(target) or target.health.is_dead:
		print("  (target died before burn check - acceptable)")
	else:
		var burned_hp := target.health.current_health
		await _wait_frames(70)
		var burn_ticked := not is_instance_valid(target) or target.health.current_health < burned_hp
		_check(burn_ticked, "burn ticks damage over time")

	# --- earthbreaker ---
	lab.kill_all_enemies()
	await _wait_frames(20)
	var eb_target := MeleeRusher.new()
	lab.enemies_root.add_child(eb_target)
	eb_target.player = player
	eb_target.global_position = player.global_position + Vector3(2, 0.2, 0)
	await _wait_frames(2)
	player.gain_resonance(100.0)
	var res_before := player.resonance
	var eb_hp := eb_target.health.current_health
	_check(player.try_earthbreaker(), "earthbreaker starts with resonance")
	_check(player.resonance < res_before, "earthbreaker consumes Resonance")
	await _wait_frames(70)
	var eb_hit := not is_instance_valid(eb_target) or eb_target.health.current_health < eb_hp
	_check(eb_hit, "earthbreaker damages nearby enemy")
	_check(player.state == Player.State.MOVE, "earthbreaker recovers to MOVE")
	player.resonance = 0.0
	player.reset_cooldowns()
	_check(not player.try_earthbreaker(), "earthbreaker refused without Resonance")

	# --- status effects: chill + shock ---
	lab.kill_all_enemies()
	await _wait_frames(20)
	var status_dummy := MeleeRusher.new()
	lab.enemies_root.add_child(status_dummy)
	status_dummy.player = player
	status_dummy.global_position = player.global_position + Vector3(0, 0.2, -3)
	await _wait_frames(2)
	status_dummy.status.apply_chill()
	_check(status_dummy.status.speed_multiplier() < 1.0, "chill slows movement")
	status_dummy.status.apply_shock()
	var pre_shock_hp := status_dummy.health.current_health
	var shock_probe := HitInfo.create(10.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, player.global_position)
	status_dummy.take_hit(shock_probe)
	_check(absf(pre_shock_hp - status_dummy.health.current_health - 12.0) < 0.01, "shock amplifies damage taken (+20%)")

	# --- storm step ---
	lab.kill_all_enemies()
	await _wait_frames(20)
	player.reset_cooldowns()
	var dash_victim := MeleeRusher.new()
	lab.enemies_root.add_child(dash_victim)
	dash_victim.player = player
	dash_victim.global_position = player.global_position + player.facing() * 3.0
	await _wait_frames(2)
	var dash_hp := dash_victim.health.current_health
	var dash_from := player.global_position
	# Priority 1: held movement input steers the dash (camera looks -Z,
	# holding BACK must dash +Z).
	Input.action_press(&"move_back")
	var stepped := player.try_storm_step()
	Input.action_release(&"move_back")
	_check(stepped, "storm step starts")
	await _wait_frames(20)
	_check(player.state == Player.State.MOVE, "storm step recovers to MOVE")
	_check(player.global_position.z > dash_from.z + 3.0, "held movement input steers the dash")
	_check(not player.try_storm_step(), "storm step respects cooldown")
	_check(player.collision_mask == 0b101, "storm step restores collision mask")

	# Priority 3: no input, no target -> camera-directed dash zaps the path.
	player.reset_cooldowns()
	player.global_position = dash_from
	player.velocity = Vector3.ZERO
	await _wait_frames(2)
	_check(player.try_storm_step(), "camera dash starts")
	await _wait_frames(20)
	_check(player.global_position.z < dash_from.z - 3.0, "no input: dash follows the camera")
	_check(dash_victim.health.current_health < dash_hp, "storm step zaps enemies on the path")
	_check(dash_victim.status.has_shock(), "storm step applies Shock")

	# Priority 2: marked target in view -> gap-closer lands in melee range.
	lab.kill_all_enemies()
	await _wait_frames(20)
	player.global_position = Vector3(0, 0.2, 6)
	player.velocity = Vector3.ZERO
	var gap_target := Brute.new()
	lab.enemies_root.add_child(gap_target)
	gap_target.player = player
	gap_target.global_position = player.global_position + Vector3(0.5, 0, -5.5)
	await _wait_frames(2)
	lab.targeting.cycle_target()
	_check(lab.targeting.current == gap_target, "gap-close test: target marked")
	player.reset_cooldowns()
	_check(player.try_storm_step(), "gap-close dash starts")
	await _wait_frames(20)
	var gap := player.global_position.distance_to(gap_target.global_position)
	_check(gap > 0.6 and gap < 3.0, "gap-closer lands in melee range (%.2fm)" % gap)

	# --- chain spark ---
	lab.kill_all_enemies()
	await _wait_frames(20)
	player.reset_cooldowns()
	_check(not player.try_chain_spark(), "chain spark refused without any target")
	var chain_targets: Array[EnemyBase] = []
	for i in 3:
		var e := MeleeRusher.new()
		lab.enemies_root.add_child(e)
		e.player = player
		e.global_position = player.global_position + player.facing() * (4.0 + i * 3.0)
		chain_targets.append(e)
	await _wait_frames(2)
	player.reset_cooldowns()
	_check(player.try_chain_spark(), "chain spark casts with targets ahead")
	await _wait_frames(2)
	var chained := 0
	for e in chain_targets:
		if is_instance_valid(e) and e.health.current_health < e.health.max_health:
			chained += 1
	_check(chained == 3, "chain spark jumps to 3 enemies (hit %d)" % chained)
	_check(chain_targets[0].status.has_shock(), "chain spark applies Shock")

	# --- fracture rune ---
	lab.kill_all_enemies()
	await _wait_frames(20)
	player.reset_cooldowns()
	var rune_victim := MeleeRusher.new()
	lab.enemies_root.add_child(rune_victim)
	rune_victim.player = player
	rune_victim.global_position = player.global_position + player.facing() * 5.0
	await _wait_frames(2)
	var rune_hp := rune_victim.health.current_health
	_check(player.try_fracture_rune(), "fracture rune places")
	await _wait_frames(30)
	_check(rune_victim.health.current_health == rune_hp, "fracture rune has not detonated during arming")
	await _wait_frames(60)
	var rune_hit := not is_instance_valid(rune_victim) or rune_victim.health.current_health < rune_hp
	_check(rune_hit, "fracture rune detonates and damages")
	if is_instance_valid(rune_victim) and not rune_victim.health.is_dead:
		_check(rune_victim.status.has_chill(), "fracture rune applies Chill")

	# --- brute: stagger resistance ---
	lab.kill_all_enemies()
	await _wait_frames(20)
	var brute := Brute.new()
	lab.enemies_root.add_child(brute)
	brute.player = player
	brute.global_position = player.global_position + Vector3(8, 0.2, 0)
	await _wait_frames(10)
	var medium_hit := HitInfo.create(5.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.MEDIUM, player.global_position)
	brute.take_hit(medium_hit)
	_check(brute.ai_state != EnemyBase.AIState.STAGGER, "brute shrugs off MEDIUM stagger")
	var heavy_hit := HitInfo.create(5.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.HEAVY, player.global_position)
	brute.take_hit(heavy_hit)
	_check(brute.ai_state == EnemyBase.AIState.STAGGER, "HEAVY hits stagger the brute")

	# --- assassin: engages into circling behavior ---
	var assassin := Assassin.new()
	lab.enemies_root.add_child(assassin)
	assassin.player = player
	assassin.global_position = player.global_position + Vector3(0, 0.2, -8)
	await _wait_frames(120)
	var engaged := assassin.ai_state in [EnemyBase.AIState.CIRCLE, EnemyBase.AIState.ATTACK,
		EnemyBase.AIState.WINDUP, EnemyBase.AIState.RETREAT]
	_check(engaged, "assassin engages (circle/dash/stab loop)")

	# --- elite modifier ---
	lab.kill_all_enemies()
	await _wait_frames(20)
	var elite := lab.spawn_elite(EliteModifier.Kind.EMBERBOUND, player.global_position + Vector3(0, 0.2, -10))
	await _wait_frames(5)
	_check(elite.is_elite, "elite flag set")
	_check(elite.display_name == "Emberbound Cinder Marauder", "elite name carries its modifier (%s)" % elite.display_name)
	_check(absf(elite.health.max_health - 165.0) < 0.01, "elite health tripled")
	var patch_found := false
	for i in 240:
		await get_tree().physics_frame
		for child in get_tree().current_scene.get_children():
			if child is FirePatch:
				patch_found = true
				break
		if patch_found:
			break
	_check(patch_found, "emberbound elite drops fire patches while moving")

	# =========================== M03: LOOT & BUILDS ===========================
	lab.kill_all_enemies()
	await _wait_frames(20)
	# Recenter: earlier movement tests drifted the player toward arena walls;
	# projectile tests need a clear line of fire.
	player.global_position = Vector3(0, 0.2, 6)
	player.velocity = Vector3.ZERO
	await _wait_frames(2)

	# --- generator invariants ---
	var leg := ItemGenerator.generate_legendary()
	_check(leg.rarity == ItemData.Rarity.LEGENDARY and leg.legendary_id != &"", "legendary rolls a power")
	_check(leg.affixes.size() == 2, "legendary rolls 2 affixes")
	var elite_ok := true
	for i in 20:
		var it := ItemGenerator.generate(2)
		if it.rarity < ItemData.Rarity.RARE:
			elite_ok = false
	_check(elite_ok, "elite drops are always rare or better")

	# --- equip stats: max hp + cooldown reduction ---
	var hp_item := ItemData.new()
	hp_item.slot = ItemData.Slot.ARMOR
	hp_item.rarity = ItemData.Rarity.MAGIC
	hp_item.display_name = "Test Cuirass"
	hp_item.affixes = [{"id": &"max_hp", "label": "+30 maximum health", "stat": &"max_hp", "value": 30.0}]
	player.equipment.add_item(hp_item)
	player.equipment.equip(hp_item)
	_check(absf(player.health.max_health - 130.0) < 0.01, "equipping +30 HP raises max health")

	var cd_item := ItemData.new()
	cd_item.slot = ItemData.Slot.RELIC
	cd_item.rarity = ItemData.Rarity.MAGIC
	cd_item.display_name = "Test Sigil"
	cd_item.affixes = [{"id": &"cooldown_pct", "label": "20% cooldown reduction", "stat": &"cooldown_pct", "value": 20.0}]
	player.equipment.add_item(cd_item)
	player.equipment.equip(cd_item)
	player.reset_cooldowns()
	player.try_ember()
	var expected_cd: float = player.ember.cooldown * 0.8
	_check(absf(float(player._cooldowns[&"ember"]) - expected_cd) < 0.01, "cooldown reduction applies")
	await _wait_frames(20)

	# --- equip swap ---
	var weapon_a := ItemData.new()
	weapon_a.slot = ItemData.Slot.WEAPON
	weapon_a.display_name = "Blade A"
	var weapon_b := ItemData.new()
	weapon_b.slot = ItemData.Slot.WEAPON
	weapon_b.display_name = "Blade B"
	player.equipment.add_item(weapon_a)
	player.equipment.add_item(weapon_b)
	player.equipment.equip(weapon_a)
	player.equipment.equip(weapon_b)
	_check(player.equipment.equipped[ItemData.Slot.WEAPON] == weapon_b
		and player.equipment.inventory.has(weapon_a), "equip swaps the previous item back")

	# --- drop pickup ---
	var inv_before := player.equipment.inventory.size()
	lab.spawn_item_drop(ItemGenerator.generate(0), player.global_position + Vector3(0.5, 0, 0))
	await _wait_frames(30)
	_check(player.equipment.inventory.size() == inv_before + 1, "walking over a drop picks it up")

	# --- ember pierce affix ---
	var pierce_item := ItemData.new()
	pierce_item.slot = ItemData.Slot.WEAPON
	pierce_item.display_name = "Piercer"
	pierce_item.affixes = [{"id": &"ember_pierce", "label": "pierce", "stat": &"ember_pierce", "value": 1.0}]
	player.equipment.add_item(pierce_item)
	player.equipment.equip(pierce_item)
	var front := MeleeRusher.new()
	var back := MeleeRusher.new()
	for pair in [[front, 4.0], [back, 7.0]]:
		var e: EnemyBase = pair[0]
		lab.enemies_root.add_child(e)
		e.player = player
		e.global_position = player.global_position + player.facing() * (pair[1] as float)
	await _wait_frames(2)
	player.reset_cooldowns()
	player.try_ember()
	await _wait_frames(40)
	var front_hit := not is_instance_valid(front) or front.health.current_health < front.health.max_health
	var back_hit := not is_instance_valid(back) or back.health.current_health < back.health.max_health
	_check(front_hit and back_hit, "pierce affix: one lance hits both aligned enemies")
	player.equipment.equip(weapon_b)  # unequip piercer

	# --- Cindermaw ---
	lab.kill_all_enemies()
	await _wait_frames(20)
	var cindermaw := ItemData.new()
	cindermaw.slot = ItemData.Slot.WEAPON
	cindermaw.rarity = ItemData.Rarity.LEGENDARY
	cindermaw.display_name = "Cindermaw"
	cindermaw.legendary_id = &"cindermaw"
	player.equipment.add_item(cindermaw)
	player.equipment.equip(cindermaw)
	var burn_target := Brute.new()
	var bystander := Brute.new()
	for pair in [[burn_target, 5.0, 0.0], [bystander, 5.0, 1.8]]:
		var e: EnemyBase = pair[0]
		lab.enemies_root.add_child(e)
		e.player = player
		e.global_position = player.global_position + player.facing() * (pair[1] as float) \
			+ Vector3(pair[2] as float, 0, 0)
	await _wait_frames(2)
	burn_target.status.apply_burn()
	var bystander_hp := bystander.health.current_health
	player.reset_cooldowns()
	player.try_ember()
	await _wait_frames(40)
	_check(bystander.health.current_health < bystander_hp, "Cindermaw: burning target erupts onto neighbor")

	# --- Conductor's Oath ---
	lab.kill_all_enemies()
	await _wait_frames(20)
	var oath := ItemData.new()
	oath.slot = ItemData.Slot.RELIC
	oath.rarity = ItemData.Rarity.LEGENDARY
	oath.display_name = "Conductor's Oath"
	oath.legendary_id = &"conductors_oath"
	player.equipment.add_item(oath)
	player.equipment.equip(oath)
	var cond_a := Brute.new()
	var cond_b := Brute.new()
	for pair in [[cond_a, 4.0, 0.0], [cond_b, 4.0, 3.0]]:
		var e: EnemyBase = pair[0]
		lab.enemies_root.add_child(e)
		e.player = player
		e.global_position = player.global_position + player.facing() * (pair[1] as float) \
			+ Vector3(pair[2] as float, 0, 0)
	await _wait_frames(2)
	player.reset_cooldowns()
	_check(player.try_chain_spark(), "chain spark casts for conductor test")
	await _wait_frames(3)
	_check(cond_a.status.is_conductor() and cond_b.status.is_conductor(), "chain spark marks Conductors")
	var b_hp_before_arc := cond_b.health.current_health
	var zap := HitInfo.create(5.0, HitInfo.DamageType.LIGHTNING, HitInfo.Weight.LIGHT, player.global_position)
	cond_a.take_hit(zap)
	await _wait_frames(2)
	_check(cond_b.health.current_health < b_hp_before_arc, "lightning on a Conductor arcs to other Conductors")

	# --- Glacier Heart ---
	lab.kill_all_enemies()
	await _wait_frames(20)
	var glacier := ItemData.new()
	glacier.slot = ItemData.Slot.ARMOR
	glacier.rarity = ItemData.Rarity.LEGENDARY
	glacier.display_name = "Glacier Heart"
	glacier.legendary_id = &"glacier_heart"
	player.equipment.add_item(glacier)
	player.equipment.equip(glacier)
	var frost_victim := Brute.new()
	lab.enemies_root.add_child(frost_victim)
	frost_victim.player = player
	frost_victim.global_position = player.global_position + Vector3(2, 0.2, 0)
	await _wait_frames(2)
	player.gain_resonance(100.0)
	player.reset_cooldowns()
	player.try_earthbreaker()
	await _wait_frames(80)
	var field_found := false
	for child in get_tree().current_scene.get_children():
		if child is FrostField:
			field_found = true
	_check(field_found, "Glacier Heart leaves a frost field")
	_check(is_instance_valid(frost_victim) and frost_victim.status.has_chill(), "frost field chills enemies inside")

	# --- elite always drops loot ---
	lab.kill_all_enemies()
	await _wait_frames(20)
	var loot_elite := lab.spawn_elite(EliteModifier.Kind.STORMTOUCHED, player.global_position + Vector3(0, 0.2, -6))
	await _wait_frames(3)
	loot_elite.take_hit(HitInfo.create(99999.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, player.global_position))
	await _wait_frames(5)
	var drop_found: ItemDrop = null
	for child in lab.world.get_children():
		if child is ItemDrop:
			drop_found = child
	_check(drop_found != null, "elite death drops an item")
	if drop_found != null:
		_check(drop_found.item.rarity >= ItemData.Rarity.RARE, "elite drop is rare or better")
		drop_found.free()

	# --- inventory UI toggling ---
	lab.inventory_ui.toggle()
	_check(lab.inventory_ui.visible and player.input_locked, "inventory opens and locks input")
	lab.inventory_ui.toggle()
	_check(not lab.inventory_ui.visible and not player.input_locked, "inventory closes and unlocks input")

	# Cleanup: fresh equipment for the remaining M01/M02 sections.
	for slot: ItemData.Slot in [ItemData.Slot.WEAPON, ItemData.Slot.ARMOR, ItemData.Slot.RELIC]:
		player.equipment.unequip(slot)
	player.equipment.inventory.clear()
	player.equipment.changed.emit()

	# --- enemy AI: rusher chase ---
	lab.kill_all_enemies()
	await _wait_frames(20)
	var chaser := MeleeRusher.new()
	lab.enemies_root.add_child(chaser)
	chaser.player = player
	chaser.global_position = player.global_position + Vector3(10, 0.2, 0)
	await _wait_frames(5)
	var chase_dist := chaser.distance_to_player()
	await _wait_frames(60)
	_check(chaser.distance_to_player() < chase_dist - 2.0, "rusher chases player")

	# --- enemy AI: caster fires bolt ---
	var caster := RangedCaster.new()
	lab.enemies_root.add_child(caster)
	caster.player = player
	caster.global_position = player.global_position + Vector3(0, 0.2, -9)
	var bolt_found := false
	for i in 240:
		await get_tree().physics_frame
		for child in get_tree().current_scene.get_children():
			if child is EnemyBolt:
				bolt_found = true
				break
		if bolt_found:
			break
	_check(bolt_found, "caster fires a bolt")

	# --- player damage + god mode ---
	var hp_before := player.health.current_health
	var incoming := HitInfo.create(10.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, player.global_position + Vector3(1, 0, 0))
	player.take_hit(incoming)
	_check(player.health.current_health < hp_before, "player takes damage")
	player.god_mode = true
	var hp_god := player.health.current_health
	player.take_hit(HitInfo.create(10.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, Vector3.ZERO))
	_check(player.health.current_health == hp_god, "god mode blocks damage")
	player.god_mode = false

	# --- enemy death signal / stagger ---
	var victim := MeleeRusher.new()
	lab.enemies_root.add_child(victim)
	victim.player = player
	victim.global_position = player.global_position + Vector3(0, 0.2, 3)
	await _wait_frames(2)
	var died_flag: Array[bool] = [false]
	victim.enemy_died.connect(func(_e: EnemyBase) -> void: died_flag[0] = true)
	victim.take_hit(HitInfo.create(9999.0, HitInfo.DamageType.FIRE, HitInfo.Weight.HEAVY, player.global_position))
	await _wait_frames(5)
	_check(died_flag[0], "enemy death signal fires")

	# --- style switching ---
	lab.cycle_style()
	await _wait_frames(3)
	lab.cycle_style()
	await _wait_frames(3)
	lab.cycle_style()
	await _wait_frames(3)
	_check(lab.style_manager.style == StyleManager.Style.HYBRID, "style cycle returns to hybrid")

	# --- reset ---
	lab.reset_lab()
	await _wait_frames(10)
	_check(lab.enemy_count() == 3, "reset_lab respawns initial wave")
	_check(player.health.current_health == player.health.max_health, "reset_lab heals player")

	# ========================= M04: WORLD & PERSISTENCE =======================

	# --- ItemData serialization roundtrip ---
	var original := ItemGenerator.generate_legendary()
	var restored := ItemData.from_dict(original.to_dict())
	var roundtrip_ok := restored.display_name == original.display_name \
		and restored.slot == original.slot and restored.rarity == original.rarity \
		and restored.legendary_id == original.legendary_id \
		and restored.affixes.size() == original.affixes.size()
	if roundtrip_ok and not original.affixes.is_empty():
		roundtrip_ok = restored.affixes[0]["stat"] == original.affixes[0]["stat"] \
			and absf(float(restored.affixes[0]["value"]) - float(original.affixes[0]["value"])) < 0.001
	_check(roundtrip_ok, "ItemData serialization roundtrip")

	# --- save/load roundtrip ---
	var marker := ItemData.new()
	marker.slot = ItemData.Slot.RELIC
	marker.display_name = "Persistence Marker"
	player.equipment.add_item(marker)
	var keepsake := ItemData.new()
	keepsake.slot = ItemData.Slot.WEAPON
	keepsake.display_name = "Saved Blade"
	player.equipment.add_item(keepsake)
	player.equipment.equip(keepsake)
	SaveGame.save_now()
	player.equipment.inventory.clear()
	player.equipment.equipped.clear()
	player.equipment._recompute()
	SaveGame.reload_from_disk()
	SaveGame.restore_player(player)
	var restored_names: Array[String] = []
	for it in player.equipment.inventory:
		restored_names.append(it.display_name)
	var equipped_weapon: ItemData = player.equipment.equipped.get(ItemData.Slot.WEAPON)
	_check(restored_names.has("Persistence Marker"), "save restores inventory")
	_check(equipped_weapon != null and equipped_weapon.display_name == "Saved Blade", "save restores equipped gear")

	# --- corrupt save handled ---
	var f := FileAccess.open(SaveGame.save_path, FileAccess.WRITE)
	f.store_string("{{{ not json")
	f.close()
	SaveGame.reload_from_disk()
	_check(not SaveGame.has_save(), "corrupt save falls back to fresh start")
	SaveGame.wipe()

	# --- travel: lab -> hub, gear survives via save ---
	player.equipment.add_item(marker)
	lab.travel_to("res://scenes/hub.tscn")
	for i in 60:
		await get_tree().process_frame
		if get_tree().current_scene is HubZone:
			break
	var hub := get_tree().current_scene as HubZone
	_check(hub != null, "portal travel loads the hub")
	if hub == null:
		print("== %d failures ==" % _failures.size())
		get_tree().quit(1)
		return
	await _wait_frames(5)
	_check(hub.player != null and hub.enemy_count() == 0, "hub is safe (no enemies)")
	var hub_portals := 0
	for child in hub.world.get_children():
		if child is Portal:
			hub_portals += 1
	_check(hub_portals == 2, "hub has both portals")
	var carried := false
	for it in hub.player.equipment.inventory:
		if it.display_name == "Persistence Marker":
			carried = true
	_check(carried, "gear persists across zone travel")

	# --- highlands ---
	hub.travel_to("res://scenes/ashen_highlands.tscn")
	for i in 60:
		await get_tree().process_frame
		if get_tree().current_scene is AshenHighlands:
			break
	var highlands := get_tree().current_scene as AshenHighlands
	_check(highlands != null, "highlands zone loads")
	if highlands == null:
		print("== %d failures ==" % _failures.size())
		get_tree().quit(1)
		return
	await _wait_frames(5)
	_check(highlands.enemy_count() == 0, "highlands spawners idle before approach")

	# First camp triggers once.
	highlands.player.global_position = Vector3(0, 0.2, 16)
	await _wait_frames(10)
	var camp_count := highlands.enemy_count()
	_check(camp_count >= 2, "camp spawner triggers on approach")

	# Chest opens and pops loot.
	var chest: TreasureChest = null
	for child in highlands.world.get_children():
		if child is TreasureChest:
			chest = child
			break
	var inv_before_chest := highlands.player.equipment.inventory.size()
	highlands.player.global_position = chest.global_position + Vector3(1.0, 0.2, 0)
	await _wait_frames(30)
	var drops_out := 0
	for child in highlands.world.get_children():
		if child is ItemDrop:
			drops_out += 1
	var chest_loot := drops_out + (highlands.player.equipment.inventory.size() - inv_before_chest)
	_check(chest.opened, "chest opens on proximity")
	_check(chest_loot >= 2, "chest pops at least 2 items")

	# Boss: trigger, enrage, kill, unlock.
	highlands.player.god_mode = true
	highlands.player.global_position = Vector3(0, 0.2, -19)
	await _wait_frames(10)
	_check(highlands.boss != null, "boss fight starts at the arena")
	_check(highlands.boss_portal.locked, "north portal sealed while boss lives")
	var boss := highlands.boss
	boss.take_hit(HitInfo.create(320.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, Vector3.ZERO))
	await _wait_frames(3)
	_check(boss.enraged, "colossus enrages below 50%")
	# Regression: the hit squash must return to boss scale, not man-size.
	await _wait_frames(20)
	_check(boss.visual.scale.x > 1.6, "boss keeps his size after being hit")
	boss.take_hit(HitInfo.create(99999.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, Vector3.ZERO))
	await _wait_frames(5)
	_check(not highlands.boss_portal.locked, "boss death unseals the portal")
	var legendary_drop_found := false
	for child in highlands.world.get_children():
		if child is ItemDrop and (child as ItemDrop).item.rarity == ItemData.Rarity.LEGENDARY:
			legendary_drop_found = true
	_check(legendary_drop_found, "boss drops a guaranteed legendary")

	# ========================== M05: SHATTERED SPIRE ==========================

	# --- flags set + persist (colossus kill above set the flag) ---
	_check(SaveGame.has_flag(&"colossus_defeated"), "colossus kill sets world flag")
	SaveGame.reload_from_disk()
	_check(SaveGame.has_flag(&"colossus_defeated"), "world flags persist through reload")
	_check(not highlands.spire_portal.locked, "spire portal unseals with the colossus")

	# --- spire zone boots ---
	highlands.travel_to("res://scenes/shattered_spire.tscn")
	for i in 60:
		await get_tree().process_frame
		if get_tree().current_scene is SpireZone:
			break
	var spire := get_tree().current_scene as SpireZone
	_check(spire != null, "shattered spire loads")
	if spire == null:
		print("== %d failures ==" % _failures.size())
		get_tree().quit(1)
		return
	await _wait_frames(5)
	_check(spire.enemy_count() == 0, "spire camps idle before approach")
	_check(spire.boss_portal.locked, "spire exit sealed before the boss")

	# --- hollow warden: frontal block ---
	var warden := HollowWarden.new()
	spire.enemies_root.add_child(warden)
	warden.player = spire.player
	warden.global_position = spire.player.global_position + Vector3(0, 0.2, -4)
	await _wait_frames(2)
	# Face the warden toward the player (south of it, +Z): facing dir (0,0,1)
	# means rotation.y = atan2(-0, -1) = PI.
	warden.visual.rotation.y = PI
	var warden_front := HitInfo.create(10.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, spire.player.global_position)
	var hp0 := warden.health.current_health
	warden.take_hit(warden_front)
	var front_loss := hp0 - warden.health.current_health
	var warden_back := HitInfo.create(10.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT,
		warden.global_position + Vector3(0, 0, -6))  # behind it
	var hp1 := warden.health.current_health
	warden.take_hit(warden_back)
	var back_loss := hp1 - warden.health.current_health
	_check(absf(front_loss - 5.0) < 0.01, "warden halves frontal damage (lost %.1f)" % front_loss)
	_check(absf(back_loss - 10.0) < 0.01, "warden takes full damage from behind")
	warden.take_hit(HitInfo.create(9999.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, warden.global_position + Vector3(0, 0, -6)))
	await _wait_frames(10)

	# --- shadow rune detonates on the player ---
	spire.player.god_mode = false
	spire.player.health.heal_full()
	var rune := ShadowRune.new()
	rune.position = spire.player.global_position
	get_tree().current_scene.add_child(rune)
	var hp_before_rune := spire.player.health.current_health
	await _wait_frames(90)
	_check(spire.player.health.current_health < hp_before_rune, "shadow rune detonates and damages the player")
	spire.player.god_mode = true
	spire.player.health.heal_full()

	# --- boss fight ---
	spire.player.global_position = Vector3(0, 0.2, -20)
	await _wait_frames(10)
	_check(spire.boss != null, "vessel spawns at the arena")
	var vessel := spire.boss
	if vessel != null:
		# Phase 1 adds.
		var before_adds := spire.enemy_count()
		vessel._summon_timer = 0.0
		await _wait_frames(10)
		_check(spire.enemy_count() >= before_adds + 2, "vessel summons adds in phase 1")
		# Phase transition at 50%.
		vessel.take_hit(HitInfo.create(760.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, spire.player.global_position))
		await _wait_frames(3)
		_check(vessel.health.invulnerable, "shatter transition grants brief invulnerability")
		await _wait_frames(80)
		_check(vessel.phase == 2, "vessel enters phase 2 below 50%")
		# Blink.
		var pos_before_blink := vessel.global_position
		vessel._blink_timer = 0.0
		await _wait_frames(5)
		_check(vessel.global_position.distance_to(pos_before_blink) > 2.0, "vessel blinks between anchors")
		# Kill: rewards + flag + portal.
		vessel.take_hit(HitInfo.create(99999.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, spire.player.global_position))
		await _wait_frames(5)
		_check(SaveGame.has_flag(&"spire_cleansed"), "vessel death sets spire flag")
		_check(not spire.boss_portal.locked, "vessel death unseals the exit")
		var legendaries := 0
		var total_drops := 0
		for child in spire.world.get_children():
			if child is ItemDrop:
				total_drops += 1
				if (child as ItemDrop).item.rarity == ItemData.Rarity.LEGENDARY:
					legendaries += 1
		_check(legendaries >= 1 and total_drops >= 3, "vessel drops legendary + rares (%d drops)" % total_drops)

	# --- hub shows the spire shortcut once the colossus flag is set ---
	spire.travel_to("res://scenes/hub.tscn")
	for i in 60:
		await get_tree().process_frame
		if get_tree().current_scene is HubZone:
			break
	var hub2 := get_tree().current_scene as HubZone
	if hub2 != null:
		await _wait_frames(5)
		var portal_count := 0
		for child in hub2.world.get_children():
			if child is Portal:
				portal_count += 1
		_check(portal_count == 3, "hub gains the spire shortcut portal")

	SaveGame.wipe()
	print("== %d failures ==" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)

