class_name EnemyBolt
extends Area3D
## Slow, highly readable enemy projectile. Its job is to force movement,
## so it is bright, big, and audible.

const LIFETIME := 6.0

var speed: float = 8.0
var damage: float = 12.0
var _dir: Vector3 = Vector3.FORWARD
var _age: float = 0.0
var _dead: bool = false


func setup(dir: Vector3, bolt_speed: float, bolt_damage: float) -> void:
	_dir = dir.normalized()
	speed = bolt_speed
	damage = bolt_damage


func _ready() -> void:
	collision_layer = 0b100000
	collision_mask = 0b1001  # world + player hurtbox
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	col.shape = sphere
	add_child(col)

	var core := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.22
	mesh.height = 0.44
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.8, 0.4, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.7, 0.3, 1.0)
	mat.emission_energy_multiplier = 2.2
	mesh.material = mat
	core.mesh = mesh
	add_child(core)

	var light := OmniLight3D.new()
	light.light_color = Color(0.75, 0.4, 1.0)
	light.light_energy = 1.2
	light.omni_range = 3.5
	light.shadow_enabled = false
	add_child(light)

	body_entered.connect(func(_b: Node3D) -> void: _pop(null))
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_age += delta
	if _age > LIFETIME:
		queue_free()
		return
	global_position += _dir * speed * delta


func _on_area_entered(area: Area3D) -> void:
	var hb := area as Hurtbox
	if hb != null and hb.owner_entity is Player:
		_pop(hb.owner_entity)


func _pop(victim: Node) -> void:
	if _dead:
		return
	_dead = true
	var scene := get_tree().current_scene
	VFX.flash(scene, global_position, Color(0.8, 0.5, 1.0), 0.6, 0.12)
	VFX.burst(scene, global_position, {
		"tex": "spark", "amount": 8, "lifetime": 0.3, "size": 0.13,
		"spread": 85.0, "vel_min": 2.0, "vel_max": 4.0,
		"colors": [Color(0.9, 0.7, 1.0), Color(0.5, 0.2, 0.8, 0.0)] as Array[Color],
	})
	Sfx.play("bolt_impact", global_position, -4.0)
	if victim != null and victim.has_method(&"take_hit"):
		var hit := HitInfo.create(damage, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.MEDIUM, global_position - _dir)
		hit.knockback = 2.5
		victim.call(&"take_hit", hit)
	queue_free()
