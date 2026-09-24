class_name ItemDrop
extends Node3D
## World pickup: bobbing rarity-colored shape, presentation scaled by rarity
## (label → glow → beam → tall beam + fanfare). Auto-pickup on proximity.

signal picked_up(item: ItemData)

const PICKUP_RANGE := 1.4

var item: ItemData
var player: Player

var _bob_time: float = 0.0
var _shape: Node3D


## M06 C5 loot shapes: blade / cuirass / relic from the common kit, the three
## legendaries get their own models. The glow part carries the rarity colour
## (commons stay unlit). Returns null when the kit is missing.
func _kit_shape(color: Color) -> Node3D:
	var prop_name: String = ["loot_blade", "loot_armor", "loot_relic", "loot_helm", "loot_gloves", "loot_boots", "loot_ring"][item.slot]
	if item.rarity == ItemData.Rarity.LEGENDARY and SetPieces.prop_path("legendary_" + String(item.legendary_id)) != "":
		prop_name = "legendary_" + String(item.legendary_id)
	if SetPieces.prop_path(prop_name) == "":
		return null
	var holder := Node3D.new()
	add_child(holder)
	var inst := SetPieces.prop(holder, prop_name, global_position)
	inst.position = Vector3.ZERO
	inst.scale = Vector3.ONE * 1.25
	if not prop_name.begins_with("legendary_"):
		for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
			for s in mi.mesh.get_surface_count():
				var m := mi.get_surface_override_material(s) as StandardMaterial3D
				if m != null and m.emission_enabled:
					if item.rarity == ItemData.Rarity.COMMON:
						var plain := StandardMaterial3D.new()
						plain.albedo_color = color
						mi.set_surface_override_material(s, plain)
					else:
						mi.set_surface_override_material(s, ArtKit.glow_material(color, 1.2))
	return holder


func _ready() -> void:
	var color := ItemData.rarity_color(item.rarity)
	_shape = _kit_shape(color)
	if _shape != null:
		_shape.position = Vector3(0, 0.55, 0)
	else:
		_build_greybox_shape(color)
	_add_presentation(color)


func _build_greybox_shape(color: Color) -> void:
	var box_shape := MeshInstance3D.new()
	_shape = box_shape
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = item.rarity != ItemData.Rarity.COMMON
	mat.emission = color
	mat.emission_energy_multiplier = 1.2
	var mesh: Mesh
	match item.slot:
		ItemData.Slot.WEAPON:
			var blade := BoxMesh.new()
			blade.size = Vector3(0.1, 0.55, 0.16)
			mesh = blade
		ItemData.Slot.CHEST:
			var cuirass := BoxMesh.new()
			cuirass.size = Vector3(0.4, 0.35, 0.2)
			mesh = cuirass
		_:
			var orb := SphereMesh.new()
			orb.radius = 0.16
			orb.height = 0.32
			mesh = orb
	(mesh as PrimitiveMesh).material = mat
	box_shape.mesh = mesh
	add_child(_shape)
	_shape.position = Vector3(0, 0.55, 0)


func _add_presentation(color: Color) -> void:
	var label := Label3D.new()
	label.text = item.display_name
	label.font_size = 36
	label.pixel_size = 0.004
	label.modulate = color
	label.outline_size = 10
	label.outline_modulate = Color(0.05, 0.03, 0.08)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0, 1.15, 0)
	UiTheme.label3d(label)
	add_child(label)

	if item.rarity >= ItemData.Rarity.MAGIC:
		var light := OmniLight3D.new()
		light.light_color = color
		light.light_energy = 0.9
		light.omni_range = 2.5
		light.shadow_enabled = false
		light.position = Vector3(0, 0.6, 0)
		add_child(light)

	if item.rarity >= ItemData.Rarity.RARE:
		var beam := MeshInstance3D.new()
		var beam_mesh := BoxMesh.new()
		var tall := item.rarity == ItemData.Rarity.LEGENDARY
		beam_mesh.size = Vector3(0.1, 5.0 if tall else 2.5, 0.1)
		var beam_mat := StandardMaterial3D.new()
		beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		beam_mat.albedo_color = Color(color.r, color.g, color.b, 0.45)
		beam_mat.emission_enabled = true
		beam_mat.emission = color
		beam_mat.emission_energy_multiplier = 1.5
		beam_mat.disable_receive_shadows = true
		beam_mat.disable_fog = true  # ART_BIBLE: loot beams are fog-exempt
		beam_mesh.material = beam_mat
		beam.mesh = beam_mesh
		beam.position = Vector3(0, beam_mesh.size.y * 0.5, 0)
		add_child(beam)

	if item.rarity == ItemData.Rarity.LEGENDARY:
		Sfx.play("legendary_drop", global_position, 0.0, 0.02)
	elif item.rarity == ItemData.Rarity.RARE:
		Sfx.play("rune_place", global_position, -6.0, 0.1, 0.8)


func _process(delta: float) -> void:
	_bob_time += delta
	_shape.position.y = 0.55 + sin(_bob_time * 2.4) * 0.12
	_shape.rotate_y(delta * 1.5)
	if player != null and is_instance_valid(player) \
			and player.global_position.distance_to(global_position) <= PICKUP_RANGE:
		_try_pickup()


func _try_pickup() -> void:
	if not player.equipment.add_item(item):
		return  # inventory full: stays on the ground
	var pitch := 1.0 + 0.12 * float(item.rarity)
	Sfx.play("pickup", global_position, -4.0, 0.04, pitch)
	picked_up.emit(item)
	queue_free()
