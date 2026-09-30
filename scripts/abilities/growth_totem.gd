class_name GrowthTotem
extends Node3D
## M11 druid: Totem of Growth - a carved post the druid drives into the
## ground. Every PULSE each hero within `radius` gets `damage_pct` more damage
## (a timed buff that outlasts the pulse a little, so leaving the totem ends
## it soon) and heals `heal`. Built on every machine (HeroFx "growth_totem");
## each applies it to the heroes it simulates.

const PULSE := 2.0

var radius: float = 8.0
var duration: float = 12.0
var damage_pct: float = 15.0
var heal: float = 3.0
var _age: float = 0.0
var _pulse_left: float = 0.0
var _ring_mat: StandardMaterial3D


func _ready() -> void:
	Sfx.play("totem", global_position, -1.0, 0.05)
	if not Net.has_view():
		return
	var bark := ArtKit.color("palettes.druid.bark.2", Color("#54392C"))
	var bark_hi := ArtKit.color("palettes.druid.bark.4", Color("#86604A"))
	var green := ArtKit.color("color_roles.nature.body", Color("#7ED957"))
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = bark
	post_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	var band_mat := StandardMaterial3D.new()
	band_mat.albedo_color = bark_hi
	band_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	var glow_mat := StandardMaterial3D.new()
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.albedo_color = green
	var root := Node3D.new()
	add_child(root)
	_part(root, BoxMesh.new(), Vector3(0.34, 1.5, 0.34), Vector3(0, 0.75, 0), post_mat)
	for y: float in [0.45, 1.05]:
		_part(root, BoxMesh.new(), Vector3(0.4, 0.08, 0.4), Vector3(0, y, 0), band_mat)
	for x: float in [-0.08, 0.08]:
		_part(root, BoxMesh.new(), Vector3(0.06, 0.06, 0.04), Vector3(x, 1.28, -0.18), glow_mat)  # its eyes
	for k in 3:  # a crown of leaves
		var leaf := _part(root, BoxMesh.new(), Vector3(0.08, 0.34, 0.16), Vector3(0, 1.62, 0), glow_mat)
		leaf.rotation = Vector3(0.0, TAU * k / 3.0, 0.5)
	root.scale = Vector3(1, 0.05, 1)
	var rise := root.create_tween()  # it rises out of the ground where the staff struck
	rise.tween_property(root, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	VFX.player_ring(self, global_position, radius, duration, green)
	var light := OmniLight3D.new()
	light.light_color = green
	light.light_energy = 0.8
	light.omni_range = 3.0
	light.shadow_enabled = false
	light.position.y = 1.4
	add_child(light)


func _part(parent: Node3D, mesh: BoxMesh, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	mesh.size = size
	mesh.material = mat
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = pos
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	return m


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= duration:
		queue_free()
		return
	_pulse_left -= delta
	if _pulse_left > 0.0:
		return
	_pulse_left = PULSE
	var zone := ZoneBase.zone_of(self)
	if zone == null:
		return
	if Net.has_view():
		VFX.ground_ring(get_tree().current_scene, global_position, ArtKit.color("color_roles.nature.body"), radius, 0.4)
	for p in zone.players_within(global_position, radius):
		if p.net_role == Player.NetRole.OWNER:
			p.add_buff(&"damage_pct", damage_pct, PULSE + 0.5)
			p.receive_heal(heal)
