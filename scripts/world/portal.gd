class_name Portal
extends Node3D
## Zone gateway: glowing pixel ring, name label, walk-in travel.
## Can start locked (greyed, inert) and unlock later (boss gates).

const TRIGGER_RANGE := 1.6

var destination_scene: String = ""
var label_text: String = "PORTAL"
var locked: bool = false
## M08: yaw of the gate frame (NAN = legacy: face the world origin).
var face_yaw: float = NAN
## M08: POI id of the gate / shrine the hero appears at in the destination.
var arrival: String = ""

var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _gate_mat: ShaderMaterial  # M06 gate (art pass); null on the legacy look
var _frame: Node3D

const GATE_SHADER := preload("res://shaders/portal_gate.gdshader")
var _light: OmniLight3D
var _label: Label3D
var _cooldown: float = 1.5  # grace period so arrivals don't instantly re-trigger
var _prompt: InteractPrompt


func _ready() -> void:
	var zone := _zone()
	if zone != null and zone.look != null and zone.look.art_pass:
		_build_gate()
	else:
		_build_ring()
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
	_label.position = Vector3(0, 3.7 if _gate_mat != null else 2.0, 0)
	# Pixelify, not Jacquard: the blackletter face was unreadable as a world label
	UiTheme.label3d(_label, UiTheme.BIG)
	add_child(_label)
	_prompt = InteractPrompt.create(self, 1.2)
	_add_motes()
	_apply_lock_visuals()
	_add_hum()


## The zone this portal belongs to (it is a child of the zone's world; the
## tree's current_scene may still be the loader while zones build).
func _zone() -> ZoneBase:
	var n := get_parent()
	while n != null and not n is ZoneBase:
		n = n.get_parent()
	return n as ZoneBase


## M06 C5 gate: flush octagonal rune plate, an upright swirling oval and
## floating arch stones (all >= 2.2 m) turned to face the zone's centre.
func _build_gate() -> void:
	SetPieces.prop(self, "portal_plate", global_position)
	_frame = Node3D.new()
	_frame.name = "Frame"
	add_child(_frame)
	SetPieces.prop(_frame, "portal_arch", Vector3.ZERO)
	var arch := _frame.get_child(0) as Node3D
	if arch != null:
		arch.position = Vector3.ZERO
		var bob := arch.create_tween().set_loops()
		bob.tween_property(arch, "position:y", 0.06, 1.8).set_trans(Tween.TRANS_SINE)
		bob.tween_property(arch, "position:y", -0.02, 1.8).set_trans(Tween.TRANS_SINE)
	var gate := MeshInstance3D.new()
	gate.name = "Gate"
	var quad := QuadMesh.new()
	quad.size = Vector2(2.5, 3.1)
	_gate_mat = ShaderMaterial.new()
	_gate_mat.shader = GATE_SHADER
	_gate_mat.set_shader_parameter(&"core_color", ArtKit.color("color_roles.player_accent.body"))
	quad.material = _gate_mat
	gate.mesh = quad
	gate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gate.position = Vector3(0, 1.45, 0)
	_frame.add_child(gate)
	_face_centre.call_deferred()


## Positions are set right after add_child: turn once they are.
## The way the gate looks (front = (sin, 0, cos) of this yaw).
func facing_yaw() -> float:
	if not is_nan(face_yaw):
		return face_yaw
	return atan2(-global_position.x, -global_position.z)


func _face_centre() -> void:
	if _frame == null:
		return
	if not is_nan(face_yaw):
		_frame.rotation.y = face_yaw
		return
	var to := -Vector3(global_position.x, 0.0, global_position.z)
	if to.length() > 0.5:
		_frame.rotation.y = atan2(to.x, to.z)


func _build_ring() -> void:
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


func _add_motes() -> void:
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


func _add_hum() -> void:
	var path := "res://assets/sfx/portal_hum_01.wav"
	if not ResourceLoader.exists(path):
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = load(path)  # loops via its .import (edit/loop_mode = Forward)
	p.bus = &"Ambience"
	p.volume_db = -14.0
	p.max_distance = 14.0
	p.autoplay = true
	add_child(p)


func set_locked(value: bool) -> void:
	locked = value
	_apply_lock_visuals()


func _apply_lock_visuals() -> void:
	var color := Color(0.35, 0.35, 0.4) if locked else Color(0.35, 0.95, 0.85)
	if _ring_mat != null:
		_ring_mat.albedo_color = color
	if _gate_mat != null:
		_gate_mat.set_shader_parameter(&"lit", 0.0 if locked else 1.0)
	_light.light_color = color
	_light.light_energy = 0.4 if locked else 1.4
	_label.modulate = color
	_label.text = label_text + ("  [SEALED]" if locked else "")


func _process(delta: float) -> void:
	if _ring != null:
		_ring.rotate_y(delta * 0.8)
	var zone := get_tree().current_scene as ZoneBase
	if zone == null or zone.player == null or not is_instance_valid(zone.player):
		_prompt.update(false, "")
		return
	var near := zone.player.global_position.distance_to(global_position) <= TRIGGER_RANGE
	if locked:
		_prompt.update(near, "Sealed")
		return
	_prompt.update(near and _cooldown <= 0.0, "Travel")
	if _cooldown > 0.0:
		_cooldown -= delta
		return
	# M07 feedback: travel on the interact key, never by walking in by accident.
	if _prompt.pressed(zone.player):
		zone.travel_to(destination_scene, arrival)
		_cooldown = 10.0
