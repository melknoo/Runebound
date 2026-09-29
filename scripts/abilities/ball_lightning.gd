class_name BallLightning
extends Node3D
## M10 Elementalist: Ball Lightning - a slow orb drifting along the aim for
## `lifetime`; every ZAP it strikes (Lightning + Shock) each enemy within
## `radius` through its caster's roll, with an arc to each. It passes through
## enemies and stops at walls. A puppet's copy on a co-op client flies and
## crackles for show only.

const ZAP := 0.5

var lifetime: float = 3.0
var speed: float = 6.0
var radius: float = 3.0
var visual_only: bool = false
var _dir: Vector3 = Vector3.FORWARD
var _data: AbilityData
var _source: Player
var _age: float = 0.0
var _zap_left: float = 0.15
var _stopped: bool = false


func setup(data: AbilityData, dir: Vector3, source: Player) -> void:
	_data = data
	_source = source
	_dir = Vector3(dir.x, 0.0, dir.z).normalized() if Vector3(dir.x, 0.0, dir.z).length() > 0.01 else Vector3.FORWARD
	speed = data.projectile_speed
	lifetime = data.active
	radius = data.aoe_radius


func _ready() -> void:
	if not Net.has_view():
		return
	var core := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.32
	sphere.height = 0.64
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = ArtKit.color("color_roles.lightning.core", Color.WHITE)
	mat.emission_enabled = true
	mat.emission = ArtKit.color("color_roles.lightning.body", Color(1.0, 0.96, 0.63))
	mat.emission_energy_multiplier = 4.0
	sphere.material = mat
	core.mesh = sphere
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)
	VFX.attach_trail(self, "spark", [ArtKit.color("color_roles.lightning.core"), ArtKit.color("color_roles.lightning.body"),
		Color(ArtKit.color("color_roles.lightning.edge"), 0.0)] as Array[Color], 32, 0.16)
	var pulse := core.create_tween().set_loops()
	pulse.tween_property(core, "scale", Vector3.ONE * 1.25, 0.12)
	pulse.tween_property(core, "scale", Vector3.ONE * 0.85, 0.12)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	if not _stopped:
		var step := _dir * speed * delta
		var space := get_world_3d().direct_space_state if is_inside_tree() else null
		if space != null:
			var q := PhysicsRayQueryParameters3D.create(global_position, global_position + step + _dir * 0.3, 1)
			if not space.intersect_ray(q).is_empty():
				_stopped = true  # a wall: it hangs there, crackling, until it fades
		if not _stopped:
			global_position += step
	_zap_left -= delta
	if _zap_left > 0.0:
		return
	_zap_left = ZAP
	var scene := get_tree().current_scene
	var zapped := 0
	for e: EnemyBase in EnemyBase.all_enemies.duplicate():
		if not is_instance_valid(e) or e.ai_state == EnemyBase.AIState.DEAD:
			continue
		var chest := e.global_position + Vector3(0, 1.0, 0)
		if chest.distance_to(global_position) > radius:
			continue
		VFX.lightning_arc(scene, global_position, chest, Color(1.0, 0.95, 0.5))
		zapped += 1
		if visual_only or _source == null or not is_instance_valid(_source):
			continue
		var hit := _source.roll_ability_hit(_data)
		hit.source_position = global_position
		if e.take_hit(hit):
			_source.gain_resonance(_data.resonance_gain_per_hit, true)
	if zapped > 0:
		Sfx.play("ball_lightning", global_position, -6.0, 0.15)
