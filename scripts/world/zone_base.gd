class_name ZoneBase
extends Node
## Base for every playable zone (Combat Lab, Runehold hub, regions):
## bootstraps player/camera/targeting/HUD/inventory/debug, provides greybox
## building helpers, enemy/drop plumbing, zone travel with save persistence.

var world: Node3D
var player: Player
var camera_rig: CameraRig
var targeting: TargetingSystem
var hud: Hud
var debug_overlay: DebugOverlay
var style_manager: StyleManager
var inventory_ui: InventoryUI
var enemies_root: Node3D

var style_name: String:
	get:
		return style_manager.style_name() if style_manager != null else "-"

var _travelling: bool = false


func _ready() -> void:
	world = Node3D.new()
	world.name = "World"
	add_child(world)

	_build_environment()

	enemies_root = Node3D.new()
	enemies_root.name = "Enemies"
	world.add_child(enemies_root)

	_build_zone()
	_spawn_player()

	hud = Hud.new()
	hud.layer = 5
	add_child(hud)
	hud.setup(player)

	debug_overlay = DebugOverlay.new()
	add_child(debug_overlay)
	debug_overlay.setup(self)

	inventory_ui = InventoryUI.new()
	add_child(inventory_ui)
	inventory_ui.setup(player)

	style_manager = StyleManager.new()
	add_child(style_manager)
	style_manager.setup(self, world)

	SaveGame.restore_player(player)
	_zone_ready()

	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if "--worldcapture" in OS.get_cmdline_user_args():
		var capture: Node = (load("res://tests/world_capture.gd") as GDScript).new()
		add_child(capture)


# ---------------------------------------------------------------------------
# Zone interface (override in subclasses)
# ---------------------------------------------------------------------------

## Build the zone's geometry, spawners, portals.
func _build_zone() -> void:
	pass


## Called after the full bootstrap (player, HUD, save restore) finished.
func _zone_ready() -> void:
	pass


func _player_spawn_point() -> Vector3:
	return Vector3(0, 0.2, 6)


## Environment palette per zone.
func _environment_colors() -> Dictionary:
	return {
		"sky_top": Color(0.12, 0.08, 0.22),
		"sky_horizon": Color(0.45, 0.22, 0.3),
		"fog": Color(0.35, 0.2, 0.35),
		"sun": Color(1.0, 0.85, 0.7),
		"sun_energy": 1.2,
	}


# ---------------------------------------------------------------------------
# Bootstrap pieces
# ---------------------------------------------------------------------------

func _build_environment() -> void:
	var colors := _environment_colors()
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = colors["sky_top"]
	sky_mat.sky_horizon_color = colors["sky_horizon"]
	sky_mat.ground_bottom_color = Color(0.08, 0.06, 0.12)
	sky_mat.ground_horizon_color = (colors["sky_horizon"] as Color).darkened(0.25)
	sky_mat.sun_angle_max = 30.0
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.1
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_light_color = colors["fog"]
	env.fog_density = 0.012
	env.fog_sky_affect = 0.2
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	world.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 35, 0)
	sun.light_color = colors["sun"]
	sun.light_energy = colors["sun_energy"]
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 60.0
	world.add_child(sun)

	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-30, 205, 0)
	rim.light_color = Color(0.4, 0.3, 0.7)
	rim.light_energy = 0.5
	world.add_child(rim)


func _spawn_player() -> void:
	player = Player.new()
	player.name = "Player"
	world.add_child(player)
	player.global_position = _player_spawn_point()

	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	world.add_child(camera_rig)
	camera_rig.set_target(player)
	player.camera_rig = camera_rig
	player.player_died.connect(_on_player_died)

	targeting = TargetingSystem.new()
	targeting.name = "Targeting"
	world.add_child(targeting)
	targeting.player = player
	targeting.camera_rig = camera_rig
	player.targeting = targeting


func _on_player_died() -> void:
	player.health.heal_full()
	player.global_position = _player_spawn_point()
	player.velocity = Vector3.ZERO
	GameFeel.camera_shake(0.4)


# ---------------------------------------------------------------------------
# Greybox building helpers
# ---------------------------------------------------------------------------

