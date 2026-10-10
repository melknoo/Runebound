class_name EmberSeed
extends Node3D
## M13 the Warrens' tome (Elementalist): a seed of embers planted in one
## enemy. It glows brighter as it ripens and bursts FUSE seconds later - or
## at once when its host dies - in a ring of fire around the host (the
## ability's aoe_radius): Fire damage and Burn on every enemy in it. A player
## ring shows the blast. The caster's machine deals the damage (like every
## spell); another player's seed is a visual copy that follows the same
## enemy by its net id.

const FUSE := 3.0

var host: EnemyBase = null
var visual_only: bool = false
var _data: AbilityData
var _source: Player
var _t: float = 0.0
var _core: MeshInstance3D
var _mat: StandardMaterial3D
var _last_at: Vector3 = Vector3.ZERO
var _done: bool = false


func setup(data: AbilityData, source: Player, target: EnemyBase) -> void:
	_data = data
	_source = source
	host = target


func _ready() -> void:
	_core = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.28
	_mat = EnemyBase.flat_material(ArtKit.color("color_roles.fire.core", Color(1.0, 0.82, 0.48)), true, 1.0)
	box.material = _mat
	_core.mesh = box
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_core)
	_follow()
	VFX.player_ring(self, _ground(), _data.aoe_radius if _data != null else 3.5, FUSE,
		ArtKit.color("color_roles.fire.body", Color(1.0, 0.5, 0.2)))
	Sfx.play("ember_cast", global_position, -6.0, 0.1, 0.7)


func _ground() -> Vector3:
	return ZoneBase.ground_under(self, _last_at + Vector3(0, 1.0, 0), 0.03)


func _follow() -> void:
	if host != null and is_instance_valid(host) and host.ai_state != EnemyBase.AIState.DEAD:
		_last_at = host.global_position
	global_position = _last_at + Vector3(0, 1.4, 0)


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	_follow()
	_core.rotation += Vector3(3.0, 4.0, 0.0) * delta
	_mat.emission_energy_multiplier = 1.0 + 3.0 * _t / FUSE
	_core.scale = Vector3.ONE * (1.0 + 0.6 * _t / FUSE)
	var host_gone := host == null or not is_instance_valid(host) or host.ai_state == EnemyBase.AIState.DEAD
	if _t >= FUSE or host_gone:
		_burst()


func _burst() -> void:
	_done = true
	var at := _ground()
	var radius := _data.aoe_radius if _data != null else 3.5
	var scene := get_tree().current_scene
	VFX.ember_impact(scene, at + Vector3(0, 0.6, 0))
	VFX.ground_ring(scene, at, ArtKit.color("color_roles.fire.body", Color(1.0, 0.5, 0.2)), radius, 0.35)
	Sfx.play("ember_impact", at, 0.0, 0.08, 0.8)
	if not visual_only and _data != null:
		for e: EnemyBase in EnemyBase.all_enemies.duplicate():
			if not is_instance_valid(e) or e.ai_state == EnemyBase.AIState.DEAD or not e.targetable:
				continue
			var d := e.global_position - at
			d.y = 0.0
			if d.length() > radius:
				continue
			var hit: HitInfo
			if _source != null and is_instance_valid(_source):
				hit = _source.roll_ability_hit(_data)
			else:
				hit = _data.roll_hit(at)
			hit.source_position = at
			e.take_hit(hit)
		if _source != null and is_instance_valid(_source):
			_source.feel_shake(0.2)
	queue_free()
