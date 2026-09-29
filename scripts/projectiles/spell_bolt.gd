class_name SpellBolt
extends Area3D
## M10: the Elementalist's Rune Bolt — a small, fast arcane dart in the player
## teal (a hero's own projectile never borrows the enemies' void violet). Hits
## the first enemy, builds the class resource, pops on walls. Cheap on
## purpose: it fires about three times a second (no light, a short trail).

const LIFETIME := 1.0

var _data: AbilityData
var _dir: Vector3 = Vector3.FORWARD
var _source: Node3D
var _age: float = 0.0
var _dead: bool = false
## M09: another player's bolt on a co-op client flies for show only.
var visual_only: bool = false


func setup(data: AbilityData, dir: Vector3, source: Node3D) -> void:
	_data = data
	_dir = dir.normalized()
	_source = source


func _ready() -> void:
	collision_layer = 0b100000
	collision_mask = 0b1 if visual_only else 0b10001  # world + enemy hurtboxes (a copy: world only)
	monitoring = true
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.2
	col.shape = sphere
	add_child(col)
	if Net.has_view():
		var core := MeshInstance3D.new()
		var mesh := PrismMesh.new()
		mesh.size = Vector3(0.16, 0.16, 0.55)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = ArtKit.color("color_roles.player_accent.hot", Color(0.62, 0.95, 0.9))
		mat.emission_enabled = true
		mat.emission = ArtKit.color("color_roles.player_accent.body", Color(0.24, 0.75, 0.7))
		mat.emission_energy_multiplier = 3.2
		mesh.material = mat
		core.mesh = mesh
		core.rotation_degrees = Vector3(-90, 0, 0)
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(core)
		VFX.attach_trail(self, "spark", [ArtKit.color("color_roles.player_accent.hot"),
			Color(ArtKit.color("color_roles.player_accent.body"), 0.0)] as Array[Color], 20, 0.12)
	if _dir.length() > 0.01 and absf(_dir.dot(Vector3.UP)) < 0.99:
		look_at(global_position + _dir, Vector3.UP)
	body_entered.connect(func(_b: Node3D) -> void: _pop(null))
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_age += delta
	if _age > LIFETIME:
		queue_free()
		return
	global_position += _dir * _data.projectile_speed * delta


func _on_area_entered(area: Area3D) -> void:
	if visual_only:
		return
	var hb := area as Hurtbox
	if hb == null or hb.owner_entity == null or hb.owner_entity == _source:
		return
	_pop(hb.owner_entity)


func _pop(victim: Node) -> void:
	if _dead:
		return
	_dead = true
	var scene := get_tree().current_scene
	VFX.flash(scene, global_position, ArtKit.color("color_roles.player_accent.hot"), 0.45, 0.08)
	if not visual_only and victim != null and victim.has_method(&"take_hit"):
		var hit: HitInfo
		var hero := _source as Player
		if hero != null and is_instance_valid(hero):
			hit = hero.roll_ability_hit(_data)
			hit.source_position = hero.global_position
		else:
			hit = _data.roll_hit(global_position)
		if bool(victim.call(&"take_hit", hit)) and hero != null and is_instance_valid(hero):
			hero.gain_resonance(_data.resonance_gain_per_hit)
			Sfx.play("bolt_impact", global_position, -10.0, 0.15, 1.6)
	queue_free()
