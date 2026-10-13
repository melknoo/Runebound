class_name Cloudburst
extends Node3D
## M13b the Stormwatch's tome (druid): a rain cloud over the druid that goes
## where she goes. Every TICK each hero within `radius` of her heals
## `rate` a second and the rain washes off its slows. With Rainheart every
## hero still under it when it ends gets a barrier. Built on every machine
## as a child of the druid's hero (HeroFx "cloudburst"), so it follows her
## puppet too; each machine heals the heroes it simulates (the hybrid
## authority rule, like the Renewal Grove).

const TICK := 0.5
const HEIGHT := 4.2
const BARRIER_TIME := 5.0

var radius: float = 6.0
var duration: float = 6.0
var rate: float = 6.0
## Rainheart (the legendary): the barrier it leaves when it ends (0 = none).
var end_barrier: float = 0.0
var _age: float = 0.0
var _tick_left: float = 0.0
var _cloud: Node3D
var _rain: CPUParticles3D


func _ready() -> void:
	Sfx.play("water_splash", global_position + Vector3(0, 2.0, 0), -3.0, 0.08, 0.7)
	Sfx.play("grove", global_position, -6.0, 0.05, 1.2)
	if not Net.has_view():
		return
	var water := ArtKit.color("palettes.cistern.water_hi", Color(0.36, 0.62, 0.64))
	var green := ArtKit.color("color_roles.nature.body", Color("#7ED957"))
	_cloud = Node3D.new()
	_cloud.position = Vector3(0, HEIGHT, 0)
	add_child(_cloud)
	var grey := EnemyBase.flat_material(Color("#5A6474"))
	var light := EnemyBase.flat_material(Color("#76808E"))
	var puffs := [[Vector3(0, 0, 0), 1.5], [Vector3(1.3, -0.1, 0.3), 1.1], [Vector3(-1.2, -0.05, -0.4), 1.2],
		[Vector3(0.2, 0.25, -1.1), 1.0], [Vector3(-0.3, 0.15, 1.1), 1.05]]
	for i in puffs.size():
		var puff := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		var r := float(puffs[i][1])
		sphere.radius = r
		sphere.height = r * 1.1
		sphere.radial_segments = 10
		sphere.rings = 5
		sphere.material = grey if i % 2 == 0 else light
		puff.mesh = sphere
		puff.position = puffs[i][0] as Vector3
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_cloud.add_child(puff)
	# the rain: thin streaks falling from the cloud over the whole circle
	_rain = CPUParticles3D.new()
	_rain.amount = int(clampf(radius * 14.0, 40.0, 120.0))
	_rain.lifetime = 0.5
	_rain.local_coords = false
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(radius * 0.75, 0.1, radius * 0.75)
	_rain.direction = Vector3.DOWN
	_rain.spread = 4.0
	_rain.initial_velocity_min = 8.0
	_rain.initial_velocity_max = 10.0
	_rain.gravity = Vector3(0, -4.0, 0)
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(water.lightened(0.4), 0.0), Color(water.lightened(0.4), 0.8), Color(water, 0.0)])
	_rain.color_ramp = ramp
	var streak := QuadMesh.new()
	streak.size = Vector2(0.03, 0.45)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	streak.material = mat
	_rain.mesh = streak
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain.position = Vector3(0, HEIGHT - 0.4, 0)
	add_child(_rain)
	VFX.player_ring(self, global_position, radius, duration, Color(green.lerp(water, 0.5), 1.0))
	_cloud.scale = Vector3(0.2, 0.2, 0.2)
	var grow := _cloud.create_tween()
	grow.tween_property(_cloud, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if _cloud != null:
		_cloud.rotation.y += delta * 0.25


func contains(p: Node3D) -> bool:
	var d := p.global_position - global_position
	return absf(d.y) < 3.0 and Vector2(d.x, d.z).length() <= radius


func _heroes_under() -> Array[Player]:
	var out: Array[Player] = []
	var zone := ZoneBase.zone_of(self)
	if zone == null:
		return out
	for p in zone.players:
		if p != null and is_instance_valid(p) and p.net_role == Player.NetRole.OWNER \
				and not p.health.is_dead and contains(p):
			out.append(p)
	return out


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= duration:
		_end()
		return
	_tick_left -= delta
	if _tick_left > 0.0:
		return
	_tick_left = TICK
	for p in _heroes_under():
		p.receive_heal(rate * TICK)
		p.clear_slow()


func _end() -> void:
	set_physics_process(false)
	if end_barrier > 0.0:
		for p in _heroes_under():
			p.grant_barrier(end_barrier, BARRIER_TIME)
	if _rain != null:
		_rain.emitting = false
	if _cloud == null:
		queue_free()
		return
	var tw := _cloud.create_tween()
	tw.tween_property(_cloud, "scale", Vector3(0.1, 0.1, 0.1), 0.3)
	tw.tween_interval(0.4)
	tw.tween_callback(queue_free)
