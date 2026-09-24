class_name AshenHighlands
extends ZoneBase
## First region: a winding ash path through ridge pockets — four escalating
## camps, an elite camp, two chests (one on a detour), and the Ashvein
## Colossus guarding the sealed north portal.

const WIDTH := 100.0
const LENGTH := 70.0
## Camp centres along the path (encounters + the kit's keep-clear circles).
const CAMPS: Array[Vector3] = [Vector3(0, 0, 16), Vector3(-4, 0, 4), Vector3(-16, 0, -8),
	Vector3(4, 0, -18), Vector3(19, 0, -8)]

var boss: AshveinColossus = null
var boss_portal: Portal
var spire_portal: Portal
var _boss_started: bool = false


## M06 gold-standard look (ember dusk). Palette from assets/art_spec.json;
## key light low from the west-southwest = side light on a S->N path, so
## chunky forms read in two values with long shadows across the path.
func _zone_look() -> ZoneLook:
	var l := ZoneLook.new()
	l.sky_top = ArtKit.color("palettes.highlands.sky.top")
	l.sky_mid = ArtKit.color("palettes.highlands.sky.mid")
	l.sky_horizon = ArtKit.color("palettes.highlands.sky.horizon")
	l.sun_disc = ArtKit.color("palettes.highlands.sky.sun")
	l.fog_color = ArtKit.color("palettes.highlands.fog")
	l.ambient_color = ArtKit.color("palettes.highlands.ambient")
	l.ambient_energy = 1.35
	l.sun_rotation_deg = Vector3(-40, -67.5, 0)
	l.sun_color = Color(1.0, 0.8, 0.6)
	l.sun_energy = 1.3
	l.rim_rotation_deg = Vector3(-25, 112.5, 0)
	l.rim_color = Color(0.42, 0.38, 0.78)
	l.rim_energy = 0.5
	l.silhouette_far = Color(0.29, 0.15, 0.22)
	l.silhouette_near = Color(0.17, 0.1, 0.14)
	l.cloud_color = Color(0.38, 0.18, 0.27)
	l.cloud_lit_color = Color(0.7, 0.35, 0.3)
	l.cloud_amount = 0.42
	l.split_shadows = Color(0.47, 0.46, 0.56)
	l.split_highlights = Color(0.56, 0.5, 0.44)
	l.split_amount = 0.35
	l.vignette = 0.18
	l.ash_fall = 1.0
	return l


func _zone_music() -> String:
	return "highlands"


func zone_title() -> String:
	return "ASHEN HIGHLANDS"


## South of the corridor ridge 1, north 2, the Colossus 3.
func _enemy_level(enemy: EnemyBase, pos: Vector3) -> int:
	if enemy is AshveinColossus:
		return 3
	return 1 if pos.z > -2.0 else 2


