extends Node
## Data-driven screenshot runner: `tools\run_godot.ps1 shots <list>` launches
## the list's zone with `-- --shots=<json>`; ZoneBase attaches this node.
## One JSON file per shot list (tests/shots/*.json):
##   zone      scene the shots are taken in (the runner switches there first)
##   out       output folder under the project (e.g. "captures_shots/vignette")
##   variants  optional [{name, look:{...}}] — every shot is taken per variant,
##             look settings go through LookDev.apply()
##   shots     [{name, player:[x,y,z], face (yaw rad), yaw, pitch, zoom, clear,
##             spawners, spawn:[{id, at:[x,y,z], face, freeze, call}], actions:[...],
##             settle}]
## Actions: {"do": "melee"|"ember"|"earthbreaker"|"storm_step"|"chain_spark"|
## "fracture_rune"|"dodge"|"tab"}, {"wait": s}, {"press": action, "for": s},
## {"hold": action} / {"release": action} (e.g. keep running while casting),
## {"do": "inventory"} toggles the inventory, {"hover": "<slot id>"} puts the
## mouse on an ability slot (tooltip shots), {"do": "loot"} drops a random item,
## {"do": "legendary"} a legendary. M07: {"xp": n} grants XP, {"learn": [ids]}
## learns talents, {"do": "talents" | "runic_guard" | "resonance_burst"}.
## M07b: {"gold": n}, {"learn_abilities": [ids] | "all"}, {"do": "trainer" |
## "hero_inventory" | "hero_character" | "hero_talents" | "gold"}; a list with
## "fresh_abilities": true starts with the one-ability kit.

var list_path: String = ""

var _zone: ZoneBase
var _list: Dictionary = {}
var _shot_index: int = 0


func _ready() -> void:
	_zone = get_parent() as ZoneBase
	_list = _load_list(list_path)
	if _list.is_empty():
		push_error("shot_runner: cannot read shot list '%s'" % list_path)
		get_tree().quit(1)
		return
	var zone_path: String = _list.get("zone", "")
	if zone_path != "" and _zone.scene_file_path != zone_path:
		# Launched in the wrong scene: hop to the list's zone; the fresh zone
		# attaches its own runner from the same command-line flag.
		get_tree().change_scene_to_file.call_deferred(zone_path)
		return
	_run.call_deferred()


