class_name FlameWall
extends Node3D
## M10 Elementalist: Flame Wall - a line of fire on the ground, `length` long
## across `axis`, for `duration`. Every TICK it hits (Fire + Burn) each enemy
## within REACH of the line through its caster's roll. A puppet's copy on a
## co-op client burns for show only (the owner's wall deals the damage).

const TICK := 0.5
const REACH := 0.9

var length: float = 6.0
var duration: float = 4.0
var axis: Vector3 = Vector3.RIGHT
## M09-style copy on another player's screen: flames only.
var visual_only: bool = false
var _data: AbilityData
var _source: Player
var _age: float = 0.0
var _tick_left: float = 0.0


func setup(data: AbilityData, source: Player) -> void:
	_data = data
	_source = source


func _ready() -> void:
	axis = Vector3(axis.x, 0.0, axis.z).normalized() if Vector3(axis.x, 0.0, axis.z).length() > 0.01 else Vector3.RIGHT
	Sfx.play("flame_wall", global_position, -2.0, 0.08)
	if not Net.has_view():
		return
	var fire := ArtKit.color("color_roles.fire.body", Color(1.0, 0.42, 0.16))
	var core := ArtKit.color("color_roles.fire.core", Color(1.0, 0.82, 0.48))
	var edge := ArtKit.color("color_roles.fire.edge", Color(0.72, 0.2, 0.11))
	var along := Basis(Vector3.UP, atan2(-axis.z, axis.x))  # local X along the wall
	# flame tongues: big soft sprites that rise and shrink, dense along the line
	var tongues := _flames(int(clampf(length * 9.0, 18.0, 70.0)), 0.6, VFX._quad("flash", 0.6),
		[core, fire, Color(edge, 0.0)] as Array[Color], 1.6, 3.0)
	tongues.basis = along
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.25))
	tongues.scale_amount_curve = shrink
	add_child(tongues)
	# embers: small sparks that fly higher than the flames
	var sparks := _flames(int(clampf(length * 5.0, 10.0, 40.0)), 0.9, VFX._quad("ember", 0.14),
		[core, Color(fire, 0.0)] as Array[Color], 2.6, 4.4)
	sparks.basis = along
	add_child(sparks)
	# a steady fire light along the wall, so it lights the ground and the enemies in it
	var glow := OmniLight3D.new()
	glow.light_color = fire
	glow.light_energy = 1.6
	glow.omni_range = maxf(length * 0.75, 3.0)
	glow.shadow_enabled = false
	glow.position.y = 0.8
	add_child(glow)
	# a scorched strip under the flames (a player mark: a line, never the red disc)
	var strip := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(length, 0.45)
	var strip_mat := StandardMaterial3D.new()
	strip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	strip_mat.albedo_color = Color(fire, 0.6)
	strip_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	strip_mat.emission_enabled = true
	strip_mat.emission = fire
	strip_mat.emission_energy_multiplier = 1.2
	plane.material = strip_mat
	strip.mesh = plane
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	strip.position.y = 0.04
	strip.basis = along
	add_child(strip)
	# the fire dies down over the last half second instead of popping out
	var fade := create_tween()
	fade.tween_interval(maxf(duration - 0.5, 0.0))
	fade.tween_callback(func() -> void:
		tongues.emitting = false
		sparks.emitting = false)
	fade.parallel().tween_property(glow, "light_energy", 0.0, 0.5)
	fade.parallel().tween_property(strip_mat, "albedo_color:a", 0.0, 0.5)


## One looping emitter along the wall (a thin box `length` long).
func _flames(amount: int, lifetime: float, quad: QuadMesh, colors: Array[Color], vel_min: float, vel_max: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(length * 0.5, 0.05, 0.14)
	p.direction = Vector3.UP
	p.spread = 10.0
	p.initial_velocity_min = vel_min
	p.initial_velocity_max = vel_max
	p.gravity = Vector3(0, 1.0, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.4
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray(colors)
	var offsets := PackedFloat32Array()
	for i in colors.size():
		offsets.append(float(i) / float(maxi(colors.size() - 1, 1)))
	ramp.offsets = offsets
	p.color_ramp = ramp
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Distance from `pos` to the wall's line (flat).
func distance_to_line(pos: Vector3) -> float:
	var d := pos - global_position
	d.y = 0.0
	var along := clampf(d.dot(axis), -length * 0.5, length * 0.5)
	return (d - axis * along).length()


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= duration:
		queue_free()
		return
	if visual_only or _source == null or not is_instance_valid(_source):
		return
	_tick_left -= delta
	if _tick_left > 0.0:
		return
	_tick_left = TICK
	for e: EnemyBase in EnemyBase.all_enemies.duplicate():
		if not is_instance_valid(e) or e.ai_state == EnemyBase.AIState.DEAD:
			continue
		if absf(e.global_position.y - global_position.y) > 2.5 or distance_to_line(e.global_position) > REACH:
			continue
		var hit := _source.roll_ability_hit(_data)
		hit.source_position = global_position
		if e.take_hit(hit):
			_source.gain_resonance(_data.resonance_gain_per_hit)