func _warm_up_ids() -> Array[String]:
	return ["rusher", "caster", "assassin", "brute", "colossus"]


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
	var ground_mat := _zone_material(&"highlands_ground", "res://assets/textures/ash_ground.png", Color(0.34, 0.3, 0.28), 18.0)
	var rock_mat := _zone_material(&"highlands_rock", "res://assets/textures/ash_rock.png", Color(0.42, 0.36, 0.32), 2.5)
	var accent_mat := _material_from_texture("res://assets/textures/rune_stone.png", Color(0.3, 0.4, 0.45), 1.0)

	_add_box(Vector3(0, -0.5, 0), Vector3(WIDTH, 1.0, LENGTH), ground_mat)
	# Border cliffs.
	var hw := WIDTH * 0.5
	var hl := LENGTH * 0.5
	# Outer faces may bulge beyond the playable area (RockHull wild bits:
	# 0 +X, 1 -X, 2 +Z, 3 -Z).
	_add_box(Vector3(0, 3.0, -hl), Vector3(WIDTH, 6, 2), rock_mat, Vector3.ZERO, &"highlands_rock", 1 << 3)
	_add_box(Vector3(0, 3.0, hl), Vector3(WIDTH, 6, 2), rock_mat, Vector3.ZERO, &"highlands_rock", 1 << 2)
	_add_box(Vector3(-hw, 3.0, 0), Vector3(2, 6, LENGTH), rock_mat, Vector3.ZERO, &"highlands_rock", 1 << 1)
	_add_box(Vector3(hw, 3.0, 0), Vector3(2, 6, LENGTH), rock_mat, Vector3.ZERO, &"highlands_rock", 1 << 0)

	# Ridge pockets shaping the path (funnel points + cover).
	for ridge in [
		[Vector3(-12, 1.5, 22), Vector3(14, 3, 3), 12.0], [Vector3(14, 1.5, 21), Vector3(12, 3, 3), -8.0],
		[Vector3(-20, 1.75, 10), Vector3(3, 3.5, 14), 0.0], [Vector3(12, 1.5, 8), Vector3(3, 3, 10), 20.0],
		[Vector3(-6, 1.5, -2), Vector3(8, 3, 2.5), -15.0], [Vector3(24, 2.0, -2), Vector3(3, 4, 16), 0.0],
		[Vector3(-26, 2.0, -12), Vector3(10, 4, 3), 30.0], [Vector3(6, 1.5, -14), Vector3(10, 3, 3), 5.0],
		# Boss arena half-walls.
		[Vector3(-14, 2.5, -24), Vector3(3, 5, 14), 0.0], [Vector3(14, 2.5, -24), Vector3(3, 5, 14), 0.0],
	]:
		_add_box(ridge[0], ridge[1], rock_mat, Vector3(0, ridge[2], 0), &"highlands_rock")

	# Scattered rocks + rune monoliths (landmarks).
	for rock in [Vector3(-8, 0.75, 14), Vector3(18, 0.6, 14), Vector3(-16, 0.6, -4), Vector3(2, 0.75, -8)]:
		_add_box(rock, Vector3(2, 1.5, 1.8), rock_mat, Vector3(0, randf() * 40.0, 0), &"highlands_rock")
	var monolith_west := _add_box(Vector3(-24, 2.0, 2), Vector3(1.2, 4, 1.2), accent_mat, Vector3(0, 15, 0))
	var monolith_east := _add_box(Vector3(20, 2.0, -16), Vector3(1.2, 4, 1.2), accent_mat, Vector3(0, -20, 0))
	if look != null and look.art_pass:
		_dress_gold_target(monolith_west)
		_dress_north(monolith_east)

	# --- encounters: escalating along the path ---
	_add_camp(CAMPS[0], ["rusher", "rusher"] as Array[String])
	_add_camp(CAMPS[1], ["rusher", "caster", "rusher"] as Array[String])
	_add_camp(CAMPS[2], ["assassin", "assassin", "caster"] as Array[String])
	_add_camp(CAMPS[3], ["brute", "rusher", "caster"] as Array[String])
	_add_camp(CAMPS[4], ["elite", "rusher", "rusher"] as Array[String])  # elite pocket

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


