class_name EmberLanceProjectile
extends Area3D
## Fast fire projectile: emissive core, pixel-ember trail, burn on hit.

const LIFETIME := 3.0

var _data: AbilityData
var _dir: Vector3 = Vector3.FORWARD
var _source: Node3D
var _age: float = 0.0
var _dead: bool = false
var _pierces_left: int = 0
var _already_hit: Array[Node] = []
## M07 talents: split shards deal a share of the damage and never split again.
var damage_scale: float = 1.0
var can_split: bool = true

const SPLIT_ANGLE := 0.45
const PHOENIX_RADIUS := 2.0


func setup(data: AbilityData, dir: Vector3, source: Node3D) -> void:
	_data = data
	_dir = dir.normalized()
	_source = source
	if source is Player:
		_pierces_left = int((source as Player).stat(&"ember_pierce"))


func _ready() -> void:
	collision_layer = 0b100000
	collision_mask = 0b10001  # world + enemy hurtboxes
	monitoring = true

	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.25
	col.shape = sphere
	add_child(col)

	# Core: bright lance-shaped emissive mesh oriented along travel.
	# Core: fat emissive lance + white-hot inner tip. Must read at 26 m/s.
	var core := MeshInstance3D.new()
	var mesh := PrismMesh.new()
	mesh.size = Vector3(0.3, 0.3, 0.9)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.75, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.12)
	mat.emission_energy_multiplier = 4.0
	mesh.material = mat
	core.mesh = mesh
	core.rotation_degrees = Vector3(-90, 0, 0)
	add_child(core)

	var hot := MeshInstance3D.new()
	var hot_mesh := SphereMesh.new()
	hot_mesh.radius = 0.14
	hot_mesh.height = 0.28
	var hot_mat := StandardMaterial3D.new()
	hot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hot_mat.albedo_color = Color(1.0, 0.98, 0.85)
	hot_mat.emission_enabled = true
	hot_mat.emission = Color(1.0, 0.9, 0.6)
	hot_mat.emission_energy_multiplier = 5.0
	hot_mesh.material = hot_mat
	hot.mesh = hot_mesh
	hot.position = Vector3(0, 0, -0.25)
	add_child(hot)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 2.8
	light.omni_range = 6.0
	light.shadow_enabled = false
	add_child(light)

	VFX.attach_ember_trail(self)

	if _dir.length() > 0.01 and absf(_dir.normalized().dot(Vector3.UP)) < 0.99:
		look_at(global_position + _dir, Vector3.UP)

	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_age += delta
	if _age > LIFETIME:
		queue_free()
		return
	global_position += _dir * _data.projectile_speed * delta


func _on_body_entered(_body: Node3D) -> void:
	_explode(null)


func _on_area_entered(area: Area3D) -> void:
	var hb := area as Hurtbox
	if hb == null or hb.owner_entity == null or hb.owner_entity == _source:
		return
	if _already_hit.has(hb.owner_entity):
		return
	if _pierces_left > 0:
		_pierces_left -= 1
		_already_hit.append(hb.owner_entity)
		_damage(hb.owner_entity)
		_split_from(hb.owner_entity)
		VFX.enemy_hit(get_tree().current_scene, global_position, Color(1.0, 0.6, 0.2))
		Sfx.play("ember_impact", global_position, -8.0, 0.15, 1.3)
	else:
		_explode(hb.owner_entity)


func _damage(victim: Node) -> void:
	if not victim.has_method(&"take_hit"):
		return
	# Cindermaw: hitting an ALREADY burning enemy makes it erupt.
	var was_burning: bool = victim is EnemyBase and (victim as EnemyBase).status.has_burn()
	var hit: HitInfo
	if _source is Player:
		hit = (_source as Player).roll_ability_hit(_data)
		hit.source_position = _source.global_position
		hit.damage *= damage_scale
	else:
		hit = _data.roll_hit(global_position)
	if bool(victim.call(&"take_hit", hit)):
		GameFeel.camera_impulse(_dir, 0.04)
		if _source is Player:
			(_source as Player).gain_resonance(_data.resonance_gain_per_hit)
			if was_burning and (_source as Player).has_power(&"cindermaw"):
				_cindermaw_erupt(victim as EnemyBase)


func _cindermaw_erupt(center_enemy: EnemyBase) -> void:
	var scene := get_tree().current_scene
	var pos := center_enemy.global_position + Vector3(0, 0.9, 0)
	VFX.ember_impact(scene, pos)
	VFX.ground_ring(scene, center_enemy.global_position, Color(1.0, 0.5, 0.15, 0.9), 2.5, 0.3)
	Sfx.play("earthbreaker_impact", pos, -4.0, 0.1, 1.4)
	for other in EnemyBase.all_enemies.duplicate():
		if other == center_enemy or not is_instance_valid(other) or other.ai_state == EnemyBase.AIState.DEAD:
			continue
		if other.global_position.distance_to(center_enemy.global_position) > 2.5:
			continue
		var splash := HitInfo.create(15.0, HitInfo.DamageType.FIRE, HitInfo.Weight.LIGHT, center_enemy.global_position)
		splash.applies_burn = true
		other.take_hit(splash)


func _explode(victim: Node) -> void:
	if _dead:
		return
	_dead = true
	var scene := get_tree().current_scene
	VFX.ember_impact(scene, global_position)
	Sfx.play("ember_impact", global_position, 0.0, 0.1)
	if victim != null:
		_damage(victim)
		_split_from(victim)
	_phoenix_burst(victim)
	queue_free()


## M07 Split Lance: the first hit forks two half-damage shards (+-26 deg).
## Added deferred: this runs inside a physics callback.
func _split_from(victim: Node) -> void:
	if not can_split or not _source is Player or not (_source as Player).has_power(&"split_lance"):
		return
	can_split = false
	for side: float in [-1.0, 1.0]:
		var d := _dir.rotated(Vector3.UP, side * SPLIT_ANGLE)
		var shard := EmberLanceProjectile.new()
		shard.setup(_data, d, _source)
		shard.damage_scale = damage_scale * 0.5
		shard.can_split = false
		shard._already_hit.append(victim)
		shard.position = global_position + d * 0.6
		get_tree().current_scene.add_child.call_deferred(shard)


## M07 Phoenix Burst: where a lance ends it bursts (50 % damage, Burn, 2 m).
func _phoenix_burst(victim: Node) -> void:
	if not _source is Player or not (_source as Player).has_power(&"phoenix_burst"):
		return
	var scene := get_tree().current_scene
	VFX.ground_ring(scene, Vector3(global_position.x, 0.0, global_position.z), ArtKit.color("color_roles.fire.body"),
		PHOENIX_RADIUS, 0.25)
	for other in EnemyBase.all_enemies.duplicate():
		if not is_instance_valid(other) or other == victim or other.ai_state == EnemyBase.AIState.DEAD:
			continue
		if other.global_position.distance_to(global_position) > PHOENIX_RADIUS + 0.5:
			continue
		var burst := (_source as Player).roll_ability_hit(_data)
		burst.damage *= 0.5 * damage_scale
		burst.applies_burn = true
		burst.source_position = global_position
		other.take_hit(burst)
