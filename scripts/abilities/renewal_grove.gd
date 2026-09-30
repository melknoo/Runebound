class_name RenewalGrove
extends Node3D
## M11 druid: Renewal Grove - a ring of young growth on the ground; every
## hero inside heals `rate` a second while it lasts. Like the tank's Warding
## Rune it exists on every machine (HeroFx "renewal_grove") and each one heals
## the heroes it simulates (the hybrid authority rule: an owner owns its
## health). The caster's own copy also does what only the caster may: a
## Heartwood Idol roots enemies stepping in (once each), Green Tide refills
## the druid's Sap while it stands inside.

const TICK := 0.5
const IDOL_ROOT := 1.0
const GREEN_TIDE_SAP := 2.0  # per second

var radius: float = 5.0
var duration: float = 8.0
var rate: float = 4.0
var roots_enemies: bool = false
var green_tide: bool = false
## The druid who planted it (its owner applies the caster-only extras).
var source: Player = null
var _age: float = 0.0
var _tick_left: float = 0.0
var _rooted: Array[int] = []


func _ready() -> void:
	Sfx.play("grove", global_position, -2.0, 0.05)
	if not Net.has_view():
		return
	var green := ArtKit.color("color_roles.nature.body", Color("#7ED957"))
	var hot := ArtKit.color("color_roles.nature.hot", Color("#E4FFC4"))
	var glyph := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(radius * 0.9, radius * 0.9)  # the glyph's pixel scale of the Warding Rune
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.3
	if ResourceLoader.exists("res://assets/vfx/glyph.png"):
		mat.albedo_texture = load("res://assets/vfx/glyph.png")
	mat.albedo_color = green
	mat.emission_enabled = true
	mat.emission = ArtKit.color("color_roles.nature.edge", Color("#2E6B34"))
	mat.emission_energy_multiplier = 1.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.disable_receive_shadows = true
	plane.material = mat
	glyph.mesh = plane
	glyph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glyph.position.y = 0.05
	add_child(glyph)
	var spin := glyph.create_tween().set_loops()
	spin.tween_property(glyph, "rotation:y", -TAU, 12.0).from(0.0)
	VFX.player_ring(self, global_position, radius, duration, green)
	# leaf-light motes drifting up across the grove
	var motes := CPUParticles3D.new()
	motes.amount = int(clampf(radius * 5.0, 12.0, 40.0))
	motes.lifetime = 1.6
	motes.local_coords = false
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	motes.emission_box_extents = Vector3(radius * 0.7, 0.05, radius * 0.7)
	motes.direction = Vector3.UP
	motes.spread = 15.0
	motes.initial_velocity_min = 0.4
	motes.initial_velocity_max = 0.9
	motes.gravity = Vector3(0, 0.3, 0)
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([hot, green, Color(green, 0.0)])
	motes.color_ramp = ramp
	motes.mesh = VFX._quad("spark", 0.12)
	motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	motes.position.y = 0.3
	add_child(motes)


func contains(p: Node3D) -> bool:
	var d := p.global_position - global_position
	return absf(d.y) < 3.0 and Vector2(d.x, d.z).length() <= radius


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= duration:
		queue_free()
		return
	var mine := source != null and is_instance_valid(source) and source.net_role == Player.NetRole.OWNER
	if mine and green_tide and contains(source) and source.resonance < source.max_resource():
		source.resonance = minf(source.resonance + GREEN_TIDE_SAP * delta, source.max_resource())
		source.resonance_changed.emit(source.resonance, source.max_resource())
	_tick_left -= delta
	if _tick_left > 0.0:
		return
	_tick_left = TICK
	var zone := ZoneBase.zone_of(self)
	if zone != null:
		for p in zone.players:
			if p != null and is_instance_valid(p) and p.net_role == Player.NetRole.OWNER \
					and not p.health.is_dead and contains(p):
				p.receive_heal(rate * TICK)
	if mine and roots_enemies:
		for e in EnemyBase.all_enemies:
			if is_instance_valid(e) and e.ai_state != EnemyBase.AIState.DEAD and contains(e) \
					and not _rooted.has(e.get_instance_id()):
				_rooted.append(e.get_instance_id())
				e.status.apply_root(IDOL_ROOT)
