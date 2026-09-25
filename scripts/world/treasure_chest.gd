class_name TreasureChest
extends Node3D
## Greybox chest: glows until opened by proximity, pops 2–3 items with beams.

const OPEN_RANGE := 2.0
const CHEST_XP := 60  # M07
const CHEST_GOLD := Vector2i(40, 60)  # M07b, scaled by item level

var min_rarity_bias: int = 0
var opened: bool = false
## M09: in co-op every hero this close gets its own purse when the chest opens.
const PARTY_RANGE := 12.0
var _requested: bool = false

var _lid: MeshInstance3D
var _prompt: InteractPrompt
var _glow_mat: StandardMaterial3D


func _ready() -> void:
	if not _build_kit_chest():
		_build_greybox()
	var col_body := StaticBody3D.new()
	col_body.collision_layer = 1
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, 0.8, 0.65)
	col.shape = shape
	col.position = Vector3(0, 0.4, 0)
	col_body.add_child(col)
	add_child(col_body)
	_prompt = InteractPrompt.create(self, 1.3)


## M06 C5: the common-kit chest (banded body, rune lock, lid hinged at its
## back edge) wrapping the same collider; the greybox stays for the legacy look.
func _build_kit_chest() -> bool:
	var n := get_parent()
	while n != null and not n is ZoneBase:
		n = n.get_parent()
	var zone := n as ZoneBase
	if zone == null or zone.look == null or not zone.look.art_pass:
		return false
	var chest := SetPieces.prop(self, "treasure_chest", global_position)
	if chest == null:
		return false
	chest.position = Vector3.ZERO
	_lid = chest.find_child("lid", true, false) as MeshInstance3D
	for mi: MeshInstance3D in chest.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(s) as StandardMaterial3D
			if m != null and m.emission_enabled:
				_glow_mat = m
	return _lid != null and _glow_mat != null


func _build_greybox() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.38, 0.27, 0.18)
	wood.roughness = 0.85
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(1.0, 0.55, 0.65)
	body_mesh.material = wood
	body.mesh = body_mesh
	body.position = Vector3(0, 0.28, 0)
	add_child(body)

	_lid = MeshInstance3D.new()
	var lid_mesh := BoxMesh.new()
	lid_mesh.size = Vector3(1.0, 0.2, 0.65)
	lid_mesh.material = wood
	_lid.mesh = lid_mesh
	_lid.position = Vector3(0, 0.65, 0)
	add_child(_lid)

	var band := MeshInstance3D.new()
	var band_mesh := BoxMesh.new()
	band_mesh.size = Vector3(0.16, 0.6, 0.7)
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.albedo_color = Color(1.0, 0.8, 0.35)
	_glow_mat.emission_enabled = true
	_glow_mat.emission = Color(1.0, 0.75, 0.3)
	_glow_mat.emission_energy_multiplier = 1.6
	band_mesh.material = _glow_mat
	band.mesh = band_mesh
	band.position = Vector3(0, 0.35, 0)
	add_child(band)


func _process(_delta: float) -> void:
	var zone := get_tree().current_scene as ZoneBase
	if opened or zone == null or zone.player == null:
		_prompt.update(false, "")
		return
	_prompt.update(zone.player.global_position.distance_to(global_position) <= OPEN_RANGE and not _requested, "Open")
	if _prompt.pressed(zone.player):  # M07 feedback: opened on the interact key
		if Net.is_client():
			_requested = true  # the server opens it (once, for everyone) and sends our purse
			zone.net_world.request_chest(self)
		else:
			open(zone)


## M09: the same id on every peer (zones build deterministically).
func net_key() -> String:
	return "%d_%d" % [roundi(global_position.x * 10.0), roundi(global_position.z * 10.0)]


## Opens the chest (authority): its look, then a purse for the local hero,
## or in co-op for every hero within PARTY_RANGE (personal loot, own rolls).
func open(zone: ZoneBase) -> void:
	if opened:
		return
	present_open()
	var heroes: Array[Player] = []
	if Net.is_online():
		heroes = zone.heroes_near(global_position, PARTY_RANGE)
	elif zone.player != null:
		heroes.append(zone.player)
	var ilvl := zone._enemy_level(null, global_position)
	var front := global_position + Vector3(0, 0, 1.3)
	for hero in heroes:
		var items: Array[ItemData] = []
		for i in 2 + (randi() % 2):
			var item := ItemGenerator.generate(min_rarity_bias, hero.class_data.id)
			ItemGenerator.apply_item_level(item, ilvl)
			items.append(item)
		# M07b: a purse of gold, scaled like the items are.
		var gold := int(round(float(randi_range(CHEST_GOLD.x, CHEST_GOLD.y)) * (1.0 + 0.15 * float(ilvl - 1))))
		zone.give_reward(hero, CHEST_XP, gold, 1, items, front)
	if zone.net_world != null:
		zone.net_world.chest_opened(self)


## The lid swings open (the authority, and every co-op client when the
## server says so).
func present_open() -> void:
	if opened:
		return
	opened = true
	Sfx.play("chest_open", global_position, -2.0)
	var tw := _lid.create_tween()
	tw.tween_property(_lid, "rotation_degrees:x", -70.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_glow_mat.emission_energy_multiplier = 0.2
	VFX.flash(get_tree().current_scene, global_position + Vector3(0, 0.8, 0), Color(1.0, 0.9, 0.6), 1.2, 0.15)