## M06 gold target (Highlands South): kit set pieces on the existing layout —
## no new collision, no coordinates changed. The layout itself is rebuilt as an
## open zone in M08, so this is placement of reusable builders only.
func _dress_gold_target(monolith: StaticBody3D) -> void:
	# Camp 1 behind the funnel: banners on the two funnel ridge tops (y 3.0).
	SetPieces.raider_camp(self, Vector3(0, 0, 16), [Vector3(-8.1, 3.0, 21.2), Vector3(10.0, 3.0, 20.4)] as Array[Vector3])
	# Camp 2 in the corridor: banner on the west corridor ridge (y 3.5).
	SetPieces.raider_camp(self, Vector3(-4, 0, 4), [Vector3(-20.0, 3.5, 7.0)] as Array[Vector3])
	SetPieces.wrap_collider(monolith, "rune_monolith")
	# Charred trees on the south + west perimeter tops (outer half, y 6).
	for spot: Vector3 in [Vector3(-31, 6, 35.3), Vector3(-13, 6, 35.4), Vector3(17, 6, 35.3), Vector3(33, 6, 35.4),
			Vector3(-50.3, 6, 22), Vector3(-50.4, 6, 6), Vector3(50.3, 6, 16)]:
		SetPieces.prop(dressing(), "charred_tree", spot, fposmod(spot.x * 0.37 + spot.z, TAU), 1.25)
	# Rule-placed scatter along every dressed wall, ridge and rock base (the
	# whole zone gets the automatic kit; open combat space stays clear).
	var keep_clear: Array[Vector3] = [Vector3(0, 29, 3.0)]  # spawn
	for camp: Vector3 in CAMPS:
		keep_clear.append(Vector3(camp.x, camp.z, 3.5))
	for spot: Vector2 in [Vector2(-3, -31), Vector2(3, -31), Vector2(3, 32)]:  # portals
		keep_clear.append(Vector3(spot.x, spot.y, 2.5))
	for spot: Vector2 in [Vector2(-30, 8), Vector2(28, -20)]:  # chests
		keep_clear.append(Vector3(spot.x, spot.y, 1.6))
	keep_clear.append(Vector3(0, -24, 7.0))  # colossus arena floor
	Scatter.populate(self, {
		"area": Rect2(-WIDTH * 0.5 + 1.0, -LENGTH * 0.5 + 1.0, WIDTH - 2.0, LENGTH - 2.0),
		"obstacles": scatter_obstacles(),
		"exclude": keep_clear,
		"seed": 2609,
		"items": [
			{"prop": "ash_tuft", "per_m": 0.9, "band": Vector2(0.3, 1.4), "scale": Vector2(0.75, 1.3),
				"cluster": Vector2i(2, 5), "spread": 0.35},
			{"prop": "stone_cluster", "per_m": 0.3, "band": Vector2(0.25, 0.9), "scale": Vector2(0.8, 1.6),
				"cluster": Vector2i(1, 2), "spread": 0.3},
		],
	})


## M06 C1: the rest of the Highlands gets the same automatic kit (layout is
## rebuilt in M08): raider camps 3-5 with banners on their ridge tops, the
## east monolith wrapped, banners on the boss arena's half-walls (the arena
## floor itself stays clear for the Colossus' telegraphs).
func _dress_north(monolith: StaticBody3D) -> void:
	SetPieces.raider_camp(self, CAMPS[2], [Vector3(-23.8, 4.0, -13.25)] as Array[Vector3])
	SetPieces.raider_camp(self, CAMPS[3], [Vector3(3.0, 3.0, -13.74)] as Array[Vector3])
	SetPieces.raider_camp(self, CAMPS[4], [Vector3(24.0, 4.0, -6.0)] as Array[Vector3])  # elite pocket
	SetPieces.wrap_collider(monolith, "rune_monolith")
	for spot: Vector3 in [Vector3(-14, 5.0, -19.5), Vector3(14, 5.0, -19.5), Vector3(-14, 5.0, -28.5), Vector3(14, 5.0, -28.5)]:
		var to_arena := Vector2(-spot.x, -24.0 - spot.z)
		SetPieces.prop(dressing(), "banner_pole", spot, atan2(-to_arena.x, -to_arena.y) + PI)
	# Charred trees on the north perimeter top (outer half, y 6).
	for spot: Vector3 in [Vector3(-40, 6, -35.3), Vector3(-22, 6, -35.4), Vector3(26, 6, -35.3), Vector3(42, 6, -35.4),
			Vector3(50.3, 6, -20), Vector3(-50.4, 6, -24)]:
		SetPieces.prop(dressing(), "charred_tree", spot, fposmod(spot.x * 0.37 + spot.z, TAU), 1.25)


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
	if MusicDirector.instance != null:
		MusicDirector.instance.stinger("victory")
	boss_portal.set_locked(false)
	spire_portal.set_locked(false)
	SaveGame.set_flag(&"colossus_defeated")
	# Guaranteed legendary on top of the regular drop roll.
	var legendary := ItemGenerator.generate_legendary()
	ItemGenerator.apply_item_level(legendary, 3)
	spawn_item_drop(legendary, boss_portal.global_position + Vector3(1.5, 0, 3))
	hud.toast("The Shattered Spire stands unsealed", Color(0.7, 0.55, 1.0))
