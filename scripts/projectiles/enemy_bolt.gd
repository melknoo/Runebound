class_name EnemyBolt
extends Area3D
## Slow, highly readable enemy projectile. Its job is to force movement,
## so it is bright, big, and audible.

const LIFETIME := 6.0

var speed: float = 8.0
var damage: float = 12.0
## M09: a co-op client's copy of a server bolt: flies and pops for show only
## (the server decides whom it hits; NetWorld pops it when the server's does).
var visual_only: bool = false
var net_id: int = 0
var _dir: Vector3 = Vector3.FORWARD
var _age: float = 0.0
var _dead: bool = false


func setup(dir: Vector3, bolt_speed: float, bolt_damage: float) -> void:
	_dir = dir.normalized()
	speed = bolt_speed
	damage = bolt_damage


func _ready() -> void:
	collision_layer = 0b100000
	collision_mask = 0b1 if visual_only else 0b1001  # world + player hurtbox (a copy: world only)
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	col.shape = sphere
	add_child(col)

	build_visual(self)

	var light := OmniLight3D.new()
	light.light_color = Color(0.75, 0.4, 1.0)
	light.light_energy = 1.2
	light.omni_range = 3.5
	light.shadow_enabled = false
	add_child(light)

	body_entered.connect(func(_b: Node3D) -> void: _pop(null))
	area_entered.connect(_on_area_entered)
	if not visual_only:
		var zone := ZoneBase.zone_of(self)
		if zone != null and zone.net_world != null:
			zone.net_world.register_bolt(self)


func direction() -> Vector3:
	return _dir


## M09: the server's bolt popped; the copy pops where it is.
func net_pop() -> void:
	_pop(null)


static var _core_mesh: SphereMesh
static var _halo_mesh: SphereMesh


## M06 void language: white-violet core inside a violet halo plus a short
## particle wake, fog-exempt so the bolt reads across the whole arena. Meshes
## are shared (VFX.warm_up draws one at zone start, so the first bolt of a
## fight never compiles its shaders).
static func build_visual(parent: Node3D) -> void:
	if _core_mesh == null:
		_core_mesh = _sphere(0.13, ArtKit.color("color_roles.void.core", Color(0.91, 0.78, 1.0)), false)
		_halo_mesh = _sphere(0.24, Color(ArtKit.color("color_roles.void.body", Color(0.63, 0.38, 0.91)), 0.55), true)
	for mesh: SphereMesh in [_core_mesh, _halo_mesh]:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
	VFX.attach_trail(parent, "ember", [ArtKit.color("color_roles.void.core"), ArtKit.color("color_roles.void.body"),
		Color(ArtKit.color("color_roles.void.edge"), 0.0)] as Array[Color], 24, 0.12)


static func _sphere(radius: float, color: Color, halo: bool) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.disable_fog = true
	if halo:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	else:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 2.6
	mesh.material = mat
	return mesh


## Shutdown hygiene (GameFeel._exit_tree via VFX.clear_caches).
static func clear_meshes() -> void:
	_core_mesh = null
	_halo_mesh = null


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_age += delta
	if _age > LIFETIME:
		queue_free()
		return
	global_position += _dir * speed * delta


func _on_area_entered(area: Area3D) -> void:
	if visual_only:
		return
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
		hit.area_center = global_position
		hit.area_radius = 0.3
		victim.call(&"take_hit", hit)
	if net_id != 0 and not visual_only:
		var zone := ZoneBase.zone_of(self)
		if zone != null and zone.net_world != null:
			zone.net_world.bolt_popped(self)
	queue_free()
