class_name TreasureChest
extends Node3D
## Greybox chest: glows until opened by proximity, pops 2–3 items with beams.

const OPEN_RANGE := 2.0

var min_rarity_bias: int = 0
var opened: bool = false

var _lid: MeshInstance3D
var _glow_mat: StandardMaterial3D


func _ready() -> void:
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

	var col_body := StaticBody3D.new()
	col_body.collision_layer = 1
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, 0.8, 0.65)
	col.shape = shape
	col.position = Vector3(0, 0.4, 0)
	col_body.add_child(col)
	add_child(col_body)


func _physics_process(_delta: float) -> void:
	if opened:
		return
	var zone := get_tree().current_scene as ZoneBase
	if zone == null or zone.player == null:
		return
	if zone.player.global_position.distance_to(global_position) <= OPEN_RANGE:
		open(zone)


func open(zone: ZoneBase) -> void:
	if opened:
		return
	opened = true
	Sfx.play("chest_open", global_position, -2.0)
	var tw := _lid.create_tween()
	tw.tween_property(_lid, "rotation_degrees:x", -70.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_glow_mat.emission_energy_multiplier = 0.2
	VFX.flash(get_tree().current_scene, global_position + Vector3(0, 0.8, 0), Color(1.0, 0.9, 0.6), 1.2, 0.15)
	var count := 2 + (randi() % 2)
	for i in count:
		var item := ItemGenerator.generate(min_rarity_bias)
		var offset := Vector3(randf_range(-1.2, 1.2), 0, randf_range(0.8, 1.8))
		zone.spawn_item_drop(item, global_position + offset)
