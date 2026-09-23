class_name AshenHighlands
extends ZoneBase
## First region: a winding ash path through ridge pockets — four escalating
## camps, an elite camp, two chests (one on a detour), and the Ashvein
## Colossus guarding the sealed north portal.

const WIDTH := 100.0
const LENGTH := 70.0

var boss: AshveinColossus = null
var boss_portal: Portal
var spire_portal: Portal
var _boss_started: bool = false


func _environment_colors() -> Dictionary:
	return {
		"sky_top": Color(0.14, 0.07, 0.16),
		"sky_horizon": Color(0.7, 0.3, 0.22),  # ember haze
		"fog": Color(0.4, 0.22, 0.2),
		"sun": Color(1.0, 0.72, 0.5),
		"sun_energy": 1.15,
	}


func _player_spawn_point() -> Vector3:
	return Vector3(0, 0.2, 29)


func _build_zone() -> void:
	var ground_mat := _material_from_texture("res://assets/textures/ash_ground.png", Color(0.34, 0.3, 0.28), 18.0)
	var rock_mat := _material_from_texture("res://assets/textures/ash_rock.png", Color(0.42, 0.36, 0.32), 2.5)
	var accent_mat := _material_from_texture("res://assets/textures/rune_stone.png", Color(0.3, 0.4, 0.45), 1.0)

	_add_box(Vector3(0, -0.5, 0), Vector3(WIDTH, 1.0, LENGTH), ground_mat)
	# Border cliffs.
	var hw := WIDTH * 0.5
	var hl := LENGTH * 0.5
	_add_box(Vector3(0, 3.0, -hl), Vector3(WIDTH, 6, 2), rock_mat)
	_add_box(Vector3(0, 3.0, hl), Vector3(WIDTH, 6, 2), rock_mat)
	_add_box(Vector3(-hw, 3.0, 0), Vector3(2, 6, LENGTH), rock_mat)
	_add_box(Vector3(hw, 3.0, 0), Vector3(2, 6, LENGTH), rock_mat)

	# Ridge pockets shaping the path (funnel points + cover).
	for ridge in [
		[Vector3(-12, 1.5, 22), Vector3(14, 3, 3), 12.0], [Vector3(14, 1.5, 21), Vector3(12, 3, 3), -8.0],
		[Vector3(-20, 1.75, 10), Vector3(3, 3.5, 14), 0.0], [Vector3(12, 1.5, 8), Vector3(3, 3, 10), 20.0],
		[Vector3(-6, 1.5, -2), Vector3(8, 3, 2.5), -15.0], [Vector3(24, 2.0, -2), Vector3(3, 4, 16), 0.0],
		[Vector3(-26, 2.0, -12), Vector3(10, 4, 3), 30.0], [Vector3(6, 1.5, -14), Vector3(10, 3, 3), 5.0],
		# Boss arena half-walls.
		[Vector3(-14, 2.5, -24), Vector3(3, 5, 14), 0.0], [Vector3(14, 2.5, -24), Vector3(3, 5, 14), 0.0],
	]:
		_add_box(ridge[0], ridge[1], rock_mat, Vector3(0, ridge[2], 0))

	# Scattered rocks + rune monoliths (landmarks).
	for rock in [Vector3(-8, 0.75, 14), Vector3(18, 0.6, 14), Vector3(-16, 0.6, -4), Vector3(2, 0.75, -8)]:
		_add_box(rock, Vector3(2, 1.5, 1.8), rock_mat, Vector3(0, randf() * 40.0, 0))
	_add_box(Vector3(-24, 2.0, 2), Vector3(1.2, 4, 1.2), accent_mat, Vector3(0, 15, 0))
	_add_box(Vector3(20, 2.0, -16), Vector3(1.2, 4, 1.2), accent_mat, Vector3(0, -20, 0))

	# --- encounters: escalating along the path ---
	_add_camp(Vector3(0, 0, 16), ["rusher", "rusher"] as Array[String])
	_add_camp(Vector3(-4, 0, 4), ["rusher", "caster", "rusher"] as Array[String])
	_add_camp(Vector3(-16, 0, -8), ["assassin", "assassin", "caster"] as Array[String])
	_add_camp(Vector3(4, 0, -18), ["brute", "rusher", "caster"] as Array[String])
	_add_camp(Vector3(19, 0, -8), ["elite", "rusher", "rusher"] as Array[String])  # elite pocket

	# --- treasure ---
	var chest1 := TreasureChest.new()
	world.add_child(chest1)
	chest1.global_position = Vector3(-30, 0, 8)  # west detour behind the ridge
	var chest2 := TreasureChest.new()
	chest2.min_rarity_bias = 1
	world.add_child(chest2)
	chest2.global_position = Vector3(28, 0, -20)

	# --- boss arena (north end) ---
	var boss_trigger := EncounterSpawner.new()
	boss_trigger.composition = [] as Array[String]
	boss_trigger.trigger_radius = 12.0
	world.add_child(boss_trigger)
	boss_trigger.global_position = Vector3(0, 0, -20)
	boss_trigger.set_physics_process(false)  # custom trigger below
	_boss_trigger = boss_trigger

	var colossus_down := SaveGame.has_flag(&"colossus_defeated")

	boss_portal = Portal.new()
	boss_portal.destination_scene = "res://scenes/hub.tscn"
	boss_portal.label_text = "RUNEHOLD"
	boss_portal.locked = not colossus_down
	world.add_child(boss_portal)
	boss_portal.global_position = Vector3(-3, 0, -31)

	spire_portal = Portal.new()
	spire_portal.destination_scene = "res://scenes/shattered_spire.tscn"
	spire_portal.label_text = "THE SHATTERED SPIRE"
	spire_portal.locked = not colossus_down
	world.add_child(spire_portal)
	spire_portal.global_position = Vector3(3, 0, -31)

	var back_portal := Portal.new()
	back_portal.destination_scene = "res://scenes/hub.tscn"
	back_portal.label_text = "RUNEHOLD"
	world.add_child(back_portal)
	back_portal.global_position = Vector3(3, 0, 32)

	_add_ambience("wind_loop", Vector3.INF, -14.0)


var _boss_trigger: EncounterSpawner


func _add_camp(pos: Vector3, composition: Array[String]) -> void:
	var spawner := EncounterSpawner.new()
	spawner.composition = composition
	world.add_child(spawner)
	spawner.global_position = pos


func _physics_process(_delta: float) -> void:
	# Once beaten, the colossus stays beaten (world flag).
	if _boss_started or player == null or SaveGame.has_flag(&"colossus_defeated"):
		return
	if player.global_position.distance_to(_boss_trigger.global_position) <= _boss_trigger.trigger_radius:
		_start_boss_fight()


func _start_boss_fight() -> void:
	_boss_started = true
	boss = AshveinColossus.new()
	_spawn_enemy(boss, Vector3(0, 0.2, -28))
	hud.show_boss_bar("ASHVEIN COLOSSUS")
	boss.boss_health_changed.connect(hud.update_boss_bar)
	boss.enemy_died.connect(_on_boss_died)
	GameFeel.camera_shake(0.3)


func _on_boss_died(_enemy: EnemyBase) -> void:
	hud.hide_boss_bar()
	boss_portal.set_locked(false)
	spire_portal.set_locked(false)
	SaveGame.set_flag(&"colossus_defeated")
	# Guaranteed legendary on top of the regular drop roll.
	spawn_item_drop(ItemGenerator.generate_legendary(), boss_portal.global_position + Vector3(1.5, 0, 3))
	hud.toast("The Shattered Spire stands unsealed", Color(0.7, 0.55, 1.0))