static func _load_list(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _run() -> void:
	var player := _zone.player
	player.god_mode = true
	if not _list.get("fresh_abilities", false):  # M07b: shots know the whole kit unless asked not to
		player.debug_learn_all()
	await _wait(1.0)
	var variants: Array = _list.get("variants", [{"name": "", "look": {}}])
	for variant: Dictionary in variants:
		LookDev.apply(variant.get("look", {}))
		_shot_index = 0
		for shot: Dictionary in _list.get("shots", []):
			await _take(shot, variant.get("name", ""))
	print("shot_runner: done (%d variants)" % variants.size())
	get_tree().quit(0)


func _take(shot: Dictionary, variant_name: String) -> void:
	var player := _zone.player
	_set_spawners_enabled(shot.get("spawners", false))
	if shot.get("clear", true):
		for child in _zone.enemies_root.get_children():
			child.free()
	if shot.has("player"):
		player.global_position = _pos(_zone, shot["player"])
		player.velocity = Vector3.ZERO
	if shot.has("face"):
		player._visual.rotation.y = float(shot["face"])
	var rig := _zone.camera_rig
	rig._yaw = float(shot.get("yaw", rig._yaw))
	rig._pitch = float(shot.get("pitch", rig._pitch))
	if shot.has("zoom"):
		rig._zoom = float(shot["zoom"])
		rig.spring.spring_length = rig._zoom
	var frozen: Array[EnemyBase] = []
	var calls := []
	for spec: Dictionary in shot.get("spawn", []):
		var id: String = spec.get("id", "rusher")
		var enemy: EnemyBase
		if id in ["colossus", "vessel"]:  # bosses: not in spawn_by_id (zones script them)
			enemy = ZoneBase.make_enemy(id)
			_zone.call(&"_spawn_enemy", enemy, _pos(_zone, spec.get("at", [0, 0.2, 0])))
		else:
			enemy = _zone.spawn_by_id(id, _pos(_zone, spec.get("at", [0, 0.2, 0])))
		if spec.has("call"):
			calls.append([enemy, StringName(spec["call"])])
		if spec.has("face"):
			enemy.visual.rotation.y = float(spec["face"])
		if spec.get("freeze", false):
			frozen.append(enemy)
	await _wait(0.25)  # let spawns land before freezing them in place
	for enemy in frozen:
		if is_instance_valid(enemy):
			enemy.set_physics_process(false)
	# "call": start an attack on a frozen enemy (its state timer never runs, so
	# the windup pose + telegraph can be caught at any fraction by "settle")
	for entry: Array in calls:
		if is_instance_valid(entry[0]):
			(entry[0] as Node).call(entry[1])
	for action: Dictionary in shot.get("actions", []):
		await _do(action)
	await _wait(float(shot.get("settle", 0.5)))
	await _shot(shot.get("name", "shot"), variant_name)


func _do(action: Dictionary) -> void:
	var player := _zone.player
	if action.has("wait"):
		await _wait(float(action["wait"]))
	elif action.has("press"):
		var input_action := StringName(action["press"])
		Input.action_press(input_action)
		await _wait(float(action.get("for", 0.3)))
		Input.action_release(input_action)
	elif action.has("hold"):
		Input.action_press(StringName(action["hold"]))
	elif action.has("release"):
		Input.action_release(StringName(action["release"]))
	elif action.has("hover"):
		get_viewport().warp_mouse(_zone.hud.slot_rect(StringName(action["hover"])).get_center())
	elif action.has("xp"):
		player.progression.add_xp(int(action["xp"]))
	elif action.has("learn"):
		for id: String in action["learn"]:
			player.progression.learn(Progression.talent(StringName(id)))
	elif action.has("gold"):  # M07b
		player.add_gold(int(action["gold"]))
	elif action.has("give_items"):  # M07b: straight into the inventory (no pickup walk)
		for i in int(action["give_items"]):
			player.equipment.add_item(ItemGenerator.generate(randi() % 3))
	elif action.has("learn_abilities"):  # M07b: ["earthbreaker", ...] or "all"
		if str(action["learn_abilities"]) == "all":
			player.debug_learn_all()
		else:
			for id: String in action["learn_abilities"]:
				player.learn_ability(StringName(id))
	elif action.has("do"):
		match str(action["do"]):
			"melee": player.try_melee()
			"ember": player.try_ember()
			"earthbreaker":
				player.gain_resonance(Player.MAX_RESONANCE)
				player.try_earthbreaker()
			"storm_step": player.try_storm_step()
			"chain_spark": player.try_chain_spark()
			"fracture_rune": player.try_fracture_rune()
			"dodge": player.try_dodge()
			"tab": _zone.targeting.cycle_target()
			"reset": player.reset_cooldowns()
			"inventory", "hero_inventory": _zone.inventory_ui.toggle()
			"talents", "hero_talents": _zone.talent_ui.toggle()
			"hero_character": _zone.hero_ui.toggle_tab(HeroUI.Tab.CHARACTER)
			"close":
				_zone.hero_ui.close()
				_zone.trainer_ui.close()
			"trainer":
				for child in _zone.world.get_children():
					if child is TrainerNpc:
						_zone.trainer_ui.open(child)
			"gold": _zone.spawn_gold_drop(25 + randi() % 30,
				player.global_position + player.facing() * 3.5 + Vector3(randf_range(-1.0, 1.0), 0, 0))
			"runic_guard":
				player.gain_resonance(Player.MAX_RESONANCE)
				player.try_runic_guard()
			"resonance_burst":
				player.gain_resonance(Player.MAX_RESONANCE)
				player.try_resonance_burst()
			"bossbar": _zone.hud.show_boss_bar("ASHVEIN COLOSSUS")
			"loot": _zone.spawn_item_drop(ItemGenerator.generate(randi() % 3),
				player.global_position + player.facing() * 2.0 + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-0.6, 0.6)))
			"legendary": _zone.spawn_item_drop(ItemGenerator.generate_legendary(),
				player.global_position + player.facing() * 2.6)
			_: push_warning("shot_runner: unknown action %s" % action["do"])


func _set_spawners_enabled(enabled: bool) -> void:
	for child in _zone.world.get_children():
		if child is EncounterSpawner:
			child.set_physics_process(enabled)


func _shot(shot_name: String, variant_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var folder: String = _list.get("out", "captures_shots")
	if "--legacy-look" in OS.get_cmdline_user_args():
		folder += "_legacy"
	if variant_name != "":
		folder = folder.path_join(variant_name)
	var dir := ProjectSettings.globalize_path("res://" + folder)
	DirAccess.make_dir_recursive_absolute(dir)
	_ensure_gdignore(ProjectSettings.globalize_path("res://" + String(_list.get("out", "captures_shots")).get_slice("/", 0)))
	_shot_index += 1
	var path := "%s/%02d_%s.png" % [dir, _shot_index, shot_name]
	img.save_png(path)
	print("shot: ", path)


static func _ensure_gdignore(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var marker := dir.path_join(".gdignore")
	if not FileAccess.file_exists(marker):
		FileAccess.open(marker, FileAccess.WRITE).close()


static func _vec3(v: Variant) -> Vector3:
	var a := v as Array
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## M08: a position is either [x, y, z] or {"poi": id, "offset": [dx, dy, dz]}
## (offset y = lift above the ground under the point).
static func _pos(zone: ZoneBase, v: Variant) -> Vector3:
	if v is Dictionary:
		var d := v as Dictionary
		var base := zone.poi_position(String(d.get("poi", "")))
		if base == Vector3.INF:
			push_warning("unknown poi '%s'" % str(d.get("poi", "")))
			base = Vector3.ZERO
		var off := _vec3(d.get("offset", [0, 0, 0]))
		var p := base + Vector3(off.x, 0.0, off.z)
		p.y = zone.ground_y(p) + off.y
		return p
	return _vec3(v)
