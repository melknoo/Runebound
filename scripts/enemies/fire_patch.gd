class_name FirePatch
extends Area3D
## Burning ground left by Emberbound elites: ticks damage on the player
## standing in it. Self-expires.

const LIFETIME := 3.0
const RADIUS := 1.2
const TICK_DAMAGE := 3.0
const TICK_INTERVAL := 0.5

var _age: float = 0.0
var _tick_accum: float = 0.0
var _emitter: GPUParticles3D
## M09: a co-op client's copy of a server patch: burns for show only.
var visual_only: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 0 if visual_only else 0b1000  # player hurtbox
	monitoring = not visual_only
	if not visual_only:
		var zone := ZoneBase.zone_of(self)
		if zone != null and zone.net_world != null:
			zone.net_world.register_hazard(&"fire_patch", global_position)
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = RADIUS
	shape.height = 1.2
	col.shape = shape
	col.position = Vector3(0, 0.6, 0)
	add_child(col)

	VFX.decal(get_tree().current_scene, global_position, "scorch", RADIUS * 2.2, Color(1, 1, 1, 0.9), LIFETIME)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.5, 0.15)
	light.light_energy = 1.0
	light.omni_range = 2.5
	light.shadow_enabled = false
	light.position = Vector3(0, 0.4, 0)
	add_child(light)

	# Looping embers for the patch lifetime.
	_emitter = GPUParticles3D.new()
	_emitter.amount = 20
	_emitter.lifetime = 0.7
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 25.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.8
	pm.gravity = Vector3(0, 1.0, 0)
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = RADIUS * 0.8
	_emitter.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.14)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.35
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.albedo_color = Color(1.0, 0.6, 0.2)
	if ResourceLoader.exists("res://assets/vfx/ember.png"):
		mat.albedo_texture = load("res://assets/vfx/ember.png")
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.disable_receive_shadows = true
	quad.material = mat
	_emitter.draw_pass_1 = quad
	add_child(_emitter)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	_tick_accum += delta
	if _tick_accum >= TICK_INTERVAL and not visual_only:
		_tick_accum = 0.0
		for area in get_overlapping_areas():  # M09: every hero standing in it
			var hb := area as Hurtbox
			if hb != null and hb.owner_entity is Player:
				var hit := HitInfo.create(TICK_DAMAGE, HitInfo.DamageType.FIRE, HitInfo.Weight.LIGHT, global_position)
				hit.area_center = global_position + Vector3(0, 0.6, 0)
				hit.area_radius = RADIUS + 0.5
				(hb.owner_entity as Player).take_hit(hit)
