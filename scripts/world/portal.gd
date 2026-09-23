class_name Portal
extends Node3D
## Zone gateway: glowing pixel ring, name label, walk-in travel.
## Can start locked (greyed, inert) and unlock later (boss gates).

const TRIGGER_RANGE := 1.6

var destination_scene: String = ""
var label_text: String = "PORTAL"
var locked: bool = false

var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _light: OmniLight3D
var _label: Label3D
var _cooldown: float = 1.5  # grace period so arrivals don't instantly re-trigger


func _ready() -> void:
	_ring = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.6, 2.6)
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_ring_mat.alpha_scissor_threshold = 0.3
	if ResourceLoader.exists("res://assets/vfx/ring.png"):
		_ring_mat.albedo_texture = load("res://assets/vfx/ring.png")
	_ring_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_ring_mat.disable_receive_shadows = true
	plane.material = _ring_mat
	_ring.mesh = plane
	_ring.position = Vector3(0, 0.08, 0)
	add_child(_ring)

	_light = OmniLight3D.new()
	_light.omni_range = 4.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, 1.0, 0)
	add_child(_light)

	_label = Label3D.new()
	_label.text = label_text
	_label.font_size = 48
	_label.pixel_size = 0.004
	_label.outline_size = 12
	_label.outline_modulate = Color(0.05, 0.03, 0.08)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0, 2.0, 0)
	add_child(_label)

	# Rising motes.
	var motes := GPUParticles3D.new()
	motes.amount = 12
	motes.lifetime = 1.4
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 10.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.6
	pm.scale_max = 1.1
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 1.0
	motes.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.12, 0.12)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.35
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	if ResourceLoader.exists("res://assets/vfx/spark.png"):
		mat.albedo_texture = load("res://assets/vfx/spark.png")
	mat.albedo_color = Color(0.5, 0.9, 0.9)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.disable_receive_shadows = true
	quad.material = mat
	motes.draw_pass_1 = quad
	add_child(motes)

	_apply_lock_visuals()
	_add_hum()


func _add_hum() -> void:
	var path := "res://assets/sfx/portal_hum_01.wav"
	if not ResourceLoader.exists(path):
		return
	var stream := (load(path) as AudioStreamWAV).duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = stream.data.size() / 2
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = -14.0
	p.max_distance = 14.0
	p.autoplay = true
	add_child(p)


func set_locked(value: bool) -> void:
	locked = value
	_apply_lock_visuals()


func _apply_lock_visuals() -> void:
	var color := Color(0.35, 0.35, 0.4) if locked else Color(0.35, 0.95, 0.85)
	_ring_mat.albedo_color = color
	_light.light_color = color
	_light.light_energy = 0.4 if locked else 1.4
	_label.modulate = color
	_label.text = label_text + ("  [SEALED]" if locked else "")


func _process(delta: float) -> void:
	_ring.rotate_y(delta * 0.8)
	if _cooldown > 0.0:
		_cooldown -= delta
		return
	if locked:
		return
	var zone := get_tree().current_scene as ZoneBase
	if zone == null or zone.player == null or not is_instance_valid(zone.player):
		return
	if zone.player.global_position.distance_to(global_position) <= TRIGGER_RANGE:
		zone.travel_to(destination_scene)
		_cooldown = 10.0
