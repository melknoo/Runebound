extends Node
## Headless smoke test: boots the Combat Lab and exercises every M01 system.
## Run: godot --headless --path . res://tests/smoke_test.tscn
## (a scene, not a --script MainLoop: autoloads must be active)

## A hung run must fail instead of lingering: stale headless runs once kept
## burning CPU for a day, which also slowed the iGPU (shared power budget).
const WATCHDOG_SEC := 420.0  # M13: the dungeons added zone loads (the wrapper's hard limit is 8 min)

var _failures: Array[String] = []
var lab: CombatLab
## M10: the lab's hero, and the same node typed by its class (null while it
## plays the other one). _play_as() swaps the class.
var player: Player
var rb: RunebreakerHero
var mage: ElementalistHero
var druid: DruidHero


## M07b: a scripted input source (what a network peer will be) for the seam test.
class ScriptedInput extends InputSource:
	var dir := Vector3.ZERO
	var queue: Array[StringName] = []
	var held: Array[StringName] = []  # M10: keys held down (auto-fire)

	func poll(intent: PlayerIntent, _player: Player) -> void:
		intent.move_dir = dir
		intent.pressed.append_array(queue)
		intent.held.append_array(held)
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


## M10: the lab's hero plays `class_id` from here on (a fresh hero of that
## class where the old one stood; the whole trainer kit known unless told not).
func _play_as(class_id: StringName, learn_all: bool = true) -> void:
	if lab.player.class_data.id != class_id:
		lab.debug_swap_class(class_id)
	player = lab.player
	rb = player as RunebreakerHero
	mage = player as ElementalistHero
	druid = player as DruidHero
	if learn_all:
		player.debug_learn_all()
	await _wait_frames(2)


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
		var lab_cleave := (lab.player as RunebreakerHero).cleave
		var cleave_len := lab_cleave.startup + lab_cleave.active + lab_cleave.recovery
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
		var swing_cleave := (lab.player as RunebreakerHero).cleave
		var swing_len := swing_cleave.startup + swing_cleave.active + swing_cleave.recovery
		_check(missing.is_empty() and absf(p_anim.anim.get_animation(&"cleave_r").length - swing_len) < 1.5 / 60.0,
			"cleave_r clip length = cleave timing")
		var dodge_len := Player.DODGE_DURATION + Player.DODGE_RECOVERY
		_check(missing.is_empty() and absf(p_anim.anim.get_animation(&"dodge").length - dodge_len) < 1.5 / 60.0,
			"dodge clip = dash + recovery (%.2f s)" % dodge_len)
		_check(p_anim.tree != null, "player rig runs the layered animation tree")
		if p_anim.tree != null:
			p_anim._on_action(&"runic_guard")
			await _wait_frames(2)
			_check(bool(p_anim.tree.get(&"parameters/upper/active")) and p_anim._one_shot == &"",
				"Runic Guard plays on the upper-body layer, legs stay on locomotion")
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
		# M12 families
		["grave_shambler", ["idle", "run", "attack", "stagger", "emerge"], "emerge", GraveShambler.EMERGE_TIME],
		["mourner", ["idle", "glide", "charge", "cast", "stagger"], "charge", Mourner.WINDUP_TIME],
		["cinderbark", ["idle", "run", "slam", "stagger", "dormant", "wake"], "slam", Cinderbark.WINDUP_TIME + Cinderbark.RECOVER_TIME],
		["smoulder_wisp", ["idle", "glide", "charge", "cast", "stagger"], "charge", SmoulderWisp.WINDUP_TIME],
		["ash_jackal", ["idle", "run", "trot", "pounce", "stagger"], "pounce", AshJackal.WINDUP_TIME + AshJackal.LEAP_TIME],
		["carrion_vulture", ["idle", "soar", "charge", "swoop", "takeoff", "stagger"], "charge", CarrionVulture.DIVE_WINDUP],
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

	player = lab.player
	rb = player as RunebreakerHero
	_check(rb != null, "M10: a fresh save plays a RunebreakerHero")

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

	# --- M08 notes: an attack hits exactly what its marker shows ---
	player.health.invulnerable = false
	var marker_wrong: Array[String] = []
	# [id, wind-up, strike, marker ahead, marker radius]
	for spec: Array in [["rusher", &"_start_windup", &"_strike", MeleeRusher.STRIKE_AHEAD, MeleeRusher.STRIKE_RADIUS],
			["brute", &"_start_windup", &"_slam", Brute.SLAM_AHEAD, Brute.SLAM_RADIUS],
			["assassin", &"_start_windup", &"_stab", Assassin.STAB_AHEAD, Assassin.STAB_RADIUS],
			["warden", &"_start_windup", &"_spin", 0.0, HollowWarden.SPIN_RADIUS]]:
		for inside: bool in [false, true]:
			var foe := lab.spawn_by_id(str(spec[0]), player.global_position + Vector3(0, 0, -6.0))
			await _wait_frames(1)
			foe.visual.rotation.y = 0.0  # facing -Z
			foe.call(spec[1])
			var center: Vector3 = foe.global_position + Vector3(0, 0, -float(spec[3]))
			var edge := float(spec[4]) + (-0.25 if inside else EnemyBase.STRIKE_TOLERANCE + 0.15)
			player.global_position = Vector3(center.x + edge, player.global_position.y, center.z)
			player.health.heal_full()
			var before := player.health.current_health
			foe.call(spec[2])
			var was_hit := player.health.current_health < before
			if was_hit != inside:
				marker_wrong.append("%s %s" % [spec[0], "inside" if inside else "outside"])
			foe.queue_free()
			await _wait_frames(1)
	_check(marker_wrong.is_empty(),
		"M08 notes: melee hits land inside the marker and never just outside it (%s)" % ", ".join(marker_wrong))
	# The colossus charge hits inside its drawn lane only.
	var colossus := ZoneBase.make_enemy("colossus")
	lab._spawn_enemy(colossus, player.global_position + Vector3(0, 0, -20.0))
	await _wait_frames(1)
	colossus.set(&"_charge_dir", Vector3(0, 0, 1))
	colossus.visual.rotation.y = PI
	colossus.lock_strike()
	var lane_start := colossus.global_position
	player.global_position = lane_start + Vector3(1.9, 0, 1.0)
	var beside: Array = colossus.heroes_in_lane()
	player.global_position = lane_start + Vector3(1.3, 0, 1.0)
	var in_lane: Array = colossus.heroes_in_lane()
	player.global_position = lane_start + Vector3(0.0, 0, 9.0)
	var ahead_far: Array = colossus.heroes_in_lane()
	_check(beside.is_empty() and in_lane.size() == 1 and ahead_far.is_empty(),
		"the colossus charge hits inside its lane next to its body, not beside the lane or far ahead")
	colossus.queue_free()
	player.global_position = start_pos
	player.health.heal_full()
	await _wait_frames(2)

	# --- M08 notes: dodge input is not lost ---
	player._cooldowns[&"dodge"] = 0.05  # just used
	player._try_or_buffer(&"dodge")
	await _wait_frames(8)
	_check(player.state == Player.State.DODGE or player._cooldowns.get(&"dodge", 0.0) > 0.3,
		"a dodge pressed during the cooldown goes off when it ends (buffered from MOVE)")
	await _wait_frames(30)
	player._cooldowns[&"dodge"] = 0.0
	var threat := lab.spawn_by_id("rusher", player.global_position + player.facing() * 2.0)
	await _wait_frames(1)
	threat.set_physics_process(false)
	var away_dir: Vector3 = player._dodge_away_dir()
	var to_threat := threat.global_position - player.global_position
	to_threat.y = 0.0
	_check(away_dir.dot(to_threat.normalized()) < -0.9, "a dodge without a direction leaves the nearby enemy")
	threat.queue_free()
	player.global_position = start_pos
	player.velocity = Vector3.ZERO
	player.reset_cooldowns()
	await _wait_frames(2)  # the camera follows in _process
	player._face_aim_instant()  # facing and camera agree again for the melee checks
	var rusher := MeleeRusher.new()
	lab.enemies_root.add_child(rusher)
	rusher.player = player
	rusher.global_position = player.global_position + player.facing() * 1.3
	await _wait_frames(2)
	var rusher_hp := rusher.health.current_health
	_check(rb.try_melee(), "melee starts")
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
	# --- M07b / M10: one ability at the start, the rest are learned; two classes ---
	var cls := ClassData.load_by_id(&"runebreaker")
	_check(cls != null and cls.abilities.size() == 10 and cls.basic_attack == &"rune_cleave"
		and cls.starting_abilities.size() == 1 and cls.starting_abilities[0] == &"rune_cleave"
		and cls.trainer_abilities().size() == 6 and cls.trainer_abilities()[0].id == &"earthbreaker"
		and cls.trainer_abilities()[5].id == &"warding_rune" and cls.ability(&"ember_lance") == null
		and cls.role == "Tank" and is_equal_approx(cls.threat_mult, 2.0) and is_equal_approx(cls.base_max_hp, 120.0)
		and cls.ability(&"lodestone_rune").unlock == AbilityData.Unlock.TOME,
		"ClassData: the Runebreaker tanks (120 health, threat x2) with Rune Cleave on LMB and a pool of 9: 6 from the trainer, 1 from the tome")
	var mage_cls := ClassData.load_by_id(&"elementalist")
	_check(mage_cls != null and mage_cls.basic_attack == &"rune_bolt" and mage_cls.trainer_abilities().size() == 8
		and mage_cls.trainer_abilities()[0].id == &"ember_lance" and mage_cls.ability(&"fracture_rune") != null
		and (mage_cls.hero_script as Script).get_global_name() == &"ElementalistHero" and mage_cls.resource_label == "Aether",
		"ClassData: the Elementalist casts Rune Bolt on LMB, builds Aether and trains the four spells the Runebreaker gave away")
	_check(ClassData.all().size() == 3 and player.class_data == cls and player.ability(&"earthbreaker") == rb.earthbreaker,
		"three playable classes (M11: the druid); the lab hero carries its ClassData and typed ability fields")
	var fresh_names := lab.hud.ability_names()
	_check(fresh_names.size() == 2 and fresh_names[0] == "Rune Cleave" and fresh_names[1] == "Dodge"
		and player.loadout.size() == Player.LOADOUT_SIZE and player.loadout.count(&"") == 4,
		"fresh character: Rune Cleave (LMB) and Dodge, four empty slots (%s)" % [fresh_names])
	_check(player.knows(&"rune_cleave") and player.knows(&"dodge") and not player.knows(&"ember_lance")
		and not player.knows(&"earthbreaker") and not player.knows(&"runic_guard"),
		"knows(): start kit and dodge yes, trainer and talent abilities no")
	player.reset_cooldowns()
	player.resonance = 100.0
	_check(not rb.try_earthbreaker() and not rb.try_runic_guard() and not rb.try_resonance_burst()
		and not player.try_ability(&"ember_lance") and player.state == Player.State.MOVE,
		"unknown abilities refuse to cast; another class's spells are not in the kit")
	_check(not player._try_action(&"earthbreaker") and player._buffered_action == &"",
		"input dispatch ignores unknown abilities and never buffers them")
	_check(not player.learn_ability(&"nope") and not player.learn_ability(&"runic_guard") and not player.learn_ability(&"rune_cleave")
		and not player.learn_ability(&"ember_lance"),
		"learn_ability rejects unknown ids, talent abilities, known ones and another class's")
	_check(player.learn_ability(&"earthbreaker") and player.knows(&"earthbreaker") and not player.learn_ability(&"earthbreaker"),
		"learn_ability adds a trainer ability once")
	_check(lab.hud.ability_names().size() == 3 and lab.hud.ability_names().has("Earthbreaker")
		and player.loadout[0] == &"earthbreaker" and lab.hud.slot_ability(&"slot0") == &"earthbreaker"
		and player.key_label_for(&"earthbreaker") == "RMB",
		"M10: a learned ability takes the first free slot (RMB) and shows on the HUD")
	var offers := TrainerUI.offers(player)
	_check(offers.size() == 6 and offers[0].id == &"rune_wall" and offers[5].id == &"earthbreaker"
		and TrainerUI.deny_reason(player, offers[5]) == "Learned" and TrainerUI.deny_reason(player, offers[0]) == "Requires level 3",
		"the Runebreaker's trainer offers its 6 abilities, Rune Wall next (level 3), the learned ones last")
	# Debug fresh start (key 9) resets abilities, the loadout and gold too.
	player.add_gold(70)
	lab.wipe_save()
	_check(player.known_abilities.size() == 1 and player.knows(&"rune_cleave") and not player.knows(&"earthbreaker")
		and player.gold == 0 and lab.hud.ability_names().size() == 2 and player.loadout.count(&"") == 4,
		"debug fresh start returns to the one-ability kit, empty slots and no gold")
	player.resonance = 0.0
	player.resonance_changed.emit(0.0, player.max_resource())

	# --- M10: the Elementalist's trainer: level, gold, a purchase, the loadout slot ---
	await _play_as(&"elementalist", false)
	_check(mage != null and lab.hud.ability_names() == (["Rune Bolt", "Dodge"] as Array[String])
		and lab.hero_ui.player == player and lab.trainer_ui.player == player,
		"debug_swap_class: the lab hero turns into a fresh Elementalist and every window follows it")
	var m_offers := TrainerUI.offers(player)
	_check(m_offers.size() == 8 and m_offers[0].id == &"ember_lance" and m_offers[7].id == &"ember_fall",
		"the Elementalist's trainer offers its 8 spells, Ember Lance first, Ember Fall last")
	var ember_data := player.ability(&"ember_lance")
	_check(TrainerUI.deny_reason(player, ember_data) == "Requires level 2", "trainer refuses below the level requirement")
	var saved_level := player.progression.level
	player.progression.level = 2
	player.spend_gold(player.gold)
	_check(TrainerUI.deny_reason(player, ember_data) == "Need 50 more gold" and not lab.trainer_ui.try_buy(ember_data),
		"trainer refuses without the gold")
	player.add_gold(50)
	_check(TrainerUI.deny_reason(player, ember_data) == "" and lab.trainer_ui.try_buy(ember_data)
		and player.gold == 0 and player.knows(&"ember_lance") and player.loadout[0] == &"ember_lance"
		and lab.hud.ability_names().size() == 3,
		"buying at the trainer spends the gold, teaches the ability and slots it (RMB)")
	_check(TrainerUI.deny_reason(player, ember_data) == "Learned" and not lab.trainer_ui.try_buy(ember_data),
		"an ability is bought once")
	player.progression.level = saved_level
	var sigrun := TrainerNpc.new()
	sigrun.teaches_class = &"runebreaker"
	_check(not sigrun.teaches(player) and sigrun.referral_line(player).contains("Maren"),
		"a trainer of another class sends the hero to its own (Sigrun -> Maren)")
	sigrun.free()
	await _play_as(&"runebreaker", false)
	player.debug_learn_all()
	_check(lab.hud.ability_names().size() == 6 and player.loadout == ([&"earthbreaker", &"rune_wall", &"rune_challenge",
		&"warden_leap"] as Array[StringName]) and player.knows(&"warding_rune") and not player.loadout.has(&"warding_rune"),
		"debug_learn_all: the trainer kit is known, the first four fill the slots, the rest waits in the pool")

	# --- M10 loadout: 4 free slots, swaps out of combat only, only slotted abilities fire ---
	player._last_combat_msec = -1000000
	player.restore_loadout([&"earthbreaker", &"", &"", &""])
	player.progression.ranks[&"runic_guard"] = 1
	player.progression.ranks[&"resonance_burst"] = 1
	player.progression._changed()
	_check(player.loadout == ([&"earthbreaker", &"runic_guard", &"resonance_burst", &""] as Array[StringName]),
		"talent abilities join the free slots in class order (%s)" % str(player.loadout))
	_check(player.set_loadout_slot(3, &"earthbreaker") == "" and player.loadout[3] == &"earthbreaker" and player.loadout[0] == &""
		and player.slot_of(&"earthbreaker") == 3 and player.key_label_for(&"earthbreaker") == "3",
		"putting a slotted ability into another slot moves it there")
	_check(player.set_loadout_slot(0, &"rune_cleave") != "" and player.set_loadout_slot(0, &"ember_lance") != ""
		and player.set_loadout_slot(7, &"earthbreaker") != "", "the basic attack, unknown abilities and bad slots are refused")
	player.mark_combat()
	_check(player.set_loadout_slot(0, &"runic_guard") == "Not in combat" and player.loadout[1] == &"runic_guard",
		"the loadout is locked in combat (the sprint's 3 s rule)")
	player._last_combat_msec = -1000000
	lab.hero_ui.open_tab(HeroUI.Tab.LOADOUT)
	_check(lab.hero_ui.visible and lab.hero_ui.loadout_tab.visible and player.input_locked, "K opens the abilities tab")
	_check(lab.hero_ui.loadout_tab.clear_slot(1) and player.loadout[1] == &"" and not player.can_use(&"runic_guard")
		and lab.hero_ui.loadout_tab.pick(&"runic_guard") and player.loadout[0] == &"runic_guard",
		"the tab clears a slot, and a clicked ability takes the first free one")
	lab.hero_ui.close()
	player.reset_cooldowns()
	player.resonance = 100.0
	var slot_probe := ScriptedInput.new()
	var slot_local := player.input_source
	player.input_source = slot_probe
	player.set_loadout_slot(0, &"")
	slot_probe.queue.append(&"runic_guard")
	await _wait_frames(2)
	var fired_unslotted := player.barrier > 0.0
	player.set_loadout_slot(1, &"runic_guard")
	player._last_combat_msec = -1000000
	slot_probe.queue.append(&"runic_guard")
	await _wait_frames(2)
	player.input_source = slot_local
	_check(not fired_unslotted and player.barrier > 0.0, "a learned but unslotted ability never fires; slotted, it does")
	player.barrier = 0.0
	Input.action_press(&"ability_q")
	var key_intent := PlayerIntent.new()
	LocalInputSource.new().poll(key_intent, player)
	Input.action_release(&"ability_q")
	_check(key_intent.held.has(player.loadout[1]) and InputSetup.slot_label(1) == "1" and InputSetup.slot_label(0) == "RMB",
		"key 1 (ability_q) drives slot 2; the keys belong to slots, not abilities")
	var dict_loadout: Array = SaveGame.character_dict(player)["loadout"]
	_check(dict_loadout.size() == 4 and str(dict_loadout[1]) == "runic_guard", "the loadout is part of the character's save")
	player.progression.ranks.clear()
	player.progression._changed()
	_check(not player.loadout.has(&"runic_guard") and not player.loadout.has(&"resonance_burst"),
		"forgetting a talent ability empties its slot")
	player.restore_loadout([])
	player.resonance = 0.0
	player.resonance_changed.emit(0.0, player.max_resource())

	# --- M07b gold: kills pay it, it is picked up by walking over it ---	# --- M07b gold: kills pay it, it is picked up by walking over it ---
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
	_check(sheet_rows.size() == 8 and sheet_rows[0]["id"] == &"rune_cleave" and sheet_rows[0]["key"] == "LMB"
		and sheet_rows[1]["id"] == &"earthbreaker" and sheet_rows[1]["key"] == "RMB" and sheet_rows[6]["key"] == "-",
		"character sheet lists the known abilities in class order with their slot keys")
	var d_pct := player.stat(&"damage_pct")
	var c_pct := player.stat(&"crit_pct")
	var manual_avg := 24.0 * (1.0 + d_pct / 100.0) * (1.0 + (0.08 + c_pct / 100.0) * 0.6)
	_check(absf(StatSheet.expected_damage(player, rb.cleave) - manual_avg) < 0.001,
		"StatSheet's average Rune Cleave damage matches the hit formula (%.1f)" % manual_avg)
	var names_ok := true
	for def: Dictionary in AffixPool.DEFS:
		names_ok = names_ok and StatSheet.STAT_NAMES.has(def["stat"])
	_check(names_ok, "every affix stat has a display name")
	var eb_line := lab.hud._stats_line(&"earthbreaker", rb.earthbreaker)
	_check(eb_line.begins_with("Damage") and eb_line.contains("Costs 40 Resonance"),
		"ability tooltip leads with the damage and names the class resource (%s)" % eb_line)

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
	var atk_hit := player.roll_ability_hit(rb.cleave)
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
	var buddy := Player.create()
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
	_check(Progression.tree_for(&"runebreaker").size() == 24 and Progression.tree_for(&"elementalist").size() == 24
		and Progression.tree_for(&"druid").size() == 24 and Progression.tree_for(&"nope").is_empty() and player.progression.class_id == &"runebreaker"
		and Progression.talent(&"molten_core").class_id == &"runebreaker" and Progression.talent(&"split_lance").class_id == &"elementalist",
		"M10: one talent tree per class (24 nodes each); Molten Core stays with the tank, the spells' talents moved")
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
		"an unknown class never rolls class affixes or legendaries (elite drops downgrade to rare)")
	var own_legendary := false
	var tank_rolls_spell_affix := false
	for i in 300:  # 5 % legendaries from elites: 300 rolls miss one with 2e-7
		var tank_item := ItemGenerator.generate(2, &"runebreaker")
		if tank_item.legendary_id != &"":
			own_legendary = true
		for affix in tank_item.affixes:
			if affix["id"] in [&"ember_pierce", &"chain_jumps", &"storm_cd_pct", &"aether_pct"]:
				tank_rolls_spell_affix = true
	_check(own_legendary and not tank_rolls_spell_affix and AffixPool.legendaries_for(&"runebreaker").size() == 3
		and AffixPool.legendaries_for(&"elementalist").size() == 4
		and AffixPool.legendaries_for(&"druid").size() == 3
		and AffixPool.legendaries_for(&"runebreaker").size() + AffixPool.legendaries_for(&"elementalist").size()
			+ AffixPool.legendaries_for(&"druid").size() == AffixPool.LEGENDARIES.size(),
		"M10/M11: legendaries and spell affixes follow their ability to its class (tank 3, Elementalist 4, druid 3)")
	var staff_named := false
	for i in 60:
		var mage_item := ItemGenerator.generate(0, &"elementalist")
		if mage_item.slot == ItemData.Slot.WEAPON and (mage_item.display_name.contains("Staff") or mage_item.display_name.contains("Wand")
				or mage_item.display_name.contains("Rod") or mage_item.display_name.contains("Scepter") or mage_item.display_name.contains("Spellbrand")):
			staff_named = true
	_check(staff_named, "an Elementalist's weapons are staves and wands, not blades")

	# --- the playtest checklist (J) ---
	var ids := PlaytestLog.item_ids()
	var unique := {}
	for id in ids:
		unique[id] = true
	var groups_filled := true
	for g: Dictionary in PlaytestLog.groups():
		if (g.get("items", []) as Array).is_empty():
			groups_filled = false
	_check(ids.size() >= 30 and unique.size() == ids.size() and groups_filled,
		"the playtest checklist loads (%d points, unique ids, no empty group)" % ids.size())
	var real_path := PlaytestLog.state_path
	PlaytestLog.state_path = "user://playtest_smoke.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlaytestLog.state_path))
	PlaytestLog.reload()
	PlaytestLog.set_state(ids[0], PlaytestLog.OK)
	PlaytestLog.set_state(ids[1], PlaytestLog.PROBLEM, "zu schnell")
	PlaytestLog.reload()
	var tally := PlaytestLog.counts()
	_check(PlaytestLog.state_of(ids[0]) == PlaytestLog.OK and PlaytestLog.note_of(ids[1]) == "zu schnell"
		and int(tally["ok"]) == 1 and int(tally["problem"]) == 1 and int(tally["open"]) == ids.size() - 2
		and PlaytestLog.next_state(PlaytestLog.PROBLEM) == PlaytestLog.OPEN,
		"playtest ticks and notes survive a reload, and the counts add up (%s %s %s)" % [PlaytestLog.state_of(ids[0]),
			PlaytestLog.note_of(ids[1]), str(tally)])
	lab.playtest_ui.open()
	var rows_all := lab.playtest_ui.row_count()
	var locked := player.input_locked
	lab.playtest_ui._only_open.button_pressed = true
	var rows_open := lab.playtest_ui.row_count()
	lab.playtest_ui.close()
	_check(locked and not player.input_locked and rows_all == ids.size() and rows_open == ids.size() - 2
		and InputMap.has_action(&"playtest_toggle"),
		"J opens the playtest log (all rows, 'nur offene' hides the ticked ones) and locks input while open")
	lab.playtest_ui._only_open.button_pressed = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PlaytestLog.state_path))
	PlaytestLog.state_path = real_path
	PlaytestLog.reload()

	# --- M08 notes: sprint on Shift, out of combat only ---
	player._last_combat_msec = -1000000
	player.state = Player.State.MOVE
	player.intent.move_dir = Vector3(0, 0, -1)
	player.intent.sprint = true
	var sprint_free := player.is_sprinting()
	player.mark_combat()
	var sprint_fight := player.is_sprinting()
	player.intent.clear()
	_check(sprint_free and not sprint_fight and not player.intent.sprint and InputMap.has_action(&"sprint"),
		"Shift sprints out of combat, not right after a hit, and the intent resets each tick")
	player._last_combat_msec = -1000000

	# --- M08 notes: gear comes off again ---
	var gear := player.equipment
	var off_item := ItemGenerator.generate(0)
	off_item.slot = ItemData.Slot.RING
	gear.add_item(off_item)
	gear.equip(off_item)
	var came_off := gear.unequip(ItemData.Slot.RING)
	var in_bag: bool = gear.inventory.has(off_item) and gear.equipped.get(ItemData.Slot.RING) == null
	gear.equip(off_item)
	var filler: Array[ItemData] = []
	while not gear.is_full():
		var f := ItemGenerator.generate(0)
		filler.append(f)
		gear.add_item(f)
	var refused: bool = not gear.unequip(ItemData.Slot.RING) and gear.equipped.get(ItemData.Slot.RING) == off_item
	for f in filler:
		gear.discard(f)
	gear.unequip(ItemData.Slot.RING)
	gear.discard(off_item)
	_check(came_off and in_bag and refused and not gear.unequip(ItemData.Slot.RING),
		"unequip puts the item in the bag, and refuses (item stays on) with a full bag or an empty slot")

	# --- M08 notes: portal titles only up close, at body size ---
	var title_probe := Portal.new()
	title_probe.label_text = "PROBE GATE"
	lab.world.add_child(title_probe)
	title_probe.global_position = Vector3(0, 0, -40)
	var title_label: Label3D = title_probe._label
	_check(title_label.font_size == UiTheme.BODY and is_equal_approx(title_label.visibility_range_end, 22.0)
		and title_label.visibility_range_end_margin > 0.0,
		"portal titles use the body font size and hide beyond 22 m")
	title_probe.queue_free()

	# --- M08 notes: fewer drops, rare items much rarer ---
	var rarity_counts: Array = []
	for bias in 3:
		var counts := [0, 0, 0, 0]  # common, magic, rare, legendary
		for i in 6000:
			counts[int(ItemGenerator._roll_rarity(bias))] += 1
		rarity_counts.append(counts)
	var trash_c: Array = rarity_counts[0]
	var brute_c: Array = rarity_counts[1]
	var elite_c: Array = rarity_counts[2]
	_check(int(trash_c[3]) <= 60 and int(trash_c[2]) >= 240 and int(trash_c[2]) <= 500
		and int(brute_c[3]) >= 20 and int(brute_c[3]) <= 120 and int(brute_c[2]) >= 850 and int(brute_c[2]) <= 1200
		and int(elite_c[3]) >= 200 and int(elite_c[3]) <= 420 and int(elite_c[0]) + int(elite_c[1]) == 0,
		"loot tuning: legendaries 0.3 / 1 / 5 %%, rares 6 / 17 / 95 %% (6000 rolls: %s %s %s)" % [trash_c, brute_c, elite_c])
	var drops_of := func(kind: StringName) -> int:
		var n := 0
		for i in 5000:
			if ItemGenerator.kill_drops(kind):
				n += 1
		return n
	var trash_drops: int = drops_of.call(&"trash")
	var brute_drops: int = drops_of.call(&"brute")
	var elite_drops: int = drops_of.call(&"elite")
	_check(trash_drops > 300 and trash_drops < 520 and brute_drops > 1350 and brute_drops < 1650
		and elite_drops > 2800 and elite_drops < 3200,
		"kill drop chances 8 / 30 / 60 %% (5000 kills: %d %d %d)" % [trash_drops, brute_drops, elite_drops])

	# --- M06 B5: HUD v2 look ---
	var hud_root := lab.hud.get_child(0) as Control
	var body_font := UiTheme.font()
	_check(hud_root.theme == UiTheme.theme() and body_font != null
		and body_font.antialiasing == TextServer.FONT_ANTIALIASING_NONE,
		"HUD uses the pixel UI theme (Pixelify Sans, no antialiasing)")
	var icons_ok := true
	for slot_key: StringName in Hud.SLOT_KEYS:
		if lab.hud.slot_ability(slot_key) != &"":
			icons_ok = icons_ok and (lab.hud._slots[slot_key]["icon"] as TextureRect).texture != null
	for icon_id: StringName in [&"rune_bolt", &"ember_lance", &"storm_step", &"chain_spark", &"fracture_rune", &"earthbreaker"]:
		icons_ok = icons_ok and Hud.icon(icon_id) != null
	_check(icons_ok, "every filled slot shows its pixel icon; every class ability has one")
	var plate := Label3D.new()
	UiTheme.label3d(plate)
	_check(plate.fixed_size and plate.font == body_font and plate.font_size == UiTheme.BODY,
		"world labels: pixel font at a fixed screen size (1 font px = 1 screen px)")
	plate.free()
	var hud_names := lab.hud.ability_names()
	_check(hud_names.size() == 6 and hud_names.has("Earthbreaker") and hud_names.has("Rune Wall") and hud_names.has("Dodge"),
		"HUD shows the slotted abilities by name (%s)" % str(hud_names))
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
	_check(rb.try_earthbreaker(), "earthbreaker starts with resonance")
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
	_check(not rb.try_earthbreaker(), "earthbreaker refused without Resonance")

	# ===== M10: the Elementalist's spells (the lab hero turns into one) =====
	await _play_as(&"elementalist")
	_check(mage != null and lab.hud.ability_names().size() == 6 and player.loadout.count(&"") == 0
		and player.health.max_health < 100.0,
		"the Elementalist knows its trainer kit: Rune Bolt, four slotted spells, Dodge; frailer than the tank")
	var m_anim := player.animator
	var mage_clips_ok := m_anim != null and player.class_data.rig_path.ends_with("elementalist.glb")
	if m_anim != null:
		for clip: StringName in [&"idle", &"run", &"dodge", &"bolt", &"ember", &"storm_step", &"chain_spark",
				&"fracture_rune", &"frost_nova", &"flame_wall", &"ball_lightning", &"ember_fall", &"flinch"]:
			mage_clips_ok = mage_clips_ok and m_anim.anim.has_animation(clip)
		var dodge_clip := Player.DODGE_DURATION + Player.DODGE_RECOVERY
		mage_clips_ok = mage_clips_ok and absf(m_anim.anim.get_animation(&"dodge").length - dodge_clip) < 1.5 / 60.0
	_check(mage_clips_ok, "M10: the Elementalist has its own rig with a clip for every spell (dodge at gameplay timing)")

	# --- rune bolt (the Elementalist's LMB, auto-fire while held) ---
	lab.kill_all_enemies()
	await _wait_frames(20)
	var bolt_target := MeleeRusher.new()
	lab.enemies_root.add_child(bolt_target)
	bolt_target.player = player
	var bolt_aim := player.aim_direction()
	bolt_target.global_position = player.global_position + bolt_aim * 6.0 - Vector3(0, bolt_aim.y * 6.0, 0)
	await _wait_frames(2)
	bolt_target.set_physics_process(false)
	var bolt_hp := bolt_target.health.current_health
	player.resonance = 0.0
	_check(player.basic_attack() == &"rune_bolt" and player.key_label_for(&"rune_bolt") == "LMB" and player.can_use(&"rune_bolt"),
		"the Elementalist's basic attack is Rune Bolt on LMB")
	var bolt_probe := ScriptedInput.new()
	var bolt_local := player.input_source
	player.input_source = bolt_probe
	bolt_probe.held.append(&"rune_bolt")
	await _wait_frames(45)
	bolt_probe.held.clear()
	player.input_source = bolt_local
	_check(bolt_target.health.current_health < bolt_hp - mage.rune_bolt.damage * 1.5,
		"holding LMB keeps casting Rune Bolts (%.0f damage)" % (bolt_hp - bolt_target.health.current_health))
	_check(player.resonance > 0.0 and player.state == Player.State.MOVE, "rune bolt hits build Aether; casting never roots")
	bolt_target.queue_free()
	await _wait_frames(2)

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
	_check(mage.try_ember(), "ember lance casts")
	_check(not mage.try_ember(), "ember lance respects cooldown")
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
	var stepped := mage.try_storm_step()
	Input.action_release(&"move_back")
	_check(stepped, "storm step starts")
	await _wait_frames(20)
	_check(player.state == Player.State.MOVE, "storm step recovers to MOVE")
	_check(player.global_position.z > dash_from.z + 3.0, "held movement input steers the dash")
	_check(not mage.try_storm_step(), "storm step respects cooldown")
	_check(player.collision_mask == 0b1000101, "storm step restores collision mask")

	# Priority 3: no input, no target -> camera-directed dash zaps the path.
	player.reset_cooldowns()
	player.global_position = dash_from
	player.velocity = Vector3.ZERO
	await _wait_frames(2)
	_check(mage.try_storm_step(), "camera dash starts")
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
	_check(mage.try_storm_step(), "gap-close dash starts")
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
	_check(mage.try_storm_step(), "cancel test: dash starts")
	await _wait_frames(2)
	_check(player.state == Player.State.STORM_STEP, "cancel test: still mid-dash")
	_check(player.try_dodge(), "dodge cancels a running storm step")
	_check(player.collision_mask == 0b1000101, "dodge-cancelled storm step restores collision mask")
	_check(cancel_victim.status.has_shock(), "dodge-cancelled storm step still zaps its path")
	await _wait_frames(25)
	_check(player.state == Player.State.MOVE, "dodge after storm step returns to MOVE")

	# --- chain spark ---
	lab.kill_all_enemies()
	await _wait_frames(20)
	player.reset_cooldowns()
	_check(not mage.try_chain_spark(), "chain spark refused without any target")
	var chain_targets: Array[EnemyBase] = []
	for i in 3:
		var e := MeleeRusher.new()
		lab.enemies_root.add_child(e)
		e.player = player
		e.global_position = player.global_position + player.facing() * (4.0 + i * 3.0)
		chain_targets.append(e)
	await _wait_frames(2)
	player.reset_cooldowns()
	_check(mage.try_chain_spark(), "chain spark casts with targets ahead")
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
	_check(mage.try_fracture_rune(), "fracture rune places")
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

	# ===== M10 phase 3: the Elementalist's own spells and the Frost / Ember talents =====
	lab.kill_all_enemies()
	await _wait_frames(20)
	player.global_position = Vector3(0, 0.2, 6)
	player.velocity = Vector3.ZERO
	player.reset_cooldowns()
	var spawn_still := func(at: Vector3) -> MeleeRusher:
		var e := MeleeRusher.new()
		lab.enemies_root.add_child(e)
		e.player = player
		e.global_position = at
		return e
	# Frost Nova: spends 25 Aether, hits and Chills everything within 5 m; Deep Freeze roots.
	var nova_a: MeleeRusher = spawn_still.call(player.global_position + Vector3(2.5, 0.2, 0))
	var nova_b: MeleeRusher = spawn_still.call(player.global_position + Vector3(-3.5, 0.2, 1))
	await _wait_frames(2)
	nova_a.set_physics_process(false)
	nova_b.set_physics_process(false)
	player.resonance = 10.0
	_check(not mage.try_frost_nova(), "Frost Nova needs 25 Aether")
	player.resonance = 40.0
	player.progression.ranks[&"deep_freeze"] = 1
	player.progression._changed()
	var nova_hp := nova_a.health.current_health
	_check(mage.try_frost_nova() and is_equal_approx(player.resonance, 15.0), "Frost Nova spends 25 Aether")
	_check(nova_a.health.current_health < nova_hp and nova_a.status.has_chill() and nova_b.status.has_chill()
		and nova_a.status.is_rooted() and is_zero_approx(nova_a.status.speed_multiplier()),
		"Frost Nova hits and Chills everything within 5 m; Deep Freeze roots them in place")
	player.progression.ranks.clear()
	player.progression._changed()
	# Cold Snap: a longer Chill.
	player.progression.ranks[&"cold_snap"] = 2
	player.progression._changed()
	nova_a.status.clear_all()
	var snap_hit := player.roll_ability_hit(mage.frost_nova)
	nova_a.take_hit(snap_hit)
	_check(nova_a.status._chill_left > StatusEffectComponent.CHILL_DURATION + 0.9, "Cold Snap: the Chill lasts 1 s longer at 2 ranks")
	player.progression.ranks.clear()
	player.progression._changed()
	# Absolute Zero: the third Chill within 6 s freezes solid.
	player.progression.ranks[&"absolute_zero"] = 1
	player.progression._changed()
	nova_b.status.clear_all()
	nova_b.health.max_health = 1.0e5  # three frost hits must not kill it
	nova_b.health.heal_full()
	for i in 3:
		nova_b.take_hit(player.roll_ability_hit(mage.frost_nova))
	_check(nova_b.status.is_rooted(), "Absolute Zero: a third Chill within 6 s freezes the enemy solid")
	player.progression.ranks.clear()
	player.progression._changed()
	lab.kill_all_enemies()
	await _wait_frames(20)
	# Flame Wall: a burning line at the aim; what stands in it burns.
	player.reset_cooldowns()
	var wall_exclude: Array[RID] = [player.get_rid()]
	var wall_aim := lab.camera_rig.get_aim_point(wall_exclude)
	var wall_off := Vector3(wall_aim.x - player.global_position.x, 0.0, wall_aim.z - player.global_position.z).limit_length(12.0)
	var burner_t: MeleeRusher = spawn_still.call(player.global_position + wall_off + Vector3(0, 0.2, 0))
	await _wait_frames(2)
	burner_t.set_physics_process(false)
	var burner_hp := burner_t.health.current_health
	_check(mage.try_flame_wall(), "Flame Wall raises a wall at the aim")
	await _wait_frames(40)
	var wall_node: FlameWall = null
	for child in lab.get_children():
		if child is FlameWall:
			wall_node = child
	_check(wall_node != null and burner_t.health.current_health < burner_hp and burner_t.status.has_burn(),
		"Flame Wall burns an enemy standing in it")
	lab.kill_all_enemies()
	await _wait_frames(20)
	# Ball Lightning: a slow orb that zaps and Shocks what it passes.
	player.reset_cooldowns()
	var orb_dir := player.aim_direction()
	orb_dir.y = 0.0
	var orb_t: MeleeRusher = spawn_still.call(player.global_position + orb_dir.normalized() * 5.0 + Vector3(1.0, 0.2, 0))
	await _wait_frames(2)
	orb_t.set_physics_process(false)
	var orb_hp := orb_t.health.current_health
	_check(mage.try_ball_lightning(), "Ball Lightning sends its orb")
	await _wait_frames(80)
	_check(orb_t.health.current_health < orb_hp and orb_t.status.has_shock(), "the orb zaps and Shocks an enemy it passes")
	for child in lab.get_children():  # the wall and the orb from above would burn and zap the next dummy
		if child is FlameWall or child is BallLightning:
			child.queue_free()
	lab.kill_all_enemies()
	await _wait_frames(20)
	# Ember Fall: 40 Aether, a telegraphed meteor on the aim; Cinderfall burns the ground after.
	player.reset_cooldowns()
	player.resonance = 50.0
	player.progression.ranks[&"cinderfall"] = 1
	player.progression._changed()
	var fall_exclude: Array[RID] = [player.get_rid()]
	var fall_aim := lab.camera_rig.get_aim_point(fall_exclude)
	var fall_off := Vector3(fall_aim.x - player.global_position.x, 0.0, fall_aim.z - player.global_position.z).limit_length(16.0)
	var meteor_t: MeleeRusher = spawn_still.call(player.global_position + fall_off + Vector3(0.6, 0.2, 0))
	await _wait_frames(2)
	meteor_t.set_physics_process(false)
	meteor_t.health.max_health = 1.0e4
	meteor_t.health.heal_full()
	var meteor_hp := meteor_t.health.current_health
	_check(mage.try_ember_fall() and is_equal_approx(player.resonance, 10.0) and player.state == Player.State.CAST,
		"Ember Fall spends 40 Aether and winds up")
	await _wait_frames(30)
	_check(meteor_t.health.current_health == meteor_hp, "the meteor has not landed during its fall")
	await _wait_frames(50)
	var after_rock := meteor_t.health.current_health
	_check(after_rock < meteor_hp and meteor_t.status.has_burn(), "Ember Fall lands on the aim: damage and Burn")
	await _wait_frames(70)
	_check(meteor_t.health.current_health < after_rock - 0.01, "Cinderfall: the ground keeps burning after the rock")
	player.progression.ranks.clear()
	player.progression._changed()
	lab.kill_all_enemies()
	await _wait_frames(20)
	# Echo Rune: the Fracture Rune detonates a second time at half damage.
	player.reset_cooldowns()
	player.progression.ranks[&"echo_rune"] = 1
	player.progression._changed()
	var echo_t: MeleeRusher = spawn_still.call(player.global_position + player.facing() * 5.0)
	await _wait_frames(2)
	echo_t.set_physics_process(false)
	echo_t.health.max_health = 1.0e5
	echo_t.health.heal_full()
	var echo_hp := echo_t.health.current_health
	mage.try_fracture_rune()
	await _wait_frames(80)
	var after_first := echo_t.health.current_health
	await _wait_frames(45)
	_check(after_first < echo_hp and echo_t.health.current_health < after_first, "Echo Rune: the rune bursts twice")
	player.progression.ranks.clear()
	player.progression._changed()
	lab.kill_all_enemies()
	await _wait_frames(20)
	player.global_position = Vector3(0, 0.2, 6)
	player.velocity = Vector3.ZERO

	# ===== M11: the druid - Sap, the heal target, heals on allies, heal threat =====
	await _play_as(&"druid")
	lab.kill_all_enemies()
	await _wait_frames(20)
	player.global_position = Vector3(0, 0.2, 6)
	player.velocity = Vector3.ZERO
	player.reset_cooldowns()
	var d_anim := player.animator
	var druid_clips_ok := d_anim != null and player.class_data.rig_path.ends_with("druid.glb")
	if d_anim != null:
		for clip: StringName in [&"idle", &"run", &"dodge", &"thorn", &"mend", &"bark", &"regrowth", &"root_grasp",
				&"grove", &"thornfield", &"totem", &"bloom", &"flinch"]:
			druid_clips_ok = druid_clips_ok and d_anim.anim.has_animation(clip)
		druid_clips_ok = druid_clips_ok and absf(d_anim.anim.get_animation(&"dodge").length
			- (Player.DODGE_DURATION + Player.DODGE_RECOVERY)) < 1.5 / 60.0
	_check(druid_clips_ok, "M11: the druid has its own rig with a clip for every ability (dodge at gameplay timing)")
	_check(druid != null and player.class_data.role == "Healer" and player.basic_attack() == &"thorn_volley"
		and player.can_use(&"mending_bloom") and is_equal_approx(player.resonance, player.max_resource()),
		"M11: the druid starts with Thorn Volley and Mending Bloom; its Sap starts full")
	# Sap: a pool that refills only in a fight (no regeneration out of combat)
	player.resonance = 50.0
	player._last_combat_msec = -1000000
	await _wait_frames(30)
	_check(is_equal_approx(player.resonance, 50.0), "Sap does not refill out of combat")
	player.mark_combat()
	await _wait_frames(30)
	_check(player.resonance > 51.0 and player.resonance < 54.0, "Sap refills in a fight (%.1f after 0.5 s)" % player.resonance)
	# alone: the heal goes to the druid itself
	player.resonance = 100.0
	player.health.current_health = player.health.max_health * 0.5
	var self_hp := player.health.current_health
	_check(druid.try_mending_bloom() and absf(player.health.current_health - self_hp - druid.mending_bloom.heal) < 0.01
		and absf(player.resonance - 86.0) < 0.5,
		"alone, Mending Bloom heals the druid itself (+%.0f) for 14 Sap" % (player.health.current_health - self_hp))
	player.reset_cooldowns()
	player.resonance = 5.0
	_check(not druid.try_mending_bloom(), "without the Sap for it the heal is refused")
	# with allies: the most wounded in reach, the crosshair first
	var d_ally := Player.create(ClassData.load_by_id(&"runebreaker"))
	d_ally.is_local = false
	d_ally.input_source = InputSource.new()
	lab.add_player(d_ally)
	d_ally.global_position = player.global_position + Vector3(4, 0, 0)
	var d_ally2 := Player.create(ClassData.load_by_id(&"elementalist"))
	d_ally2.is_local = false
	d_ally2.input_source = InputSource.new()
	lab.add_player(d_ally2)
	d_ally2.global_position = player.global_position + Vector3(-4, 0, 2)
	await _wait_frames(3)
	player.health.heal_full()
	d_ally.health.current_health = d_ally.health.max_health * 0.4
	d_ally2.health.current_health = d_ally2.health.max_health * 0.7
	_check(player.pick_heal_target() == d_ally, "no ally under the crosshair: the heal goes to the most wounded in reach")
	d_ally.global_position = player.global_position + Vector3(40, 0, 0)
	_check(player.pick_heal_target() == d_ally2, "an ally out of reach (30 m) is skipped")
	await _wait_frames(30)  # the camera settles behind the hero
	var cam := lab.camera_rig.camera
	var cam_fwd := -cam.global_transform.basis.z
	d_ally2.global_position = cam.global_position + cam_fwd * 9.0 - Vector3(0, 1.1, 0)
	d_ally.global_position = player.global_position + Vector3(4, 0, 0)
	d_ally2.set_physics_process(false)
	_check(lab.targeting.ally_under_aim(Player.ALLY_RANGE) == d_ally2 and player.pick_heal_target() == d_ally2,
		"the ally under the crosshair wins over the most wounded")
	lab.targeting._update_heal_target()  # (what its _process does every frame; the camera keeps easing in)
	_check(lab.targeting.heal_target == d_ally2 and lab.targeting._ally_marker.visible,
		"the heal target wears the green marker")
	d_ally2.set_physics_process(true)
	d_ally2.global_position = player.global_position + Vector3(-4, 0, 2)
	await _wait_frames(2)
	# a heal on an ally, and the threat it makes (half, split over the fighting enemies)
	var d_foe := lab.spawn_by_id("rusher", player.global_position + Vector3(0, 0.2, -6))
	await _wait_frames(3)
	d_foe.set_physics_process(false)
	d_foe.add_threat(d_ally, 10.0)
	player.reset_cooldowns()
	player.resonance = 100.0
	var ally_hp := d_ally.health.current_health
	_check(druid.try_mending_bloom() and absf(d_ally.health.current_health - ally_hp - druid.mending_bloom.heal) < 0.01,
		"Mending Bloom heals the ally (+%.0f)" % (d_ally.health.current_health - ally_hp))
	_check(absf(d_foe.threat_of(player) - druid.mending_bloom.heal * 0.5) < 0.01,
		"healing threatens: half of it on the enemy already fighting (%.1f)" % d_foe.threat_of(player))
	var threat_before := d_foe.threat_of(player)
	d_ally.health.current_health = d_ally.health.max_health - 10.0
	player.reset_cooldowns()
	druid.heal_ally(d_ally, 30.0)
	_check(absf(d_foe.threat_of(player) - threat_before - 5.0) < 0.01, "overhealing makes no threat (10 healed of 30: +5)")
	# heal over time, a shield and a buff reach allies through the same path
	d_ally.health.current_health = d_ally.health.max_health * 0.5
	var hot_hp := d_ally.health.current_health
	player.hero_fx(&"ally_hot", [lab.hero_ref(d_ally), &"regrowth", 40.0, 1.0])
	_check(d_ally.hot_left(&"regrowth") > 39.0, "a heal over time lands on the ally")
	await _wait_frames(75)
	_check(absf(d_ally.health.current_health - hot_hp - 40.0) < 0.5 and d_ally.hot_left(&"regrowth") == 0.0,
		"the heal over time gives its 40 over its second")
	d_ally.barrier = 0.0
	player.hero_fx(&"ally_shield", [lab.hero_ref(d_ally), 35.0, 6.0])
	_check(is_equal_approx(d_ally.barrier, 35.0), "a shield on the ally is its barrier")
	var dmg_before := d_ally.stat(&"damage_pct")
	player.hero_fx(&"ally_buff", [d_ally.global_position, 3.0, &"damage_pct", 15.0, 0.5])
	_check(is_equal_approx(d_ally.stat(&"damage_pct"), dmg_before + 15.0) and is_equal_approx(d_ally2.stat(&"damage_pct"), 0.0),
		"a buff reaches the allies in its radius only")
	await _wait_frames(40)
	_check(is_equal_approx(d_ally.stat(&"damage_pct"), dmg_before), "the buff runs out")
	# the barrier travels to the party frames
	d_ally.apply_net_state(d_ally.global_position, 0.0, Vector3.ZERO, 0, 50.0, 120.0, 22.0)
	_check(is_equal_approx(d_ally.barrier, 22.0), "M11: a remote hero's barrier comes with its state (party frames)")
	d_ally.barrier = 0.0
	# Thorn Volley (the druid's LMB, auto-fire while held)
	lab.kill_all_enemies()
	await _wait_frames(20)
	var thorn_target := MeleeRusher.new()
	lab.enemies_root.add_child(thorn_target)
	thorn_target.player = player
	var thorn_aim := player.aim_direction()
	thorn_target.global_position = player.global_position + thorn_aim * 6.0 - Vector3(0, thorn_aim.y * 6.0, 0)
	await _wait_frames(2)
	thorn_target.set_physics_process(false)
	var thorn_hp := thorn_target.health.current_health
	var thorn_probe := ScriptedInput.new()
	var thorn_local := player.input_source
	player.input_source = thorn_probe
	thorn_probe.held.append(&"thorn_volley")
	await _wait_frames(45)
	thorn_probe.held.clear()
	player.input_source = thorn_local
	_check(thorn_target.health.current_health < thorn_hp - druid.thorn_volley.damage * 3.0,
		"holding LMB keeps throwing Thorn Volleys (%.0f damage)" % (thorn_hp - thorn_target.health.current_health))
	thorn_target.queue_free()
	await _wait_frames(2)
	# --- M11 phase 2: the rest of the kit ---
	_check(druid.class_data.trainer_abilities().size() == 7 and druid.class_data.trainer_abilities()[0].id == &"barkskin",
		"the druid's trainer teaches 7 abilities, Barkskin first")
	player.debug_learn_all()
	player.resonance = 100.0
	player.reset_cooldowns()
	player.health.heal_full()
	d_ally2.health.heal_full()
	d_ally.health.current_health = d_ally.health.max_health * 0.5
	d_ally.barrier = 0.0
	_check(druid.try_barkskin() and absf(d_ally.barrier - druid.bark_amount()) < 0.01 and druid.bark_amount() > druid.barkskin.heal,
		"Barkskin wraps the most wounded ally in a barrier (%.0f, grows with the level)" % d_ally.barrier)
	_check(druid.try_regrowth() and d_ally.hot_left(&"regrowth") > druid.regrowth.heal - 1.0,
		"Regrowth starts a heal over time on the ally")
	# Root Grasp at the aim
	player.resonance = 100.0
	var grasp_at := druid._ground_aim(druid.root_grasp.projectile_speed)
	var grasp_foe := lab.spawn_by_id("rusher", grasp_at + Vector3(0, 0.2, 0))
	await _wait_frames(3)
	grasp_foe.health.max_health = 1.0e5
	grasp_foe.health.heal_full()
	_check(druid.try_root_grasp() and grasp_foe.status.is_rooted()
		and grasp_foe.health.current_health < grasp_foe.health.max_health,
		"Root Grasp strikes and roots the enemy at the aim")
	# Thornfield bites and Chills what stands in it
	player.resonance = 100.0
	var field_hp := grasp_foe.health.current_health
	grasp_foe.status.clear_all()
	_check(druid.try_thornfield(), "Thornfield takes root at the aim")
	await _wait_frames(40)
	_check(grasp_foe.health.current_health < field_hp and grasp_foe.status.has_chill(),
		"Thornfield bites and Chills the enemy in it (%.0f)" % (field_hp - grasp_foe.health.current_health))
	lab.kill_all_enemies()
	await _wait_frames(20)
	# Renewal Grove heals the allies standing in it
	player.resonance = 100.0
	var grove_at := druid._ground_aim(druid.renewal_grove.projectile_speed)
	d_ally.global_position = grove_at + Vector3(1.0, 0.2, 0)
	await _wait_frames(3)
	d_ally.health.current_health = d_ally.health.max_health * 0.3
	d_ally._hots.clear()
	var grove_hp := d_ally.health.current_health
	_check(druid.try_renewal_grove(), "Renewal Grove grows at the aim")
	await _wait_frames(65)
	_check(d_ally.health.current_health > grove_hp + druid.grove_rate() * 0.8,
		"Renewal Grove heals the ally in it (%.1f in 1 s)" % (d_ally.health.current_health - grove_hp))
	# Totem of Growth: +damage for the allies near, small heals
	player.resonance = 100.0
	d_ally.global_position = player.global_position + Vector3(3, 0, 0)
	var totem_dmg := d_ally.stat(&"damage_pct")
	_check(druid.try_growth_totem(), "the Totem of Growth is planted")
	await _wait_frames(3)
	_check(is_equal_approx(d_ally.stat(&"damage_pct"), totem_dmg + druid.totem_damage_pct())
		and player.buff_time(&"damage_pct") > GrowthTotem.PULSE,
		"the totem's pulse gives the allies near +%d%% damage" % roundi(druid.totem_damage_pct()))
	# Wild Bloom: every ally near heals 30 %, enemies close are thrown back and rooted
	for child in lab.get_children():
		if child is GrowthTotem or child is RenewalGrove or child is ThornField:
			child.queue_free()
	await _wait_frames(2)
	player.resonance = 100.0
	player.reset_cooldowns()
	d_ally.global_position = player.global_position + Vector3(3, 0, 0)
	d_ally._hots.clear()
	d_ally.health.current_health = d_ally.health.max_health * 0.4
	var bloom_hp := d_ally.health.current_health
	var bloom_foe := lab.spawn_by_id("rusher", player.global_position + Vector3(0, 0.2, -2.5))
	await _wait_frames(3)
	bloom_foe.health.max_health = 1.0e5
	bloom_foe.health.heal_full()
	_check(druid.try_wild_bloom() and absf(d_ally.health.current_health - bloom_hp - d_ally.health.max_health * 0.3) < 0.5
		and bloom_foe.status.is_rooted() and player.resonance < 51.0,
		"Wild Bloom heals the allies near by 30 % and roots the enemies close (50 Sap)")
	# talents and a legendary change the kit
	player.progression.ranks[&"splinter"] = 1
	player.equipment._recompute()
	player.progression._changed()
	_check(druid.thorn_count() == 4, "Splinter: Thorn Volley throws a fourth thorn")
	player.progression.ranks.clear()
	player.progression._changed()
	lab.kill_all_enemies()
	await _wait_frames(20)
	# vitals: health and Sap are what the save keeps
	player.health.current_health = 41.0
	player.resonance = 33.0
	var vit := SaveGame.character_dict(player).get("vitals", {}) as Dictionary
	player.health.heal_full()
	player.resonance = 100.0
	player.restore_vitals(vit)
	_check(is_equal_approx(player.health.current_health, 41.0) and is_equal_approx(player.resonance, 33.0),
		"M11: the save keeps health and Sap (%s)" % str(vit))
	player.health.heal_full()
	lab.remove_player(d_ally)
	d_ally.queue_free()
	lab.remove_player(d_ally2)
	d_ally2.queue_free()
	lab.targeting.current = null
	lab.kill_all_enemies()
	await _wait_frames(20)
	player.global_position = Vector3(0, 0.2, 6)
	player.velocity = Vector3.ZERO

	await _play_as(&"runebreaker")

	# ===== M10 phase 2: the tank - threat, taunts, Rune Wall, the new abilities =====
	lab.kill_all_enemies()
	await _wait_frames(20)
	player.global_position = Vector3(0, 0.2, 6)
	player.velocity = Vector3.ZERO
	player.reset_cooldowns()
	var ally := Player.create(ClassData.load_by_id(&"elementalist"))
	ally.is_local = false
	ally.input_source = InputSource.new()
	lab.add_player(ally)
	ally.global_position = player.global_position + Vector3(4, 0, 0)
	var foe_t := lab.spawn_by_id("rusher", player.global_position + Vector3(0, 0.2, -5))
	await _wait_frames(3)
	foe_t.health.max_health = 1.0e6
	foe_t.health.heal_full()
	foe_t.move_speed = 0.0
	var ally_hit := HitInfo.create(20.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, ally.global_position)
	ally_hit.from_player = true
	ally_hit.attacker_id = ally.get_instance_id()
	foe_t.take_hit(ally_hit)
	var threat_ally := foe_t.threat_of(ally)
	foe_t._retarget()
	_check(foe_t.target == ally and is_equal_approx(threat_ally, 20.0),
		"threat: the enemy turns on the hero that hurt it (20 damage = 20 threat)")
	var tank_hit := HitInfo.create(12.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, player.global_position)
	tank_hit.from_player = true
	tank_hit.attacker_id = player.get_instance_id()
	foe_t.take_hit(tank_hit)
	var threat_tank := foe_t.threat_of(player)
	foe_t._retarget()
	_check(foe_t.target == player and absf(threat_tank - 24.0) < 0.01,
		"the tank's damage threatens double: its 12 outweighs the caster's 20 (%.1f)" % threat_tank)
	var nudge := HitInfo.create(5.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, ally.global_position)
	nudge.from_player = true
	nudge.attacker_id = ally.get_instance_id()
	foe_t.take_hit(nudge)
	foe_t._retarget()
	_check(foe_t.target == player, "a new favourite needs 10 %% more threat than the current target (%.1f vs %.1f)"
		% [foe_t.threat_of(ally), foe_t.threat_of(player)])
	foe_t.add_threat(ally, 500.0)
	foe_t._retarget()
	var went_to_caster := foe_t.target == ally
	player.reset_cooldowns()
	_check(went_to_caster and rb.try_rune_challenge() and foe_t.taunted_by() == player and foe_t.target == player,
		"Rune Challenge pulls every enemy within 8 m onto the tank at once, past any threat")
	foe_t._retarget()
	_check(foe_t.target == player and foe_t.threat_of(player) > foe_t.threat_of(ally),
		"the taunt holds, and it leaves the tank on top of the threat list")
	foe_t._taunt_until = 0.0
	foe_t.add_threat(ally, 1.0e5)
	foe_t._retarget()
	_check(foe_t.target == ally and foe_t.taunted_by() == null, "once the taunt runs out, threat decides again")
	foe_t.auto_retarget = false  # the mark checks below set the target by hand
	await _wait_frames(15)
	lab.aggro_marks._left = 0.0
	foe_t.target = player
	await get_tree().process_frame
	await get_tree().process_frame
	_check(lab.aggro_marks.mark_count() >= 1, "in a party, an enemy that hunts you wears the '!' mark")
	foe_t.target = ally
	lab.aggro_marks._left = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	_check(lab.aggro_marks.mark_count() == 0, "the mark goes when it hunts someone else")
	# Rune Wall: hold to block (-75 % from the front), the first 0.3 s parry.
	player.god_mode = false
	player.health.invulnerable = false
	player.health.heal_full()
	player.barrier = 0.0
	player.reset_cooldowns()
	player.resonance = 0.0
	var wall_probe := ScriptedInput.new()
	var wall_local := player.input_source
	player.input_source = wall_probe
	wall_probe.held.append(&"rune_wall")
	wall_probe.queue.append(&"rune_wall")
	await _wait_frames(2)
	_check(player.state == Player.State.BLOCK and rb.is_blocking(), "holding the key raises Rune Wall")
	var hp_wall := player.health.current_health
	var foe_hp := foe_t.health.current_health
	var parry_hit := HitInfo.create(20.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.MEDIUM,
		player.global_position + player.facing() * 2.0)
	parry_hit.source_id = foe_t.get_instance_id()
	_check(not player.take_hit(parry_hit) and is_equal_approx(player.health.current_health, hp_wall)
		and foe_t.health.current_health < foe_hp and foe_t.ai_state == EnemyBase.AIState.STAGGER and player.resonance > 10.0,
		"a hit in the first 0.3 s is parried: no damage, the striker takes a staggering counter, Resonance")
	await _wait_frames(25)
	var block_hit := HitInfo.create(20.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.MEDIUM,
		player.global_position + player.facing() * 2.0)
	player.take_hit(block_hit)
	_check(absf(hp_wall - player.health.current_health - 5.0) < 0.01,
		"after the parry window a frontal hit is blocked: 20 -> 5 (%.1f)" % (hp_wall - player.health.current_health))
	var hp_back := player.health.current_health
	player.take_hit(HitInfo.create(20.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.MEDIUM,
		player.global_position - player.facing() * 2.0))
	_check(absf(hp_back - player.health.current_health - 20.0) < 0.01, "a hit from behind gets through Rune Wall")
	wall_probe.held.clear()
	await _wait_frames(2)
	player.input_source = wall_local
	_check(player.state == Player.State.MOVE and player._on_cooldown(&"rune_wall"), "letting go lowers the ward (short cooldown)")
	player.health.heal_full()
	# Rune Chain: drags an enemy in and taunts it; heavy foes hold their ground.
	lab.kill_all_enemies()
	await _wait_frames(20)
	player.reset_cooldowns()
	var catch := MeleeRusher.new()
	lab.enemies_root.add_child(catch)
	catch.player = ally
	catch.global_position = player.global_position + player.facing() * 9.0
	await _wait_frames(2)
	lab.targeting.current = catch
	_check(rb.try_rune_chain(), "Rune Chain throws at the held target")
	await _wait_frames(30)
	var pulled_to := catch.global_position.distance_to(player.global_position)
	_check(pulled_to < 3.8 and catch.taunted_by() == player, "Rune Chain drags the enemy to the tank and taunts it (%.1f m)" % pulled_to)
	var heavy := Brute.new()
	lab.enemies_root.add_child(heavy)
	heavy.player = ally
	heavy.global_position = player.global_position + player.facing() * 8.0
	await _wait_frames(2)
	heavy.set_physics_process(false)  # a taunted brute would walk off towards the tank
	var heavy_from := heavy.global_position
	lab.targeting.current = heavy
	player.reset_cooldowns()
	rb.try_rune_chain()
	await _wait_frames(20)
	_check(heavy.global_position.distance_to(heavy_from) < 1.5 and heavy.taunted_by() == player,
		"a heavy foe holds its ground but is taunted")
	# Warden's Leap: lands at the aim, strikes and taunts what stands there.
	lab.kill_all_enemies()
	await _wait_frames(20)
	player.reset_cooldowns()
	var leap_exclude: Array[RID] = [player.get_rid()]
	var leap_aim := lab.camera_rig.get_aim_point(leap_exclude)
	var leap_off := Vector3(leap_aim.x - player.global_position.x, 0.0, leap_aim.z - player.global_position.z).limit_length(10.0)
	var lander := MeleeRusher.new()
	lab.enemies_root.add_child(lander)
	lander.player = ally
	lander.global_position = player.global_position + leap_off + Vector3(0.8, 0.2, 0)
	await _wait_frames(2)
	lander.set_physics_process(false)
	var leap_start := player.global_position
	_check(rb.try_warden_leap() and player.state == Player.State.LEAP, "Warden's Leap takes off")
	await _wait_frames(45)
	_check(player.state == Player.State.MOVE and player.global_position.distance_to(leap_start) > 2.0
		and lander.taunted_by() == player and lander.health.current_health < lander.health.max_health
		and player.collision_mask == 0b1000101,
		"the tank lands at the aim, strikes and taunts what stands there (%.1f m)" % player.global_position.distance_to(leap_start))
	# Warding Rune: every hero inside takes 25 % less damage.
	player.reset_cooldowns()
	player.resonance = 100.0
	ally.global_position = player.global_position + Vector3(1.5, 0, 0)
	_check(rb.try_warding_rune() and player.resonance < 71.0, "Warding Rune costs 30 Resonance")
	await _wait_frames(2)
	_check(is_equal_approx(player.damage_taken_mult(), 0.75) and is_equal_approx(ally.damage_taken_mult(), 0.75),
		"the tank and an ally inside the ward take 25 % less damage")
	ally.global_position = player.global_position + Vector3(10, 0, 0)
	_check(is_equal_approx(ally.damage_taken_mult(), 1.0), "outside the ward no reduction")
	# Aegis of Runes: Runic Guard shields allies near for half.
	ally.global_position = player.global_position + Vector3(2, 0, 0)
	ally.barrier = 0.0
	player.progression.ranks[&"runic_guard"] = 1
	player.progression.ranks[&"aegis_of_runes"] = 1
	player.progression._changed()
	player.reset_cooldowns()
	player.resonance = 100.0
	rb.try_runic_guard()
	_check(absf(ally.barrier - rb.guard_amount() * 0.5) < 0.01, "Aegis of Runes: Runic Guard also shields allies within 6 m for half")
	player.progression.ranks[&"unyielding"] = 1
	player.progression._changed()
	player.health.current_health = player.health.max_health * 0.2
	_check(is_equal_approx(rb._class_damage_reduction(), 0.3), "Unyielding: below 30 % health the tank takes 30 % less")
	player.health.heal_full()
	player.progression.ranks.clear()
	player.progression._changed()
	player.barrier = 0.0
	for child in lab.get_children():
		if child is WardingRune:
			child.queue_free()
	lab.remove_player(ally)
	ally.queue_free()
	lab.targeting.current = null
	lab.kill_all_enemies()
	await _wait_frames(20)
	player.global_position = Vector3(0, 0.2, 6)
	player.velocity = Vector3.ZERO

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
	_check(absf(player.health.max_health - (150.0 + player.progression.stat(&"max_hp"))) < 0.01,
		"equipping +30 HP raises max health (on top of level bonuses)")

	# Keyboard layout (user, 2026-09-24): abilities on the number row, Q/R kept, E = interact.
	var has_key := func(action: StringName, key: Key) -> bool:
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey and (ev as InputEventKey).physical_keycode == key:
				return true
		return false
	_check(has_key.call(&"ability_q", KEY_1) and has_key.call(&"ability_q", KEY_Q) and has_key.call(&"ability_e", KEY_2)
		and not has_key.call(&"ability_e", KEY_E) and has_key.call(&"ability_r", KEY_3) and has_key.call(&"ability_r", KEY_R)
		and has_key.call(&"interact", KEY_E) and has_key.call(&"loadout_toggle", KEY_K)
		and InputSetup.SLOT_ACTIONS == ([&"secondary_ability", &"ability_q", &"ability_e", &"ability_r"] as Array[StringName]),
		"M10 keys: the slots are RMB, 1 (Q), 2, 3 (R); K opens the abilities tab; E = interact")

	# --- M07 progression: XP, levels, talent rules, save format ---
	var tree := Progression.tree()
	var t_static := Progression.talent(&"static_charge")
	var t_arc := Progression.talent(&"arc_conduit")
	_check(tree.size() == 72 and t_static != null and t_arc != null and t_arc.tier == 1,
		"talent trees load 72 data nodes (3 classes x 3 branches)")
	var prog := Progression.new()
	prog.class_id = &"elementalist"  # M10: Static Charge and Arc Conduit are the Elementalist's
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
	prog_loaded.class_id = &"elementalist"
	add_child(prog_loaded)
	prog_loaded.from_dict(saved)
	_check(prog_loaded.level == 5 and prog_loaded.rank(&"static_charge") == 3 and prog_loaded.points_free() == 1,
		"progression round-trips through the save format")
	prog.respec()
	_check(prog.points_free() == 4 and prog.stat(&"crit_pct") == 0.0, "respec returns every point")
	var v1 := SaveGame.migrate({"version": 1, "zone": "res://scenes/hub.tscn", "flags": {"x": true}, "inventory": [], "equipped": {}})
	var v1_char: Dictionary = (v1.get("characters", [{}]) as Array)[0]
	_check(int(v1.get("version", 0)) == SaveGame.VERSION and (v1_char["progression"] as Dictionary)["level"] == 1
		and (v1_char["world"] as Dictionary)["flags"].has("x") and v1_char["known_abilities"] == ["rune_cleave"]
		and not v1.has("world"),
		"v1 saves migrate all the way (level 1, Rune Cleave only, the flags now in the character's world)")
	var v2 := SaveGame.migrate({"version": 2, "zone": "res://scenes/shattered_spire.tscn", "flags": {"colossus_defeated": true},
		"inventory": [{"n": "x"}], "equipped": {}, "progression": {"level": 4, "xp": 10, "talents": {"kindling": 2}}})
	var v2_char: Dictionary = (v2.get("characters", [{}]) as Array)[0]
	_check(v2_char["class_id"] == "runebreaker" and int(v2_char["gold"]) == 475
		and v2_char["known_abilities"] == ["rune_cleave"]
		and (v2_char["inventory"] as Array).size() == 1 and (v2_char["world"] as Dictionary)["zone"].ends_with("shattered_spire.tscn")
		and int(v2.get("active", -1)) == 0,
		"v2 saves migrate to v3: one Runebreaker keeps gear, starts with Rune Cleave and the gold its level earned (475 at L4)")
	_check(SaveGame.active_class_id() == &"runebreaker", "fresh save plays the default class")
	var v5_old := {"version": 5, "world": {"zone": "res://scenes/ashen_highlands.tscn", "flags": {"colossus_defeated": true},
		"camps": {"camp_1": {"cleared_at": 9.0}}},
		"characters": [{"class_id": "runebreaker", "known_abilities": ["rune_cleave", "earthbreaker", "ember_lance", "chain_spark"],
		"gold": 20, "inventory": [], "equipped": {}, "progression": {"level": 6, "xp": 0, "talents": {"kindling": 2, "runic_plate": 1}},
		"waypoints": [], "map_discovered": [], "discovered": []}], "active": 0}
	var v6 := SaveGame.migrate(v5_old)
	var v6_char: Dictionary = (v6.get("characters", [{}]) as Array)[0]
	_check(int(v6.get("version", 0)) == 6 and not v6.has("world") and (v6_char["world"] as Dictionary)["flags"].has("colossus_defeated")
		and ((v6_char["world"] as Dictionary)["camps"] as Dictionary).has("camp_1") and v6_char["known_abilities"] == ["rune_cleave", "earthbreaker"]
		and int(v6_char["gold"]) == 20 + 150 + 400 and (v6_char["notes"] as Array).has("m10_refund:550") and v6_char.has("name"),
		"save v5 -> v6: the world moves into the character; a Runebreaker's spells come back as gold (+550) with a note")
	var v6_prog := Progression.new()
	v6_prog.class_id = &"runebreaker"
	add_child(v6_prog)
	v6_prog.from_dict(v6_char["progression"] as Dictionary)
	_check(v6_prog.rank(&"kindling") == 0 and v6_prog.rank(&"runic_plate") == 1 and v6_prog.points_free() == 4,
		"the spells' talents drop out of a migrated Runebreaker's tree (their points are free again)")
	v6_prog.queue_free()
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
	_check(rb.try_runic_guard() and player.barrier > 30.0 and player.resonance < 71.0,
		"Runic Guard spends 30 Resonance for a barrier")
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
	_check(rb.try_resonance_burst() and player.resonance == 0.0 and dummy.health.current_health < hp_dummy,
		"Resonance Burst spends all Resonance in a damaging nova")
	player.resonance = 20.0
	player.reset_cooldowns()
	_check(not rb.try_resonance_burst(), "Resonance Burst needs 50 Resonance")
	# Molten Core + Wildfire + Kindling.
	grant.call(["molten_core", "wildfire", "kindling"])
	player.progression.ranks[&"kindling"] = 3
	player.progression._changed()
	dummy.status.clear_all()
	rb._do_slam_hit()
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
	var atk_dummy_hit := player.roll_ability_hit(rb.cleave)
	atk_dummy_hit.applies_shock = false
	var atk_before := atk_dummy_hit.damage
	dummy.take_hit(atk_dummy_hit)
	_check(is_equal_approx(atk_dummy_hit.damage, atk_before * 1.24 * dummy.status.damage_taken_multiplier())
		and dummy.last_attacker() == player,
		"talent damage follows the attacker id (no assigned player needed); the enemy remembers its attacker")
	dummy.player = player
	# Unbroken: an attack inside the dodge's i-frames grants a barrier.
	grant.call(["unbroken"])
	player.barrier = 0.0
	player._cooldowns.erase(&"unbroken")
	player.health.invulnerable = true
	player.take_hit(HitInfo.create(10.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, dummy.global_position))
	player.health.invulnerable = false
	_check(is_equal_approx(player.barrier, Player.UNBROKEN_BARRIER), "Unbroken: dodging through an attack grants a barrier")
	player.barrier = 0.0
	# M10 tank talents that work without the new abilities: Stalwart, Heavy Hands, Hold the Line.
	grant.call(["stalwart", "heavy_hands", "hold_the_line"])
	player.progression.ranks[&"stalwart"] = 3
	player.progression.ranks[&"heavy_hands"] = 3
	player.progression._changed()
	var cleave_probe := HitInfo.create(10.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, player.global_position)
	cleave_probe.ability = &"rune_cleave"
	dummy.status.clear_all()
	dummy.player = null
	var mult_free := player.talent_damage_mult(cleave_probe, dummy)
	dummy.player = player
	_check(is_equal_approx(player.damage_taken_mult(), 0.91) and is_equal_approx(mult_free, 1.24)
		and is_equal_approx(player.talent_damage_mult(cleave_probe, dummy), 1.32),
		"Stalwart: 9 %% less damage taken; Heavy Hands +24 %% Rune Cleave; Hold the Line +8 %% on what attacks you")
	var hp_stalwart := player.health.current_health
	player.take_hit(HitInfo.create(10.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, dummy.global_position))
	_check(is_equal_approx(hp_stalwart - player.health.current_health, 9.1), "damage reduction applies to a real hit")
	player.health.heal_full()
	# ===== M10: the spell talents need the Elementalist =====
	grant.call([])
	await _play_as(&"elementalist")
	dummy.player = player
	neighbor.player = player
	# Overload: the Storm Step landing Shocks everything near it.
	grant.call(["overload"])
	dummy.status.clear_all()
	neighbor.status.clear_all()
	mage._dash_start = player.global_position
	mage._resolve_storm_step()
	_check(dummy.status.has_shock(), "Overload: Storm Step's end point Shocks nearby enemies")
	# Split Lance: the first hit forks two shards.
	grant.call(["split_lance"])
	var lance := EmberLanceProjectile.new()
	lance.setup(mage.ember, player.facing(), player)
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
	player._set_cooldown(&"storm_step", mage.storm_step.cooldown)
	_check(is_equal_approx(float(player._cooldowns[&"storm_step"]), mage.storm_step.cooldown * 0.76),
		"Quickstep: Storm Step cooldown -24 % at 2 ranks")
	player.resonance = 0.0
	player.gain_resonance(10.0, true)
	var surge_res := player.resonance
	player.resonance = 0.0
	player.gain_resonance(10.0)
	_check(surge_res > player.resonance + 2.9, "Storm Surge: lightning hits build +30 % more Aether")
	player.resonance = 0.0
	# Eye of the Storm: the dash refunds cooldown per enemy on its path.
	grant.call(["eye_of_the_storm"])
	player.reset_cooldowns()
	player._set_cooldown(&"storm_step", mage.storm_step.cooldown)
	var cd_full := float(player._cooldowns[&"storm_step"])
	mage._dash_start = player.global_position - player.facing() * 0.5
	player.global_position = mage._dash_start + player.facing() * 3.2  # the dash passed the dummy
	mage._resolve_storm_step()
	_check(float(player._cooldowns[&"storm_step"]) < cd_full - 0.01, "Eye of the Storm: enemies on the path refund cooldown")
	player.global_position = mage._dash_start + player.facing() * 0.5
	player.velocity = Vector3.ZERO
	# Thunderclap: the Chain Spark's last target bursts onto a neighbour.
	grant.call(["thunderclap"])
	player.reset_cooldowns()
	var clap_hp := neighbor.health.current_health
	neighbor.health.max_health = 1.0e6
	neighbor.health.heal_full()
	clap_hp = neighbor.health.current_health
	lab.targeting.current = dummy
	var sparked := mage.try_chain_spark()
	await _wait_frames(2)
	_check(sparked and neighbor.health.current_health < clap_hp, "Thunderclap / chain: the neighbour takes lightning damage")
	# Phoenix Burst: where a lance ends it bursts onto neighbours.
	grant.call(["phoenix_burst"])
	var phoenix := EmberLanceProjectile.new()
	phoenix.setup(mage.ember, player.facing(), player)
	phoenix.position = dummy.global_position + Vector3(0, 1.0, 0)
	lab.add_child(phoenix)
	var burst_hp := neighbor.health.current_health
	neighbor.status.clear_all()
	phoenix._phoenix_burst(dummy)
	_check(neighbor.health.current_health < burst_hp and neighbor.status.has_burn(),
		"Phoenix Burst: the lance's end bursts (damage + Burn) onto neighbours")
	phoenix.queue_free()
	# M10 Shatter: bonus damage to Chilled enemies (Frost branch).
	grant.call(["shatter"])
	player.progression.ranks[&"shatter"] = 3
	player.progression._changed()
	dummy.status.clear_all()
	dummy.status.apply_chill()
	var shatter_hit := HitInfo.create(10.0, HitInfo.DamageType.FROST, HitInfo.Weight.LIGHT, player.global_position)
	_check(is_equal_approx(player.talent_damage_mult(shatter_hit, dummy), 1.24), "Shatter: +24 %% damage to Chilled enemies at 3 ranks")
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
	await _play_as(&"runebreaker")
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
	player.gain_resonance(100.0)
	rb.try_earthbreaker()
	var expected_cd: float = rb.earthbreaker.cooldown * 0.8
	_check(absf(float(player._cooldowns[&"earthbreaker"]) - expected_cd) < 0.01, "cooldown reduction applies")
	_check(absf(StatSheet.effective_cooldown(player, rb.earthbreaker) - expected_cd) < 0.001,
		"the character sheet shows the same reduced cooldown")
	await _wait_frames(70)

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

	# --- ember pierce affix (M10: the Elementalist's) ---
	await _play_as(&"elementalist")
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
	mage.try_ember()
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
	mage.try_ember()
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
	_check(mage.try_chain_spark(), "chain spark casts for conductor test")
	await _wait_frames(3)
	_check(cond_a.status.is_conductor() and cond_b.status.is_conductor(), "chain spark marks Conductors")
	var b_hp_before_arc := cond_b.health.current_health
	var zap := HitInfo.create(5.0, HitInfo.DamageType.LIGHTNING, HitInfo.Weight.LIGHT, player.global_position)
	cond_a.take_hit(zap)
	await _wait_frames(2)
	_check(cond_b.health.current_health < b_hp_before_arc, "lightning on a Conductor arcs to other Conductors")

	# --- Glacier Heart (the tank's) ---
	lab.kill_all_enemies()
	await _wait_frames(20)
	await _play_as(&"runebreaker")
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
	rb.try_earthbreaker()
	await _wait_frames(80)
	var field_found := false
	for child in get_tree().current_scene.get_children():
		if child is FrostField:
			field_found = true
	_check(field_found, "Glacier Heart leaves a frost field")
	_check(is_instance_valid(frost_victim) and frost_victim.status.has_chill(), "frost field chills enemies inside")

	# --- an elite that rolls a drop drops rare or better (M08 notes: 60 %) ---
	lab.kill_all_enemies()
	await _wait_frames(20)
	var loot_elite := lab.spawn_elite(EliteModifier.Kind.STORMTOUCHED, player.global_position + Vector3(0, 0.2, -6))
	await _wait_frames(3)
	ItemGenerator.forced_drop_roll = 0.0
	loot_elite.take_hit(HitInfo.create(99999.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, player.global_position))
	ItemGenerator.forced_drop_roll = -1.0
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
	hud._update_tooltip(hud.slot_rect(&"earthbreaker").get_center())
	_check(not hud.tooltip_visible(), "ability names hidden while the inventory is closed")
	lab.inventory_ui.toggle()
	_check(lab.inventory_ui.visible and player.input_locked, "inventory opens and locks input")
	var expected_names := {
		&"rune_cleave": rb.cleave.display_name, &"earthbreaker": rb.earthbreaker.display_name, &"dodge": "Dodge",
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
	player._last_combat_msec = -1000000
	player.set_loadout_slot(2, &"earthbreaker")  # M10: the loadout rides along too
	player.consumables = {Consumables.HEALING_DRAUGHT: 3}  # M10b: and the bag
	SaveGame.save_now()
	player.consumables = {}
	player.equipment.inventory.clear()
	player.equipment.equipped.clear()
	player.equipment._recompute()
	player.gold = 0
	player.known_abilities = [&"rune_cleave"]
	player.restore_loadout([])
	SaveGame.reload_from_disk()
	SaveGame.restore_player(player)
	_check(player.gold == 123 and player.known_abilities.size() == 8 and player.knows(&"warding_rune")
		and player.loadout == ([&"rune_challenge", &"rune_wall", &"earthbreaker", &"warden_leap"] as Array[StringName]),
		"save restores gold, the learned abilities and the loadout (%s)" % str(player.loadout))
	var restored_names: Array[String] = []
	for it in player.equipment.inventory:
		restored_names.append(it.display_name)
	var equipped_weapon: ItemData = player.equipment.equipped.get(ItemData.Slot.WEAPON)
	_check(restored_names.has("Persistence Marker"), "save restores inventory")
	_check(equipped_weapon != null and equipped_weapon.display_name == "Saved Blade", "save restores equipped gear")
	_check(player.consumable_count(Consumables.HEALING_DRAUGHT) == 3, "M10b: save restores the Healing Draughts in the bag")

	# --- corrupt save handled ---
	var f := FileAccess.open(SaveGame.save_path, FileAccess.WRITE)
	f.store_string("{{{ not json")
	f.close()
	SaveGame.reload_from_disk()
	_check(not SaveGame.has_save(), "corrupt save falls back to fresh start")
	SaveGame.wipe()

	# --- travel: lab -> hub, gear survives via save ---
	player.equipment.add_item(marker)
	player.health.current_health = player.health.max_health * 0.55  # M11: travelling no longer heals
	var carried_hp := player.health.current_health
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
	_check(trainer != null and trainer.npc_name.begins_with("Sigrun") and trainer.teaches_class == &"runebreaker",
		"Sigrun, the Runebreaker's trainer, stands in Runehold")
	var mage_trainer := hub.world.get_node_or_null("TrainerElementalist") as TrainerNpc
	_check(mage_trainer != null and mage_trainer.npc_name.begins_with("Maren") and mage_trainer.teaches_class == &"elementalist",
		"M10: Maren, the Elementalist's trainer, stands in Runehold too")
	if mage_trainer != null:
		hub.trainer_ui.open(mage_trainer)
		_check(hub.trainer_ui.visible and hub.trainer_ui._rows.get_child_count() == 0
			and hub.trainer_ui._flavour.text.contains("Sigrun"),
			"the Elementalist's trainer teaches a Runebreaker nothing and points to Sigrun")
		hub.trainer_ui.close()
	if trainer != null:
		var hub_spot := hub.player.global_position
		hub.player.global_position = trainer.global_position + Vector3(1.2, 0.2, 0.6)
		await _wait_frames(2)
		await get_tree().process_frame  # the prompt updates in _process, not per physics step
		await get_tree().process_frame
		_check(trainer._prompt.visible and trainer._prompt.text.ends_with("Talk"), "trainer shows the [E] Talk prompt up close")
		hub.trainer_ui.open(trainer)
		_check(hub.trainer_ui.visible and hub.player.input_locked, "trainer panel opens and locks input")
		hub.trainer_ui.close()
		_check(not hub.trainer_ui.visible and not hub.player.input_locked, "trainer panel closes and unlocks input")
		hub.player.global_position = hub_spot
		await _wait_frames(2)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(not trainer._prompt.visible, "trainer prompt hides at a distance")
	var carried := false
	for it in hub.player.equipment.inventory:
		if it.display_name == "Persistence Marker":
			carried = true
	_check(carried, "gear persists across zone travel")
	_check(hub.player.gold == 123 and hub.player.knows(&"earthbreaker") and hub.player.loadout[2] == &"earthbreaker",
		"gold, abilities and the loadout persist across zone travel")
	_check(absf(hub.player.health.current_health - carried_hp) < 1.0,
		"M11: health carries across zone travel (%.0f of %.0f)" % [hub.player.health.current_health, hub.player.health.max_health])
	# M11: resting by the hearth heals out of combat, never in a fight
	var rest_from := hub.player.global_position
	hub.player.global_position = HubZone.FIRE_POS + Vector3(2.5, 0.2, 0)
	hub.player._last_combat_msec = -1000000
	var rest_hp := hub.player.health.current_health
	await _wait_frames(30)
	_check(hub.player.health.current_health > rest_hp + 1.0, "resting by the hearth heals out of combat")
	hub.player.mark_combat()
	rest_hp = hub.player.health.current_health
	await _wait_frames(20)
	_check(is_equal_approx(hub.player.health.current_health, rest_hp), "the hearth does not heal in a fight")
	hub.player.global_position = rest_from
	hub.player._last_combat_msec = -1000000
	hub.player.health.heal_full()
	var druid_trainer := hub.world.get_node_or_null("TrainerDruid") as TrainerNpc
	_check(druid_trainer != null and druid_trainer.npc_name.begins_with("Hild") and druid_trainer.teaches_class == &"druid",
		"M11: Hild, the druid's trainer, stands in Runehold")

	# ===== M10b: Healing Draughts (no regeneration; drunk from the inventory) =====
	var hp := hub.player
	var draught := Consumables.HEALING_DRAUGHT
	_check(hp.consumable_count(draught) == 3, "M10b: the draughts persist across zone travel")
	var merchant := hub.world.get_node_or_null("Merchant") as MerchantNpc
	_check(merchant != null and merchant.npc_name.begins_with("Ylva") and merchant.sells.has(draught),
		"M10b: Ylva stands in Runehold and sells Healing Draughts")
	if merchant != null:
		hp.add_gold(100 - hp.gold)
		hub.trainer_ui.open(merchant, hp)
		var shelf := 0
		for row: Node in hub.trainer_ui._rows.get_children():
			shelf += 0 if row.is_queued_for_deletion() else 1  # the trainer's rows go at the frame's end
		_check(hub.trainer_ui.visible and shelf == 2, "the merchant opens the panel as a shop: draughts and (M12) ember tubers (%d rows)" % shelf)
		var price := Consumables.price(draught)
		_check(hub.trainer_ui.try_buy_consumable(draught) and hp.gold == 100 - price and hp.consumable_count(draught) == 4,
			"buying a draught costs %d gold and fills the bag" % price)
		hub.trainer_ui.try_buy_consumable(draught)
		_check(hp.consumable_count(draught) == Consumables.cap(draught)
			and TrainerUI.buy_deny_reason(hp, draught) == "Bag full" and not hub.trainer_ui.try_buy_consumable(draught),
			"the bag holds %d; a full bag refuses the next one" % Consumables.cap(draught))
		hub.trainer_ui.close()
	_check(hp.add_consumable(draught, 3) == 0, "add_consumable takes nothing past the cap")
	# drinking: only when hurt, one at a time, 35 % over 4 s
	hp.health.current_health = hp.health.max_health
	_check(hp.consumable_deny_reason(draught) == "Health is full" and not hp.use_consumable(draught),
		"no drinking at full health")
	hp.health.current_health = hp.health.max_health * 0.4
	var before_drink := hp.health.current_health
	_check(hp.use_consumable(draught) and hp.consumable_count(draught) == Consumables.cap(draught) - 1,
		"drinking uses one draught")
	_check(hp.consumable_deny_reason(draught) == "Still drinking", "one draught at a time")
	hp.health.health_changed.emit(hp.health.current_health, hp.health.max_health)  # the HUD knows the start
	hub.hud._hurt_flash.color.a = 0.0
	await _wait_frames(60)
	_check(is_zero_approx(hub.hud._hurt_flash.color.a), "healing never flashes the screen red (only a loss does)")
	var mid_drink := hp.health.current_health
	await _wait_frames(200)
	var healed := hp.health.current_health - before_drink
	_check(mid_drink > before_drink and mid_drink < before_drink + hp.health.max_health * 0.3
		and absf(healed - hp.health.max_health * 0.35) < 1.0 and is_zero_approx(hp.healing_left()),
		"a draught heals over its 4 s: %.0f after 1 s, %.0f in all (35 %% of %.0f)" % [mid_drink - before_drink, healed, hp.health.max_health])
	# M12 food: Ylva sells ember tubers; eaten only out of a fight, a hit ends the meal
	var tuber := Consumables.EMBER_TUBER
	if merchant != null:
		hp.add_gold(100)
		hub.trainer_ui.open(merchant, hp)
		_check(merchant.sells.has(tuber) and hub.trainer_ui.try_buy_consumable(tuber) and hp.consumable_count(tuber) == 1,
			"M12: Ylva sells ember tubers (%d gold)" % Consumables.price(tuber))
		hub.trainer_ui.close()
	hp.add_consumable(tuber, 2)
	_check(Consumables.is_food(tuber) and Consumables.display_name(tuber) == "Ember Tuber" and Consumables.cap(tuber) == 10
		and Consumables.text(tuber).contains("50 %"), "the ember tuber is food from the text table (cap 10, 50 % over 8 s)")
	hp.health.current_health = hp.health.max_health * 0.3
	hp.mark_combat()
	_check(hp.consumable_deny_reason(tuber) == Texts.t("ui.food.in_combat") and not hp.use_consumable(tuber),
		"no eating in a fight")
	hp.set(&"_last_combat_msec", -1000000)
	var before_meal := hp.health.current_health
	_check(hp.use_consumable(tuber) and hp.is_eating() and hp.consumable_deny_reason(tuber) == Texts.t("ui.food.eating"),
		"out of the fight the hero eats (one meal at a time)")
	await _wait_frames(120)
	var after_2s := hp.health.current_health - before_meal
	hp.mark_combat()
	await _wait_frames(30)
	var after_hit := hp.health.current_health - before_meal
	_check(not hp.is_eating() and after_2s > hp.health.max_health * 0.08 and after_2s < hp.health.max_health * 0.2
		and absf(after_hit - after_2s) < 0.5,
		"a meal heals slowly (%.0f in 2 s) and a hit ends it (%.0f after)" % [after_2s, after_hit])
	hp.set(&"_last_combat_msec", -1000000)
	hp.health.current_health = hp.health.max_health * 0.3
	before_meal = hp.health.current_health
	hp.use_consumable(tuber)
	await _wait_frames(540)
	_check(absf(hp.health.current_health - before_meal - hp.health.max_health * 0.5) < 1.0 and not hp.is_eating(),
		"a whole meal gives 50 %% over 8 s (%.0f of %.0f)" % [hp.health.current_health - before_meal, hp.health.max_health])
	# drops: a draught on the ground glides into the bag; a full bag leaves it lying
	var drops_before := 0
	for child in hub.world.get_children():
		if child is ConsumableDrop:
			drops_before += 1
	hub.receive_reward(hp, 0, 0, 0, [] as Array[ItemData], hp.global_position + Vector3(2.0, 0, 0), "", false, 2)
	var drops_now: Array[ConsumableDrop] = []
	for child in hub.world.get_children():
		if child is ConsumableDrop:
			drops_now.append(child)
	_check(drops_now.size() == drops_before + 2, "a reward with 2 draughts lays 2 flasks on the ground")
	await _wait_frames(90)
	var lying := 0
	for d in drops_now:
		if is_instance_valid(d) and not d.is_queued_for_deletion():
			lying += 1
	_check(hp.consumable_count(draught) == Consumables.cap(draught) and lying == 1,
		"one flask glides into the bag (%d/%d), the other stays: the bag is full" % [hp.consumable_count(draught), Consumables.cap(draught)])
	for d in drops_now:
		if is_instance_valid(d):
			d.queue_free()
	# the rolls: bosses always leave two for every hero, chests often one
	var boss_probe := AshveinColossus.new()
	_check(Consumables.roll_kill(boss_probe) == Consumables.BOSS_DRAUGHTS, "a boss leaves %d draughts per hero" % Consumables.BOSS_DRAUGHTS)
	boss_probe.free()
	# the inventory shows the bag above the gear; the HUD counts it next to the gold
	hub.inventory_ui.toggle()
	await _wait_frames(2)
	var bag_row: Button = null
	if hub.inventory_ui._bag_box.get_child_count() > 0:
		bag_row = hub.inventory_ui._bag_box.get_child(0) as Button
	_check(bag_row != null and bag_row.text.begins_with("Healing Draught") and bag_row.text.ends_with("%d/%d" % [
		Consumables.cap(draught), Consumables.cap(draught)]), "the inventory lists the draughts (%s)" % (bag_row.text if bag_row != null else "-"))
	hp.health.current_health = hp.health.max_health * 0.5
	hub.inventory_ui._drink(draught)
	_check(hp.consumable_count(draught) == Consumables.cap(draught) - 1 and hp.healing_left() > 0.0,
		"drinking from the inventory (right-click) starts the heal")
	hub.inventory_ui.toggle()
	_check(hub.hud._draught_label.text == str(Consumables.cap(draught) - 1), "the HUD counts the draughts next to the gold")
	await _wait_frames(260)
	hp.consumables = {}
	hp.consumables_changed.emit()

	# --- M06 C3: Runehold kit on the unchanged hub layout ---
	_check(hub.look != null and hub.look.art_pass, "hub uses the Runehold ZoneLook (art pass)")
	var hub_bodies := hub.world.find_children("*", "StaticBody3D", true, false)
	_check(hub_bodies.size() == 24, "hub dressing adds no collision (%d bodies: layout 19 + three trainers + the merchant + the M08 shrine)" % hub_bodies.size())
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
	# M13: the two dungeon gates - sealed until a hero comes close, facing
	# their spurs (the arrival lands on the path side), named with a level
	var dungeon_gates: Dictionary = {}
	for child in highlands.world.get_children():
		if child is DungeonGatePortal:
			dungeon_gates[(child as DungeonGatePortal).gate_id] = child
	_check(dungeon_gates.size() == 2 and (dungeon_gates.get("dungeon_e") as DungeonGatePortal).locked
		and (dungeon_gates.get("dungeon_w") as DungeonGatePortal).locked,
		"M13: two dungeon gates stand sealed in the Highlands")
	var gate_e := dungeon_gates.get("dungeon_e") as DungeonGatePortal
	var gate_w := dungeon_gates.get("dungeon_w") as DungeonGatePortal
	if gate_e != null and gate_w != null:
		_check(gate_e.destination_scene == "res://scenes/hollow_cistern.tscn" and gate_e.arrival == "ci_exit"
			and gate_e.is_open() and not gate_w.is_open(),
			"M13: the east gate leads into the Hollow Cistern, the Ember Warrens stay sealed until built")
		var gates_face_spurs := true
		for pair: Array in [[gate_e, Vector3(126, 0, -56)], [gate_w, Vector3(-132, 0, -30)]]:
			var g := pair[0] as DungeonGatePortal
			var spur := pair[1] as Vector3
			var to_spur := Vector3(spur.x - g.global_position.x, 0.0, spur.z - g.global_position.z).normalized()
			var gate_front := Vector3(sin(g.facing_yaw()), 0.0, cos(g.facing_yaw()))
			var arrive := highlands._arrival_point(g.gate_id)
			if gate_front.dot(to_spur) < 0.7 or arrive.distance_to(spur) >= g.global_position.distance_to(spur):
				gates_face_spurs = false
		_check(gates_face_spurs, "M13: the dungeon gates face their spurs; arrivals land on the path side")
		_check(gate_e._label.text.contains("4") and gate_w._label.text.contains("5"),
			"M13: the gate labels name the recommended level (%s / %s)" % [gate_e._label.text, gate_w._label.text])

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
		if not body.has_meta(&"floating"):  # M12: a grotto's roof rests on its walls
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

	# --- M12 phase 1: the sub-biomes (mask, looks, the forest, scatter per look) ---
	var at_poi := func(id: String) -> Vector3:
		return hl_layout.biome_weights(hl_layout.poi_pos(id).x, hl_layout.poi_pos(id).z)
	_check(",".join(hl_layout.biome_ids) == "village,burnt_forest,bone_field" and hl_layout.biome_image() != null,
		"the Highlands have three sub-biomes and their mask reads headless")
	var w_c3: Vector3 = at_poi.call("camp_3")
	var w_c8: Vector3 = at_poi.call("camp_8")
	var w_c7: Vector3 = at_poi.call("camp_7")
	var w_c6: Vector3 = at_poi.call("camp_6")
	var w_c1: Vector3 = at_poi.call("camp_1")
	_check(w_c3.x > 0.9 and w_c8.y > 0.9 and w_c7.z > 0.9 and w_c6.length() < 0.05 and w_c1.length() < 0.05,
		"mask weights: camp 3 village, camp 8 forest, camp 7 bones, camps 6 and 1 ash (%s %s %s %s %s)" % [w_c3, w_c8, w_c7, w_c6, w_c1])
	var stamps_ok := true
	for pair: Array in [["camp_3", "village"], ["village_w", "village"], ["camp_8", "burnt_forest"], ["dungeon_w", "burnt_forest"],
			["cave_tome", "burnt_forest"], ["camp_7", "bone_field"], ["trial_b", "bone_field"], ["camp_1", "ash"], ["camp_6", "ash"], ["dungeon_e", "bone_field"]]:
		var poi_b := hl_layout.find(String(pair[0]))
		var px := hl_layout.poi_pos(String(pair[0]))
		stamps_ok = stamps_ok and String(poi_b.get("biome", "")) == String(pair[1]) and hl_layout.biome_at(px.x, px.z) == String(pair[1])
	_check(stamps_ok, "the bake stamps each POI with its biome and biome_at agrees")
	var looks_ok := true
	for role: StringName in [&"highlands_ground", &"highlands_rock", &"highlands_ruin"]:
		for slot in ["tops_a", "tops_b", "sides"]:
			var layers := ArtKit.biome_layers(role, slot)
			looks_ok = looks_ok and layers.size() == 4
			for n: String in layers:
				looks_ok = looks_ok and FileAccess.file_exists(ArtKit.BIOME_DIR + n + ".png")
	_check(looks_ok and ArtKit.biome_layers(&"highlands_ground", "trails").size() == 4,
		"every terrain role has four looks per slot and every texture exists")
	var grove_trees := 0
	var grove_bad := {"route": 0, "clearing": 0, "layer": 0}
	var hl_corridors := highlands._route_segments()
	for child in highlands.dressing().get_children():
		if child.name.begins_with("Grove_"):
			for p: Vector3 in (child as Node).get_meta(Grove.POINTS_META, PackedVector3Array()):
				grove_trees += 1
				if highlands._near_route(Vector2(p.x, p.z), hl_corridors, 2.4):
					grove_bad["route"] += 1
				for cid in ["camp_8", "trial_f", "nest_f", "ruin_3"]:
					var cp := hl_layout.poi_pos(cid)
					if Vector2(p.x - cp.x, p.z - cp.z).length() < float(hl_layout.find(cid).get("pad", 0.0)) + 13.0:
						grove_bad["clearing"] += 1
	for child in highlands.world.get_children():
		if child.name.begins_with("GroveBody_") and (child as StaticBody3D).collision_layer != Grove.FOLIAGE_LAYER:
			grove_bad["layer"] += 1
	_check(grove_trees >= 120 and grove_bad.values().all(func(n: int) -> bool: return n == 0),
		"the burnt forest: %d trunks, off the routes, clear of camps and shrines, on the foliage layer %s" % [grove_trees, str(grove_bad)])
	_check(highlands.camera_rig.spring.collision_mask & Grove.FOLIAGE_LAYER == 0
		and highlands.player.collision_mask & Grove.FOLIAGE_LAYER != 0,
		"heroes bump into trunks, the camera does not")
	var bones_total := 0
	var bones_inside := 0
	for child in highlands.dressing().get_children():
		if child.name.begins_with("Scatter_bone_pile"):
			for p: Vector3 in (child as Node).get_meta(Scatter.POINTS_META, PackedVector3Array()):
				bones_total += 1
				if hl_layout.biome_weight("bone_field", p.x, p.z) > 0.0:
					bones_inside += 1
	_check(bones_total > 40 and bones_inside == bones_total,
		"bones lie only in the bone field (%d of %d)" % [bones_inside, bones_total])
	var area_parent := highlands.hud.get_child(0)
	var area_labels0 := area_parent.get_child_count()
	var hero_home := highlands.player.global_position
	highlands.player.global_position = hl_layout.poi_pos("village_w") + Vector3(0, 1, 0)
	highlands._area_seen = {}
	highlands._discover_tick()
	var area_new := area_parent.get_child_count() - area_labels0
	var area_text := str((area_parent.get_child(area_parent.get_child_count() - 1) as Label).text) if area_new > 0 else ""
	_check(area_new == 1 and area_text == "Ashwick",
		"entering two areas at once shows one name, the smaller place (%d, %s)" % [area_new, area_text])
	highlands.player.global_position = hero_home
	# M12 phase 1b: the set pieces (village, graveyard, the skeleton, the scenes)
	var house_walls := 0
	for child in highlands.world.get_children():
		if child.name.begins_with("HouseWall"):
			house_walls += 1
	var kit_counts := {}
	for child in highlands.dressing().get_children():
		for kit_name in ["vl_rafters", "vl_well", "vl_grave", "vl_fence", "bn_rib", "bn_skull", "vg_fallen", "vg_tent", "vl_barricade"]:
			if child.name.begins_with(kit_name):
				kit_counts[kit_name] = int(kit_counts.get(kit_name, 0)) + 1
	var graves := int(kit_counts.get("vl_grave", 0))  # vl_grave and vl_grave_cross
	_check(house_walls >= 30 and int(kit_counts.get("vl_rafters", 0)) >= 7 and int(kit_counts.get("vl_well", 0)) == 1,
		"Ashwick: seven ruined houses (%d wall pieces), their rafters and the well" % house_walls)
	_check(graves >= 10 and int(kit_counts.get("vl_fence", 0)) >= 10,
		"the graveyard has its graves (%d) and the lane and graveyard their fences (%d)" % [graves, int(kit_counts.get("vl_fence", 0))])
	_check(int(kit_counts.get("bn_rib", 0)) >= 15 and int(kit_counts.get("bn_skull", 0)) == 1,
		"the bone field: a giant skeleton with its skull and rib sets (%d ribs)" % int(kit_counts.get("bn_rib", 0)))
	_check(int(kit_counts.get("vg_fallen", 0)) >= 7 and int(kit_counts.get("vg_tent", 0)) == 2 and int(kit_counts.get("vl_barricade", 0)) == 2,
		"places that tell a story: the fallen, the abandoned camp, the barricade %s" % str(kit_counts))
	var fences_on_pads := 0
	var vl_pads := highlands._pads()
	for child in highlands.dressing().get_children():
		if child.name.begins_with("vl_fence"):
			var fp := (child as Node3D).global_position
			for pad in vl_pads:
				if Vector2(fp.x - pad.x, fp.z - pad.y).length() < pad.z - 1.5:
					fences_on_pads += 1
	_check(fences_on_pads == 0, "no fence stands on a combat or shrine pad (%d)" % fences_on_pads)
	var snags := 0
	for child in highlands.dressing().get_children():
		if child.name.begins_with("Grove_bf_snag"):
			snags += (child as MultiMeshInstance3D).multimesh.instance_count
	var stumps := 0
	for child in highlands.dressing().get_children():
		if child.name.begins_with("Scatter_bf_stump"):
			stumps += (child as Node).get_meta(Scatter.POINTS_META, PackedVector3Array()).size()
	_check(snags >= 25 and stumps >= 20, "the forest's undergrowth: %d snags, %d smouldering stumps" % [snags, stumps])

	# --- M12 phase 2: interactables, lore, the chronicle, shards, gathering, ghosts ---
	var texts_ok := true
	for poi in hl_layout.by_type("lore") + hl_layout.by_type("ghost"):
		var lid := String(poi.get("text", ""))
		texts_ok = texts_ok and Texts.has(lid + ".title") and Texts.has(lid + ".body")
	for poi in hl_layout.by_type("shard"):
		texts_ok = texts_ok and Texts.has("shard.%d" % int(poi.get("index", 0)))
	_check(texts_ok and highlands.lore_objects.size() == 12 and highlands.ghosts.size() == 2 and highlands.shards.size() == RuneShard.TOTAL,
		"12 lore objects, 2 ghosts, 12 shards; every text in the table (%d / %d / %d)"
		% [highlands.lore_objects.size(), highlands.ghosts.size(), highlands.shards.size()])
	var hero12 := highlands.player
	var spot12 := hl_layout.poi_pos("camp_1") + Vector3(0, 0, 18)
	hero12.global_position = highlands.ground_point(spot12, 0.2)
	var near_a := LoreObject.build(highlands, {"id": "smoke_a", "kind": "note", "text": "lore.ash.letter_1",
		"pos": [spot12.x + 1.0, spot12.z]})
	var near_b := LoreObject.build(highlands, {"id": "smoke_b", "kind": "note", "text": "lore.ash.ledger",
		"pos": [spot12.x + 1.8, spot12.z]})
	await get_tree().process_frame
	await get_tree().process_frame
	_check(near_a._prompt.visible and not near_b._prompt.visible,
		"two things in reach: only the nearer one shows its [E] prompt")
	near_a.queue_free()
	near_b.queue_free()
	hero12.progression.xp = 0  # well short of the next level: the reward shows as it is
	var xp0 := hero12.progression.xp
	var lore_grave := highlands.lore_objects["lore_grave_nameless"] as LoreObject
	hero12.global_position = lore_grave.global_position + Vector3(1.0, 0.2, 0)
	lore_grave.use_by(hero12)
	var first_xp := hero12.progression.xp - xp0
	_check(highlands.lore_ui.visible and highlands.lore_ui.shown_id == "lore.village.grave_nameless"
		and str((highlands.lore_ui.get(&"_kind") as Label).text) == "GRAVE" and hero12.lore_read.has("lore.village.grave_nameless")
		and first_xp == LoreObject.READ_XP, "reading a grave opens its text, puts it in the chronicle, +%d XP" % first_xp)
	highlands.lore_ui.close()
	lore_grave.use_by(hero12)
	_check(hero12.progression.xp - xp0 == LoreObject.READ_XP, "reading it again pays nothing")
	highlands.lore_ui.close()
	var chron_ev := InputEventAction.new()
	chron_ev.action = &"chronicle_toggle"
	chron_ev.pressed = true
	highlands.lore_ui._unhandled_input(chron_ev)
	var chron_list := highlands.lore_ui.get(&"_list_box") as VBoxContainer
	await get_tree().process_frame
	_check(highlands.lore_ui.visible and highlands.lore_ui.chronicle and chron_list.get_child_count() >= 2
		and highlands.lore_ui.shown_id == "lore.village.grave_nameless", "L opens the chronicle with what this hero has read")
	highlands.lore_ui._unhandled_input(chron_ev)
	_check(not highlands.lore_ui.visible and not hero12.input_locked, "L again closes it")
	var shard := highlands.shards["shard_4"] as RuneShard
	var gold0 := hero12.gold
	hero12.global_position = shard.global_position + Vector3(1.0, 0.2, 0)
	shard.use_by(hero12)
	await get_tree().process_frame
	_check(hero12.collected.has("shard_4") and shard.prompt_text(hero12) == "" and not shard.can_interact(hero12),
		"a rune shard is taken once (gold +%d)" % (hero12.gold - gold0))
	_check(highlands.gather_nodes.size() == 40 and highlands.world.get_node_or_null("Gather_pot_camp_1") != null,
		"40 ember tuber patches and a cooking pot in every camp")
	var patch12 := highlands.gather_nodes["tuber_0"] as GatherNode
	var bag0 := hero12.consumable_count(Consumables.EMBER_TUBER)
	hero12.consumables[Consumables.EMBER_TUBER] = 0
	patch12.use_by(hero12)
	_check(hero12.consumable_count(Consumables.EMBER_TUBER) == 1 and not patch12.ready_for(hero12) and patch12.prompt_text(hero12) == "",
		"gathering a patch fills the bag; the patch is empty for this hero")
	hero12.gathered["tuber_0"] = Time.get_unix_time_from_system() - GatherNode.RESPAWN_S - 1.0
	hero12.consumables[Consumables.EMBER_TUBER] = Consumables.cap(Consumables.EMBER_TUBER)
	_check(patch12.ready_for(hero12) and patch12.prompt_text(hero12) == Texts.t("ui.prompt.bag_full"),
		"a patch grows back after 15 min; a full bag says so")
	hero12.consumables[Consumables.EMBER_TUBER] = bag0
	var gather_bad := 0
	for key: String in highlands.gather_nodes:
		var gnp := (highlands.gather_nodes[key] as Node3D).global_position
		if highlands._near_route(Vector2(gnp.x, gnp.z), hl_corridors, 1.5) or highlands._near_pad(Vector2(gnp.x, gnp.z), vl_pads, 2.0):
			gather_bad += 1
	_check(gather_bad == 0, "no tuber patch sits on a trail or a pad (%d)" % gather_bad)
	var saved12 := SaveGame.character_dict(hero12)
	_check((saved12["lore_read"] as Array).has("lore.village.grave_nameless") and (saved12["collected"] as Array).has("shard_4")
		and (saved12["gathered"] as Dictionary).has("tuber_0"), "lore read, shards and gathered patches go into the save")
	var ghost12 := highlands.ghosts["ghost_burner_f"] as Ghost
	hero12.global_position = ghost12.global_position + Vector3(1.5, 0.2, 0)
	ghost12.use_by(hero12)
	_check(highlands.lore_ui.visible and highlands.lore_ui.shown_id == "lore.ghost.burner" and hero12.lore_read.has("lore.ghost.burner"),
		"a ghost tells its story ([E] Listen)")
	highlands.lore_ui.close()
	highlands._discover_tick()
	var lore_marked := false
	for m in highlands.map_markers():
		lore_marked = lore_marked or String(m.get("icon", "")) == "ghost"
	_check(lore_marked and hero12.map_discovered.has("ghost_burner_f"), "a ghost seen up close shows on the map")

	# --- M12 phase 3: the four outdoor puzzles, the grottos, the secret climb ---
	var braz := highlands.puzzles["braziers_v"] as BrazierPuzzle
	hero12.global_position = braz.global_position + Vector3(0, 0.3, 0)
	var target0 := braz.get_node("BrazierTarget0") as BrazierTarget
	var gave := target0.take_hit(HitInfo.create(5.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, target0.global_position))
	_check(not gave and bool((braz.state["lit"] as Array)[0]) and not braz.is_solved()
		and not EnemyBase.all_enemies.has(braz), "a hit lights a brazier (no Resonance from it); one is not enough")
	braz.set(&"_lit_at", [float(Time.get_ticks_msec()) - BrazierPuzzle.WINDOW * 1000.0 - 100.0, -1.0, -1.0] as Array[float])
	braz._process(0.0)
	_check(not bool((braz.state["lit"] as Array)[0]), "a brazier burns out after %d s" % int(BrazierPuzzle.WINDOW))
	for bi in 3:
		braz.strike(bi, hero12)
	await get_tree().process_frame
	_check(braz.is_solved() and highlands.world.get_node_or_null("PuzzleChest_braziers_v") != null
		and bool(SaveGame.poi_state("braziers_v").get("solved", false)),
		"all three alight at once: solved, the crypt chest is there, the world remembers")
	_check((highlands.world.get_node_or_null("PuzzleChest_braziers_v") as TreasureChest).persist_key == "chest:braziers_v_chest",
		"M13: a puzzle's chest opens once (it keeps its state in the world)")
	var mono := highlands.puzzles["monoliths_x"] as MonolithPuzzle
	hero12.global_position = mono.global_position + Vector3(0, 0.3, 0)
	var reach0 := mono.beam_reach()
	var turns := 0
	for si in MonolithPuzzle.STONES.size():
		for _t in 8:
			if mono.beam_reach() > si or mono.is_solved():
				break
			mono.request("turn", si, hero12)
			turns += 1
	_check(reach0 < MonolithPuzzle.STONES.size() and mono.is_solved() and mono.beam_reach() == MonolithPuzzle.STONES.size(),
		"turning the stones carries the beam stone by stone to the seal (%d turns from reach %d)" % [turns, reach0])
	var cave_tome: Dictionary = highlands.grottos["cave_tome"]
	var boulder := cave_tome["puzzle"] as BoulderPuzzle
	var door := cave_tome["door"] as StaticBody3D
	_check((cave_tome["roof"] as Node).has_meta(&"floating") and door != null and door.collision_layer == 1
		and highlands.grottos.has("cave_flats") and highlands.chests.has("cave_flats"),
		"two grottos (roofed rock hulls); the tome grotto is sealed, the other holds a chest")
	hero12.global_position = boulder.global_position + Vector3(0, 0.3, 0)
	var rock0 := (boulder.get(&"_rock") as Node3D).global_position
	for _p in boulder.steps:
		boulder.request("push", 0, hero12)
	await _wait_frames(110)
	var rock1 := (boulder.get(&"_rock") as Node3D).global_position
	_check(boulder.is_solved() and rock1.distance_to(rock0) > BoulderPuzzle.STEP * (boulder.steps - 1)
		and door.collision_layer == 0, "the boulder rolls step by step onto the plate and the grotto's door sinks")
	var run := highlands.puzzles["dodge_b"] as DodgeRun
	var strip_at := run.strip_centre(2)
	hero12.global_position = highlands.ground_point(strip_at, 0.1)
	hero12.health.current_health = 5.0
	run._burst(2, hero12)
	var off_at := run.strip_centre(2) + Vector3(0, 0, 0) + (run.end - run.start).normalized() * 2.5
	_check(run.on_strip(2, strip_at) and not run.on_strip(2, off_at) and is_equal_approx(hero12.health.current_health, 1.0)
		and not hero12.health.is_dead and highlands.chests.has("dodge_b"),
		"the dodge run's spikes hurt whoever stands on the strip, never the last point; a chest at the end")
	hero12.health.current_health = hero12.health.max_health
	var climb_stones := 0
	var climb := hl_layout.route_points("climb_tome")
	for child in highlands.world.get_children():
		if child.name.begins_with("Rock") and child is Node3D:
			var cp := Vector2((child as Node3D).global_position.x, (child as Node3D).global_position.z)
			for ci in climb.size() - 1:
				var seg := climb[ci + 1] - climb[ci]
				var tt := clampf((cp - climb[ci]).dot(seg) / seg.length_squared(), 0.0, 1.0)
				if cp.distance_to(climb[ci] + seg * tt) < 3.0:
					climb_stones += 1
					break
	_check(climb_stones >= 6, "the secret climb has low stones along its edge (%d)" % climb_stones)

	# --- M12 phase 4: the village and forest families ---
	var types_ok := true
	for pair: Array in [["grave_shambler", GraveShambler], ["mourner", Mourner], ["cinderbark", Cinderbark],
			["smoulder_wisp", SmoulderWisp], ["brute", Brute]]:
		var probe := ZoneBase.make_enemy(String(pair[0]))
		types_ok = types_ok and is_instance_of(probe, pair[1]) and probe.type_id == String(pair[0])
		probe.free()
	var odd := ZoneBase.make_enemy("no_such_enemy")
	types_ok = types_ok and odd is MeleeRusher
	odd.free()
	var c3_comp := PoiBuilder.composition_of(hl_layout.find("camp_3"))
	var c8_comp := PoiBuilder.composition_of(hl_layout.find("camp_8"))
	_check(types_ok and c3_comp.has("grave_shambler") and c3_comp.has("mourner") and c8_comp.has("cinderbark")
		and c8_comp.has("smoulder_wisp") and highlands.camps.has("lurker_f1")
		and AshenHighlands.marker_label(hl_layout.find("camp_3")) == Texts.t("map.camp.village"),
		"the registry knows the four new enemies; camp 3 holds the Restless, camp 8 the Charwood, lurkers wait")
	var foe_spot := hl_layout.poi_pos("trial_f") + Vector3(0, 0.2, 0)
	hero12.global_position = highlands.ground_point(foe_spot + Vector3(0, 0, 14), 0.2)
	var shambler := highlands.spawn_by_id("grave_shambler", highlands.ground_point(foe_spot, 0.2)) as GraveShambler
	await _wait_frames(3)
	var buried_ok := shambler.ai_state == EnemyBase.AIState.BURIED and not shambler.targetable and shambler.collision_layer == 0 \
		and not shambler.take_hit(HitInfo.create(10.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, foe_spot)) \
		and not shambler.visual.visible and is_equal_approx(shambler.health.current_health, shambler.health.max_health)
	hero12.global_position = highlands.ground_point(foe_spot + Vector3(0, 0, 4), 0.2)
	await _wait_frames(15)
	var emerging := shambler.ai_state == EnemyBase.AIState.EMERGE
	await _wait_frames(70)
	_check(buried_ok and emerging and shambler.targetable and shambler.visual.visible and shambler.collision_layer == 0b100,
		"a grave shambler waits buried (no target, no hit), claws out when a hero comes near, then fights")
	shambler.queue_free()
	var bark := highlands.spawn_by_id("cinderbark", highlands.ground_point(foe_spot + Vector3(8, 0, 0), 0.2)) as Cinderbark
	hero12.global_position = highlands.ground_point(foe_spot + Vector3(8, 0, 16), 0.2)
	await _wait_frames(3)
	var dormant_ok := bark.ai_state == EnemyBase.AIState.DORMANT and not bark.targetable \
		and bark.collision_layer == Grove.FOLIAGE_LAYER and bark.loot_kind == &"brute"
	var aimed := false
	for cand in highlands.targeting.gather_candidates():
		aimed = aimed or cand == bark
	hero12.global_position = highlands.ground_point(foe_spot + Vector3(8, 0, 4), 0.2)
	await _wait_frames(70)
	_check(dormant_ok and not aimed and bark.targetable and bark.ai_state != EnemyBase.AIState.DORMANT,
		"a cinderbark stands as a trunk (solid, no target) until a hero comes close, then wakes")
	bark.queue_free()
	var mourn := highlands.spawn_by_id("mourner", highlands.ground_point(foe_spot + Vector3(-8, 0, 0), 0.2)) as Mourner
	await _wait_frames(2)
	mourn.visual.rotation.y = 0.0  # facing -Z
	hero12.global_position = highlands.ground_point(mourn.global_position + Vector3(0, 0, -3.0), 0.2)
	hero12.clear_slow()
	mourn.lock_strike()
	var hp_mourn := hero12.health.current_health
	mourn._scream()
	_check(is_equal_approx(hero12.slow_pct, Player.CHILL_SLOW) and hero12.health.current_health < hp_mourn,
		"the mourner's scream hurts and slows a hero in its strip (%.0f %%)" % (hero12.slow_pct * 100.0))
	hero12.apply_slow(0.2, 1.0)
	var kept := is_equal_approx(hero12.slow_pct, Player.CHILL_SLOW)
	hero12.set(&"_slow_left", 0.01)
	await _wait_frames(3)
	_check(kept and is_zero_approx(hero12.slow_pct), "the stronger slow wins, and it wears off")
	hero12.health.current_health = hero12.health.max_health
	mourn.queue_free()
	var wisp := highlands.spawn_by_id("smoulder_wisp", highlands.ground_point(foe_spot + Vector3(0, 0, -10), 0.2)) as SmoulderWisp
	await _wait_frames(2)
	wisp.player = hero12
	hero12.global_position = highlands.ground_point(wisp.global_position + Vector3(0, 0, 2.0), 0.2)
	var wisp_from := wisp.global_position
	wisp._start_blink()
	await _wait_frames(40)
	_check(wisp.global_position.distance_to(wisp_from) >= SmoulderWisp.BLINK_MIN - 0.5 and wisp.visual.visible
		and wisp.ai_state == EnemyBase.AIState.CHASE, "a cornered smoulder wisp blinks away (%.1f m)" % wisp.global_position.distance_to(wisp_from))
	wisp.queue_free()
	await _wait_frames(2)
	# --- M12 phase 5: the bone field's carrion brood and the animals ---
	var c7_comp := PoiBuilder.composition_of(hl_layout.find("camp_7"))
	var brood_ok := is_instance_of(ZoneBase.make_enemy("ash_jackal"), AshJackal) \
		and is_instance_of(ZoneBase.make_enemy("carrion_vulture"), CarrionVulture)
	_check(brood_ok and c7_comp.count("ash_jackal") == 3 and c7_comp.has("carrion_vulture")
		and highlands.camps.has("lurker_b1")
		and AshenHighlands.marker_label(hl_layout.find("camp_7")) == Texts.t("map.camp.bone_field"),
		"camp 7 holds the carrion brood (three jackals and a vulture), a vulture lurks over the bones")
	var brood_spot := foe_spot  # the forest shrine's clearing: the bone field would wake the elite patrol
	hero12.global_position = highlands.ground_point(brood_spot + Vector3(0, 0, 7.0), 0.2)
	hero12.health.current_health = hero12.health.max_health
	var vult := highlands.spawn_by_id("carrion_vulture", highlands.ground_point(brood_spot, 0.2)) as CarrionVulture
	await _wait_frames(3)
	var aloft_ok := CarrionVulture.airborne(vult.ai_state) and not vult.targetable and vult.collision_layer == 0 \
		and vult.collision_mask == 0 and not vult.take_hit(HitInfo.create(10.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, brood_spot))
	var aimed_v := false
	for cand in highlands.targeting.gather_candidates():
		aimed_v = aimed_v or cand == vult
	vult.player = hero12
	vult.global_position = highlands.ground_point(brood_spot, 0.2)
	vult.velocity = Vector3.ZERO
	var hp_vult := hero12.health.current_health
	vult._start_dive()
	await _wait_frames(int((CarrionVulture.DIVE_WINDUP + CarrionVulture.DIVE_TIME) * 60.0) + 6)
	var landed_ok := vult.ai_state == EnemyBase.AIState.RECOVER and vult.targetable and vult.collision_layer == 0b100 \
		and vult.global_position.distance_to(brood_spot) > CarrionVulture.DIVE_LENGTH - 2.0
	_check(aloft_ok and not aimed_v and landed_ok and hero12.health.current_health < hp_vult,
		"a carrion vulture circles out of reach, swoops down its lane (the hero in it is struck) and lands, open to hits")
	await _wait_frames(int((CarrionVulture.LANDED_TIME + CarrionVulture.TAKEOFF_TIME) * 60.0) + 6)
	_check(CarrionVulture.airborne(vult.ai_state) and not vult.targetable,
		"after LANDED_TIME on the ground the vulture beats back up into the air")
	vult.queue_free()
	# a hero at the edge of its leash: it must still come down (it used to fly
	# out and home again for ever, out of reach)
	var edge_home := Vector3(-30.0, 0.0, 150.0)  # open ash in the south (no trunks across its lanes)
	var edge_vult := highlands.spawn_by_id("carrion_vulture", highlands.ground_point(edge_home, 0.2)) as CarrionVulture
	edge_vult.home = edge_vult.global_position
	edge_vult.leash = 22.0
	hero12.global_position = highlands.ground_point(edge_home + Vector3(19.0, 0, 0), 0.2)
	var edge_dived := false
	for e_frame in 900:
		await _wait_frames(1)
		if edge_vult.ai_state in [EnemyBase.AIState.ATTACK, EnemyBase.AIState.RECOVER]:
			edge_dived = true
			break
	_check(edge_dived, "a hero at the edge of a vulture's leash still draws its dive")
	edge_vult.queue_free()
	hero12.health.current_health = hero12.health.max_health
	hero12.health.current_health = hero12.health.max_health
	AshJackal._next_leap_at.clear()
	var jack_a := highlands.spawn_by_id("ash_jackal", highlands.ground_point(brood_spot + Vector3(-4, 0, 0), 0.2)) as AshJackal
	var jack_b := highlands.spawn_by_id("ash_jackal", highlands.ground_point(brood_spot + Vector3(4, 0, 0), 0.2)) as AshJackal
	await _wait_frames(2)
	jack_a.player = hero12
	jack_b.player = hero12
	var turns_ok := jack_a._claim_leap() and not jack_b._claim_leap()
	jack_b.queue_free()
	hero12.global_position = highlands.ground_point(jack_a.global_position + Vector3(0, 0, -AshJackal.LEAP_DIST), 0.2)
	jack_a.velocity = Vector3.ZERO
	var jack_from := jack_a.global_position
	var hp_jack := hero12.health.current_health
	jack_a._start_windup()
	await _wait_frames(int((AshJackal.WINDUP_TIME + AshJackal.LEAP_TIME) * 60.0) + 4)
	_check(turns_ok and hero12.health.current_health < hp_jack and jack_a.global_position.distance_to(jack_from) > 3.0
		and jack_a.ai_state in [EnemyBase.AIState.RECOVER, EnemyBase.AIState.RETREAT],
		"ash jackals take turns at a hero; a crouch, the leap onto the marked spot, the bite (%.1f m)" % jack_a.global_position.distance_to(jack_from))
	jack_a.queue_free()
	hero12.health.current_health = hero12.health.max_health
	var field := highlands.critter_field
	var kinds_ok := CritterField.kind_for(Vector3(0, 1, 0), 0.5) == -1 and CritterField.kind_for(Vector3(0, 0, 1), 0.9) == Critter.Kind.CROW \
		and CritterField.kind_for(Vector3.ZERO, 0.5) == Critter.Kind.HARE and CritterField.kind_for(Vector3(1, 0, 0), 0.3) == Critter.Kind.CROW
	hero12.global_position = highlands.ground_point(Vector3(-20.0, 0.0, 150.0), 0.2)
	if field != null:
		for i in 40:
			field.tick()
	var crit_count := field.critters.size() if field != null else 0
	var crit_clean := field != null and field.find_children("*", "CollisionObject3D", true, false).is_empty()
	_check(field != null and kinds_ok and crit_count >= 1 and crit_count <= CritterField.MAX_ACTIVE and crit_clean,
		"the animals: hares in the ash, crows on the bones, none in the burnt forest; %d around the hero, no bodies, no enemies" % crit_count)
	var hare := Critter.create(highlands, Critter.Kind.HARE, hero12.global_position + Vector3(5.0, 0, 0))
	var crow := Critter.create(highlands, Critter.Kind.CROW, hero12.global_position + Vector3(-5.0, 0, 0))
	var flee_t := 0.0
	while flee_t < 0.8:  # by time: headless process frames come faster than 60 a second
		await get_tree().process_frame
		flee_t += get_process_delta_time()
	var hare_d := hare.global_position.distance_to(hero12.global_position) if is_instance_valid(hare) else 0.0
	var crow_up := is_instance_valid(crow) and crow.state == Critter.State.FLEE and crow.height > 0.2
	_check(is_instance_valid(hare) and hare.state == Critter.State.FLEE and hare_d > 6.0 and crow_up,
		"a hare bolts from a hero (%.1f m off), a crow takes off" % hare_d)
	var crow_t := 0.0
	while is_instance_valid(crow) and crow_t < Critter.CROW_GONE + 2.0:
		await get_tree().process_frame
		crow_t += get_process_delta_time()
	_check(not is_instance_valid(crow), "the crow is gone after its flight (%.1f s)" % crow_t)
	if is_instance_valid(hare):
		hare.queue_free()
	await _wait_frames(2)
	# --- M12 phase 6: blessings, the cursed graveyard, the nests, the trial shrines ---
	var kill_all := func(foes: Array) -> void:
		for foe in foes:
			if is_instance_valid(foe) and (foe as EnemyBase).ai_state != EnemyBase.AIState.DEAD:
				(foe as EnemyBase).take_hit(HitInfo.create(99999.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT,
					(foe as EnemyBase).global_position))
	var bless_hp := hero12.health.max_health
	hero12.blessings = PackedStringArray()
	var bless_ok := is_equal_approx(Blessings.stat(PackedStringArray(["ashwick", "shards"]), &"max_hp_pct"), 6.0) \
		and hero12.grant_blessing(&"ashwick") and not hero12.grant_blessing(&"ashwick") \
		and absf(hero12.health.max_health - bless_hp * 1.03) < 0.6 \
		and hero12.grant_blessing(&"charwood") and is_equal_approx(Blessings.stat(hero12.blessings, &"damage_pct"), 2.0) \
		and (SaveGame.character_dict(hero12)["blessings"] as Array).has("charwood")
	hero12.blessings = PackedStringArray()
	hero12.equipment._recompute()
	var probe_health := HealthComponent.new()
	add_child(probe_health)
	probe_health.max_health = 100.0
	probe_health.current_health = 50.0
	probe_health.heal_mult = 0.7
	var healed_cut := probe_health.heal(10.0)
	probe_health.queue_free()
	_check(bless_ok and is_equal_approx(healed_cut, 7.0) and is_equal_approx(hero12.health.max_health, bless_hp),
		"rune blessings add their stat (+3 %% health: %.0f -> %.0f) once, are saved; a heal_mult cuts heals" % [bless_hp, bless_hp * 1.03])
	var lantern_probe := ZoneBase.make_enemy("curse_lantern")
	var objects_ok := lantern_probe is CurseLantern and lantern_probe.immobile and lantern_probe.loot_kind == &"none" \
		and Consumables.roll_kill(lantern_probe) == 0 and highlands._roll_kill_item(lantern_probe, &"runebreaker") == null \
		and ZoneBase.make_enemy("wisp_nest") is WispNest and ZoneBase.make_enemy("jackal_den") is JackalDen
	lantern_probe.free()
	_check(objects_ok and AshenHighlands.marker_icon(hl_layout.find("trial_v")) == "trial"
		and AshenHighlands.marker_icon(hl_layout.find("nest_b")) == "nest" and AshenHighlands.marker_icon(hl_layout.find("graveyard_v")) == "cursed"
		and highlands.camps.has("nest_f") and highlands.puzzles.get("trial_b") is TrialShrine,
		"the registry knows the lanterns and nests (objects drop nothing); trials, nests and the graveyard have map marks")
	var grave := highlands.puzzles["graveyard_v"] as CursedGround
	var grave_centre := grave.global_position
	hero12.global_position = highlands.ground_point(grave_centre + Vector3(1.0, 0, 1.0), 0.2)
	hero12.god_mode = true
	await _wait_frames(4)
	await get_tree().process_frame
	var cursed_ok := not grave.is_solved() and is_equal_approx(hero12.health.heal_mult, CursedGround.HEAL_MULT) \
		and not grave.ghost.visible and grave.graves.size() >= 8
	grave.spawner.trigger(highlands, hero12)
	await _wait_frames(6)
	var lanterns := grave.spawner.pack()
	var lantern_ring_ok := lanterns.size() == 3
	for l in lanterns:
		lantern_ring_ok = lantern_ring_ok and absf(Vector2(l.global_position.x - grave_centre.x, l.global_position.z - grave_centre.z).length()
			- CursedGround.LANTERN_RING) < 0.6
	var lantern_at := lanterns[0].global_position
	var shove := HitInfo.create(5.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.HEAVY, lantern_at + Vector3(1, 0, 0))
	shove.knockback = 8.0
	lanterns[0].take_hit(shove)
	await _wait_frames(150)  # the first of the dead rises
	var risen_count := grave.risen.size()
	var still := lanterns[0].global_position.distance_to(lantern_at) < 0.05
	kill_all.call(lanterns)
	await _wait_frames(10)
	await get_tree().process_frame
	_check(cursed_ok and lantern_ring_ok and still and risen_count >= 1 and grave.is_solved() and grave.risen.is_empty()
		and is_equal_approx(hero12.health.heal_mult, 1.0) and grave.ghost.visible,
		"the cursed graveyard: heals cut on its ground, three unmoving lanterns, the dead rise (%d); broken, the curse lifts and the priest appears" % risen_count)
	var forest_spot := hl_layout.poi_pos("trial_f")
	hero12.global_position = highlands.ground_point(forest_spot + Vector3(3.0, 0, 6.0), 0.2)
	var nest := highlands.spawn_by_id("wisp_nest", highlands.ground_point(forest_spot + Vector3(0, 0, 9.0), 0.2)) as WispNest
	await _wait_frames(int((EnemyNest.FIRST_BREED + EnemyNest.PULSE_TIME) * 60.0) + 20)
	var bred_first := nest.bred
	var brood_wisp := nest.brood.size() == 1 and nest.brood[0] is SmoulderWisp
	kill_all.call([nest])
	await _wait_frames(4)
	var brood_left: Array = nest.brood.duplicate() if is_instance_valid(nest) else []
	kill_all.call(brood_left)
	_check(bred_first == 1 and brood_wisp, "a wisp nest swells, then lets out a smoulder wisp; it breaks like any foe")
	await _wait_frames(4)
	var trial := highlands.puzzles["trial_f"] as TrialShrine
	hero12.global_position = highlands.ground_point(trial.global_position + Vector3(0, 0, 2.5), 0.2)
	await _wait_frames(2)
	trial.switch.use_by(hero12)
	await _wait_frames(2)
	var trial_started := trial.phase() == "running" and trial.wave_alive.size() == 3 and trial.joined_seq == int(trial.state["seq"])
	for t_frame in 400:
		if trial.phase() != "running":
			break
		kill_all.call(trial.wave_alive)
		await _wait_frames(1)
	await get_tree().process_frame
	_check(trial_started and trial.phase() == "cleared" and hero12.blessings.has("charwood")
		and is_equal_approx(hero12.stat(&"damage_pct") - hero12.equipment.stat(&"damage_pct") - hero12.progression.stat(&"damage_pct") - hero12.buff_stat(&"damage_pct"), 2.0),
		"a trial: two waves around the altar, cleared in time without too many hits - the Charwood's blessing")
	hero12.blessings = PackedStringArray()
	trial.state = {"phase": "idle", "seq": int(trial.state["seq"])}
	trial.commit()
	trial.switch.use_by(hero12)
	await _wait_frames(2)
	trial.hits = TrialShrine.DEFS["trial_f"]["hits"] + 1
	for t_frame in 400:
		if trial.phase() != "running":
			break
		kill_all.call(trial.wave_alive)
		await _wait_frames(1)
	var struck_ok := trial.phase() == "cleared" and not hero12.blessings.has("charwood")
	trial.state = {"phase": "idle", "seq": int(trial.state["seq"])}
	trial.commit()
	trial.switch.use_by(hero12)
	await _wait_frames(2)
	var doomed := trial.wave_alive.duplicate()
	trial.state["t0"] = Time.get_ticks_msec() - int(trial.time_limit() * 1000.0) - 100
	await _wait_frames(3)
	var gone := true
	for d in doomed:
		gone = gone and (not is_instance_valid(d) or d.is_queued_for_deletion())
	_check(struck_ok and trial.phase() == "failed" and gone and trial.wave_alive.is_empty(),
		"struck too often: no blessing; out of time: the trial fails and its wave is gone")
	trial.state = {"phase": "idle", "seq": int(trial.state["seq"])}
	trial.commit()
	var shard_ids: Array[String] = []
	for sid: String in highlands.shards.keys():
		shard_ids.append(sid)
	shard_ids.sort()
	hero12.collected = PackedStringArray()
	for i in shard_ids.size() - 1:
		hero12.collected.append(shard_ids[i])
	(highlands.shards[shard_ids[shard_ids.size() - 1]] as RuneShard).use_by(hero12)
	_check(shard_ids.size() == RuneShard.TOTAL and hero12.blessings.has("shards"),
		"the twelfth shard of the Shattered Rune brings its blessing")
	var fmt_bad := ""
	for tkey: String in Texts._table.keys():
		var tentry: Dictionary = Texts._table[tkey]
		var t_en := str(tentry.get("en", ""))
		var t_de := str(tentry.get("de", t_en))
		if t_en.contains("{0}") or t_de.contains("{0}") or t_en.count("%") != t_de.count("%"):
			fmt_bad = tkey
	_check(fmt_bad == "", "every text-table entry formats with %% alike in both languages (%s)" % fmt_bad)
	hero12.blessings = PackedStringArray()
	hero12.collected = PackedStringArray()
	hero12.equipment._recompute()
	hero12.god_mode = false
	hero12.health.current_health = hero12.health.max_health
	await _wait_frames(2)
	# --- M12 phase 7: the tome and its three abilities ---
	var tome_ids: Array[String] = []
	var tome_ok := true
	for cid: StringName in [&"runebreaker", &"elementalist", &"druid"]:
		var cdata := ClassData.load_by_id(cid)
		var tomes := 0
		for adata in cdata.abilities:
			if adata != null and adata.unlock == AbilityData.Unlock.TOME:
				tomes += 1
				tome_ids.append(String(adata.id))
		for tdata in cdata.trainer_abilities():
			tome_ok = tome_ok and tdata.unlock != AbilityData.Unlock.TOME
		tome_ok = tome_ok and tomes == 1
	var grotto_tome := highlands.grottos["cave_tome"]["tome"] as Tome
	var my_tome := Tome.ability_for(hero12)
	if my_tome != null:
		hero12.known_abilities.erase(my_tome.id)
	grotto_tome.use_by(hero12)
	if highlands.lore_ui != null:
		highlands.lore_ui.close()
	_check(tome_ok and ",".join(tome_ids) == "lodestone_rune,hoarfrost_fan,rootwalk" and my_tome != null
		and hero12.knows(my_tome.id) and hero12.lore_read.has(Tome.LORE_ID)
		and my_tome.title() == Texts.t("ability." + String(my_tome.id)),
		"the tome in the sealed grotto teaches each class its own art (%s); the trainer never sells them" % ", ".join(tome_ids))
	var tome_spot := hl_layout.poi_pos("trial_f")
	var lode_at := highlands.ground_point(tome_spot + Vector3(-4.0, 0, -8.0), 0.1)
	var rb7 := Player.create(ClassData.load_by_id(&"runebreaker")) as RunebreakerHero
	rb7.is_local = false
	rb7.input_source = InputSource.new()
	highlands.add_player(rb7)
	rb7.global_position = highlands.ground_point(tome_spot + Vector3(-4.0, 0, 20.0), 0.2)  # out of their aggro
	hero12.global_position = highlands.ground_point(tome_spot + Vector3(18.0, 0, 18.0), 0.2)
	await _wait_frames(3)
	var pulled_a := highlands.spawn_by_id("rusher", highlands.ground_point(lode_at + Vector3(5.0, 0, 0), 0.2))
	var pulled_b := highlands.spawn_by_id("caster", highlands.ground_point(lode_at + Vector3(-1.0, 0, -4.6), 0.2))
	await _wait_frames(2)
	var flat_d := func(e: Node3D, p: Vector3) -> float: return Vector2(e.global_position.x - p.x, e.global_position.z - p.z).length()
	var da0: float = flat_d.call(pulled_a, lode_at)
	var db0: float = flat_d.call(pulled_b, lode_at)
	var lode := LodestoneRune.new()
	lode.setup(rb7.lodestone_rune, rb7)
	lode.position = lode_at
	highlands.add_child(lode)
	await _wait_frames(int(rb7.lodestone_rune.startup * 60.0) + 24)
	var da1: float = flat_d.call(pulled_a, lode_at)
	var db1: float = flat_d.call(pulled_b, lode_at)
	_check(da1 < da0 - 2.0 and db1 < db0 - 2.0 and pulled_a.taunted_by() == rb7 and pulled_b.taunted_by() == rb7
		and pulled_a.health.current_health < pulled_a.health.max_health,
		"Lodestone Rune: arms, drags the pack in (%.1f -> %.1f m, %.1f -> %.1f m), strikes and taunts it" % [da0, da1, db0, db1])
	rb7.learn_ability(&"lodestone_rune")
	rb7.resonance = 100.0
	var lode_cast := rb7.try_lodestone_rune()
	_check(lode_cast and is_equal_approx(rb7.resonance, 70.0) and rb7._on_cooldown(&"lodestone_rune") and not rb7.try_lodestone_rune(),
		"Lodestone Rune costs 30 Resonance and its cooldown")
	pulled_a.queue_free()
	pulled_b.queue_free()
	var el7 := Player.create(ClassData.load_by_id(&"elementalist")) as ElementalistHero
	el7.is_local = false
	el7.input_source = InputSource.new()
	highlands.add_player(el7)
	el7.global_position = highlands.ground_point(tome_spot + Vector3(6.0, 0, 6.0), 0.2)
	el7._visual.rotation.y = 0.0
	el7.intent.aim_dir = Vector3(0, 0, -1)
	await _wait_frames(3)
	var cold := highlands.spawn_by_id("rusher", highlands.ground_point(el7.global_position + Vector3(0.3, 0, -4.0), 0.2))
	var warm := highlands.spawn_by_id("rusher", highlands.ground_point(el7.global_position + Vector3(-1.2, 0, -5.0), 0.2))
	var aside := highlands.spawn_by_id("rusher", highlands.ground_point(el7.global_position + Vector3(4.5, 0, 1.0), 0.2))
	await _wait_frames(2)
	cold.status.apply_chill()
	el7.learn_ability(&"hoarfrost_fan")
	el7.resonance = 100.0
	var fan_cast := el7.try_hoarfrost_fan()
	_check(fan_cast and cold.status.is_rooted() and not warm.status.is_rooted() and warm.status.has_chill()
		and warm.health.current_health < warm.health.max_health and is_equal_approx(aside.health.current_health, aside.health.max_health)
		and is_equal_approx(el7.resonance, 80.0),
		"Hoarfrost Fan: rime in a cone ahead (Chill), the already Chilled freeze in place; nothing aside is touched")
	for foe in [cold, warm, aside]:
		foe.queue_free()
	var dr7 := Player.create(ClassData.load_by_id(&"druid")) as DruidHero
	dr7.is_local = false
	dr7.input_source = InputSource.new()
	highlands.add_player(dr7)
	dr7.global_position = highlands.ground_point(tome_spot + Vector3(-7.0, 0, 8.0), 0.2)
	dr7.intent.aim_dir = Vector3(0, 0, -1)
	await _wait_frames(3)
	hero12.global_position = highlands.ground_point(dr7.global_position + Vector3(1.5, 0, 0), 0.2)
	hero12.apply_slow(0.4, 5.0)
	hero12.health.current_health = hero12.health.max_health * 0.5
	var hp_walk := hero12.health.current_health
	dr7.learn_ability(&"rootwalk")
	var walk_from := dr7.global_position
	var walked := dr7.try_rootwalk()
	var walking := dr7.state == Player.State.ROOTWALK and dr7.health.invulnerable
	await _wait_frames(int(dr7.rootwalk.active * 60.0) + 8)
	var walk_len := Vector2(dr7.global_position.x - walk_from.x, dr7.global_position.z - walk_from.z).length()
	_check(walked and walking and dr7.state == Player.State.MOVE and not dr7.health.invulnerable and walk_len >= 6.0
		and is_zero_approx(hero12.slow_pct) and hero12.health.current_health > hp_walk,
		"Rootwalk: through the roots (%.1f m, untouchable), the bloom heals an ally and takes its slow" % walk_len)
	for h7: Player in [rb7, el7, dr7]:
		highlands.remove_player(h7)
		h7.queue_free()
	hero12.health.current_health = hero12.health.max_health
	await _wait_frames(2)
	hero12.global_position = hero_home

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
	await _wait_frames(45)  # proximity checks tick every 0.5 s, spawns are staggered
	var camp_count := highlands.enemy_count()
	_check(camp_count >= 2, "camp spawner triggers on approach")
	var enemies_grounded := true
	for e in highlands.enemies_root.get_children():
		var ep := (e as Node3D).global_position
		enemies_grounded = enemies_grounded and absf(ep.y - highlands.ground_y(ep)) < 0.8
	_check(enemies_grounded, "camp enemies stand on the terrain pad")
	var foliage_enemies := true
	for e in highlands.enemies_root.get_children():
		foliage_enemies = foliage_enemies and (e as EnemyBase).collision_mask & Grove.FOLIAGE_LAYER != 0
	_check(foliage_enemies, "M12: enemies bump into the forest's trunks too (foliage in their mask)")
	await _wait_frames(60)
	_check(director != null and director.combat_mix > 0.3, "combat layer swells in once the camp engages (%.2f)"
		% (director.combat_mix if director != null else 0.0))

	# --- M08 camps: persistence, respawn timer, leash, ambush, roaming pack ---
	highlands.player.god_mode = true
	_check(camp1.state == EncounterSpawner.State.ACTIVE and camp1.pack().size() == camp_count and camp1.camp_id == "camp_1",
		"camp 1 is ACTIVE with its pack alive and carries its persistence id")
	for e in camp1.pack():
		e.take_hit(HitInfo.create(99999.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, e.global_position))
	await _wait_frames(3)
	_check(camp1.state == EncounterSpawner.State.CLEARED and SaveGame.camp_cleared_at("camp_1") > 0.0,
		"clearing a camp marks it CLEARED and records the time in the save")
	SaveGame.save_now()
	SaveGame.reload_from_disk()
	_check(SaveGame.camp_cleared_at("camp_1") > 0.0, "camp state survives a save round-trip")
	var cnow := Time.get_unix_time_from_system()
	camp1.check_rearm(cnow)
	_check(camp1.state == EncounterSpawner.State.CLEARED, "a freshly cleared camp stays cleared")
	camp1._cleared_at = cnow - 11.0 * 60.0  # eleven minutes pass, but a hero still stands on the pad
	camp1.check_rearm(cnow)
	_check(camp1.state == EncounterSpawner.State.CLEARED, "a camp never re-arms while a hero stands within its rearm radius")
	highlands.player.global_position = highlands.ground_point(camp1.global_position + Vector3(0, 0, 70), 0.3)
	highlands.player.velocity = Vector3.ZERO
	await _wait_frames(2)
	camp1.check_rearm(cnow)
	_check(camp1.state == EncounterSpawner.State.ARMED and SaveGame.camp_cleared_at("camp_1") < 0.0,
		"after the respawn time, with nobody near, the camp re-arms and drops its save entry")
	highlands.player.global_position = highlands.ground_point(camp1.global_position + Vector3(0, 0, camp1.trigger_radius - 1.5), 0.3)
	highlands.player.velocity = Vector3.ZERO
	for i in 90:
		await get_tree().physics_frame
		if highlands.enemy_count() >= camp1.composition.size():
			break
	_check(highlands.enemy_count() >= camp1.composition.size(), "a re-armed camp triggers again on approach")
	var staggered := camp1.spawn_frames.size() == camp1.composition.size()
	for i in range(1, camp1.spawn_frames.size()):
		staggered = staggered and camp1.spawn_frames[i] > camp1.spawn_frames[i - 1]
	_check(staggered, "camp packs spawn one enemy per physics frame, never all in one %s" % str(camp1.spawn_frames))
	for e in camp1.pack():
		e.take_hit(HitInfo.create(99999.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, e.global_position))
	await _wait_frames(3)
	# Leash: a member dragged far from home walks back, rests and heals.
	var leash_home := highlands.poi_position("camp_2")
	var runner := highlands.spawn_by_id("rusher", highlands.ground_point(leash_home + Vector3(0, 0, 30), 0.2))
	runner.home = leash_home
	runner.leash = 26.0
	runner.move_speed = 12.0
	runner.health.current_health = runner.health.max_health * 0.4
	await _wait_frames(5)
	_check(runner.ai_state == EnemyBase.AIState.RETURN, "a camp member beyond its leash turns for home")
	for i in 300:
		await get_tree().physics_frame
		if runner.ai_state == EnemyBase.AIState.IDLE:
			break
	_check(runner.ai_state == EnemyBase.AIState.IDLE and runner.global_position.distance_to(leash_home) < 3.0
		and runner.health.current_health == runner.health.max_health, "it arrives home, rests and is fully healed")
	runner.free()
	# Ambush: the pack appears on a ring around the hero, not around the spawner.
	var ambush := highlands.camps["ambush_1"] as EncounterSpawner
	_check(ambush.around_players and ambush.camp_id == "ambush_1", "ambush spawners surround the hero who walks in")
	highlands.player.global_position = highlands.ground_point(ambush.global_position, 0.3)
	highlands.player.velocity = Vector3.ZERO
	for i in 90:
		await get_tree().physics_frame
		if ambush.pack().size() >= ambush.composition.size():
			break
	var ring_ok := ambush.pack().size() == ambush.composition.size()
	for e in ambush.pack():
		var d := Vector2(e.global_position.x - highlands.player.global_position.x, e.global_position.z - highlands.player.global_position.z).length()
		ring_ok = ring_ok and d >= 4.5 and d <= 10.5
	_check(ring_ok, "the ambush pack appears on a 6-9 m ring around the hero (%d enemies)" % ambush.pack().size())
	for e in ambush.pack():
		e.take_hit(HitInfo.create(99999.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, e.global_position))
	await _wait_frames(3)
	# Roaming elite pack: wakes from afar, then its home walks the patrol path.
	var patrol := highlands.camps["patrol_east"] as EncounterSpawner
	_check(patrol.patrol.size() == 4 and patrol.trigger_radius > 50.0, "the elite patrol has a 4-point path and a long wake radius")
	highlands.player.global_position = highlands.ground_point(patrol.global_position + Vector3(0, 0, 40), 0.3)
	highlands.player.velocity = Vector3.ZERO
	for i in 90:
		await get_tree().physics_frame
		if patrol.pack().size() >= patrol.composition.size():
			break
	_check(patrol.state == EncounterSpawner.State.ACTIVE and patrol.pack().size() == 3, "the patrol wakes from 40 m and fields its elite pack")
	var home0 := patrol.home
	await _wait_frames(60)
	_check(patrol.home.distance_to(home0) > 0.5 or patrol._patrol_pause > 0.0, "the pack's home walks its patrol while nobody fights")
	for e in patrol.pack():
		e.take_hit(HitInfo.create(99999.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, e.global_position))
	await _wait_frames(3)
	var v3 := SaveGame.migrate({"version": 3, "world": {"zone": "res://scenes/hub.tscn", "flags": {"a": true}},
		"characters": [{"class_id": "runebreaker", "known_abilities": ["rune_cleave"], "gold": 5, "inventory": [],
			"equipped": {}, "progression": {"level": 2, "xp": 0, "talents": {}}}], "active": 0})
	var v3_char: Dictionary = (v3["characters"] as Array)[0]
	_check(int(v3.get("version", 0)) == SaveGame.VERSION and (v3_char["world"] as Dictionary).get("camps", null) is Dictionary
		and v3_char.has("waypoints"),
		"v3 saves migrate: camps in the (character's) world, waypoints per character")
	highlands.player.god_mode = false

	# --- M08 waypoints + fast travel ---
	var wp := highlands.waypoints["wp_ashford"] as Waypoint
	_check(wp != null and highlands.waypoints.size() == 5 and not highlands.player.knows_waypoint(wp.id)
		and wp.id == "ashen_highlands:wp_ashford" and not wp.is_lit(),
		"five waypoint shrines stand in the Highlands, none attuned on a fresh character")
	_check(WaypointRegistry.all().size() == 6 and WaypointRegistry.all()[0]["key"] == WaypointRegistry.HUB_KEY,
		"the waypoint registry lists Runehold plus the five Highlands shrines")
	var xp_before_wp := highlands.player.progression.xp + highlands.player.progression.level * 100000
	highlands.player.global_position = highlands.ground_point(wp.global_position + Vector3(0, 0, 3.0), 0.3)
	highlands.player.velocity = Vector3.ZERO
	await _wait_frames(5)
	for i in 4:
		await get_tree().process_frame
	var xp_after_wp := highlands.player.progression.xp + highlands.player.progression.level * 100000
	_check(highlands.player.knows_waypoint(wp.id) and wp.is_lit() and xp_after_wp > xp_before_wp,
		"walking up to a shrine attunes it: remembered, lit, XP paid")
	SaveGame.save_now()
	SaveGame.reload_from_disk()
	var saved_wps: Array = SaveGame.active_character().get("waypoints", [])
	_check(saved_wps.has(wp.id), "attuned shrines are saved with the character")
	highlands.waypoint_ui.open(wp, highlands.player)
	var listed := highlands.waypoint_ui.listed_keys()
	_check(highlands.waypoint_ui.visible and highlands.player.input_locked and listed.size() == 2
		and listed.has(WaypointRegistry.HUB_KEY) and listed.has(wp.id),
		"the travel list shows Runehold and the attuned shrine only (%s)" % str(listed))
	_check(highlands.waypoint_ui.map_scene() == highlands.scene_file_path
		and highlands.waypoint_ui.map_has_shrine(String(listed[listed.size() - 1])),
		"M08 notes: the travel panel shows the Highlands map with the known shrines on it")
	var reg_map := WaypointRegistry.zone_map(highlands.scene_file_path)
	var probe_view := ZoneMapView.new()
	probe_view.setup(reg_map.get("texture") as Texture2D, reg_map.get("bounds", Rect2()) as Rect2, MapUI.MAP_PX)
	var probe_pos := highlands.poi_position("spawn")
	_check(reg_map.get("texture") != null and (reg_map["bounds"] as Rect2).is_equal_approx(highlands.map_bounds())
		and probe_view.world_to_map(probe_pos).is_equal_approx(highlands.map_ui.world_to_map(probe_pos)),
		"the registry's map matches the zone's, and ZoneMapView places things like the full map")
	probe_view.free()
	highlands.waypoint_ui.close()
	_check(not highlands.waypoint_ui.visible and not highlands.player.input_locked, "closing the travel list frees the input")
	highlands.player.discover_waypoint("ashen_highlands:wp_crossroads", "Crossroads Cairn")
	highlands.fast_travel("ashen_highlands:wp_crossroads")
	for i in 60:
		await get_tree().process_frame
	var cross := highlands.waypoints["wp_crossroads"] as Waypoint
	_check(highlands.player.global_position.distance_to(cross.global_position) < 4.5 and highlands.player.is_on_floor(),
		"fast travel within the zone lands the hero beside the target shrine (%.1f m)" % highlands.player.global_position.distance_to(cross.global_position))
	highlands.player.global_position = highlands.ground_point(cross.global_position + Vector3(20, 0, 0), 0.3)
	highlands._on_player_died(highlands.player)
	_check(highlands.player.global_position.distance_to(cross.global_position) < 4.5,
		"death respawns at the nearest attuned shrine")
	await _wait_frames(2)

	# --- M08 compass + map ---
	_check(InputMap.has_action(&"map_toggle") and InputSetup.key_label(&"map_toggle") == "M", "the zone map is on M")
	var compass := highlands.hud.compass
	_check(compass != null and compass.visible, "the HUD shows the compass strip in a zone with a map")
	highlands.camera_rig._yaw = 0.0
	for i in 3:
		await get_tree().process_frame  # the rig applies its yaw in _process
	_check(absf(compass.heading()) < 0.02, "compass heading is north when the camera looks down -Z (%.3f)" % compass.heading())
	highlands.camera_rig._yaw = -PI * 0.5
	for i in 3:
		await get_tree().process_frame
	_check(absf(compass.heading() - PI * 0.5) < 0.02, "turning the camera east reads as 90 degrees (%.3f)" % compass.heading())
	highlands.camera_rig._yaw = 0.0
	var compass_ids: Array[String] = []
	for m in compass.markers():
		compass_ids.append(String(m["id"]))
	_check(compass_ids.has("wp_ashford") and compass_ids.has("wp_crossroads") and compass_ids.has("gate_south")
		and not compass_ids.has("chest_south"), "compass markers: attuned shrines and the gate, no chests (%s)" % str(compass_ids))
	highlands.map_ui.toggle()
	var spawn_px := highlands.map_ui.world_to_map(highlands.poi_position("spawn"))
	_check(highlands.map_ui.visible and highlands.player.input_locked and highlands.map_ui.marker_count() >= 3
		and absf(spawn_px.x - 300.0) < 12.0 and spawn_px.y > 520.0,
		"M opens the map: input locked, markers drawn, the spawn projects to the bottom centre (%s)" % str(spawn_px))
	highlands.map_ui.toggle()
	_check(not highlands.map_ui.visible and not highlands.player.input_locked, "M again closes the map and frees the input")
	highlands.hero_ui.open_tab(HeroUI.Tab.CHARACTER)
	highlands.map_ui.open()
	_check(highlands.map_ui.visible and not highlands.hero_ui.visible and highlands.player.input_locked,
		"opening the map closes the hero window (one window at a time)")
	highlands.map_ui.close()
	var ruin_pos := highlands.poi_position("ruin_1")
	_check(not highlands.player.map_discovered.has("ruin_1"), "a far ruin is not on the map yet")
	highlands.player.global_position = highlands.ground_point(ruin_pos + Vector3(0, 0, 14), 0.3)
	highlands.player.velocity = Vector3.ZERO
	await _wait_frames(40)
	var map_ids: Array[String] = []
	for m in highlands.map_markers():
		map_ids.append(String(m["id"]))
	_check(highlands.player.map_discovered.has("ruin_1") and map_ids.has("ruin_1"),
		"walking up to a ruin puts it on the map")
	_check(highlands._area_seen.has("westreach") or highlands._area_seen.has("ashford"),
		"entering a named area announces it (%s)" % str(highlands._area_seen.keys()))
	SaveGame.save_now()
	SaveGame.reload_from_disk()
	_check((SaveGame.active_character().get("map_discovered", []) as Array).has("ruin_1"), "map discovery is saved with the character")

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
	_check(chest_loot >= ItemGenerator.CHEST_ITEMS.x, "chest pops at least %d item(s)" % ItemGenerator.CHEST_ITEMS.x)
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

	# =========================== M13: DUNGEONS ===========================
	# The Hollow Cistern's shell: travel in, the layout's floors and walls,
	# camps in their rooms, the map, a late joiner's spot, the camera in a
	# corridor, a slope; then out through the exit to the Highlands gate,
	# whose seal breaks with the hero standing at it.
	spire.travel_to("res://scenes/hollow_cistern.tscn", "ci_exit")
	for i in 60:
		await get_tree().process_frame
		if get_tree().current_scene is CisternZone:
			break
	var cistern := get_tree().current_scene as CisternZone
	_check(cistern != null, "M13: the Hollow Cistern loads")
	var leave_zone: ZoneBase = spire
	if cistern != null:
		await _wait_frames(8)
		leave_zone = cistern
		var ch13 := cistern.player
		ch13.god_mode = true
		_check(cistern.look != null and cistern.look.interior and MusicDirector.instance.zone_key() == "spire",
			"M13: the Cistern is an interior with the Spire's music")
		_check(ch13.global_position.distance_to(cistern._player_spawn_point()) < 3.0 and cistern.room_id_at(ch13.global_position) == "ci_inlet",
			"M13: the hero arrives in the inlet, in front of the exit (%s)" % ch13.global_position)
		_check(ch13.is_on_floor() and absf(ch13.global_position.y - cistern.ground_y(ch13.global_position)) < 0.6,
			"M13: the hero stands on the inlet's floor")
		_check(ch13.discovered_zones.has("hollow_cistern"), "M13: the first visit is a discovery")
		var poi_floor_ok := true
		var poi_prefix_ok := true
		for poi in cistern.layout.pois.pois:
			var pp13 := ZoneLayout.pos_of(poi)
			var poi_beside := pp13 + Vector3(1.2, 0.5, 0)  # beside the POI: its own collider (a chest) is no floor
			var gp13 := cistern.ground_point(poi_beside)
			var floor_beside := cistern.layout.floor_at(poi_beside.x, poi_beside.z, -99.0)
			if absf(pp13.y - cistern.layout.floor_at(pp13.x, pp13.z, -99.0)) > 0.05 or absf(gp13.y - floor_beside) > 0.1:
				poi_floor_ok = false
			if not String(poi["id"]).begins_with("ci_"):
				poi_prefix_ok = false
		_check(poi_floor_ok, "M13: every Cistern POI stands on its room's floor (layout and colliders agree)")
		_check(poi_prefix_ok, "M13: every Cistern id carries the ci_ prefix")
		var spot_probe := PhysicsShapeQueryParameters3D.new()
		var spot_ball := SphereShape3D.new()
		spot_ball.radius = 0.5
		spot_probe.shape = spot_ball
		spot_probe.collision_mask = 1
		var spots_clear := true
		var spot_count := 0
		for camp_key: String in cistern.camps:
			var csp := cistern.camps[camp_key] as EncounterSpawner
			for spot: Vector3 in csp.spots:
				spot_count += 1
				spot_probe.transform = Transform3D(Basis(), spot + Vector3(0, 1.0, 0))
				if not cistern.world.get_world_3d().direct_space_state.intersect_shape(spot_probe, 4).is_empty():
					spots_clear = false
				if cistern.room_id_at(spot) != cistern.room_id_at(csp.global_position):
					spots_clear = false
		_check(spot_count >= 8 and spots_clear, "M13: %d camp spots stand clear inside their rooms" % spot_count)
		_check(cistern.enemy_count() == 0, "M13: no Cistern camp wakes on arrival")
		_check(cistern.builder.secret_walls.has("ci_d_run_vault") and cistern.builder.plugs.has("ci_d_c4_threshold"),
			"M13: the secret wall and the shortcut start closed")
		var in_wall := Vector3(-11.0, 0.0, 33.0)
		var made_safe := cistern.safe_spawn(in_wall)
		_check(not cistern.layout.is_walkable(in_wall.x, in_wall.z) and cistern.layout.is_walkable(made_safe.x, made_safe.z),
			"M13: a late joiner's spot in a wall moves into the nearest room")
		# the camera across a 6 m corridor keeps its distance
		ch13.global_position = Vector3(-20, 0.2, 40)
		ch13.velocity = Vector3.ZERO
		cistern.camera_rig._yaw = 0.0
		await _wait_frames(6)
		await get_tree().process_frame
		var arm := cistern.camera_rig.spring.get_hit_length()
		_check(arm >= CameraRig.ZOOM_MIN, "M13: in a corridor the camera keeps %.1f m (>= %.1f)" % [arm, CameraRig.ZOOM_MIN])
		# up the slope from the frost channel to the mirror gallery
		ch13.global_position = Vector3(-45, 0.2, -4)
		ch13.velocity = Vector3.ZERO
		cistern.camera_rig._yaw = 0.0  # camera-forward = -Z (north, up the slope)
		await _wait_frames(3)
		Input.action_press(&"move_forward")
		await _wait_frames(200)
		Input.action_release(&"move_forward")
		var up_top := ch13.global_position
		_check(up_top.y > 1.6 and up_top.z < -19.0, "M13: the hero walks up the slope to the gallery (at %s)" % up_top)
		# a camp wakes in its room; cleared it stays down, comes back once nobody is near
		var sluice := cistern.camps["ci_camp_sluice"] as EncounterSpawner
		ch13.global_position = Vector3(-45, 0.2, 40)
		await _wait_frames(40)
		_check(sluice.state != EncounterSpawner.State.ARMED and cistern.enemy_count() >= 3, "M13: the sluice hall's camp wakes")
		cistern.kill_all_enemies()
		await _wait_frames(20)
		_check(sluice.state == EncounterSpawner.State.CLEARED and SaveGame.camp_cleared_at("ci_camp_sluice") > 0.0,
			"M13: a cleared dungeon camp is saved")
		sluice.check_rearm(Time.get_unix_time_from_system() + 601.0)
		_check(sluice.state == EncounterSpawner.State.CLEARED, "M13: no respawn while a hero stands in the room")
		ch13.global_position = cistern._player_spawn_point()
		await _wait_frames(3)
		sluice.check_rearm(Time.get_unix_time_from_system() + 601.0)
		_check(sluice.state == EncounterSpawner.State.ARMED, "M13: the camp comes back after its minutes with nobody near")
		# map and names
		var known: Array[String] = []
		for m in cistern.map_markers():
			known.append(String(m["id"]))
		_check(cistern.map_texture() != null and is_equal_approx(cistern.map_bounds().size.x, cistern.map_bounds().size.y)
			and known.has("ci_exit") and known.has("ci_camp_sluice") and not known.has("ci_chest_vault"),
			"M13: the Cistern map shows what was found, never the hidden vault (%s)" % ", ".join(known))
		_check(cistern._room_seen.has("ci_sluice") and Texts.t("area.ci_sluice") != "area.ci_sluice",
			"M13: rooms announce their names")
		# --- phase 1: runes, death, the boss arenas, gates, chests that open once ---
		var rune_ante := cistern.runes["ci_rune_ante"] as DungeonRune
		_check(not rune_ante.is_solved() and cistern.respawn_point(Vector3(10, 2, -40)).distance_to(cistern._player_spawn_point()) < 0.1,
			"M13: without a lit rune a fallen hero wakes at the entrance")
		ch13.global_position = rune_ante.global_position + Vector3(0, 0.2, 1.5)
		await _wait_frames(3)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(rune_ante.is_solved() and bool(SaveGame.poi_state("ci_rune_ante").get("solved", false)),
			"M13: a hero beside a rune wakes it (the world keeps it)")
		ch13.god_mode = false
		ch13.global_position = Vector3(-4, 2.2, -50)  # in the basin, by its west wall
		await _wait_frames(2)
		ch13.take_hit(HitInfo.create(99999.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, ch13.global_position))
		await _wait_frames(2)
		_check(not ch13.health.is_dead and ch13.health.current_health >= ch13.health.max_health - 0.1
			and ch13.global_position.distance_to(rune_ante.respawn_point()) < 0.6,
			"M13: a hero who falls wakes healed at the nearest lit rune")
		ch13.god_mode = true
		var keeper := cistern.arenas["ci_arena_keeper"] as BossArena
		var basin_gate := cistern.gates["ci_d_basin_run"] as DungeonGate
		_check(not keeper.fighting() and not keeper.is_done() and basin_gate != null and not basin_gate.is_open,
			"M13: the mid-boss sleeps, its gate is shut")
		ch13.global_position = Vector3(10, 2.2, -36)
		await _wait_frames(20)
		_check(keeper.fighting() and keeper.boss.level == 4 and cistern.hud._boss_root != null and cistern.hud._boss_root.visible,
			"M13: a hero in the basin wakes the mid-boss (level 4, the boss bar)")
		var first_boss := keeper.boss
		if first_boss != null:
			first_boss.take_hit(HitInfo.create(200.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, ch13.global_position))
		ch13.global_position = rune_ante.respawn_point()  # out of the room: nobody left in the fight
		await _wait_frames(int(BossArena.RESET_GRACE * 60.0) + 40)
		_check(keeper.resets == 1 and not keeper.fighting() and not is_instance_valid(first_boss) and not cistern.hud._boss_root.visible,
			"M13: with nobody left in the arena the fight resets (the boss goes, the bar too)")
		ch13.global_position = Vector3(10, 2.2, -36)
		await _wait_frames(20)
		_check(keeper.fighting() and keeper.starts == 2 and is_equal_approx(keeper.boss.health.current_health, keeper.boss.health.max_health),
			"M13: the next try meets the boss at full health")
		var keeper_boss := keeper.boss
		if keeper_boss != null:
			keeper_boss.global_position = Vector3(40, 2.2, -40)  # pushed out of the room...
			await _wait_frames(2)
			_check(DungeonLayout.rect_of(cistern.layout.room("ci_basin")).has_point(Vector2(keeper_boss.global_position.x, keeper_boss.global_position.z)),
				"M13: a boss never leaves its room")
			keeper_boss.take_hit(HitInfo.create(99999.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, ch13.global_position))
		await _wait_frames(30)
		var boss_drops := 0
		for child in cistern.world.get_children():
			if child is ItemDrop:
				boss_drops += 1
		_check(SaveGame.has_flag(&"ci_keeper_down") and keeper.is_done() and basin_gate.is_open and boss_drops >= 1,
			"M13: the mid-boss falls: its flag, the gate opens, loot (%d drops)" % boss_drops)
		var maw := cistern.arenas["ci_arena_deepmaw"] as BossArena
		var heart_exit := cistern.portals["ci_exit_heart"] as Portal
		_check(heart_exit.locked, "M13: the way out of the heart is sealed while its boss lives")
		ch13.global_position = Vector3(83, 0.2, 33)
		await _wait_frames(20)
		_check(maw.fighting(), "M13: the end boss wakes in the heart")
		if maw.fighting():
			maw.boss.take_hit(HitInfo.create(99999.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, ch13.global_position))
		await _wait_frames(10)
		var legendary_from_maw := false
		for child in cistern.world.get_children():
			if child is ItemDrop and (child as ItemDrop).item.rarity == ItemData.Rarity.LEGENDARY:
				legendary_from_maw = true
		_check(SaveGame.has_flag(&"ci_deepmaw_down") and not heart_exit.locked and legendary_from_maw,
			"M13: the end boss falls: a legendary, the way out opens")
		var pump_chest := cistern.chests["ci_chest_pump"] as TreasureChest
		pump_chest.open(cistern)
		_check(pump_chest.opened and bool(SaveGame.poi_state("chest:ci_chest_pump").get("opened", false)),
			"M13: a dungeon chest remembers it was opened")
		# out through the exit: back at the Cistern gate, whose seal breaks
		cistern.travel_to("res://scenes/ashen_highlands.tscn", "dungeon_e")
		for i in 90:
			await get_tree().process_frame
			if get_tree().current_scene is AshenHighlands:
				break
		var back_hl := get_tree().current_scene as AshenHighlands
		_check(back_hl != null, "M13: the Cistern's exit leads back to the Highlands")
		if back_hl != null:
			leave_zone = back_hl
			await _wait_frames(8)
			await get_tree().process_frame
			var gate_at := back_hl.poi_position("dungeon_e")
			_check(back_hl.player.global_position.distance_to(back_hl._arrival_point("dungeon_e")) < 3.0
				and Vector2(back_hl.player.global_position.x - 126, back_hl.player.global_position.z + 56).length()
					< Vector2(gate_at.x - 126, gate_at.z + 56).length(),
				"M13: the hero comes out in front of the Cistern gate, on the path side")
			var seal_gate: DungeonGatePortal = null
			var warren_gate: DungeonGatePortal = null
			for child in back_hl.world.get_children():
				if child is DungeonGatePortal:
					if (child as DungeonGatePortal).gate_id == "dungeon_e":
						seal_gate = child
					else:
						warren_gate = child
			_check(seal_gate != null and not seal_gate.locked and back_hl.player.map_discovered.has(DungeonGatePortal.seal_key("dungeon_e")),
				"M13: standing at the gate breaks its seal (remembered by the character)")
			_check(warren_gate != null and warren_gate.locked, "M13: the Ember Warrens' gate stays sealed")
			# back in: what was done stays done
			back_hl.travel_to("res://scenes/hollow_cistern.tscn", "ci_exit")
			for i in 60:
				await get_tree().process_frame
				if get_tree().current_scene is CisternZone:
					break
			var cistern2 := get_tree().current_scene as CisternZone
			_check(cistern2 != null, "M13: into the Cistern again")
			if cistern2 != null:
				leave_zone = cistern2
				await _wait_frames(6)
				cistern2.player.god_mode = true
				_check((cistern2.chests["ci_chest_pump"] as TreasureChest).opened, "M13: the opened chest stays open")
				_check((cistern2.runes["ci_rune_ante"] as DungeonRune).is_solved()
					and (cistern2.gates["ci_d_basin_run"] as DungeonGate).is_open
					and not (cistern2.portals["ci_exit_heart"] as Portal).locked,
					"M13: the lit rune, the open gate and the open way out stay")
				cistern2.player.global_position = Vector3(10, 2.2, -36)
				await _wait_frames(30)
				_check(not (cistern2.arenas["ci_arena_keeper"] as BossArena).fighting() and cistern2.enemy_count() == 0,
					"M13: a fallen boss stays dead")
				# --- phase 2: the puzzle kit in its lab ---
				cistern2.travel_to("res://scenes/puzzle_lab.tscn", "lab_exit")
				for i in 60:
					await get_tree().process_frame
					if get_tree().current_scene is PuzzleLabZone:
						break
				var lab13 := get_tree().current_scene as PuzzleLabZone
				_check(lab13 != null and lab13.zone_title() == "", "M13: the puzzle lab loads (no title, no discovery)")
				if lab13 != null:
					leave_zone = lab13
					await _wait_frames(6)
					var lh := lab13.player
					lh.god_mode = true
					# a lever opens its gate (and the world keeps it)
					var gate_c2 := lab13.gates["lab_d_hub_c2"] as DungeonGate
					var lever := lab13.puzzles["lab_lever"] as PuzzleLever
					_check(not gate_c2.is_open and gate_c2._body.collision_layer != 0, "M13 kit: a gate waits shut on its lever")
					lever._switch.use_by(lh)
					await _wait_frames(2)
					_check(lever.is_on() and gate_c2.is_open and gate_c2._body.collision_layer == 0
						and bool(SaveGame.poi_state("lab_lever").get("on", false)), "M13 kit: the lever pulled, the gate opens")
					# plates: one latches under a hero, one wants the block
					var plate_a := lab13.puzzles["lab_plate_a"] as PressurePlate
					var plate_b := lab13.puzzles["lab_plate_b"] as PressurePlate
					var gate_beam := lab13.gates["lab_d_plates_beam"] as DungeonGate
					lh.global_position = plate_b.global_position + Vector3(0, 0.2, 0)
					await _wait_frames(12)
					lh.global_position = Vector3(48, 0.2, -8)
					await _wait_frames(12)
					_check(plate_b.is_down() and not plate_a.is_down() and not gate_beam.is_open,
						"M13 kit: a latching plate stays down after the hero steps off; one plate is not enough")
					var block := lab13.puzzles["lab_block"] as PushBlock
					_check(not block.cell_free(Vector2i(-4, 0)) and not block.cell_free(Vector2i(0, -8)) and block.cell_free(Vector2i(0, -1)),
						"M13 kit: a block never leaves its grid or the room")
					# walking into the block pushes it
					lh.global_position = block.rest_position() + Vector3(0, 0.2, 2.6)
					lh.velocity = Vector3.ZERO
					lab13.camera_rig._yaw = 0.0  # camera-forward = -Z (north)
					await _wait_frames(3)
					Input.action_press(&"move_forward")
					await _wait_frames(70)
					Input.action_release(&"move_forward")
					await _wait_frames(3)
					_check(block.cell_of().y <= -1, "M13 kit: walking into the block pushes it along the grid (cell %s)" % block.cell_of())
					for push_i in 6:
						if block.cell_of().y <= -5:
							break
						lh.global_position = block.rest_position() + Vector3(0, 0.2, 2.2)
						await _wait_frames(2)
						block.request("push", [0, -1], lh)
					lh.global_position = Vector3(48, 0.2, -8)
					await _wait_frames(12)
					_check(block.cell_of() == Vector2i(0, -5) and plate_a.is_down() and gate_beam.is_open,
						"M13 kit: the block on its plate and a latched plate open the gate")
					lh.global_position = block.rest_position() + Vector3(2.4, 0.2, 0)
					block.request("push", [-1, 0], lh)  # the hero stands east of it: into the next cell west
					block.request("push", [0, 1], lh)   # not behind it: refused
					_check(block.cell_of() == Vector2i(-1, -5), "M13 kit: a push only from behind (cell %s)" % block.cell_of())
					lh.global_position = block.rest_position() + Vector3(-2.4, 0.2, 0)
					block.request("push", [1, 0], lh)
					await _wait_frames(12)
					_check(block.cell_of() == Vector2i(0, -5) and plate_a.is_down(), "M13 kit: pushed back onto the plate")
					# the beam: two crystals turned until the light reaches the receiver
					var beam := lab13.puzzles["lab_light"] as BeamPuzzle
					var gate_water := lab13.gates["lab_d_beam_water"] as DungeonGate
					_check(not bool(beam.trace()["reached"]) and not gate_water.is_open, "M13 kit: the light starts off its mark")
					for turn_i in 5:
						beam.request("turn", 0, lh)
					_check(not beam.is_solved() and (beam.trace()["points"] as Array).size() >= 3,
						"M13 kit: the first crystal sends the light on (%d legs)" % ((beam.trace()["points"] as Array).size() - 1))
					for turn_i in 5:
						beam.request("turn", 1, lh)
					await _wait_frames(2)
					_check(beam.is_solved() and gate_water.is_open, "M13 kit: the light reaches its receiver, the gate opens")
					# the water: two valves drain it, the causeway carries a hero, the rest stays fenced
					var water := lab13.waters["lab_water_ch"] as WaterChannel
					(lab13.puzzles["lab_valve_a"] as PuzzleLever).request("pull", 0, lh)
					await _wait_frames(2)
					_check(not water.drained, "M13 kit: one valve of two leaves the channel full")
					(lab13.puzzles["lab_valve_b"] as PuzzleLever).request("pull", 0, lh)
					await _wait_frames(2)
					_check(water.drained and water.crossable_at(18, -36) and not water.crossable_at(10, -36),
						"M13 kit: both valves drain the channel; the causeway shows")
					lh.global_position = Vector3(10, 0.2, -31)
					lh.velocity = Vector3.ZERO
					lab13.camera_rig._yaw = 0.0
					await _wait_frames(3)
					Input.action_press(&"move_forward")
					await _wait_frames(90)
					Input.action_release(&"move_forward")
					var fenced_at := lh.global_position
					lh.global_position = Vector3(18, 0.2, -31)
					lh.velocity = Vector3.ZERO
					await _wait_frames(3)
					Input.action_press(&"move_forward")
					await _wait_frames(110)
					Input.action_release(&"move_forward")
					var crossed_at := lh.global_position
					_check(fenced_at.z > -34.3 and crossed_at.z < -38.5 and absf(crossed_at.y) < 0.6,
						"M13 kit: deep water stops a hero, the causeway carries one across (%s / %s)" % [fenced_at, crossed_at])
					# the cracked wall: found by a melee query, broken by three strikes
					var wall := lab13.builder.secret_walls["lab_d_hub_hidden"] as SecretWall
					var probe_at := Vector3(-13.0, 1.2, -7.0)  # where a sword swung at the wall's face reaches
					_check(lh._query_hurtboxes(probe_at, 1.5).has(wall), "M13 kit: a swing at the cracked wall finds it")
					for strike_i in 3:
						wall.take_hit(HitInfo.create(10.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, probe_at))
						await get_tree().create_timer(SecretWall.STRIKE_GAP + 0.05).timeout
					await _wait_frames(2)
					_check(wall.is_solved() and wall._body.collision_layer == 0 and int(wall.state.get("hits", 0)) == 3,
						"M13 kit: three strikes break the cracked wall")
					# the shortcut: its lever stands on the far side
					var short_gate := lab13.gates["lab_d_c3_hub"] as DungeonGate
					_check(not short_gate.is_open, "M13 kit: the shortcut is barred")
					(lab13.puzzles["lab_lever_short"] as PuzzleLever)._switch.use_by(lh)
					await _wait_frames(2)
					_check(short_gate.is_open, "M13 kit: its lever opens the shortcut")
					# a stuck block goes home; the plate rises and its gate shuts again
					lh.global_position = Vector3(36, 0.2, 2)
					var reset_sw := lab13.world.get_node_or_null("Reset_lab_block_reset") as PuzzleSwitch
					if reset_sw != null:
						reset_sw.use_by(lh)
					lh.global_position = Vector3(48, 0.2, -8)
					await _wait_frames(12)
					_check(reset_sw != null and block.cell_of() == Vector2i.ZERO and not plate_a.is_down() and not gate_beam.is_open,
						"M13 kit: the reset slab sends the block home; its plate rises and the gate shuts")

	# --- hub shows the spire shortcut once the colossus flag is set ---
	leave_zone.travel_to("res://scenes/hub.tscn", "gate_spire")  # M08 arrival hint: appear at the Spire gate
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
		_check(Vector2(hub2.player.global_position.x - HubZone.PORTAL_SPOTS["spire"].x,
			hub2.player.global_position.z - HubZone.PORTAL_SPOTS["spire"].z).length() < 4.5,
			"M08 arrival hint: the hero appears at the gate they came through")
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

		# --- M09 AI sleep: idle enemies with no hero near skip their tick ---
		var hero := hub2.player
		hub2.remove_player(hero)  # nobody in the zone: the new enemy has no one to hunt
		var sleeper := hub2.spawn_by_id("rusher", hero.global_position + Vector3(0, 0.2, -6))
		await _wait_frames(70)
		_check(sleeper.sleeping and sleeper.ai_state == EnemyBase.AIState.IDLE,
			"M09: an idle enemy with no hero within 60 m sleeps")
		var slept_at := sleeper.global_position
		await _wait_frames(20)
		_check(sleeper.global_position.distance_to(slept_at) < 0.01, "a sleeping enemy does not move")
		sleeper.take_hit(HitInfo.create(1.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, sleeper.global_position))
		_check(not sleeper.sleeping, "a hit wakes a sleeping enemy")
		hub2.add_player(hero)
		sleeper.free()

	# --- M09 co-op foundations (offline side; tests/net_test.tscn runs the rest) ---
	_check(Net.mode == Net.Mode.OFFLINE and Net.is_authority() and Net.has_view() and not Net.is_client()
		and multiplayer.multiplayer_peer is OfflineMultiplayerPeer, "M09: singleplayer is the offline authority (no socket)")
	var a1 := NetAddress.parse("melvin-laptop.tail94658b.ts.net", 7777)
	var a2 := NetAddress.parse(" 100.101.57.51:7780 ", 7777)
	var a3 := NetAddress.parse("[2a0d:3341::1]:7001", 7777)
	var a4 := NetAddress.parse("2a0d:3341::1", 7777)
	_check(str(a1["url"]) == "wss://melvin-laptop.tail94658b.ts.net/"
		and a2["host"] == "100.101.57.51" and int(a2["port"]) == 7780 and str(a2["url"]) == ""
		and a3["host"] == "2a0d:3341::1" and int(a3["port"]) == 7001 and str(a3["url"]) == ""
		and a4["host"] == "2a0d:3341::1" and int(a4["port"]) == 7777 and str(a4["url"]) == "",
		"server addresses parse: a bare name (Funnel, WebSocket), host:port, [v6]:port, bare v6 (ENet)")
	var w1 := NetAddress.parse("wss://Laptop.tail9.ts.net/rb", 7777)
	var w2 := NetAddress.parse("ws://127.0.0.1:17840", 7777)
	var w3 := NetAddress.parse(" https://laptop.tail9.ts.net ", 7777)
	var w4 := NetAddress.parse("127.0.0.1", 7777)
	_check(str(w1["url"]) == "wss://Laptop.tail9.ts.net/rb" and str(w2["url"]) == "ws://127.0.0.1:17840/"
		and str(w3["url"]) == "wss://laptop.tail9.ts.net/" and str(w4["url"]) == "" and int(w4["port"]) == 7777,
		"M09b: wss://, https:// and ws:// go over WebSocket, a bare IP stays ENet")
	_check(String(NetAddress.parse("", 7777)["error"]) != "" and String(NetAddress.parse("host:99999", 7777)["error"]) != ""
		and String(NetAddress.parse("host:abc", 7777)["error"]) != "" and String(NetAddress.parse("[::1", 7777)["error"]) != ""
		and String(NetAddress.parse("wss://", 7777)["error"]) != "",
		"bad addresses are refused with a reason")
	_check(NetAddress.format("2a0d::1", 7777) == "[2a0d::1]:7777" and NetAddress.format("host", 1) == "host:1",
		"addresses print back (IPv6 in brackets)")
	_check(Net.godot_minor("4.6.3-stable (official)") == "4.6" and Net.godot_minor("4.6-stable (official)") == "4.6"
		and Net.godot_minor("4.10.1-rc1") == "4.10" and Net.godot_minor(Net.godot_version()) != "",
		"server and clients compare Godot by major.minor (patch releases may differ)")
	_check(Net.broken_scripts().is_empty(), "every script co-op needs compiles (title and server check this)")

	# --- M09b: invite codes and the join handshake (NetAuth) ---
	_check(NetAuth.normalize_code(" k7qm-2xrp vb4t_5nhl ") == "K7QM2XRPVB4T5NHL" and NetAuth.normalize_code("0o1i8b") == "OOIIBB"
		and NetAuth.is_valid_code("K7QM-2XRP-VB4T-5NHL") and not NetAuth.is_valid_code("K7QM-2XRP-VB4T"),
		"M09b: invite codes forgive case, dashes and 0/O, 1/I, and have exactly 16 characters")
	var code_a := NetAuth.generate_code()
	_check(NetAuth.is_valid_code(code_a) and code_a.length() == 19 and code_a != NetAuth.generate_code(),
		"generated codes are well-formed (XXXX-XXXX-XXXX-XXXX) and random")
	_check(NetAuth.code_key("k7qm 2xrp vb4t 5nhl") == NetAuth.code_key("K7QM-2XRP-VB4T-5NHL") and NetAuth.code_key(code_a).size() == 32
		and NetAuth.code_key(code_a) != NetAuth.code_key("K7QM-2XRP-VB4T-5NHL"), "a code's key ignores formatting and differs per code")
	var invite_list := NetAuth.parse_invites("# RUNEBOUND invites\nanna\tK7QM-2XRP-VB4T-5NHL\t2026-09-25\n\njust-a-name\nbo b ZZZZ\n  ben   %s  \n" % code_a)
	var invite_keys: Dictionary = invite_list["keys"]
	_check(invite_keys.size() == 2 and invite_keys.has("anna") and invite_keys.has("ben") and int(invite_list["bad"]) == 2,
		"the invite list reads name + code lines and skips comments and broken lines")
	var nonce := NetAuth.new_nonce()
	var hello_in := {"protocol": Net.PROTOCOL, "name": "Anna"}
	var answer := NetAuth.build_join("k7qm-2xrp-vb4t-5nhl", nonce, hello_in)
	var verdict_ok := NetAuth.verify_join(answer, nonce, invite_keys, false)
	_check(int(verdict_ok["verdict"]) == NetAuth.Verdict.OK and str(verdict_ok["invite"]) == "anna"
		and str((bytes_to_var(verdict_ok["hello"] as PackedByteArray) as Dictionary).get("name", "")) == "Anna",
		"the right code gets in and names the friend; the hello arrives intact")
	var tampered := answer.duplicate()
	tampered[tampered.size() - 1] = tampered[tampered.size() - 1] ^ 1
	_check(int(NetAuth.verify_join(answer, NetAuth.new_nonce(), invite_keys, false)["verdict"]) == NetAuth.Verdict.BAD_CODE
		and int(NetAuth.verify_join(tampered, nonce, invite_keys, false)["verdict"]) == NetAuth.Verdict.BAD_CODE
		and int(NetAuth.verify_join(NetAuth.build_join(NetAuth.generate_code(), nonce, hello_in), nonce, invite_keys, false)["verdict"])
			== NetAuth.Verdict.BAD_CODE,
		"a replayed answer, a changed hello and an unknown code are all refused")
	var no_code := NetAuth.build_join("", nonce, hello_in)
	_check(int(NetAuth.verify_join(no_code, nonce, invite_keys, false)["verdict"]) == NetAuth.Verdict.NO_CODE
		and int(NetAuth.verify_join(no_code, nonce, {}, true)["verdict"]) == NetAuth.Verdict.OPEN,
		"no code: refused by a server with invites, fine for an open one")
	var big := NetAuth.MAGIC.to_ascii_buffer()
	big.resize(NetAuth.MAX_JOIN_SIZE + 1)
	var junk_checks: Array[Dictionary] = [NetAuth.verify_join(PackedByteArray([1, 2, 3]), nonce, invite_keys, false),
		NetAuth.verify_join(var_to_bytes({"protocol": 7, "name": "Old"}), nonce, invite_keys, false),
		NetAuth.verify_join(big, nonce, invite_keys, false)]
	_check(int(junk_checks[0]["verdict"]) == NetAuth.Verdict.MALFORMED and int(junk_checks[1]["verdict"]) == NetAuth.Verdict.OLD_CLIENT
		and int(junk_checks[2]["verdict"]) == NetAuth.Verdict.MALFORMED
		and not junk_checks[0].has("hello") and not junk_checks[1].has("hello") and not junk_checks[2].has("hello"),
		"noise, an old game's hello and oversized answers are refused without decoding anything")
	_check(not (multiplayer as SceneMultiplayer).server_relay, "clients never talk to each other through the server")
	SaveGame.flags = {"colossus_defeated": true}
	SaveGame.camps = {"camp_1": {"cleared_at": 5.0}}
	SaveGame.current_zone = "res://scenes/hub.tscn"
	SaveGame.save_now()
	SaveGame.begin_online_session({"spire_cleansed": true})
	_check(SaveGame.has_flag(&"spire_cleansed") and not SaveGame.has_flag(&"colossus_defeated") and SaveGame.camps.is_empty(),
		"online: the server's flags replace ours in memory")
	SaveGame.current_zone = "res://scenes/ashen_highlands.tscn"
	SaveGame.set_flag(&"server_side")  # writes the save at once
	var disk_chars: Array = SaveGame._read_file().get("characters", [])
	var disk_world: Dictionary = (disk_chars[SaveGame.active] as Dictionary).get("world", {}) if SaveGame.active < disk_chars.size() else {}
	var disk_flags: Dictionary = disk_world.get("flags", {})
	_check(disk_flags.has("colossus_defeated") and not disk_flags.has("server_side") and not disk_flags.has("spire_cleansed")
		and (disk_world.get("camps", {}) as Dictionary).has("camp_1") and str(disk_world.get("zone", "")) == "res://scenes/hub.tscn",
		"online saves keep our own world (flags, camps, zone) on disk")
	SaveGame.end_online_session()
	_check(SaveGame.has_flag(&"colossus_defeated") and not SaveGame.has_flag(&"spire_cleansed")
		and SaveGame.camps.has("camp_1") and SaveGame.current_zone == "res://scenes/hub.tscn",
		"leaving co-op restores our own world")
	var got: Array = []
	var probe := func(from: int, payload: Array) -> void: got.append([from, payload])
	Net.on(9999, probe)
	Net.send_to_server(9999, ["hi"])
	Net.off(9999, probe)
	_check(got.size() == 1 and int((got[0] as Array)[0]) == 1 and str(((got[0] as Array)[1] as Array)[0]) == "hi",
		"offline: send_to_server runs the handler right here (never an RPC to itself)")

	# --- M09 phase 2: remote heroes (puppets), interpolation, character sync ---
	var s0 := {"t": 0.0, "pos": Vector3.ZERO, "yaw": 0.0, "vel": Vector3(10, 0, 0), "state": 0, "hp": 50.0, "hp_max": 100.0, "tp": 0}
	var s1 := {"t": 100.0, "pos": Vector3(1, 0, 0), "yaw": 1.0, "vel": Vector3(10, 0, 0), "state": 1, "hp": 40.0, "hp_max": 100.0, "tp": 0}
	var mid := NetWorld.sample_at([s0, s1], 50.0)
	_check((mid["pos"] as Vector3).is_equal_approx(Vector3(0.5, 0, 0)) and is_equal_approx(float(mid["yaw"]), 0.5),
		"puppets interpolate between two snapshots")
	var jumped := s1.duplicate()
	jumped["tp"] = 1
	jumped["pos"] = Vector3(50, 0, 0)
	_check((NetWorld.sample_at([s0, jumped], 50.0)["pos"] as Vector3).is_equal_approx(Vector3(50, 0, 0)),
		"a teleport snaps instead of sliding")
	var ahead := NetWorld.sample_at([s0, s1], 1000.0)
	_check((ahead["pos"] as Vector3).is_equal_approx(Vector3(1.0 + 10.0 * NetWorld.MAX_EXTRAPOLATE_MS / 1000.0, 0, 0)),
		"with no newer snapshot a puppet extrapolates briefly, then holds")
	var zone_now := get_tree().current_scene as ZoneBase
	var puppet := Player.create()
	puppet.net_role = Player.NetRole.PUPPET
	puppet.is_local = false
	zone_now.add_player(puppet)
	var hurtbox_layer := -1
	for child in puppet.get_children():
		if child is Hurtbox:
			hurtbox_layer = (child as Hurtbox).collision_layer
	_check(not (puppet.input_source is LocalInputSource) and puppet.collision_layer == 0 and hurtbox_layer == 0,
		"a puppet reads no keyboard, blocks nobody and cannot be hit here")
	var died := [false]
	puppet.player_died.connect(func() -> void: died[0] = true)
	puppet.apply_net_state(Vector3(3, 0, 3), 1.2, Vector3.ZERO, 0, 0.0, 120.0)
	await _wait_frames(3)
	_check(puppet.global_position.is_equal_approx(Vector3(3, 0, 3)) and is_equal_approx(puppet.facing_yaw(), 1.2)
		and puppet.health.is_dead and not died[0] and is_equal_approx(puppet.health.max_health, 120.0),
		"network state poses a puppet; 0 HP marks it dead without dying locally")
	_check(not puppet.take_hit(HitInfo.create(10.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, Vector3.ZERO)),
		"hits on a puppet are ignored (its owner decides)")
	zone_now.remove_player(puppet)
	puppet.free()
	var proxy_hero := Player.create(ClassData.load_by_id(&"elementalist"))
	proxy_hero.net_role = Player.NetRole.PROXY
	proxy_hero.is_local = false
	zone_now.add_player(proxy_hero)
	var sword := ItemData.new()
	sword.slot = ItemData.Slot.WEAPON
	sword.display_name = "Test Blade"
	var ch := {"class_id": "elementalist", "known_abilities": ["rune_bolt", "ember_lance"], "gold": 5,
		"inventory": [sword.to_dict()], "equipped": {}, "progression": {"level": 4, "xp": 0, "talents": {}}}
	SaveGame.apply_character(proxy_hero, ch)
	SaveGame.apply_character(proxy_hero, ch)
	_check(proxy_hero.equipment.inventory.size() == 1 and proxy_hero.progression.level == 4 and proxy_hero.knows(&"ember_lance")
		and proxy_hero is ElementalistHero and proxy_hero.loadout[0] == &"ember_lance",
		"a proxy takes a client's character and class (re-applied without doubling the inventory)")
	zone_now.remove_player(proxy_hero)
	proxy_hero.free()

	# --- M09 phase 3a: enemy replication (offline side) ---
	var h0 := HitInfo.create(23.5, HitInfo.DamageType.FIRE, HitInfo.Weight.HEAVY, Vector3(1, 2, 3))
	h0.is_crit = true
	h0.applies_burn = true
	h0.burn_mult = 1.5
	h0.ability = &"ember_lance"
	h0.knockback = 4.0
	h0.area_center = Vector3(4, 5, 6)
	h0.area_radius = 1.1
	h0.from_player = true
	h0.threat_mult = 2.5
	h0.taunt = 3.0
	h0.pull_to = Vector3(7, 0, 8)
	h0.source_net_id = 77
	h0.chill_bonus = 1.0
	var h1 := NetCodec.hit_from_array(NetCodec.hit_to_array(h0))
	_check(is_equal_approx(h1.threat_mult, 2.5) and is_equal_approx(h1.taunt, 3.0) and h1.pull_to == Vector3(7, 0, 8)
		and h1.source_net_id == 77 and is_equal_approx(h1.chill_bonus, 1.0),
		"M10: threat, taunt, the pull, the striking enemy and Cold Snap survive the wire")
	_check(is_equal_approx(h1.damage, 23.5) and h1.type == HitInfo.DamageType.FIRE and h1.weight == HitInfo.Weight.HEAVY
		and h1.is_crit and h1.applies_burn and not h1.applies_chill and is_equal_approx(h1.burn_mult, 1.5)
		and h1.ability == &"ember_lance" and h1.area_center == Vector3(4, 5, 6) and is_equal_approx(h1.area_radius, 1.1)
		and h1.from_player and h1.attacker_id == 0,
		"hits survive the wire (the attacker is filled in by the receiver)")
	var rows: Array[Dictionary] = [{"id": 513, "pos": Vector3(-120.25, 14.5, 99.75), "yaw": 2.5, "vel": Vector3(3, 0, -4),
		"state": 5, "seq": 201, "hp": 77.5, "bits": NetCodec.ST_BURN | NetCodec.ST_INVULNERABLE}]
	var bytes := NetCodec.encode_enemies(rows)
	var decoded := NetCodec.decode_enemies(bytes)
	_check(bytes.size() == NetCodec.ENEMY_BYTES and decoded.size() == 1 and int(decoded[0]["id"]) == 513
		and (decoded[0]["pos"] as Vector3).is_equal_approx(Vector3(-120.25, 14.5, 99.75))
		and absf(float(decoded[0]["yaw"]) - 2.5) < 0.001 and (decoded[0]["vel"] as Vector3).is_equal_approx(Vector3(3, 0, -4))
		and int(decoded[0]["state"]) == 5 and int(decoded[0]["seq"]) == 201 and is_equal_approx(float(decoded[0]["hp"]), 77.5)
		and int(decoded[0]["bits"]) == NetCodec.ST_BURN | NetCodec.ST_INVULNERABLE,
		"an enemy snapshot row packs into %d bytes and back" % NetCodec.ENEMY_BYTES)
	var ghost := ZoneBase.make_enemy("caster")
	ghost.net_puppet = true
	zone_now.enemies_root.add_child(ghost)
	ghost.global_position = zone_now.player.global_position + Vector3(0, 0, -5)
	await _wait_frames(3)
	var ghost_hp := ghost.health.current_health
	var took := ghost.take_hit(HitInfo.create(30.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.MEDIUM, Vector3.ZERO))
	ghost.status.apply_shock()
	_check(took and is_equal_approx(ghost.health.current_health, ghost_hp) and not ghost.status.has_shock()
		and ghost.type_id == "caster",
		"a puppet enemy sends hits and statuses to the server instead of taking them")
	ghost.apply_net_pose(Vector3(2, 0, 2), 1.0, Vector3.ZERO, 10.0, NetCodec.ST_SHOCK)
	_check(ghost.status.has_shock() and is_equal_approx(ghost.health.current_health, 10.0),
		"snapshots set a puppet's health and statuses")
	await _wait_frames(40)
	_check(ghost.global_position.is_equal_approx(Vector3(2, 0, 2)) and ghost.ai_state == EnemyBase.AIState.IDLE,
		"a puppet enemy never thinks or moves on its own")
	ghost.present_death()
	await _wait_frames(30)
	_check(not is_instance_valid(ghost), "the server's death removes the puppet")

	# --- M09 phase 4: rewards, save v5 ---
	var v4 := {"version": 4, "world": {"zone": "res://scenes/hub.tscn", "flags": {"discovered_hub": true,
		"discovered_ashen_highlands": true, "colossus_defeated": true}, "camps": {}},
		"characters": [{"class_id": "runebreaker", "known_abilities": ["rune_cleave"], "gold": 3, "inventory": [],
		"equipped": {}, "progression": {"level": 2, "xp": 0, "talents": {}}, "waypoints": [], "map_discovered": []}],
		"active": 0}
	var v5 := SaveGame.migrate(v4)
	var migrated: Array = ((v5.get("characters", []) as Array)[0] as Dictionary).get("discovered", [])
	_check(int(v5.get("version", 0)) == SaveGame.VERSION and migrated.has("hub") and migrated.has("ashen_highlands")
		and migrated.size() == 2, "save v4 -> v5: zone discovery moves into the character")
	var rewardee := zone_now.player
	var reward_xp0 := rewardee.progression.xp
	var reward_lv0 := rewardee.progression.level
	var reward_drops0 := 0
	for child in zone_now.world.get_children():
		if child is ItemDrop or child is GoldDrop:
			reward_drops0 += 1
	var loot: Array[ItemData] = [ItemGenerator.generate(0), ItemGenerator.generate(0)]
	var far_spot := rewardee.global_position + Vector3(30, 0, 0)  # out of pickup reach
	zone_now.give_reward(rewardee, 7, 25, 2, loot, far_spot)
	var reward_drops1 := 0
	for child in zone_now.world.get_children():
		if child is ItemDrop or child is GoldDrop:
			reward_drops1 += 1
	_check(reward_drops1 - reward_drops0 == 4 and (rewardee.progression.xp != reward_xp0 or rewardee.progression.level != reward_lv0),
		"a reward for the local hero: XP at once, gold piles and items on the ground")
	_check(zone_now.heroes_near(rewardee.global_position, 1.0).has(rewardee) and zone_now.party().has(rewardee),
		"the local hero is in reward range and in the party")
	_check(rewardee.discovered_zones.has(zone_now.scene_file_path.get_file().get_basename())
		and SaveGame.character_dict(rewardee).has("discovered"),
		"zone discovery is remembered per character (save v5)")
	for child in zone_now.world.get_children():
		if child is ItemDrop or child is GoldDrop:
			if child.global_position.distance_to(far_spot) < 3.0:
				child.free()

	# --- M17a: settings (GameSettings) ---
	_check(GameSettings.dev_tools() and is_equal_approx(float(GameSettings.value("audio/master")), 1.0)
		and GameSettings.test_run, "a test run plays on the default settings with the developer tools on")
	var settings_file := "user://settings_smoke_m17a.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_file))  # a killed run may have left one
	var pre := ConfigFile.new()
	pre.set_value("coop", "name", "Keeper")
	pre.save(settings_file)
	GameSettings.use_file(settings_file)
	GameSettings.set_value("audio/music", 0.5)
	var m17_music_bus := AudioServer.get_bus_index("Music")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(m17_music_bus), float(Sfx.BUSES["Music"]) + linear_to_db(0.5))
		and not AudioServer.is_bus_mute(m17_music_bus), "music at 50 %% sits 6 dB under its mix level (%.1f dB)" % AudioServer.get_bus_volume_db(m17_music_bus))
	GameSettings.set_value("audio/effects", 0.0)
	_check(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")) and AudioServer.is_bus_mute(AudioServer.get_bus_index("Telegraph")),
		"effects at 0 mute the SFX and telegraph buses")
	var saved_cfg := ConfigFile.new()
	saved_cfg.load(settings_file)
	_check(is_equal_approx(float(saved_cfg.get_value("audio", "music", -1.0)), 0.5) and str(saved_cfg.get_value("coop", "name", "")) == "Keeper",
		"a setting is saved at once and the co-op section stays in the file")
	GameSettings.reset_section("audio")
	GameSettings.use_file(settings_file)
	_check(is_equal_approx(float(GameSettings.value("audio/music")), 1.0) and not AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX"))
		and is_equal_approx(AudioServer.get_bus_volume_db(m17_music_bus), float(Sfx.BUSES["Music"])),
		"Reset brings the volumes back and survives a reload")
	GameSettings.set_value("controls/sensitivity", 2.0)
	GameSettings.use_file(settings_file)
	_check(is_equal_approx(GameSettings.mouse_sensitivity(), 2.0), "the sensitivity is read back from the file")
	var m17_rig := zone_now.camera_rig
	var yaw0 := float(m17_rig.get(&"_yaw"))
	var pitch0 := float(m17_rig.get(&"_pitch"))
	m17_rig.look(Vector2(10, 10))
	var yaw_step := yaw0 - float(m17_rig.get(&"_yaw"))
	var pitch_step := pitch0 - float(m17_rig.get(&"_pitch"))
	GameSettings.set_value("controls/invert_y", true)
	m17_rig.look(Vector2(0, 10))
	var pitch_back := float(m17_rig.get(&"_pitch")) - (pitch0 - pitch_step)
	_check(is_equal_approx(yaw_step, m17_rig.sensitivity * 20.0) and is_equal_approx(pitch_step, m17_rig.sensitivity * 20.0)
		and is_equal_approx(pitch_back, m17_rig.sensitivity * 20.0),
		"mouse look follows the sensitivity (x2) and invert-Y turns the pitch around")
	GameSettings.reset_section("controls")
	GameSettings.set_value("controls/zoom_speed", 2.0)
	var zoom0 := float(m17_rig.get(&"_zoom"))
	var zoom_ev := InputEventAction.new()
	zoom_ev.action = &"zoom_out"
	zoom_ev.pressed = true
	m17_rig._unhandled_input(zoom_ev)
	_check(is_equal_approx(float(m17_rig.get(&"_zoom")) - zoom0, minf(CameraRig.ZOOM_STEP * 2.0, CameraRig.ZOOM_MAX - zoom0)),
		"the zoom speed scales a wheel step")
	GameSettings.reset_section("controls")
	GameSettings.set_value("gameplay/shake", 0.5)
	m17_rig.set(&"_trauma", 0.0)
	m17_rig.add_trauma(0.4)
	var half_trauma := float(m17_rig.get(&"_trauma"))
	GameSettings.set_value("gameplay/shake", 0.0)
	m17_rig.set(&"_trauma", 0.0)
	m17_rig.add_trauma(0.4)
	_check(is_equal_approx(half_trauma, 0.2) and is_zero_approx(float(m17_rig.get(&"_trauma"))),
		"screen shake follows its setting (50 % halves it, 0 turns it off)")
	var flash_hud := zone_now.hud
	var flash_hp := zone_now.player.health
	GameSettings.set_value("gameplay/hurt_flash", false)
	flash_hud._hurt_flash.color.a = 0.0
	flash_hud.set(&"_last_health", flash_hp.max_health)
	flash_hud._on_health_changed(flash_hp.max_health * 0.5, flash_hp.max_health)
	var flash_off := flash_hud._hurt_flash.color.a
	GameSettings.set_value("gameplay/hurt_flash", true)
	flash_hud.set(&"_last_health", flash_hp.max_health)
	flash_hud._on_health_changed(flash_hp.max_health * 0.5, flash_hp.max_health)
	_check(is_zero_approx(flash_off) and flash_hud._hurt_flash.color.a > 0.1, "the red hit flash can be switched off")
	flash_hud._on_health_changed(flash_hp.current_health, flash_hp.max_health)
	flash_hud._hurt_flash.color.a = 0.0
	GameSettings.set_value("gameplay/damage_numbers", false)
	var labels0 := zone_now.find_children("*", "Label3D", true, false).size()
	GameFeel.damage_number(zone_now.player.global_position, 12.0)
	var labels_off := zone_now.find_children("*", "Label3D", true, false).size()
	GameSettings.set_value("gameplay/damage_numbers", true)
	GameFeel.damage_number(zone_now.player.global_position, 12.0)
	_check(labels_off == labels0 and zone_now.find_children("*", "Label3D", true, false).size() == labels0 + 1,
		"damage numbers can be switched off")
	GameSettings.set(&"_dev_forced", false)
	var f1 := InputEventAction.new()
	f1.action = &"debug_toggle"
	f1.pressed = true
	zone_now.debug_overlay._unhandled_input(f1)
	var j_key := InputEventAction.new()
	j_key.action = &"playtest_toggle"
	j_key.pressed = true
	zone_now.playtest_ui._unhandled_input(j_key)
	var dev_hidden := not zone_now.debug_overlay._visible and not zone_now.playtest_ui.visible
	GameSettings.set_value("gameplay/dev_tools", true)
	zone_now.debug_overlay._unhandled_input(f1)
	var dev_shown := zone_now.debug_overlay._visible
	zone_now.debug_overlay._unhandled_input(f1)
	_check(dev_hidden and dev_shown and not zone_now.debug_overlay._visible,
		"without the developer tools setting F1 and J do nothing; with it F1 opens the debug panel")
	GameSettings.set(&"_dev_forced", true)
	GameSettings.reset_section("gameplay")
	# M17a phase 4: key bindings
	_check(KeyBindings.codes(&"interact") == PackedStringArray(["key:%d" % KEY_E]) and InputSetup.key_label(&"dodge") == "SPC"
		and InputSetup.key_label(&"primary_attack") == "LMB" and InputSetup.key_label(&"secondary_ability") == "RMB",
		"the default bindings: E interacts, Space dodges, the mouse attacks")
	var taken_none := KeyBindings.bind(&"interact", 0, "key:%d" % KEY_F)
	_check(taken_none == &"" and InputSetup.key_label(&"interact") == "F" and InteractPrompt.key_name() == "F",
		"interact moves to F; the [E] prompts follow")
	var taken_k := KeyBindings.bind(&"talents_toggle", 0, "key:%d" % KEY_K)
	_check(taken_k == &"loadout_toggle" and KeyBindings.is_unbound(&"loadout_toggle")
		and KeyBindings.codes(&"talents_toggle") == PackedStringArray(["key:%d" % KEY_K]),
		"a key taken from another action leaves it (the loadout has no key now)")
	KeyBindings.bind(&"ability_q", 0, "key:%d" % KEY_4)
	_check(KeyBindings.bind(&"dodge", 0, "key:%d" % KEY_ESCAPE) == &"" and InputSetup.key_label(&"dodge") == "SPC",
		"Esc cannot be bound (it opens the menu)")
	GameSettings.save_bindings()
	var slot1_label := str((zone_now.hud._slots[&"slot1"]["key_label"] as Label).text)
	var talents_tab := str((zone_now.hero_ui.get(&"_buttons") as Array)[HeroUI.Tab.TALENTS].text)
	_check(slot1_label == "4" and talents_tab.contains("K"),
		"rebinding relabels the HUD slot (%s) and the hero window tab (%s)" % [slot1_label, talents_tab])
	var keys_cfg := ConfigFile.new()
	keys_cfg.load(settings_file)
	GameSettings.use_file(settings_file)
	_check(keys_cfg.has_section_key("keys", "interact") and InputSetup.key_label(&"interact") == "F"
		and KeyBindings.is_unbound(&"loadout_toggle") and not keys_cfg.has_section_key("keys", "dodge"),
		"the changed bindings are saved and read back (only the changed ones)")
	GameSettings.reset_bindings()
	keys_cfg = ConfigFile.new()
	keys_cfg.load(settings_file)
	_check(InputSetup.key_label(&"interact") == "E" and InputSetup.key_label(&"loadout_toggle") == "K"
		and KeyBindings.codes(&"ability_q") == PackedStringArray(["key:%d" % KEY_1, "key:%d" % KEY_Q])
		and not keys_cfg.has_section("keys") and str((zone_now.hud._slots[&"slot1"]["key_label"] as Label).text) == "1",
		"Reset puts every key back (and empties the [keys] section)")

	# --- M12 phase 0: the text table (DE/EN), the language setting, the lore window ---
	_check(Texts.keys().size() >= 4 and Texts.incomplete().is_empty(),
		"every text key has English and German (%d keys, missing: %s)" % [Texts.keys().size(), str(Texts.incomplete())])
	_check(str(GameSettings.value("general/language")) == "en" and Texts.language() == "en"
		and Texts.t("lore.ash.letter_1.title") == "A soldier's last letter",
		"a test run reads the texts in English (%s)" % Texts.language())
	_check(Texts.t("no.such.key") == "no.such.key" and Texts.t("ui.lore.close", ["E"]).begins_with("[E]")
		and Texts.resolve("de") == "de" and Texts.resolve("auto") in Texts.LANGUAGES,
		"a missing key shows itself, arguments format, auto resolves to a known language")
	var lang_label := UiTheme.caption("ui.settings.language_hint")
	zone_now.hud.add_child(lang_label)
	var hint_en := lang_label.atr(lang_label.text)
	GameSettings.set_value("general/language", "de")
	var hint_de := lang_label.atr(lang_label.text)
	_check(Texts.language() == "de" and Texts.t("lore.ash.letter_1.title") == "Der letzte Brief eines Soldaten"
		and hint_en.begins_with("German covers") and hint_de.begins_with("Deutsch gibt es"),
		"switching to German translates the texts and a Label showing a key")
	lang_label.queue_free()
	GameSettings.reset_section("gameplay")
	var lang_cfg := ConfigFile.new()
	lang_cfg.load(settings_file)
	GameSettings.use_file(settings_file)
	_check(Texts.language() == "de" and str(lang_cfg.get_value("general", "language", "")) == "de",
		"the language is saved, read back, and the Gameplay tab's Reset leaves it alone")
	var lore := zone_now.lore_ui
	lore.open("lore.ash.letter_1", "", zone_now.player)
	var lore_title_de := str((lore.get(&"_title") as Label).text)
	_check(lore != null and lore.visible and zone_now.player.input_locked and lore_title_de == "Der letzte Brief eines Soldaten"
		and str((lore.get(&"_body") as Label).text).begins_with("Edda, seit"),
		"the lore window shows a text in the current language and locks the hero")
	GameSettings.set_value("general/language", "en")
	_check(str((lore.get(&"_title") as Label).text) == "A soldier's last letter"
		and str((lore.get(&"_footer") as Label).text).begins_with("[E]"),
		"the open lore window follows a language switch at once")
	var lore_esc := InputEventAction.new()
	lore_esc.action = &"toggle_cursor"
	lore_esc.pressed = true
	lore._unhandled_input(lore_esc)
	_check(not lore.visible and not zone_now.player.input_locked and lore.shown_id == "", "Esc closes the lore window and frees the hero")
	lore.open("lore.ash.letter_1")
	var lore_e := InputEventAction.new()
	lore_e.action = &"interact"
	lore_e.pressed = true
	lore._unhandled_input(lore_e)
	var closed_by_e := not lore.visible
	lore.open("lore.ash.letter_1")
	zone_now.hero_ui.open_tab(HeroUI.Tab.INVENTORY)
	var closed_by_window := not lore.visible and zone_now.player.input_locked
	zone_now.hero_ui.close()
	lore.open("lore.ash.letter_1")
	_check(closed_by_e and closed_by_window and zone_now.close_windows() and not lore.visible and not zone_now.player.input_locked,
		"the interact key closes it too; another window or close_windows() closes it")

	# --- M17a: the Esc menu ---
	var menu := zone_now.pause_menu
	var esc_ev := InputEventAction.new()
	esc_ev.action = &"toggle_cursor"
	esc_ev.pressed = true
	_check(menu != null and not menu.visible and not PauseMenu.showing and not get_tree().paused,
		"every zone has an Esc menu, closed at the start")
	Input.parse_input_event(esc_ev)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(menu.visible and PauseMenu.showing and get_tree().paused and menu.get(&"_title").text == "PAUSED",
		"Esc with nothing open opens the menu and pauses the solo world")
	var inv_ev := InputEventAction.new()
	inv_ev.action = &"inventory_toggle"
	inv_ev.pressed = true
	zone_now.hero_ui._unhandled_input(inv_ev)
	_check(not zone_now.hero_ui.visible, "no window opens under the Esc menu (I does nothing)")
	menu.open_settings()
	await get_tree().process_frame
	var menu_settings_open := menu.get(&"_settings") != null
	Input.parse_input_event(esc_ev)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(menu_settings_open and menu.get(&"_settings") == null and menu.visible,
		"Settings opens from the menu; Esc closes them and the menu stays")
	Input.parse_input_event(esc_ev)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not menu.visible and not PauseMenu.showing and not get_tree().paused, "Esc again closes the menu and the world runs on")
	zone_now.hero_ui.open_tab(HeroUI.Tab.INVENTORY)
	Input.parse_input_event(esc_ev)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not zone_now.hero_ui.visible and not menu.visible, "an open window takes Esc first (it closes, no menu)")
	zone_now.playtest_ui.open()
	var list_open := zone_now.playtest_ui.visible
	zone_now.debug_overlay.set(&"_visible", true)
	Input.parse_input_event(esc_ev)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(list_open and not zone_now.playtest_ui.visible and not menu.visible,
		"Esc closes a window even while the F1 panel shows (the playtest list)")
	zone_now.debug_overlay.set(&"_visible", false)
	menu.close()
	zone_now.player.health.current_health = zone_now.player.health.max_health * 0.6

	# --- M10: several characters per save, each with its own world (title screen) ---
	SaveGame.flags = {"colossus_defeated": true}
	SaveGame.save_now()
	# 2026-10-01: the Join page's server list. The title reads its own settings
	# file; settings from before the list (last address + its code) pick the
	# listed server.
	var real_settings := ClientSettings.path
	ClientSettings.path = "user://settings_smoke.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ClientSettings.path))
	var known_servers: Array[Dictionary] = ServerList.all()
	var acer := ServerList.by_id("acer")
	var smoke_code := "K7QM-2XRP-VB4T-5NHL"
	if not acer.is_empty():
		var old_cfg := ConfigFile.new()
		old_cfg.set_value("coop", "last_server", " %s " % str(acer["address"]).to_upper())
		old_cfg.set_value("coop", "invites", {str(acer["address"]).to_lower(): smoke_code})
		old_cfg.save(ClientSettings.path)
	# M17a: the way back is the Esc menu's "Save and return to title"
	var hp_left := zone_now.player.health.current_health
	menu.open()
	(menu.get(&"_back_btn") as Button).pressed.emit()
	for i in 300:
		await get_tree().process_frame
		if get_tree().current_scene != null and get_tree().current_scene.scene_file_path == "res://scenes/title.tscn":
			break
	var title := get_tree().current_scene
	_check(title != null and title.scene_file_path == "res://scenes/title.tscn", "the title screen loads")
	var saved_hp := float((SaveGame.active_character().get("vitals", {}) as Dictionary).get("hp", -1.0))
	_check(is_equal_approx(saved_hp, hp_left) and not get_tree().paused and not PauseMenu.showing,
		"\"Save and return to title\" saves the hero (health %.0f) and unpauses" % saved_hp)
	_check(not (title.get(&"_main_status") as Label).visible, "a return from the menu shows no warning on the title")
	var first_count := SaveGame.characters().size()
	var tank_line := str(title.call(&"_continue_label"))
	var mage_index := SaveGame.create_character(&"elementalist", "Brynja")
	_check(SaveGame.characters().size() == first_count + 1 and SaveGame.active == mage_index
		and SaveGame.active_class_id() == &"elementalist" and not SaveGame.has_flag(&"colossus_defeated")
		and SaveGame.current_zone == SaveGame.HUB_SCENE,
		"a new character starts in its own fresh world (no boss down, in Runehold)")
	_check(tank_line.contains("Runebreaker") and str(title.call(&"_continue_label")).contains("Brynja, Elementalist level 1"),
		"Continue names the active character (%s)" % str(title.call(&"_continue_label")))
	SaveGame.flags = {"mage_flag": true}
	_check(SaveGame.select_character(0) and SaveGame.active_class_id() == &"runebreaker" and SaveGame.has_flag(&"colossus_defeated")
		and not SaveGame.has_flag(&"mage_flag"), "switching back brings the first character's world back")
	_check(SaveGame.select_character(mage_index) and SaveGame.has_flag(&"mage_flag"), "each character keeps its own world")
	title.call(&"_show_characters")
	await get_tree().process_frame
	var list_rows := (title.get(&"_chars_list") as VBoxContainer).get_child_count()
	title.call(&"_delete_character", mage_index)
	var armed := SaveGame.characters().size() == first_count + 1
	title.call(&"_delete_character", mage_index)
	_check(list_rows == first_count + 1 and armed and SaveGame.characters().size() == first_count and SaveGame.active == 0,
		"the character list shows every character; Delete needs a second click, then the character is gone")
	SaveGame.reload_from_disk()
	_check(SaveGame.characters().size() == first_count and SaveGame.active_class_id() == &"runebreaker",
		"the characters survive a reload from disk")

	# The server dropdown: names only, the address stays out of sight.
	var all_valid := not known_servers.is_empty()
	for server: Dictionary in known_servers:
		all_valid = all_valid and String(NetAddress.parse(str(server["address"]), Net.DEFAULT_PORT)["error"]) == ""
	_check(all_valid and not acer.is_empty() and str(acer["name"]) == "Acer"
		and str(NetAddress.parse(str(acer["address"]), Net.DEFAULT_PORT)["url"]).begins_with("wss://"),
		"the server list (resources/net/servers.json) loads; the Acer is a Funnel name (WebSocket)")
	var pick := title.get(&"_server_pick") as OptionButton
	var address_edit := title.get(&"_address_edit") as LineEdit
	var invite_edit := title.get(&"_invite_edit") as LineEdit
	title.call(&"_show_join")
	await get_tree().process_frame
	_check(pick != null and pick.item_count == known_servers.size() + 1 and pick.get_item_text(0) == "Acer"
		and pick.get_item_text(pick.item_count - 1) == "Other address ...",
		"the Join page offers the listed servers by name, then \"Other address\"")
	_check(pick != null and pick.selected == 0 and not address_edit.is_visible_in_tree() and invite_edit.text == smoke_code
		and str(title.call(&"_join_label")) == "Acer" and str(title.call(&"_join_address")) == str(acer.get("address", "")),
		"settings from before the list pick the Acer and keep its invite code (picked %d, code \"%s\")" % [
			pick.selected if pick != null else -1, invite_edit.text])
	var shown: Array[String] = []
	var visit: Array[Node] = [title.get(&"_join_page") as Node]
	while not visit.is_empty():
		var n: Node = visit.pop_back()
		visit.append_array(n.get_children())
		if n is Control and not (n as Control).is_visible_in_tree():
			continue
		if n is Label:
			shown.append((n as Label).text)
		elif n is LineEdit and not (n as LineEdit).secret:
			shown.append((n as LineEdit).text)
		elif n is Button:
			shown.append((n as Button).text)
	if pick != null:
		for i in pick.item_count:
			shown.append(pick.get_item_text(i))
	var leaks := shown.filter(func(t: String) -> bool: return t.contains(".ts.net") or t.contains(str(acer.get("address", "?"))))
	_check(leaks.is_empty(), "no visible text on the Join page names the server's address (%s)" % [leaks])
	if pick != null:
		title.call(&"_select_server", pick.item_count - 1)
		address_edit.text = "127.0.0.1:7777"
		var typed_ok := address_edit.is_visible_in_tree() and str(title.call(&"_join_label")) == "127.0.0.1:7777"
		title.call(&"_select_server", 0)
		_check(typed_ok and not address_edit.is_visible_in_tree() and invite_edit.text == smoke_code,
			"\"Other address\" shows the address field, picking the Acer again hides it and brings its code back")
	_check(Net.version_reason(8, 12).contains("older RUNEBOUND") and Net.version_reason(8, 12).contains("release")
		and Net.version_reason(12, 8).contains("Update your game") and not Net.version_reason(12, 8).contains("older RUNEBOUND"),
		"a protocol refusal says which side is behind (a newer game: the host updates the server)")
	# M17a: character first, then solo or online; the campfire scene behind
	var backdrop := title.get(&"_backdrop") as TitleBackdrop
	_check(backdrop != null and backdrop.hero != null and backdrop.camera != null and backdrop.camera.current
		and backdrop.hero.class_id == SaveGame.active_class_id(),
		"the title has its campfire scene with the active character's rig (%s)" % [backdrop.hero.class_id if backdrop != null and backdrop.hero != null else &"-"])
	title.call(&"_show_create")
	for b: Button in title.get(&"_class_buttons"):
		if b.get_meta(&"class_id") == &"druid":
			b.button_pressed = true
			b.pressed.emit()
	_check(backdrop.hero.class_id == &"druid", "picking a class on the create page shows that class by the fire")
	(title.get(&"_char_name_edit") as LineEdit).text = ""
	var chars_before := SaveGame.characters().size()
	title.call(&"_create")
	_check(SaveGame.characters().size() == chars_before + 1 and SaveGame.active == chars_before
		and (title.get(&"_chars_page") as Control).visible and SaveGame.active_class_id() == &"druid",
		"Create adds the character, selects it and shows the list (Play solo / Play online)")
	title.call(&"_select_character", 0)
	_check(SaveGame.active == 0 and backdrop.hero.class_id == SaveGame.active_class_id(),
		"clicking a character selects it and the fire shows its class")
	title.call(&"_select_character", chars_before)
	title.call(&"_show_join")
	var name_edit := title.get(&"_name_edit") as LineEdit
	var join_as := str((title.get(&"_join_as") as Label).text)
	_check(name_edit.visible and join_as.contains("Druid, level 1"),
		"an unnamed character going online is asked for a name (%s)" % join_as)
	name_edit.text = ""
	var blocked := not bool(title.call(&"_apply_name"))
	name_edit.text = "Ashroot"
	_check(blocked and bool(title.call(&"_apply_name")) and str(SaveGame.active_character().get("name", "")) == "Ashroot"
		and not name_edit.visible and str((title.get(&"_join_as") as Label).text).contains("Ashroot, Druid level 1"),
		"the name is required, then saved to the character (the party sees it)")
	title.call(&"_show_join")
	_check(not name_edit.visible, "a named character goes online under its own name (no name field)")
	ClientSettings.set_value("last_mode", "online")
	ClientSettings.set_value("server_pick", "acer")
	var online_line := str(title.call(&"_continue_mode_text"))
	ClientSettings.set_value("last_mode", "solo")
	var solo_line := str(title.call(&"_continue_mode_text"))
	_check(online_line == "Online  -  Acer" and solo_line == "Solo  -  Runehold",
		"Continue says how it plays: \"%s\" / \"%s\"" % [online_line, solo_line])
	title.call(&"_delete_character", SaveGame.active)
	title.call(&"_delete_character", SaveGame.active)
	_check(SaveGame.characters().size() == chars_before, "the selected character is deleted with two clicks")
	title.call(&"_show_characters")
	title.call(&"_unhandled_input", esc_ev)
	_check((title.get(&"_main_page") as Control).visible, "Esc goes back from the list to the main page")

	# M17a: the settings window on the title screen
	title.call(&"_show_main")
	title.call(&"show_settings")
	await get_tree().process_frame
	var settings_ui := title.get(&"_settings") as SettingsUI
	var music_slider := settings_ui.find_child("audio_music", true, false) as HSlider if settings_ui != null else null
	_check(settings_ui != null and settings_ui.is_visible_in_tree() and not (title.get(&"_column") as Control).visible
		and music_slider != null and is_equal_approx(music_slider.value, 1.0),
		"Settings on the title opens the settings window (four tabs, the music slider at 100 %)")
	if music_slider != null:
		music_slider.value = 0.3
	_check(is_equal_approx(float(GameSettings.value("audio/music")), 0.3), "moving a slider changes the setting")
	# the Controls tab: click a binding, press the new key; Esc cancels, Delete clears
	settings_ui.open_tab(SettingsUI.Tab.CONTROLS)
	await get_tree().process_frame
	var bind_btn := settings_ui.find_child("bind_interact_0", true, false) as Button
	var g_key := InputEventKey.new()
	g_key.physical_keycode = KEY_G
	g_key.keycode = KEY_G
	g_key.pressed = true
	if bind_btn != null:
		bind_btn.pressed.emit()
	var waiting := settings_ui.is_capturing() and bind_btn != null and bind_btn.text == "Press a key ..."
	Input.parse_input_event(g_key)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(waiting and not settings_ui.is_capturing() and InputSetup.key_label(&"interact") == "G" and bind_btn.text == "G",
		"the Controls tab: click Interact, press G - Interact is on G")
	bind_btn.pressed.emit()
	Input.parse_input_event(esc_ev)
	await get_tree().process_frame
	await get_tree().process_frame
	var still_g := InputSetup.key_label(&"interact") == "G" and title.get(&"_settings") != null
	bind_btn.pressed.emit()
	var del_key := InputEventKey.new()
	del_key.physical_keycode = KEY_DELETE
	del_key.keycode = KEY_DELETE
	del_key.pressed = true
	Input.parse_input_event(del_key)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(still_g and KeyBindings.is_unbound(&"interact") and bind_btn.text == "Not bound",
		"Esc while waiting cancels (the window stays open), Delete clears the binding (shown as Not bound)")
	GameSettings.reset_bindings()
	_check(InputSetup.key_label(&"interact") == "E" and bind_btn.text == "E", "the list follows a reset")
	title._unhandled_input(esc_ev)
	await get_tree().process_frame
	_check(title.get(&"_settings") == null and (title.get(&"_column") as Control).visible, "Esc closes the settings window")
	GameSettings.reset_section("audio")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings_smoke_m17a.cfg"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ClientSettings.path))
	ClientSettings.path = real_settings

	SaveGame.wipe()
	print("== %d failures ==" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)

