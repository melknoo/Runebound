extends Node
## Headless smoke test: boots the Combat Lab and exercises every M01 system.
## Run: godot --headless --path . res://tests/smoke_test.tscn
## (a scene, not a --script MainLoop: autoloads must be active)

## A hung run must fail instead of lingering: stale headless runs once kept
## burning CPU for a day, which also slowed the iGPU (shared power budget).
const WATCHDOG_SEC := 300.0

var _failures: Array[String] = []
var lab: CombatLab


## M07b: a scripted input source (what a network peer will be) for the seam test.
class ScriptedInput extends InputSource:
	var dir := Vector3.ZERO
	var queue: Array[StringName] = []

	func poll(intent: PlayerIntent, _player: Player) -> void:
		intent.move_dir = dir
		intent.pressed.append_array(queue)
		queue.clear()


func _ready() -> void:
	get_tree().create_timer(WATCHDOG_SEC, true, false, true).timeout.connect(_on_watchdog)
	_run.call_deferred()


func _on_watchdog() -> void:
	printerr("  FAIL: smoke watchdog - run exceeded %d s" % int(WATCHDOG_SEC))
	get_tree().quit(2)


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
	# M06 C3: training grounds dressed from the Runehold kit, layout untouched.
	var lab_bodies := lab.world.find_children("*", "StaticBody3D", true, false)
	_check(lab.look != null and lab_bodies.size() == 14,
		"training grounds: Runehold look, dressing adds no collision (%d bodies, layout had 14)" % lab_bodies.size())

	# --- M08 terrain spike: heightmap terrain + ground seam (built 1 km east of the lab) ---
	var terrain := Terrain.load_from("res://assets/world/highlands", ArtKit.material(&"highlands_ground"))
	lab.world.add_child(terrain)
	terrain.position = Vector3(1000, 0, 0)
	lab.terrain = terrain  # the lab borrows it: ground_y / ground_point read the heightmap
	_check(terrain.res == 385, "terrain: 385 x 385 samples decoded")
	_check(terrain.chunk_count() == 144, "terrain: 144 chunks x 3 LODs built in %d ms" % terrain.build_ms)
	_check(terrain.build_ms < 2500, "terrain: build under 2.5 s (%d ms)" % terrain.build_ms)
	await _wait_frames(3)
	var layout := ZoneLayout.load_from("res://assets/world/highlands/layout.json")
	_check(layout.pois.size() >= 26, "layout: %d POIs loaded" % layout.pois.size())
	_check(layout.find("arena").get("type", "") == "arena" and layout.level_at(0.0, -150.0) == 3
		and layout.level_at(0.0, 150.0) == 1, "layout: POI lookup and level bands (north 3, south 1)")
	# Bake orientation: the SE test bump reads at its spot; north is higher than south.
	var bump: Dictionary = layout.raw["test_bump"]
	var bx := 1000.0 + float(bump["pos"][0])
	var bz := float(bump["pos"][1])
	_check(terrain.height_at(bx, bz) - terrain.height_at(bx, bz + 20.0) > 3.0,
		"terrain: test bump rises where the bake put it (row 0 = north, x east)")
	_check(terrain.height_at(1000.0, -150.0) > terrain.height_at(1000.0, 150.0) + 5.0, "terrain: north plateau above the south slopes")
	var space := lab.world.get_world_3d().direct_space_state
	var trng := RandomNumberGenerator.new()
	trng.seed = 42
	var worst := 0.0
	for i in 50:
		var tx := 1000.0 + trng.randf_range(-180.0, 180.0)
		var tz := trng.randf_range(-180.0, 180.0)
		var q := PhysicsRayQueryParameters3D.create(Vector3(tx, 150.0, tz), Vector3(tx, -10.0, tz), 1)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			worst = INF
			break
		worst = maxf(worst, absf((hit["position"] as Vector3).y - terrain.height_at(tx, tz)))
	_check(worst <= 0.05, "terrain: HeightMapShape3D matches height_at at 50 random points (worst %.3f m)" % worst)
	var spawn_poi := layout.poi_pos("spawn")
	_check(terrain.normal_at(1000.0 + spawn_poi.x, spawn_poi.z).y > 0.999, "terrain: the spawn pad is flat")
	_check(absf(terrain.height_at(1000.0 + spawn_poi.x, spawn_poi.z) - spawn_poi.y) < 0.05, "layout: baked POI height matches the terrain")
	# Ground seam: flat zones stay at 0; ground_point raycasts onto whatever is below.
	var gp := lab.ground_point(Vector3(2.0, 1.5, 2.0))
	_check(absf(gp.y) < 0.05, "ground seam: ground_point lands on the lab floor (y %.3f)" % gp.y)
	var slope_pt := Vector3(1000.0 + 40.0, 0.0, 160.0)  # on the 25-degree test ramp
	slope_pt.y = terrain.height_at(slope_pt.x, slope_pt.z) + 0.5  # callers pass feet positions
	var gp2 := lab.ground_point(slope_pt, 0.2)
	_check(absf(gp2.y - 0.2 - terrain.height_at(slope_pt.x, slope_pt.z)) < 0.05, "ground seam: ground_point finds the terrain 1 km away")
	var slope_disc := VFX.telegraph_disc(lab.world, slope_pt, 2.0, 0.5)
	_check(absf(slope_disc.global_position.y - terrain.height_at(slope_pt.x, slope_pt.z)) < 0.12
		and slope_disc.global_transform.basis.y.dot(terrain.normal_at(slope_pt.x, slope_pt.z)) > 0.99,
		"ground seam: a telegraph disc snaps onto the slope and tilts with it")
	slope_disc.queue_free()
	var flat_disc := VFX.telegraph_disc(lab.world, Vector3(2.0, 0.0, -2.0), 1.0, 0.5)
	_check(absf(flat_disc.global_position.y - 0.05) < 0.02, "ground seam: telegraph discs on the flat floor still sit at 0.05")
	flat_disc.queue_free()
	# The player walks up the test ramp (grade 0.47 = 25 deg) and stays on the floor.
	var walker := lab.player
	var walk_back := walker.global_position
	var ramp_start := Vector3(1040.0, 0.0, 174.0)
	walker.global_position = lab.ground_point(ramp_start, 0.3)
	walker.velocity = Vector3.ZERO
	await _wait_frames(5)
	var ramp_scripted := ScriptedInput.new()
	var ramp_local := walker.input_source
	walker.input_source = ramp_scripted
	ramp_scripted.dir = Vector3(0, 0, -1)  # north, uphill
	var y0 := walker.global_position.y
	await _wait_frames(90)
	ramp_scripted.dir = Vector3.ZERO
	await _wait_frames(3)
	_check(walker.global_position.y - y0 > 1.5 and walker.is_on_floor(),
		"terrain: the player climbs the 25-degree ramp on foot (+%.2f m, on floor)" % (walker.global_position.y - y0))
	# A drop spawned from the slope lands on it, not at y 0.
	var slope_drop := lab.spawn_gold_drop(5, walker.global_position + Vector3(1.0, 0.0, 0.0))
	_check(absf(slope_drop.position.y - terrain.height_at(slope_drop.position.x, slope_drop.position.z)) < 0.1,
		"ground seam: gold drops land on the terrain")
	slope_drop.queue_free()
	walker.input_source = ramp_local
	walker.global_position = walk_back
	walker.velocity = Vector3.ZERO
	lab.terrain = null
	_check(lab.ground_y(Vector3(3, 0, 3)) == 0.0 and lab.ground_normal(Vector3(3, 0, 3)) == Vector3.UP, "ground seam: flat zone reports y 0, normal up")
	terrain.queue_free()
	await _wait_frames(3)

	# --- M06 rigs: animation follows gameplay timing, never the other way ---
	var p_anim := lab.player.animator
	_check(p_anim != null and p_anim.anim.has_animation(&"cleave_l") and p_anim.anim.has_animation(&"run"),
		"runebreaker rig loads with idle/run/cleave clips")
	if p_anim != null:
		var cleave_len := lab.player.cleave.startup + lab.player.cleave.active + lab.player.cleave.recovery
		_check(absf(p_anim.anim.get_animation(&"cleave_l").length - cleave_len) < 1.5 / 60.0,
			"cleave clip length = startup + active + recovery (%.3f s)" % cleave_len)
	var marauder: MeleeRusher = null
	for e in lab.enemies_root.get_children():
		if e is MeleeRusher:
			marauder = e
			break
	if marauder != null and marauder.animator != null:
		var m_anim := marauder.animator.anim
		var attack_len := MeleeRusher.WINDUP_TIME + MeleeRusher.ATTACK_TIME + MeleeRusher.RECOVER_TIME
		_check(absf(m_anim.get_animation(&"attack").length - attack_len) < 1.5 / 60.0,
			"marauder attack clip = windup + strike + recover (%.2f s)" % attack_len)
		_check(not marauder._flash_mats.has(marauder._axe_glow) and marauder._flash_mats.size() == 1,
			"telegraph axe material is never in the hit-flash list")
		marauder.apply_hitstop(0.2)
		var pos_before := m_anim.current_animation_position
		await _wait_frames(3)
		_check(is_equal_approx(m_anim.current_animation_position, pos_before), "rig freezes during hitstop")
		var body_mat: StandardMaterial3D = marauder._flash_mats[0]
		marauder._flash_white()
		await _wait_frames(8)
		_check(body_mat.emission_enabled and is_equal_approx(body_mat.emission_energy_multiplier, 0.0),
			"hit flash changes energy only (no shader-variant toggle)")
	else:
		_check(false, "marauder rig loads")

	# --- M06 B4: one threat language; bursts never compile process shaders ---
	var disc := VFX.telegraph_disc(lab, Vector3(0, 0, -30), 1.4, 0.3)
	var disc_mat := (disc.mesh as PlaneMesh).material as ShaderMaterial
	await _wait_frames(9)
	var fill: float = disc_mat.get_shader_parameter(&"progress")
	_check(disc_mat.shader == VFX.THREAT_SHADER and fill > 0.2 and fill < 0.9
		and disc_mat.render_priority == VFX.THREAT_PRIORITY,
		"enemy telegraph = threat shader with visible fill progress (%.2f), sorted on top" % fill)
	var fx := VFX.burst(lab, Vector3(0, 1, -30), {"amount": 4, "lifetime": 0.2})
	_check(fx is CPUParticles3D, "combat bursts are CPU particles by default")

	# --- M06 B2: every ability has a clip at gameplay timing; layered player ---
	if p_anim != null:
		var missing: Array[String] = []
		for clip: StringName in [&"cleave_r", &"dodge", &"ember", &"earthbreaker_rise", &"earthbreaker_impact",
				&"storm_step", &"chain_spark", &"fracture_rune", &"flinch"]:
			if not p_anim.anim.has_animation(clip):
				missing.append(String(clip))
		_check(missing.is_empty(), "runebreaker has a clip for every ability %s" % str(missing))
		var swing_len := lab.player.cleave.startup + lab.player.cleave.active + lab.player.cleave.recovery
		_check(missing.is_empty() and absf(p_anim.anim.get_animation(&"cleave_r").length - swing_len) < 1.5 / 60.0,
			"cleave_r clip length = cleave timing")
		var dodge_len := Player.DODGE_DURATION + Player.DODGE_RECOVERY
		_check(missing.is_empty() and absf(p_anim.anim.get_animation(&"dodge").length - dodge_len) < 1.5 / 60.0,
			"dodge clip = dash + recovery (%.2f s)" % dodge_len)
		_check(p_anim.tree != null, "player rig runs the layered animation tree")
		if p_anim.tree != null:
			p_anim._on_action(&"chain_spark")
			await _wait_frames(2)
			_check(bool(p_anim.tree.get(&"parameters/upper/active")) and p_anim._one_shot == &"",
				"chain spark plays on the upper-body layer, legs stay on locomotion")
			p_anim._on_action(&"cleave_l")
			await _wait_frames(1)
			var started := p_anim._one_shot == &"cleave_l"
			await _wait_frames(40)
			_check(started and p_anim._one_shot == &"", "full-body one-shot hands back to locomotion")
	if marauder != null and marauder.animator != null:
		_check(marauder.animator.anim.has_animation(&"stagger")
			and marauder.animator.profile["states"][EnemyBase.AIState.STAGGER] == &"stagger",
			"marauder staggers with its own clip")
	var weaver := RangedCaster.new()
	lab.enemies_root.add_child(weaver)
	weaver.global_position = Vector3(6, 0.2, -12)
	await _wait_frames(2)
	if weaver.animator != null:
		var w_anim := weaver.animator.anim
		_check(w_anim.has_animation(&"glide") and w_anim.has_animation(&"cast") and w_anim.has_animation(&"stagger"),
			"duskweaver rig loads with glide/cast/stagger")
		_check(w_anim.has_animation(&"charge")
			and absf(w_anim.get_animation(&"charge").length - RangedCaster.WINDUP_TIME) < 1.5 / 60.0,
			"duskweaver charge clip = WINDUP_TIME")
		_check(weaver._orb_mesh != null and weaver._orb_mesh.position.is_equal_approx(Vector3(0.42, 1.7, 0))
			and weaver._orb_mesh.get_parent() == weaver.visual and weaver._flash_mats.size() == 1,
			"duskweaver orb stays the bolt origin, outside the hit-flash list")
	else:
		_check(false, "duskweaver rig loads")
	weaver.queue_free()

	# --- M06 C1/C2/C4: every enemy type has its rig; clip timing follows gameplay ---
	var rig_specs := [
		["brute", ["idle", "run", "slam", "stagger"], "slam", Brute.WINDUP_TIME + Brute.RECOVER_TIME],
		["assassin", ["idle", "run", "strafe", "dash", "retreat", "stab", "stagger"], "", 0.0],
		["warden", ["idle", "run", "windup", "spin", "stagger"], "windup", HollowWarden.WINDUP_TIME],
		["colossus", ["idle", "run", "slam", "charge_windup", "charge", "stun", "roar", "stagger"], "charge_windup", 0.8],
		["vessel", ["idle", "run", "slam", "shatter", "p2_idle", "fan", "stagger"], "", 0.0],
	]
	for spec: Array in rig_specs:
		var foe := ZoneBase.make_enemy(spec[0])
		lab.enemies_root.add_child(foe)
		foe.global_position = Vector3(-10, 0.2, -20)
		await _wait_frames(1)
		var clips_ok := foe.animator != null
		if clips_ok:
			for clip: String in spec[1]:
				clips_ok = clips_ok and foe.animator.anim.has_animation(StringName(clip))
		var timing_ok := true
		if clips_ok and spec[2] != "":
			timing_ok = absf(foe.animator.anim.get_animation(StringName(spec[2])).length - float(spec[3])) < 1.5 / 60.0
		_check(clips_ok and timing_ok and foe._flash_mats.size() == 1,
			"%s rig: clips %s, %s timing matches gameplay, glow parts outside the hit flash" % [spec[0], str(spec[1]), spec[2]])
		foe.queue_free()
	await _wait_frames(1)
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
	var to_target := rusher.global_position - player.global_position
	var facing_dot := player.facing().dot(Vector3(to_target.x, 0, to_target.z).normalized())
	_check(facing_dot > 0.9, "melee faced the enemy")

	# --- tab targeting ---
	_check(lab.targeting.current == null, "no target before Tab is pressed")
	lab.targeting.cycle_target()
	_check(lab.targeting.current == rusher, "tab selects enemy near aim")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(lab.targeting._name_label.visible and lab.targeting._name_label.text.begins_with("Cinder Marauder"),
		"target name plate shows the enemy name")
	# --- M07b: one ability at the start, the rest are learned ---
	var cls := ClassData.load_by_id(&"runebreaker")
	_check(cls != null and cls.abilities.size() == 8 and cls.starting_abilities.size() == 1
		and cls.starting_abilities[0] == &"rune_cleave"
		and cls.trainer_abilities().size() == 5 and cls.trainer_abilities()[0].id == &"earthbreaker",
		"ClassData: Runebreaker has 8 abilities, starts with Rune Cleave, trains 5 (Earthbreaker first)")
	_check(player.class_data == cls and player.ability(&"ember_lance") == player.ember,
		"player carries its ClassData; typed ability fields are its abilities")
	var fresh_names := lab.hud.ability_names()
	_check(fresh_names.size() == 2 and fresh_names[0] == "Rune Cleave" and fresh_names[1] == "Dodge",
		"fresh character: HUD shows Rune Cleave and Dodge only (%s)" % [fresh_names])
	_check(player.knows(&"rune_cleave") and player.knows(&"dodge") and not player.knows(&"ember_lance")
		and not player.knows(&"earthbreaker") and not player.knows(&"runic_guard"),
		"knows(): start kit and dodge yes, trainer and talent abilities no")
	player.reset_cooldowns()
	player.resonance = 100.0
	_check(not player.try_ember() and not player.try_earthbreaker() and not player.try_storm_step()
		and not player.try_chain_spark() and not player.try_fracture_rune() and player.state == Player.State.MOVE,
		"unknown abilities refuse to cast")
	_check(not player._try_action(&"storm_step") and player._buffered_action == &"",
		"input dispatch ignores unknown abilities and never buffers them")
	_check(not player.learn_ability(&"nope") and not player.learn_ability(&"runic_guard") and not player.learn_ability(&"rune_cleave"),
		"learn_ability rejects unknown ids, talent abilities and known ones")
	_check(player.learn_ability(&"earthbreaker") and player.knows(&"earthbreaker") and not player.learn_ability(&"earthbreaker"),
		"learn_ability adds a trainer ability once")
	_check(lab.hud.ability_names().size() == 3 and lab.hud.ability_names().has("Earthbreaker"),
		"HUD slot appears once the ability is learned")
	# Trainer: offers, refusal reasons, a purchase.
	var offers := TrainerUI.offers(player)
	_check(offers.size() == 5 and offers[offers.size() - 1].id == &"earthbreaker" and offers[0].id == &"ember_lance",
		"trainer offers the 5 trainer abilities, known ones last")
	var ember_data := player.ability(&"ember_lance")
	_check(TrainerUI.deny_reason(player, ember_data) == "Requires level 3", "trainer refuses below the level requirement")
	var saved_level := player.progression.level
	player.progression.level = 3
	player.spend_gold(player.gold)  # earlier kills in this run may have paid some
	_check(TrainerUI.deny_reason(player, ember_data) == "Need 150 more gold" and not lab.trainer_ui.try_buy(ember_data),
		"trainer refuses without the gold")
	player.add_gold(150)
	_check(TrainerUI.deny_reason(player, ember_data) == "" and lab.trainer_ui.try_buy(ember_data)
		and player.gold == 0 and player.knows(&"ember_lance") and lab.hud.ability_names().size() == 4,
		"buying at the trainer spends the gold and teaches the ability")
	_check(TrainerUI.deny_reason(player, ember_data) == "Learned" and not lab.trainer_ui.try_buy(ember_data),
		"an ability is bought once")
	player.progression.level = saved_level
	# Debug fresh start (key 9) resets abilities and gold too.
	player.add_gold(70)
	lab.wipe_save()
	_check(player.known_abilities.size() == 1 and player.knows(&"rune_cleave") and not player.knows(&"ember_lance")
		and player.gold == 0 and lab.hud.ability_names().size() == 2,
		"debug fresh start returns to the one-ability kit with no gold")
	player.debug_learn_all()
	_check(lab.hud.ability_names().size() == 7, "debug_learn_all knows the whole trainer kit (7 slots)")
	player.resonance = 0.0
	player.resonance_changed.emit(0.0, player.max_resource())

	# --- M07b gold: kills pay it, it is picked up by walking over it ---
	var gold_rusher := MeleeRusher.new()
	lab.enemies_root.add_child(gold_rusher)
	gold_rusher.global_position = Vector3(-14, 0.2, -18)
	await _wait_frames(1)
	var gold_pay := gold_rusher.gold_reward()
	_check(gold_pay >= 8 and gold_pay <= 13, "a level-1 rusher pays 8-13 gold (%d)" % gold_pay)
	var count_gold := func() -> int:
		var n := 0
		for child in lab.world.get_children():
			if child is GoldDrop:
				n += 1
		return n
	var gold_drops_before: int = count_gold.call()  # earlier kills in this run left theirs
	gold_rusher.enemy_died.connect(lab._on_enemy_died)
	gold_rusher.take_hit(HitInfo.create(99999.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, gold_rusher.global_position))
	await _wait_frames(2)
	_check(count_gold.call() == gold_drops_before + 1, "a kill leaves one gold drop")
	for child in lab.world.get_children():
		if child is GoldDrop:
			child.free()
	var gold_before := player.gold
	var gold_drop := lab.spawn_gold_drop(37, player.global_position + player.facing() * 0.5)
	# pickups run in _process: wait for idle frames (several physics steps can pass in one slow frame)
	for i in 4:
		await get_tree().process_frame
	_check(player.gold == gold_before + 37 and not is_instance_valid(gold_drop), "gold is picked up by walking over it")
	_check(lab.hud.gold_text() == str(player.gold), "HUD shows the gold total")
	_check(not player.spend_gold(player.gold + 1) and player.spend_gold(37) and player.gold == gold_before,
		"spend_gold refuses an overdraft and pays otherwise")

	# --- M07b hero window (I / C / N tabs) + StatSheet ---
	lab.hero_ui.open_tab(HeroUI.Tab.CHARACTER)
	_check(lab.hero_ui.visible and lab.hero_ui.character_tab.visible and not lab.inventory_ui.visible and player.input_locked,
		"hero window opens on the character tab and locks input")
	lab.hero_ui.open_tab(HeroUI.Tab.TALENTS)
	_check(lab.talent_ui.visible and not lab.hero_ui.character_tab.visible, "N switches the hero window to the talent tab")
	lab.talent_ui.toggle()
	_check(not lab.hero_ui.visible and not lab.talent_ui.visible and not player.input_locked,
		"the showing tab's key closes the hero window")
	lab.inventory_ui.toggle()
	_check(lab.hero_ui.visible and lab.inventory_ui.visible and lab.hero_ui.current == HeroUI.Tab.INVENTORY,
		"I opens the hero window on the inventory tab")
	lab.hero_ui.close()
	var sheet_rows := StatSheet.ability_rows(player)
	_check(sheet_rows.size() == 6 and sheet_rows[0]["id"] == &"rune_cleave" and sheet_rows[0]["key"] == "LMB",
		"character sheet lists the 6 known abilities in class order with their keys")
	var d_pct := player.stat(&"damage_pct")
	var c_pct := player.stat(&"crit_pct")
	var manual_avg := 24.0 * (1.0 + d_pct / 100.0) * (1.0 + (0.08 + c_pct / 100.0) * 0.6)
	_check(absf(StatSheet.expected_damage(player, player.cleave) - manual_avg) < 0.001,
		"StatSheet's average Rune Cleave damage matches the hit formula (%.1f)" % manual_avg)
	var names_ok := true
	for def: Dictionary in AffixPool.DEFS:
		names_ok = names_ok and StatSheet.STAT_NAMES.has(def["stat"])
	_check(names_ok, "every affix stat has a display name")
	_check(lab.hud._stats_line(&"ember_lance", player.ember).begins_with("Damage"), "ability tooltip leads with the damage")

	# --- M07b input seam: Player only reads its intent; any source drives it ---
	_check(player.input_source is LocalInputSource, "the local player polls keyboard and mouse through LocalInputSource")
	var scripted := ScriptedInput.new()
	var local_source := player.input_source
	player.input_source = scripted
	var seam_start := player.global_position
	var seam_yaw: float = player._visual.rotation.y  # the melee-facing check below still needs it
	scripted.dir = Vector3(0, 0, 1)  # back towards the spawn: nothing stands there
	await _wait_frames(30)
	scripted.dir = Vector3.ZERO
	_check(player.global_position.z - seam_start.z > 1.0, "a scripted input source moves the player")
	await _wait_frames(12)
	player.reset_cooldowns()
	_check(player.try_dodge() and player.state == Player.State.DODGE, "dodge starts for the buffer check")
	await _wait_frames(10)
	scripted.queue.append(&"rune_cleave")
	await _wait_frames(2)
	_check(player._buffered_action == &"rune_cleave", "an action pressed mid-dodge is buffered through the seam")
	await _wait_frames(12)
	_check(player.state == Player.State.MELEE, "the buffered melee fires when the dodge ends")
	await _wait_frames(30)
	player.input_source = local_source
	player.global_position = seam_start
	player._visual.rotation.y = seam_yaw
	await _wait_frames(2)

	# --- M07b attacker identity on hits ---
	var atk_hit := player.roll_ability_hit(player.cleave)
	_check(atk_hit.attacker_id == player.get_instance_id() and atk_hit.attacker_player() == player,
		"player hits carry their attacker")
	_check(HitInfo.create(1.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, Vector3.ZERO).attacker() == null,
		"world hits have no attacker")

	# --- M07b player registry, retargeting, local-only presentation ---
	_check(lab.players.size() == 1 and lab.local_player == lab.player and player.is_local and player.peer_id == 1,
		"the zone registry holds the local hero")
	_check(lab.nearest_player(Vector3.ZERO) == player and lab.players_within(player.global_position, 1.0).size() == 1,
		"nearest_player / players_within find the local hero")
	var hunter := lab.spawn_by_id("rusher", player.global_position + player.facing() * 7.0)
	await _wait_frames(2)
	_check(hunter.player == player and hunter.auto_retarget, "a spawned enemy hunts the nearest hero and may retarget")
	var buddy := Player.new()
	buddy.is_local = false
	buddy.input_source = InputSource.new()  # inert: a remote hero gets its intent elsewhere
	lab.add_player(buddy)
	buddy.global_position = hunter.global_position + Vector3(1.2, 0, 0)
	await _wait_frames(2)
	_check(lab.players.size() == 2 and not buddy.is_local and lab.nearest_player(hunter.global_position) == buddy,
		"a second hero registers; nearest_player picks it near the enemy")
	await _wait_frames(25)  # > RETARGET_INTERVAL
	_check(hunter.player == buddy, "the enemy retargets to the closer hero")
	var rig := lab.camera_rig
	rig._trauma = 0.0
	buddy.take_hit(HitInfo.create(3.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, buddy.global_position + Vector3.FORWARD))
	_check(is_zero_approx(rig._trauma), "a remote hero being hit leaves the local camera still")
	player.health.invulnerable = false
	player.take_hit(HitInfo.create(3.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, player.global_position + Vector3.FORWARD))
	_check(rig._trauma > 0.0, "the local hero being hit shakes the camera")
	player.health.heal_full()
	hunter.health.max_health = 1.0
	hunter.take_hit(HitInfo.create(99999.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, hunter.global_position))
	lab.remove_player(buddy)
	buddy.queue_free()
	await _wait_frames(20)
	for child in lab.world.get_children():  # the hunter's gold, so it can't skew the later loot counts
		if child is GoldDrop:
			child.free()
	_check(lab.players.size() == 1, "removing the second hero leaves the local one")

	# --- M07b class filters: talents and class-specific loot ---
	_check(Progression.tree_for(&"runebreaker").size() == 24 and Progression.tree_for(&"nope").is_empty()
		and player.progression.class_id == &"runebreaker",
		"the talent tree is filtered by class")
	var foreign_tagged := 0
	var foreign_legendary := 0
	for i in 200:
		var roll_item := ItemGenerator.generate(2, &"nope")
		if roll_item.legendary_id != &"":
			foreign_legendary += 1
		for affix in roll_item.affixes:
			for def: Dictionary in AffixPool.DEFS:
				if def["id"] == affix["id"] and def.has("class"):
					foreign_tagged += 1
	_check(foreign_tagged == 0 and foreign_legendary == 0,
		"another class never rolls Runebreaker affixes or legendaries (elite drops downgrade to rare)")
	var own_legendary := false
	for i in 60:
		if ItemGenerator.generate(2, &"runebreaker").legendary_id != &"":
			own_legendary = true
	_check(own_legendary and AffixPool.legendaries_for(&"runebreaker").size() == AffixPool.LEGENDARIES.size(),
		"the Runebreaker still rolls its own legendaries")

	# --- M06 B5: HUD v2 look ---
	var hud_root := lab.hud.get_child(0) as Control
	var body_font := UiTheme.font()
	_check(hud_root.theme == UiTheme.theme() and body_font != null
		and body_font.antialiasing == TextServer.FONT_ANTIALIASING_NONE,
		"HUD uses the pixel UI theme (Pixelify Sans, no antialiasing)")
	var icons_ok := true
	for id: StringName in [&"rune_cleave", &"ember_lance", &"earthbreaker", &"storm_step", &"chain_spark", &"fracture_rune", &"dodge"]:
		icons_ok = icons_ok and (lab.hud._slots[id]["icon"] as TextureRect).texture != null
	_check(icons_ok, "every ability slot shows its pixel icon")
	var plate := Label3D.new()
	UiTheme.label3d(plate)
	_check(plate.fixed_size and plate.font == body_font and plate.font_size == UiTheme.BODY,
		"world labels: pixel font at a fixed screen size (1 font px = 1 screen px)")
	plate.free()
	var hud_names := lab.hud.ability_names()
	_check(hud_names.size() == 7 and hud_names.has("Fracture Rune") and hud_names.has("Dodge"),
		"HUD knows all 7 ability names")
	lab.targeting.cycle_target()
	_check(lab.targeting.current == rusher, "tab cycle wraps with single candidate")
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
	# Default camera looks down at the hero: a floor hit must not steer the
	# lance into the ground (user feedback 2026-09-24).
	var saved_pitch: float = player.camera_rig._pitch
	player.camera_rig._pitch = -0.45
	await _wait_frames(2)
	var floor_aim := player.aim_direction()
	_check(player.camera_rig.last_aim_on_floor and absf(floor_aim.y) < 0.08,
		"ember aim stays level when the camera ray hits the floor (y=%.2f)" % floor_aim.y)
	player.camera_rig._pitch = saved_pitch
	await _wait_frames(2)
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
	var actions_seen: Array[StringName] = []
	var record := func(a: StringName) -> void: actions_seen.append(a)
	player.action_started.connect(record)
	_check(player.try_earthbreaker(), "earthbreaker starts with resonance")
	_check(player.resonance < res_before, "earthbreaker consumes Resonance")
	await _wait_frames(70)
	player.action_started.disconnect(record)
	var eb_hit := not is_instance_valid(eb_target) or eb_target.health.current_health < eb_hp
	_check(eb_hit, "earthbreaker damages nearby enemy")
	_check(player.state == Player.State.MOVE, "earthbreaker recovers to MOVE")
	_check(actions_seen.size() == 2 and actions_seen[0] == &"earthbreaker" and actions_seen[1] == &"earthbreaker_impact",
		"earthbreaker emits rise then impact for the rig (%s)" % str(actions_seen))
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
	await _wait_frames(1)  # M07b: movement reaches the player through its per-tick intent
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

	# M06 fix: dodging out of a running Storm Step still ends the dash
	# (collision mask restored, path zapped) instead of leaving the player
	# phasing through enemies.
	lab.kill_all_enemies()
	await _wait_frames(20)
	player.global_position = Vector3(0, 0.2, 6)
	player.velocity = Vector3.ZERO
	var cancel_victim := MeleeRusher.new()
	lab.enemies_root.add_child(cancel_victim)
	cancel_victim.player = player
	cancel_victim.global_position = player.global_position + Vector3(0, 0, -1.5)
	await _wait_frames(2)
	player.reset_cooldowns()
	_check(player.try_storm_step(), "cancel test: dash starts")
	await _wait_frames(2)
	_check(player.state == Player.State.STORM_STEP, "cancel test: still mid-dash")
	_check(player.try_dodge(), "dodge cancels a running storm step")
	_check(player.collision_mask == 0b101, "dodge-cancelled storm step restores collision mask")
	_check(cancel_victim.status.has_shock(), "dodge-cancelled storm step still zaps its path")
	await _wait_frames(25)
	_check(player.state == Player.State.MOVE, "dodge after storm step returns to MOVE")

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
	var rune_node: Node = null
	for child in get_tree().current_scene.get_children():
		if child is FractureRune:
			rune_node = child
	_check(rune_node != null and rune_node.get_node_or_null("PlayerRing") != null
		and rune_node.find_children("ThreatMarker", "", true, false).is_empty(),
		"player rune marks its radius with a broken ring, never the red threat disc")
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
	hp_item.slot = ItemData.Slot.CHEST
	hp_item.rarity = ItemData.Rarity.MAGIC
	hp_item.display_name = "Test Cuirass"
	hp_item.affixes = [{"id": &"max_hp", "label": "+30 maximum health", "stat": &"max_hp", "value": 30.0}]
	player.equipment.add_item(hp_item)
	player.equipment.equip(hp_item)
	_check(absf(player.health.max_health - (130.0 + player.progression.stat(&"max_hp"))) < 0.01,
		"equipping +30 HP raises max health (on top of level bonuses)")

	# Keyboard layout (user, 2026-09-24): abilities on the number row, Q/R kept, E = interact.
	var has_key := func(action: StringName, key: Key) -> bool:
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey and (ev as InputEventKey).physical_keycode == key:
				return true
		return false
	_check(has_key.call(&"ability_q", KEY_1) and has_key.call(&"ability_q", KEY_Q) and has_key.call(&"ability_e", KEY_2)
		and not has_key.call(&"ability_e", KEY_E) and has_key.call(&"ability_r", KEY_3) and has_key.call(&"ability_r", KEY_R)
		and has_key.call(&"ability_f", KEY_4) and has_key.call(&"ability_runic_guard", KEY_5)
		and has_key.call(&"ability_resonance_burst", KEY_6) and has_key.call(&"interact", KEY_E),
		"number-row ability layout with Q/R alternates, E = interact")

	# --- M07 progression: XP, levels, talent rules, save format ---
	var tree := Progression.tree()
	var t_static := Progression.talent(&"static_charge")
	var t_arc := Progression.talent(&"arc_conduit")
	_check(tree.size() == 24 and t_static != null and t_arc != null and t_arc.tier == 1,
		"talent tree loads 24 data nodes (3 branches)")
	var prog := Progression.new()
	add_child(prog)
	prog.add_xp(Progression.xp_to_next(1) + Progression.xp_to_next(2) + Progression.xp_to_next(3) + Progression.xp_to_next(4))
	_check(prog.level == 5 and prog.xp == 0 and prog.points_free() == 4, "XP fills levels exactly; one point per level")
	_check(absf(prog.stat(&"max_hp") - 24.0) < 0.01 and absf(prog.stat(&"damage_pct") - 8.0) < 0.01,
		"levels grant +6 health and +2 % damage each")
	_check(not prog.can_learn(t_arc), "tier 2 stays closed until 3 points sit below it")
	for i in 3:
		prog.learn(t_static)
	_check(prog.rank(&"static_charge") == 3 and absf(prog.stat(&"crit_pct") - 9.0) < 0.01, "ranks stack a talent's stat")
	_check(prog.learn(t_arc) and prog.stat(&"chain_jumps") == 1.0, "tier 2 opens after 3 points")
	_check(not prog.can_unlearn(t_static), "a rank that holds a higher tier open can't be removed")
	_check(prog.unlearn(t_arc) and prog.can_unlearn(t_static), "unlearning from the top works")
	_check(not prog.learn(t_static), "a maxed talent takes no more points")
	var saved := prog.to_dict()
	var prog_loaded := Progression.new()
	add_child(prog_loaded)
	prog_loaded.from_dict(saved)
	_check(prog_loaded.level == 5 and prog_loaded.rank(&"static_charge") == 3 and prog_loaded.points_free() == 1,
		"progression round-trips through the save format")
	prog.respec()
	_check(prog.points_free() == 4 and prog.stat(&"crit_pct") == 0.0, "respec returns every point")
	var v1 := SaveGame.migrate({"version": 1, "zone": "res://scenes/hub.tscn", "flags": {"x": true}, "inventory": [], "equipped": {}})
	var v1_char: Dictionary = (v1.get("characters", [{}]) as Array)[0]
	_check(int(v1.get("version", 0)) == SaveGame.VERSION and (v1_char["progression"] as Dictionary)["level"] == 1
		and (v1["world"] as Dictionary)["flags"].has("x") and v1_char["known_abilities"] == ["rune_cleave"],
		"v1 saves migrate to v3 (level 1, Rune Cleave only, flags kept in world)")
	var v2 := SaveGame.migrate({"version": 2, "zone": "res://scenes/shattered_spire.tscn", "flags": {"colossus_defeated": true},
		"inventory": [{"n": "x"}], "equipped": {}, "progression": {"level": 4, "xp": 10, "talents": {"kindling": 2}}})
	var v2_char: Dictionary = (v2.get("characters", [{}]) as Array)[0]
	_check(v2_char["class_id"] == "runebreaker" and int(v2_char["gold"]) == 475
		and v2_char["known_abilities"] == ["rune_cleave"]
		and (v2_char["inventory"] as Array).size() == 1 and (v2["world"] as Dictionary)["zone"].ends_with("shattered_spire.tscn")
		and int(v2.get("active", -1)) == 0,
		"v2 saves migrate to v3: one Runebreaker keeps gear, starts with Rune Cleave and the gold its level earned (475 at L4)")
	_check(SaveGame.active_class_id() == &"runebreaker", "fresh save plays the default class")
	prog.queue_free()
	prog_loaded.queue_free()
	_check(absf(player.stat(&"damage_pct") - player.equipment.stat(&"damage_pct") - player.progression.stat(&"damage_pct")) < 0.001,
		"player stats sum equipment and progression")
	var xp_before := player.progression.level * 100000 + player.progression.xp  # monotonic across level-ups
	var xp_victim := MeleeRusher.new()
	lab.enemies_root.add_child(xp_victim)
	xp_victim.global_position = Vector3(-12, 0.2, -18)
	xp_victim.enemy_died.connect(lab._on_enemy_died)
	await _wait_frames(2)
	xp_victim.take_hit(HitInfo.create(99999.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, xp_victim.global_position))
	await _wait_frames(2)
	var xp_after := player.progression.level * 100000 + player.progression.xp
	_check(xp_after > xp_before, "a kill pays XP (%d -> %d)" % [xp_before, xp_after])

	# --- M07 behavior talents + abilities 7-8 (powers granted directly) ---
	var grant := func(ids: Array) -> void:
		player.progression.ranks.clear()
		for id in ids:
			player.progression.ranks[StringName(id)] = 1
		player.progression._changed()
	var dummy := MeleeRusher.new()
	lab.enemies_root.add_child(dummy)
	dummy.player = player
	dummy.global_position = player.global_position + player.facing() * 1.6
	await _wait_frames(2)
	dummy.set_physics_process(false)  # a still target
	dummy.health.max_health = 1.0e6
	dummy.health.heal_full()
	# Runic Guard: barrier soaks a hit.
	grant.call(["runic_guard", "glacial_bulwark"])
	player.reset_cooldowns()
	player.resonance = 100.0
	_check(player.try_runic_guard() and player.barrier > 30.0 and player.resonance < 71.0,
		"Runic Guard (key 5) spends 30 Resonance for a barrier")
	var hp_guard := player.health.current_health
	player.take_hit(HitInfo.create(12.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, dummy.global_position))
	_check(is_equal_approx(player.health.current_health, hp_guard) and dummy.status.has_chill(),
		"the barrier absorbs the hit; Glacial Bulwark chills the attacker")
	player.barrier = 0.0
	# Resonance Burst: spends everything, hits around the hero.
	grant.call(["resonance_burst"])
	player.reset_cooldowns()
	player.resonance = 80.0
	var hp_dummy := dummy.health.current_health
	_check(player.try_resonance_burst() and player.resonance == 0.0 and dummy.health.current_health < hp_dummy,
		"Resonance Burst (key 6) spends all Resonance in a damaging nova")
	player.resonance = 20.0
	player.reset_cooldowns()
	_check(not player.try_resonance_burst(), "Resonance Burst needs 50 Resonance")
	# Molten Core + Wildfire + Kindling.
	grant.call(["molten_core", "wildfire", "kindling"])
	player.progression.ranks[&"kindling"] = 3
	player.progression._changed()
	dummy.status.clear_all()
	player._do_slam_hit()
	_check(dummy.status.has_burn() and is_equal_approx(dummy.status._burn_dps, StatusEffectComponent.BURN_DPS * 1.6),
		"Molten Core: Earthbreaker ignites; Kindling scales the Burn (x1.6 at 3 ranks)")
	var neighbor := MeleeRusher.new()
	lab.enemies_root.add_child(neighbor)
	neighbor.player = player
	neighbor.global_position = dummy.global_position + Vector3(1.5, 0, 0)
	await _wait_frames(2)
	neighbor.set_physics_process(false)
	var burner := MeleeRusher.new()
	lab.enemies_root.add_child(burner)
	burner.player = player
	burner.global_position = neighbor.global_position + Vector3(0.8, 0, 0.8)
	await _wait_frames(2)
	burner.status.apply_burn()
	neighbor.status.clear_all()
	burner.take_hit(HitInfo.create(99999.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, burner.global_position))
	_check(neighbor.status.has_burn(), "Wildfire: a Burning enemy's death spreads its Burn")
	# Galvanize: bonus damage to Shocked targets.
	grant.call(["galvanize"])
	player.progression.ranks[&"galvanize"] = 3
	player.progression._changed()
	var galv_hit := HitInfo.create(10.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, player.global_position)
	galv_hit.from_player = true
	dummy.status.clear_all()
	dummy.status.apply_shock()
	_check(is_equal_approx(player.talent_damage_mult(galv_hit, dummy), 1.24), "Galvanize: +24 % damage to Shocked enemies at 3 ranks")
	# M07b: the multiplier comes from the ATTACKER, not from the enemy's assigned player.
	dummy.player = null
	var atk_dummy_hit := player.roll_ability_hit(player.cleave)
	atk_dummy_hit.applies_shock = false
	var atk_before := atk_dummy_hit.damage
	dummy.take_hit(atk_dummy_hit)
	_check(is_equal_approx(atk_dummy_hit.damage, atk_before * 1.24 * dummy.status.damage_taken_multiplier())
		and dummy.last_attacker() == player,
		"talent damage follows the attacker id (no assigned player needed); the enemy remembers its attacker")
	dummy.player = player
	# Overload: the Storm Step landing Shocks everything near it.
	grant.call(["overload"])
	dummy.status.clear_all()
	neighbor.status.clear_all()
	player._dash_start = player.global_position
	player._resolve_storm_step()
	_check(dummy.status.has_shock(), "Overload: Storm Step's end point Shocks nearby enemies")
	# Split Lance: the first hit forks two shards.
	grant.call(["split_lance"])
	var lance := EmberLanceProjectile.new()
	lance.setup(player.ember, player.facing(), player)
	lance.position = dummy.global_position + Vector3(0, 1.0, 0)
	lab.add_child(lance)
	lance._split_from(dummy)
	var split_done := not lance.can_split  # the lance itself may be gone after its hit
	await _wait_frames(2)
	var lances := 0
	for child in lab.get_children():
		if child is EmberLanceProjectile:
			lances += 1
	_check(lances >= 2 and split_done, "Split Lance: the first hit forks two half-damage shards")
	# Unbroken: an attack inside the dodge's i-frames grants a barrier.
	grant.call(["unbroken"])
	player.barrier = 0.0
	player._cooldowns.erase(&"unbroken")
	player.health.invulnerable = true
	player.take_hit(HitInfo.create(10.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, dummy.global_position))
	player.health.invulnerable = false
	_check(is_equal_approx(player.barrier, Player.UNBROKEN_BARRIER), "Unbroken: dodging through an attack grants a barrier")
	player.barrier = 0.0
	# Searing Lance + Fuel the Fire: conditional damage by ability / Burning.
	grant.call(["searing_lance", "fuel_the_fire"])
	player.progression.ranks[&"searing_lance"] = 3
	player.progression.ranks[&"fuel_the_fire"] = 2
	player.progression._changed()
	var lance_hit := HitInfo.create(10.0, HitInfo.DamageType.FIRE, HitInfo.Weight.LIGHT, player.global_position)
	lance_hit.from_player = true
	lance_hit.ability = &"ember_lance"
	dummy.status.clear_all()
	dummy.status.apply_burn()
	_check(is_equal_approx(player.talent_damage_mult(lance_hit, dummy), 1.44),
		"Searing Lance (+24 %) and Fuel the Fire (+20 % on Burning) add up")
	# Quickstep + Storm Surge: Storm Step cooldown and lightning Resonance.
	grant.call(["quickstep", "storm_surge"])
	player.progression.ranks[&"quickstep"] = 2
	player.progression.ranks[&"storm_surge"] = 2
	player.progression._changed()
	player.reset_cooldowns()
	player._set_cooldown(&"storm_step", player.storm_step.cooldown)
	_check(is_equal_approx(float(player._cooldowns[&"storm_step"]), player.storm_step.cooldown * 0.76),
		"Quickstep: Storm Step cooldown -24 % at 2 ranks")
	player.resonance = 0.0
	player.gain_resonance(10.0, true)
	var surge_res := player.resonance
	player.resonance = 0.0
	player.gain_resonance(10.0)
	_check(surge_res > player.resonance + 2.9, "Storm Surge: lightning hits build +30 % more Resonance")
	player.resonance = 0.0
	# Eye of the Storm: the dash refunds cooldown per enemy on its path.
	grant.call(["eye_of_the_storm"])
	player.reset_cooldowns()
	player._set_cooldown(&"storm_step", player.storm_step.cooldown)
	var cd_full := float(player._cooldowns[&"storm_step"])
	player._dash_start = player.global_position - player.facing() * 0.5
	player.global_position = player._dash_start + player.facing() * 3.2  # the dash passed the dummy
	player._resolve_storm_step()
	_check(float(player._cooldowns[&"storm_step"]) < cd_full - 0.01, "Eye of the Storm: enemies on the path refund cooldown")
	player.global_position = player._dash_start + player.facing() * 0.5
	player.velocity = Vector3.ZERO
	# Thunderclap: the Chain Spark's last target bursts onto a neighbour.
	grant.call(["thunderclap"])
	player.reset_cooldowns()
	var clap_hp := neighbor.health.current_health
	neighbor.health.max_health = 1.0e6
	neighbor.health.heal_full()
	clap_hp = neighbor.health.current_health
	lab.targeting.current = dummy
	var sparked := player.try_chain_spark()
	await _wait_frames(2)
	_check(sparked and neighbor.health.current_health < clap_hp, "Thunderclap / chain: the neighbour takes lightning damage")
	# Phoenix Burst: where a lance ends it bursts onto neighbours.
	grant.call(["phoenix_burst"])
	var phoenix := EmberLanceProjectile.new()
	phoenix.setup(player.ember, player.facing(), player)
	phoenix.position = dummy.global_position + Vector3(0, 1.0, 0)
	lab.add_child(phoenix)
	var burst_hp := neighbor.health.current_health
	neighbor.status.clear_all()
	phoenix._phoenix_burst(dummy)
	_check(neighbor.health.current_health < burst_hp and neighbor.status.has_burn(),
		"Phoenix Burst: the lance's end bursts (damage + Burn) onto neighbours")
	phoenix.queue_free()
	# Talent panel: toggles, locks input, learns through the rules.
	grant.call([])
	lab.talent_ui.toggle()
	_check(lab.talent_ui.visible and player.input_locked, "talent panel (N) opens and locks combat input")
	var learnable := Progression.talent(&"static_charge")
	var free_before := player.progression.points_free()
	var learned := lab.talent_ui.try_learn(learnable)
	_check(learned == (free_before > 0), "the panel learns a rank when a point is free")
	lab.talent_ui.toggle()
	_check(not lab.talent_ui.visible and not player.input_locked, "talent panel closes and frees combat input")
	player.progression.respec()
	for m07_foe in [dummy, neighbor]:
		if is_instance_valid(m07_foe):
			m07_foe.queue_free()
	for child in lab.get_children():
		if child is EmberLanceProjectile:
			child.queue_free()
	await _wait_frames(2)

	# 7 equipment slots: every slot rolls affixes and has an icon; old values keep their meaning.
	var slots_ok := true
	for slot_i in ItemData.SLOT_COUNT:
		var sl := slot_i as ItemData.Slot
		slots_ok = slots_ok and AffixPool.defs_for_slot(sl).size() >= 3
		var probe := ItemData.new()
		probe.slot = sl
		slots_ok = slots_ok and UiTheme.item_icon(probe) != null
	_check(slots_ok and ItemData.Slot.CHEST == 1 and ItemData.Slot.AMULET == 2 and ItemData.SLOT_ORDER.size() == 7,
		"7 gear slots: each has 3+ affixes and an icon; saved armor/relic map to chest/amulet")
	var ring := ItemData.new()
	ring.slot = ItemData.Slot.RING
	ring.display_name = "Test Band"
	player.equipment.add_item(ring)
	player.equipment.equip(ring)
	_check(player.equipment.equipped.get(ItemData.Slot.RING) == ring
		and ItemData.from_dict(ring.to_dict()).slot == ItemData.Slot.RING, "a ring equips into its own slot and saves")
	player.equipment.unequip(ItemData.Slot.RING)

	# M07 item level + compare
	var scaled := ItemData.new()
	scaled.affixes = [{"id": &"damage_pct", "label": "+15% damage", "stat": &"damage_pct", "value": 15.0},
		{"id": &"ember_pierce", "label": "Ember Lance pierces 1 additional enemy", "stat": &"ember_pierce", "value": 1.0}]
	ItemGenerator.apply_item_level(scaled, 6)
	_check(scaled.item_level == 6 and is_equal_approx(float(scaled.affixes[0]["value"]), 20.0)
		and scaled.affixes[0]["label"] == "+20% damage" and float(scaled.affixes[1]["value"]) == 1.0,
		"item level scales numeric affixes (+6 %/level), behavioral ones stay")
	var cmp := InventoryUI.compare_lines(scaled, hp_item)
	_check(cmp.size() == 3, "compare lists every stat that changes (%d lines)" % cmp.size())

	var cd_item := ItemData.new()
	cd_item.slot = ItemData.Slot.AMULET
	cd_item.rarity = ItemData.Rarity.MAGIC
	cd_item.display_name = "Test Sigil"
	cd_item.affixes = [{"id": &"cooldown_pct", "label": "20% cooldown reduction", "stat": &"cooldown_pct", "value": 20.0}]
	player.equipment.add_item(cd_item)
	player.equipment.equip(cd_item)
	player.reset_cooldowns()
	player.try_ember()
	var expected_cd: float = player.ember.cooldown * 0.8
	_check(absf(float(player._cooldowns[&"ember_lance"]) - expected_cd) < 0.01, "cooldown reduction applies")
	_check(absf(StatSheet.effective_cooldown(player, player.ember) - expected_cd) < 0.001,
		"the character sheet shows the same reduced cooldown")
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
	oath.slot = ItemData.Slot.AMULET
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
	glacier.slot = ItemData.Slot.CHEST
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

	# --- inventory UI toggling + ability tooltips (names only on hover) ---
	var hud := lab.hud
	hud._update_tooltip(hud.slot_rect(&"fracture_rune").get_center())
	_check(not hud.tooltip_visible(), "ability names hidden while the inventory is closed")
	lab.inventory_ui.toggle()
	_check(lab.inventory_ui.visible and player.input_locked, "inventory opens and locks input")
	var expected_names := {
		&"rune_cleave": player.cleave.display_name, &"ember_lance": player.ember.display_name,
		&"earthbreaker": player.earthbreaker.display_name, &"storm_step": player.storm_step.display_name,
		&"chain_spark": player.chain_spark.display_name, &"fracture_rune": player.fracture_rune.display_name,
		&"dodge": "Dodge",
	}
	var tooltips_ok := true
	for id: StringName in expected_names:
		hud._update_tooltip(hud.slot_rect(id).get_center())
		if not hud.tooltip_visible() or hud.tooltip_title() != expected_names[id]:
			tooltips_ok = false
	_check(tooltips_ok, "hovering each ability slot (inventory open) shows its name")
	# Headless viewports are 64x64, so check the placement rule at a real window size.
	var tip_size := Vector2(270, 120)
	var slot_1600 := Rect2(Vector2(720, 804), Vector2(44, 44))
	var tip_pos := Hud.tooltip_position(slot_1600, tip_size, Vector2(1600, 900))
	_check(tip_pos.y + tip_size.y <= slot_1600.position.y
		and absf(tip_pos.x + tip_size.x * 0.5 - slot_1600.get_center().x) < 1.0,
		"ability tooltip sits centered above its slot")
	var edge_pos := Hud.tooltip_position(Rect2(Vector2(1590, 804), Vector2(44, 44)), tip_size, Vector2(1600, 900))
	_check(edge_pos.x + tip_size.x <= 1592.0, "ability tooltip stays on screen at the edge")
	hud._update_tooltip(Vector2(-100, -100))
	_check(not hud.tooltip_visible(), "tooltip hides when the mouse leaves the slots")
	lab.inventory_ui.toggle()
	_check(not lab.inventory_ui.visible and not player.input_locked, "inventory closes and unlocks input")

	# Cleanup: fresh equipment for the remaining M01/M02 sections.
	for slot: ItemData.Slot in [ItemData.Slot.WEAPON, ItemData.Slot.CHEST, ItemData.Slot.AMULET]:
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
	# M06 fix: the low-res style reparents the world; enemies must stay registered
	# (Tab targeting, Chain Spark jumps and separation all read the registry).
	var registry_ok := lab.enemies_root.get_child_count() > 0
	for child in lab.enemies_root.get_children():
		if child is EnemyBase and not EnemyBase.all_enemies.has(child):
			registry_ok = false
	_check(registry_ok, "enemy registry survives the low-res style reparent")

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
	marker.slot = ItemData.Slot.AMULET
	marker.display_name = "Persistence Marker"
	player.equipment.add_item(marker)
	var keepsake := ItemData.new()
	keepsake.slot = ItemData.Slot.WEAPON
	keepsake.display_name = "Saved Blade"
	player.equipment.add_item(keepsake)
	player.equipment.equip(keepsake)
	player.add_gold(123 - player.gold)  # M07b: gold and known abilities ride along
	SaveGame.save_now()
	player.equipment.inventory.clear()
	player.equipment.equipped.clear()
	player.equipment._recompute()
	player.gold = 0
	player.known_abilities = [&"rune_cleave"]
	SaveGame.reload_from_disk()
	SaveGame.restore_player(player)
	_check(player.gold == 123 and player.known_abilities.size() == 6 and player.knows(&"fracture_rune"),
		"save restores gold and the learned abilities")
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
	# M07b: Sigrun stands in Runehold; talking opens the trainer panel.
	var trainer := hub.world.get_node_or_null("Trainer") as TrainerNpc
	_check(trainer != null and trainer.npc_name.begins_with("Sigrun"), "the trainer stands in Runehold")
	if trainer != null:
		var hub_spot := hub.player.global_position
		hub.player.global_position = trainer.global_position + Vector3(1.2, 0.2, 0.6)
		await _wait_frames(2)
		_check(trainer._prompt.visible and trainer._prompt.text.ends_with("Talk"), "trainer shows the [E] Talk prompt up close")
		hub.trainer_ui.open(trainer)
		_check(hub.trainer_ui.visible and hub.player.input_locked, "trainer panel opens and locks input")
		hub.trainer_ui.close()
		_check(not hub.trainer_ui.visible and not hub.player.input_locked, "trainer panel closes and unlocks input")
		hub.player.global_position = hub_spot
		await _wait_frames(2)
		_check(not trainer._prompt.visible, "trainer prompt hides at a distance")
	var carried := false
	for it in hub.player.equipment.inventory:
		if it.display_name == "Persistence Marker":
			carried = true
	_check(carried, "gear persists across zone travel")
	_check(hub.player.gold == 123 and hub.player.knows(&"storm_step"), "gold and abilities persist across zone travel")

	# --- M06 C3: Runehold kit on the unchanged hub layout ---
	_check(hub.look != null and hub.look.art_pass, "hub uses the Runehold ZoneLook (art pass)")
	var hub_bodies := hub.world.find_children("*", "StaticBody3D", true, false)
	_check(hub_bodies.size() == 20, "hub dressing adds no collision (%d bodies: layout 19 + the trainer's body)" % hub_bodies.size())
	var wall_trims := 0
	var sod_roofs := 0
	var roofs_fit := true
	for b: Node in hub_bodies:
		if b.get_node_or_null("WallTrim") != null:
			wall_trims += 1
		var roof := b.get_node_or_null("SodRoof") as MeshInstance3D
		if roof == null:
			continue
		sod_roofs += 1
		var h := ((b.get_child(1) as CollisionShape3D).shape as BoxShape3D).size * 0.5
		var box := roof.mesh.get_aabb()
		roofs_fit = roofs_fit and box.position.x <= -h.x and box.position.y <= -h.y and box.position.z <= -h.z \
			and box.end.x >= h.x and box.end.y >= h.y and box.end.z >= h.z and box.end.y <= h.y + 0.31 \
			and box.end.x <= h.x + 0.31 and box.end.z <= h.z + 0.31
	_check(wall_trims == 4 and sod_roofs == 3, "hub walls get masonry trim (%d), huts sod roofs (%d)" % [wall_trims, sod_roofs])
	_check(roofs_fit, "sod roofs contain their slab collider, within the camera margin and overhang limits")
	_check(hub.dressing().find_children("*", "CollisionObject3D", true, false).is_empty(), "hub dressing adds no collision")
	var gates := 0
	for child in hub.world.get_children():
		if child is Portal and child.get_node_or_null("Frame/Gate") != null and (child as Portal)._gate_mat != null:
			gates += 1
	_check(gates == 2, "hub portals are v2 gates (floating arch, upright swirl, flush plate)")
	var hub_portal: Portal = null
	for child in hub.world.get_children():
		if child is Portal:
			hub_portal = child
			break
	var spot_before := hub.player.global_position
	hub_portal._cooldown = 0.0
	hub.player.global_position = hub_portal.global_position + Vector3(0.8, 0.2, 0)
	await _wait_frames(5)
	_check(hub_portal._prompt.visible and not hub._travelling, "portal shows its prompt and waits for the interact key")
	hub.player.global_position = spot_before
	await _wait_frames(2)
	var fire := hub.dressing().get_node_or_null("rh_hearth_fire")
	_check(fire != null and fire.find_child("flames", true, false) != null, "hub hearth is the kit fire with living flames")
	var ground := ((hub_bodies[0] as StaticBody3D).get_child(0) as MeshInstance3D).mesh.surface_get_material(0) as ShaderMaterial
	_check(ground != null and int(ground.get_shader_parameter(&"paved_circles")) == 1
		and int(ground.get_shader_parameter(&"paved_paths")) >= 5, "hub ground has a paved plaza and paths")
	var hub_scatter := 0
	for child in hub.dressing().get_children():
		if child is MultiMeshInstance3D:
			hub_scatter += ((child as MultiMeshInstance3D).get_meta(Scatter.POINTS_META, PackedVector3Array()) as PackedVector3Array).size()
	_check(hub_scatter > 100, "hub scatter along walls and huts (%d)" % hub_scatter)
	_check(MusicDirector.instance != null and MusicDirector.instance.zone_key() == "runehold"
		and MusicDirector.instance.is_playing(), "Runehold plays its own theme")

	# --- highlands (M08 open zone on the heightmap) ---
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
	var hl_layout := highlands.layout
	_check(highlands.terrain != null and highlands.terrain.chunk_count() == 144 and hl_layout.pois.size() >= 26,
		"highlands: terrain (144 chunks, %d ms) and layout (%d POIs) built" % [highlands.terrain.build_ms, hl_layout.pois.size()])
	var poi_off_ground := 0
	for poi in hl_layout.pois:
		var pp := ZoneLayout.pos_of(poi)
		if absf(pp.y - highlands.ground_y(pp)) > 0.3:
			poi_off_ground += 1
	_check(poi_off_ground == 0, "highlands: every POI's baked height matches the terrain")
	var hl_spawn := highlands.poi_position("spawn")
	var camp_too_close := false
	for camp_id: String in highlands.camps:
		var sp := highlands.camps[camp_id] as EncounterSpawner
		if camp_id.begins_with("camp") and sp.global_position.distance_to(hl_spawn) < 40.0:
			camp_too_close = true
	_check(highlands.camps.size() >= 10 and not camp_too_close,
		"highlands: %d camp / ambush spawners, no camp within 40 m of the spawn" % highlands.camps.size())
	_check(highlands.enemies_root.get_child_count() == 0, "highlands: no camp triggers on arrival")
	_check(highlands.player.is_on_floor() and absf(highlands.player.global_position.y - highlands.ground_y(highlands.player.global_position)) < 0.6,
		"highlands: the hero lands on the terrain at the spawn pad")
	_check(highlands._enemy_level(null, highlands.poi_position("camp_1")) == 1
		and highlands._enemy_level(null, highlands.poi_position("camp_4")) == 2
		and highlands._enemy_level(null, highlands.poi_position("camp_7")) == 3,
		"highlands: level bands south 1 / middle 2 / north 3")
	_check(highlands.camera_rig.camera.far > 500.0, "highlands: camera far plane opened for the 384 m zone")
	_check(highlands.boss_portal != null and highlands.spire_portal != null and highlands.boss_portal.locked,
		"highlands: arena gates built from the layout, sealed while the Colossus lives")
	var sealed_dungeons := 0
	for child in highlands.world.get_children():
		if child is Portal and (child as Portal).locked and (child as Portal).destination_scene == "":
			sealed_dungeons += 1
	_check(sealed_dungeons == 2, "highlands: two sealed dungeon gates stand as landmarks")

	# --- M06 look: data-driven environment + dressing never touches collision ---
	_check(highlands.look != null and highlands.look.art_pass, "highlands uses its ZoneLook (art pass)")
	var hull_bodies := 0
	var hull_contains := true
	var shapes_intact := true
	var rocks_grounded := true
	for child in highlands.world.get_children():
		var body := child as StaticBody3D
		if body == null or body.get_node_or_null("RockHull") == null:
			continue
		hull_bodies += 1
		var box := (body.get_child(1) as CollisionShape3D).shape as BoxShape3D
		var box_mesh := body.get_child(0) as MeshInstance3D
		shapes_intact = shapes_intact and box != null and not box_mesh.visible \
			and box.size == (box_mesh.mesh as BoxMesh).size and body.collision_layer == 1
		var h := box.size * 0.5
		# the box bottom sits under the lowest ground of its footprint (no gap on slopes)
		var span := highlands.terrain.footprint_range(body.global_position, box.size, body.rotation.y)
		rocks_grounded = rocks_grounded and body.global_position.y - h.y <= span.x + 0.01 and body.global_position.y + h.y > span.y
		var arrays := ((body.get_node("RockHull") as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)
		for v: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
			if absf(v.x) < h.x - 0.001 and absf(v.y) < h.y - 0.001 and absf(v.z) < h.z - 0.001:
				hull_contains = false
				break
	_check(hull_bodies >= 40, "ridges, arena and ruins are dressed with rock hulls (%d)" % hull_bodies)
	_check(shapes_intact, "dressed boxes keep their collider (box shape, layer 1), box mesh hidden")
	_check(hull_contains, "every rock hull vertex lies outside its collider box")
	_check(rocks_grounded, "every rock box is sunk below its footprint's lowest ground and clears the highest")
	var ruin_walls := 0
	for child in highlands.world.get_children():
		if child.name.begins_with("RuinWall") and (child as StaticBody3D).collision_layer == 1 \
				and (child as Node).get_node_or_null("WallTrim") != null:
			ruin_walls += 1
	_check(ruin_walls >= 12, "ruin walls are colliders with masonry trim (%d)" % ruin_walls)

	# --- M06 B3 / M08: rule-placed scatter + kit props stay out of play space ---
	var scatter_count := 0
	var bad := {"shadow": 0, "collider": 0, "pad": 0, "float": 0}
	var obstacles := highlands.scatter_obstacles()
	var pads := highlands._pads()
	for child in highlands.dressing().get_children():
		var mmi := child as MultiMeshInstance3D
		if mmi == null or not mmi.name.begins_with("Scatter_"):
			continue
		if mmi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			bad["shadow"] += 1
		var points: PackedVector3Array = mmi.get_meta(Scatter.POINTS_META, PackedVector3Array())
		if points.size() != mmi.multimesh.instance_count:
			bad["collider"] += 1000  # positions must match the instances
		for p in points:
			var p2 := Vector2(p.x, p.z)
			scatter_count += 1
			if Scatter._inside_any(p2, obstacles):
				bad["collider"] += 1
			for pad in pads:
				if p2.distance_to(Vector2(pad.x, pad.y)) < pad.z - 0.01:
					bad["pad"] += 1
			if scatter_count % 50 == 0 and absf(p.y - highlands.ground_y(p)) > 0.05:
				bad["float"] += 1
	_check(scatter_count > 3000, "scatter: obstacle bands plus open-ground fields (%d instances)" % scatter_count)
	_check(bad.values().all(func(n: int) -> bool: return n == 0),
		"scatter: no shadows, never inside a collider or a POI pad, sits on the terrain %s" % str(bad))
	var banner := highlands.dressing().get_node_or_null("banner_pole") as Node3D
	var banner_sways := false
	if banner != null:
		var banner_mesh := banner.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		for s in banner_mesh.mesh.get_surface_count():
			banner_sways = banner_sways or banner_mesh.get_surface_override_material(s) is ShaderMaterial
	_check(banner_sways, "hide banners sway in the wind (cloth surface uses the wind shader)")
	var seats_low := true
	var seats := 0
	for child in highlands.dressing().get_children():
		if child.name.begins_with("log_seat"):
			seats += 1
			var seat_mesh := (child as Node3D).find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
			seats_low = seats_low and seat_mesh.get_aabb().end.y <= 0.4
	_check(seats >= 12 and seats_low, "camp log seats are walk-through height (<= 0.4 m, %d seats)" % seats)
	var trees := 0
	var tall_without_blocker := 0
	var blockers := 0
	for child in highlands.world.get_children():
		if child.name.begins_with("Blocker"):
			blockers += 1
	for child in highlands.dressing().get_children():
		if child.name.begins_with("charred_tree"):
			trees += 1
	_check(trees >= 40 and blockers >= trees, "tall props (trees, banners) each stand on a collider (%d trees, %d blockers)" % [trees, blockers])

	# --- M06 audio: mix buses, music layers, looping ambience ---
	var music_bus := AudioServer.get_bus_index("Music")
	var buses_ok := music_bus != -1
	for bus_name in ["SFX", "Telegraph", "Ambience", "UI"]:
		buses_ok = buses_ok and AudioServer.get_bus_index(bus_name) != -1
	var duck := AudioServer.get_bus_effect(music_bus, 0) as AudioEffectCompressor if buses_ok else null
	_check(buses_ok and duck != null and duck.sidechain == &"Telegraph",
		"mix buses exist and telegraph sounds duck the music (sidechain)")
	var director := MusicDirector.instance
	_check(director != null and director.zone_key() == "highlands" and director.is_playing()
		and (director._sync as AudioStreamSynchronized).stream_count == 2,
		"highlands music plays its exploration + combat layers in sync")
	var loops_ok := true
	var ambience_found := 0
	for child in highlands.world.get_children():
		if (child is AudioStreamPlayer or child is AudioStreamPlayer3D) and child.get(&"bus") == &"Ambience":
			ambience_found += 1
			var wav := child.get(&"stream") as AudioStreamWAV
			loops_ok = loops_ok and wav != null and wav.loop_mode == AudioStreamWAV.LOOP_FORWARD
	_check(ambience_found >= 2 and loops_ok, "ambience loops come from the import (loop mode Forward, %d players)" % ambience_found)

	# First camp triggers once; its enemies stand on the terrain.
	var camp1 := highlands.camps["camp_1"] as EncounterSpawner
	highlands.player.global_position = highlands.ground_point(camp1.global_position + Vector3(0, 0, camp1.trigger_radius - 1.5), 0.3)
	highlands.player.velocity = Vector3.ZERO
	await _wait_frames(10)
	var camp_count := highlands.enemy_count()
	_check(camp_count >= 2, "camp spawner triggers on approach")
	var enemies_grounded := true
	for e in highlands.enemies_root.get_children():
		var ep := (e as Node3D).global_position
		enemies_grounded = enemies_grounded and absf(ep.y - highlands.ground_y(ep)) < 0.8
	_check(enemies_grounded, "camp enemies stand on the terrain pad")
	await _wait_frames(60)
	_check(director != null and director.combat_mix > 0.3, "combat layer swells in once the camp engages (%.2f)"
		% (director.combat_mix if director != null else 0.0))

	# Chest opens and pops loot; item level follows the band.
	var chest := highlands.chests["chest_south"] as TreasureChest
	_check(chest != null and highlands._enemy_level(null, chest.global_position) == 1
		and highlands._enemy_level(null, (highlands.chests["chest_hidden"] as TreasureChest).global_position) == 3,
		"chests take their item level from the band (south 1, north 3)")
	var inv_before_chest := highlands.player.equipment.inventory.size()
	highlands.player.global_position = highlands.ground_point(chest.global_position + Vector3(1.0, 0, 0), 0.2)
	highlands.player.velocity = Vector3.ZERO
	await _wait_frames(5)
	_check(not chest.opened and chest._prompt.visible and chest._prompt.text.begins_with("[E]"),
		"chest waits for the interact key and shows its prompt")
	Input.action_press(&"interact")
	await _wait_frames(2)
	Input.action_release(&"interact")
	await _wait_frames(30)
	var drops_out := 0
	for child in highlands.world.get_children():
		if child is ItemDrop:
			drops_out += 1
	var chest_loot := drops_out + (highlands.player.equipment.inventory.size() - inv_before_chest)
	_check(chest.opened, "chest opens on the interact key")
	_check(chest_loot >= 2, "chest pops at least 2 items")
	await _wait_frames(20)
	_check(chest.get_node_or_null("treasure_chest") != null and chest._lid.rotation_degrees.x < -30.0,
		"kit chest wraps the collider and swings its hinged lid open")
	# (a spawned probe, not the chest's drops: those may all have been picked up already)
	var kit_probe := highlands.spawn_item_drop(ItemGenerator.generate(0), highlands.player.global_position + Vector3(12, 0, 0))
	await _wait_frames(1)
	_check(kit_probe._shape != null and not kit_probe._shape is MeshInstance3D, "loot drops use the kit shapes")
	kit_probe.free()

	# Boss: trigger, enrage, kill, unlock.
	highlands.player.god_mode = true
	highlands.player.global_position = highlands.ground_point(highlands._boss_trigger.global_position, 0.3)
	highlands.player.velocity = Vector3.ZERO
	await _wait_frames(10)
	_check(highlands.boss != null, "boss fight starts at the arena")
	_check(highlands.boss_portal.locked, "north portal sealed while boss lives")
	var boss := highlands.boss
	_check(boss != null and absf(boss.global_position.y - highlands.ground_y(boss.global_position)) < 0.8
		and boss.level == 3, "the Colossus stands on the plateau at level 3")
	boss.take_hit(HitInfo.create(boss.health.max_health * 0.55, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, Vector3.ZERO))
	await _wait_frames(3)
	_check(boss.enraged, "colossus enrages below 50%")
	_check(boss._veins != null and boss.animator != null and boss.animator.anim.has_animation(&"charge"),
		"colossus v2 rig with code-owned ember veins")
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
	_check(MusicDirector.instance != null and MusicDirector.instance._stinger != null
		and MusicDirector.instance._stinger.playing, "a boss kill plays the victory stinger")

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
	_check(MusicDirector.instance != null and MusicDirector.instance.zone_key() == "spire"
		and (MusicDirector.instance._sync as AudioStreamSynchronized).stream_count == 2, "the Spire plays its own two-layer theme")
	# M06 C4: interior look + Spire kit on the unchanged layout.
	_check(spire.look != null and spire.look.interior, "spire uses the interior ZoneLook (no sky, no sun disc)")
	_check(spire.dressing().find_children("*", "CollisionObject3D", true, false).is_empty(),
		"spire dressing adds no collision")
	var beacons_high := true
	var beacon_count := 0
	for child in spire.dressing().get_children():
		if child.name.begins_with("sp_beacon"):
			beacon_count += 1
			beacons_high = beacons_high and (child as Node3D).global_position.y - 0.42 >= 2.05
	_check(beacon_count == 17 and beacons_high, "torches v2 float above head height (%d beacons)" % beacon_count)
	var spire_floor := (spire.world.find_children("*", "StaticBody3D", true, false)[0].get_child(0) as MeshInstance3D).mesh.surface_get_material(0) as ShaderMaterial
	_check(spire_floor != null and int(spire_floor.get_shader_parameter(&"rune_lines")) >= 12,
		"spire floor carries the rune channels (lines, no rings)")

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

	# --- M06 fix: blink anchors stay inside the 10.75 m-deep boss chamber ---
	var anchors_inside := true
	for anchor: Vector3 in spire.blink_anchors():
		if anchor.z < SpireZone.CHAMBER_MIN_Z + 1.2 or anchor.z > SpireZone.CHAMBER_MAX_Z - 1.2 \
				or absf(anchor.x) > SpireZone.WIDTH * 0.5 - 2.2:
			anchors_inside = false
	_check(anchors_inside, "vessel blink anchors lie inside the boss chamber")

	# --- M06 fix: the east ramp actually reaches its platform (top y 1.8) ---
	spire.player.global_position = Vector3(1.2, 0.2, 2.75)
	spire.player.velocity = Vector3.ZERO
	spire.camera_rig._yaw = -PI / 2.0  # camera-forward = +X, up the ramp
	await _wait_frames(3)
	Input.action_press(&"move_forward")
	await _wait_frames(80)
	Input.action_release(&"move_forward")
	var on_platform := spire.player.global_position
	_check(on_platform.y > 1.7 and on_platform.x > 8.5,
		"player walks up the gallery ramp onto the east platform (at %s)" % on_platform)
	spire.camera_rig._yaw = 0.0
	spire.kill_all_enemies()
	await _wait_frames(20)

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
		vessel.take_hit(HitInfo.create(vessel.health.max_health * 0.55, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT,
			spire.player.global_position))
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
		# M06 C6: a legendary weapon shows on the hero (the blade surface swaps).
		var cm := ItemData.new()
		cm.slot = ItemData.Slot.WEAPON
		cm.rarity = ItemData.Rarity.LEGENDARY
		cm.legendary_id = &"cindermaw"
		cm.display_name = "Cindermaw"
		hub2.player.equipment.add_item(cm)
		hub2.player.equipment.equip(cm)
		var blade_mat := hub2.player._rig_mesh.get_surface_override_material(2) if hub2.player._rig_mesh != null else null
		_check(blade_mat != null and blade_mat == hub2.player._cindermaw_mat, "Cindermaw equipped: the hero's blade turns molten")
		hub2.player.equipment.unequip(ItemData.Slot.WEAPON)
		_check(hub2.player._rig_mesh.get_surface_override_material(2) == hub2.player._body_mat, "unequipped: rune steel again")
		_check(UiTheme.item_icon(cm) != null and UiTheme.item_icon(cm).resource_path.ends_with("cindermaw.png"),
			"inventory shows the legendary's own icon")

	SaveGame.wipe()
	print("== %d failures ==" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)

