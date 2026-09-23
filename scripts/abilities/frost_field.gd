class_name FrostField
extends Area3D
## Glacier Heart: chilling frost left where Earthbreaker lands.
## Chills enemies standing in it; no damage.

const LIFETIME := 4.0
const RADIUS := 4.0
const TICK_INTERVAL := 0.4

var _age: float = 0.0
var _tick_accum: float = 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 0b10000  # enemy hurtboxes
	monitoring = true
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = RADIUS
	shape.height = 1.5
	col.shape = shape
	col.position = Vector3(0, 0.75, 0)
	add_child(col)

	# Icy floor sheen + drifting mist.
	var sheen := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(RADIUS * 2.0, RADIUS * 2.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if ResourceLoader.exists("res://assets/vfx/telegraph.png"):
		mat.albedo_texture = load("res://assets/vfx/telegraph.png")
	mat.albedo_color = Color(0.55, 0.85, 1.0, 0.28)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.disable_receive_shadows = true
	plane.material = mat
	sheen.mesh = plane
	sheen.position = Vector3(0, 0.04, 0)
	add_child(sheen)

	var mist := GPUParticles3D.new()
	mist.amount = 16
	mist.lifetime = 1.2
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 20.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.6
	pm.gravity = Vector3(0, 0.3, 0)
	pm.scale_min = 0.8
	pm.scale_max = 1.6
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = RADIUS * 0.8
	mist.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.3, 0.3)
	var mist_mat := StandardMaterial3D.new()
	mist_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mist_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mist_mat.alpha_scissor_threshold = 0.3
	mist_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mist_mat.billboard_keep_scale = true
	mist_mat.albedo_color = Color(0.7, 0.9, 1.0, 0.6)
	if ResourceLoader.exists("res://assets/vfx/dust.png"):
		mist_mat.albedo_texture = load("res://assets/vfx/dust.png")
	mist_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mist_mat.disable_receive_shadows = true
	quad.material = mist_mat
	mist.draw_pass_1 = quad
	add_child(mist)

	var tw := create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.6).set_delay(LIFETIME - 0.6)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	_tick_accum += delta
	if _tick_accum >= TICK_INTERVAL:
		_tick_accum = 0.0
		for area in get_overlapping_areas():
			var hb := area as Hurtbox
			if hb != null and hb.owner_entity is EnemyBase:
				(hb.owner_entity as EnemyBase).status.apply_chill(1.5)
