class_name EmberFall
extends Node3D
## M10 Elementalist: Ember Fall - a burning rock called down on the aim. A
## broken fire ring (a player mark, never the enemies' red disc) fills over
## `delay` while the rock falls; then it strikes `radius` around (Fire, HEAVY
## stagger, Burn) through its caster's roll. With Cinderfall the ground burns
## on for CINDER_TIME (Burn + a small hit every half second). A puppet's copy
## on a co-op client falls and bursts for show only.

const FALL_HEIGHT := 14.0
const CINDER_TIME := 3.0
const CINDER_TICK := 0.5

var delay: float = 0.9
var radius: float = 3.5
var visual_only: bool = false
var _data: AbilityData
var _source: Player
var _age: float = 0.0
var _landed: bool = false
var _cinder_left: float = 0.0
var _cinder_tick: float = 0.0
var _rock: MeshInstance3D


func setup(data: AbilityData, source: Player) -> void:
	_data = data
	_source = source
	delay = data.active
	radius = data.aoe_radius


func _ready() -> void:
	Sfx.play("ember_fall_call", global_position, -2.0, 0.05)
	if not Net.has_view():
		return
	VFX.player_ring(self, global_position, radius, delay, ArtKit.color("color_roles.fire.body"))
	var fire := ArtKit.color("color_roles.fire.body", Color(1.0, 0.42, 0.16))
	var edge := ArtKit.color("color_roles.fire.edge", Color(0.72, 0.2, 0.11))
	# a dark basalt rock glowing from its cracks (never white-hot: it has to
	# read as a rock against the sky), with an orange comet tail and a light
	# that brightens the ground as it comes down
	_rock = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.7
	sphere.height = 1.2
	sphere.radial_segments = 7
	sphere.rings = 4
	var mat := StandardMaterial3D.new()
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.albedo_color = ArtKit.color("palettes.highlands.basalt.2", Color(0.23, 0.2, 0.22))
	mat.emission_enabled = true
	mat.emission = edge
	mat.emission_energy_multiplier = 0.8
	sphere.material = mat
	_rock.mesh = sphere
	_rock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rock.position = Vector3(0, FALL_HEIGHT, 0)
	_rock.rotation = Vector3(0.4, 0.7, 0.2)  # a tumbling lump, not a ball
	add_child(_rock)
	VFX.attach_trail(_rock, "flash", [fire, edge, Color(edge, 0.0)] as Array[Color], 40, 0.5)
	var glow := OmniLight3D.new()
	glow.light_color = fire
	glow.light_energy = 2.0
	glow.omni_range = 6.0
	glow.shadow_enabled = false
	_rock.add_child(glow)


func _physics_process(delta: float) -> void:
	_age += delta
	if not _landed:
		if _rock != null:
			var k := clampf(_age / maxf(delay, 0.01), 0.0, 1.0)
			_rock.position.y = FALL_HEIGHT * (1.0 - k * k)  # accelerating down
			_rock.rotate_x(delta * 5.0)
		if _age >= delay:
			_land()
		return
	if _cinder_left <= 0.0:
		queue_free()
		return
	_cinder_left -= delta
	_cinder_tick -= delta
	if _cinder_tick > 0.0 or visual_only or _source == null or not is_instance_valid(_source):
		return
	_cinder_tick = CINDER_TICK
	for e in _enemies_in(radius * 0.8):
		var hit := _source.roll_ability_hit(_data)
		hit.damage *= 0.08  # the burning ground, not the rock again
		hit.weight = HitInfo.Weight.LIGHT
		hit.knockback = 0.0
		hit.source_position = global_position
		e.take_hit(hit)


func _land() -> void:
	_landed = true
	var scene := get_tree().current_scene
	if _rock != null:
		_rock.queue_free()
		_rock = null
	VFX.earthbreaker_slam(scene, global_position, radius)
	VFX.ember_impact(scene, global_position + Vector3(0, 0.5, 0))
	VFX.flash(scene, global_position + Vector3(0, 1.0, 0), ArtKit.color("color_roles.fire.core"), 2.6, 0.2)
	Sfx.play("ember_fall_impact", global_position, 2.0, 0.05)
	var cinder := _source != null and is_instance_valid(_source) and _source.has_power(&"cinderfall")
	_cinder_left = CINDER_TIME if cinder else 0.0
	if cinder and Net.has_view():
		VFX.player_ring(self, global_position, radius * 0.8, CINDER_TIME, ArtKit.color("color_roles.fire.edge"))
	if visual_only or _source == null or not is_instance_valid(_source):
		return
	_source.feel_shake(0.45)
	var hits := _enemies_in(radius)
	for e in hits:
		var hit := _source.roll_ability_hit(_data)
		hit.source_position = global_position
		e.take_hit(hit)
	if not hits.is_empty():
		GameFeel.hitstop(hits, 0.06)


func _enemies_in(r: float) -> Array[EnemyBase]:
	var out: Array[EnemyBase] = []
	for e: EnemyBase in EnemyBase.all_enemies.duplicate():
		if not is_instance_valid(e) or e.ai_state == EnemyBase.AIState.DEAD:
			continue
		var d := e.global_position - global_position
		if absf(d.y) > 3.0:
			continue
		d.y = 0.0
		if d.length() <= r:
			out.append(e)
	return out