func _material_from_texture(tex_path: String, fallback: Color, uv_scale: float = 8.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	if ResourceLoader.exists(tex_path):
		mat.albedo_texture = load(tex_path)
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	else:
		mat.albedo_color = fallback
	mat.roughness = 0.9
	return mat


func _add_box(pos: Vector3, size: Vector3, mat: Material, rot_degrees: Vector3 = Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	mesh.mesh = box
	body.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	world.add_child(body)
	body.global_position = pos
	body.rotation_degrees = rot_degrees
	return body


## Looping ambient sound at a position (or global when pos is INF).
func _add_ambience(key: String, pos: Vector3 = Vector3.INF, volume_db: float = -8.0) -> void:
	var path := "res://assets/sfx/%s_01.wav" % key
	if not ResourceLoader.exists(path):
		return
	var stream := (load(path) as AudioStreamWAV).duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = stream.data.size() / 2  # 16-bit mono: 2 bytes per frame
	if pos == Vector3.INF:
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.volume_db = volume_db
		p.autoplay = true
		world.add_child(p)
	else:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = stream
		p3.volume_db = volume_db
		p3.unit_size = 6.0
		p3.max_distance = 30.0
		p3.autoplay = true
		world.add_child(p3)
		p3.global_position = pos


# ---------------------------------------------------------------------------
# Enemies + loot plumbing
# ---------------------------------------------------------------------------

func _spawn_enemy(enemy: EnemyBase, pos: Vector3) -> void:
	enemies_root.add_child(enemy)
	enemy.global_position = pos
	enemy.player = player
	enemy.enemy_died.connect(_on_enemy_died)


func spawn_by_id(id: String, pos: Vector3) -> EnemyBase:
	var enemy: EnemyBase
	match id:
		"caster":
			enemy = RangedCaster.new()
		"assassin":
			enemy = Assassin.new()
		"brute":
			enemy = Brute.new()
		"warden":
			enemy = HollowWarden.new()
		"elite":
			return spawn_elite(-1, pos)
		_:
			enemy = MeleeRusher.new()
	_spawn_enemy(enemy, pos)
	return enemy


func spawn_rusher(pos: Vector3 = Vector3.INF) -> void:
	spawn_by_id("rusher", _resolve_spawn_pos(pos))


func spawn_caster(pos: Vector3 = Vector3.INF) -> void:
	spawn_by_id("caster", _resolve_spawn_pos(pos))


func spawn_assassin(pos: Vector3 = Vector3.INF) -> void:
	spawn_by_id("assassin", _resolve_spawn_pos(pos))


func spawn_brute(pos: Vector3 = Vector3.INF) -> void:
	spawn_by_id("brute", _resolve_spawn_pos(pos))


func spawn_elite(kind: int = -1, pos: Vector3 = Vector3.INF) -> EnemyBase:
	pos = _resolve_spawn_pos(pos)
	var enemy := MeleeRusher.new()
	_spawn_enemy(enemy, pos)
	var modifier := EliteModifier.new()
	modifier.name = "EliteModifier"
	modifier.kind = (randi() % 2 if kind < 0 else kind) as EliteModifier.Kind
	enemy.add_child(modifier)
	return enemy


func _resolve_spawn_pos(pos: Vector3) -> Vector3:
	if pos != Vector3.INF:
		return pos
	var angle := randf() * TAU
	var dist := randf_range(9.0, 18.0)
	return player.global_position + Vector3(cos(angle) * dist, 0.2, sin(angle) * dist)


func _on_enemy_died(enemy: EnemyBase) -> void:
	var item: ItemData = null
	if enemy.is_elite:
		item = ItemGenerator.generate(2)
	elif enemy is Brute:
		if randf() < 0.6:
			item = ItemGenerator.generate(1)
	elif randf() < 0.2:
		item = ItemGenerator.generate(0)
	if item != null:
		spawn_item_drop(item, enemy.global_position)


func spawn_item_drop(item: ItemData, pos: Vector3) -> ItemDrop:
	var drop := ItemDrop.new()
	drop.item = item
	drop.player = player
	drop.position = Vector3(pos.x, 0.0, pos.z)
	world.add_child(drop)
	drop.picked_up.connect(func(picked: ItemData) -> void:
		hud.toast("[%s] %s" % [ItemData.rarity_name(picked.rarity), picked.display_name],
			ItemData.rarity_color(picked.rarity))
		SaveGame.request_save()
	)
	return drop


func debug_drop_item(legendary: bool) -> void:
	var item := ItemGenerator.generate_legendary() if legendary else ItemGenerator.generate(1)
	var offset := Vector3(randf_range(-1.5, 1.5), 0, randf_range(-2.5, -1.5))
	spawn_item_drop(item, player.global_position + player.facing() * 2.0 + offset)


# ---------------------------------------------------------------------------
# Debug-overlay hooks
# ---------------------------------------------------------------------------

func enemy_count() -> int:
	return enemies_root.get_child_count()


func kill_all_enemies() -> void:
	for child in enemies_root.get_children():
		var enemy := child as EnemyBase
		if enemy != null and enemy.ai_state != EnemyBase.AIState.DEAD:
			enemy.take_hit(HitInfo.create(99999.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, enemy.global_position))


func heal_player() -> void:
	player.health.heal_full()


func toggle_god_mode() -> void:
	player.god_mode = not player.god_mode


func reset_cooldowns() -> void:
	player.reset_cooldowns()
	player.gain_resonance(Player.MAX_RESONANCE)


func reset_lab() -> void:
	for child in enemies_root.get_children():
		child.queue_free()
	player.global_position = _player_spawn_point()
	player.velocity = Vector3.ZERO
	player.health.heal_full()
	player.resonance = 0.0
	player.resonance_changed.emit(0.0, Player.MAX_RESONANCE)
	player.reset_cooldowns()


func stress_test() -> void:
	for i in 6:
		spawn_rusher()
	for i in 3:
		spawn_caster()
	for i in 2:
		spawn_assassin()
	spawn_brute()
	spawn_elite()


func wipe_save() -> void:
	SaveGame.wipe()
	hud.toast("Save wiped", Color(1, 0.4, 0.4))


func cycle_style() -> void:
	style_manager.cycle()


# ---------------------------------------------------------------------------
# Zone travel
# ---------------------------------------------------------------------------

func travel_to(scene_path: String) -> void:
	if _travelling:
		return
	_travelling = true
	SaveGame.current_zone = scene_path
	SaveGame.save_now()
	Sfx.play_ui("portal_travel", -4.0)
	# Fade out, then swap scenes.
	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 20
	add_child(fade_layer)
	var fade := ColorRect.new()
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.color = Color(0.02, 0.01, 0.04, 0.0)
	fade_layer.add_child(fade)
	var tw := fade.create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.35)
	tw.tween_callback(func() -> void:
		get_tree().change_scene_to_file(scene_path)
	)
