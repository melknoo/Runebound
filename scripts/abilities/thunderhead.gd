class_name Thunderhead
extends Node3D
## M13b the Stormwatch's tome (Elementalist): a thundercloud over the aim.
## Every STRIKE_EVERY s lightning falls from it on one enemy under it (the
## ability's damage, Shock), and every hero under it runs HASTE_PCT faster (a
## short buff renewed each HASTE_TICK). Built on every machine (HeroFx
## "thunderhead"): the caster's own copy strikes and sends each bolt (HeroFx
## "thunderhead_bolt", which also moves another player's copy to where the
## cloud is), and every machine speeds the heroes it simulates (like the
## druid's totem). With Cloudkeeper it lasts longer and drifts after the
## enemy it last struck.

const STRIKE_EVERY := 0.8
const FIRST_STRIKE := 0.35
const HASTE_PCT := 20.0
const HASTE_TICK := 0.5
const HEIGHT := 5.0
const DRIFT_SPEED := 2.5
## A copy of another player's cloud glides to the caster's position this fast.
const FOLLOW_RATE := 6.0

var radius: float = 4.0
var duration: float = 6.0
## Cloudkeeper (the legendary): drifts after the enemy it last struck.
var drifts: bool = false
## The Elementalist who called it (its owner strikes).
var source: Player = null
var _data: AbilityData
var _age: float = 0.0
var _strike_left: float = FIRST_STRIKE
var _haste_left: float = 0.0
var _drift_to: Vector3 = Vector3.INF
## Another player's copy: where the caster's cloud last was.
var _follow_to: Vector3 = Vector3.INF
var _cloud: Node3D
var _light: OmniLight3D


func setup(data: AbilityData, caster: Player) -> void:
	_data = data
	source = caster
	if data != null:
		radius = data.aoe_radius
		duration = data.active


func _ready() -> void:
	Sfx.play("coil_charge", global_position + Vector3(0, HEIGHT, 0), -4.0, 0.08, 0.8)
	if not Net.has_view():
		return
	var storm := ArtKit.color("palettes.stormwatch.lightning", Color("#B9A8FF"))
	_cloud = Node3D.new()
	_cloud.position = Vector3(0, HEIGHT, 0)
	add_child(_cloud)
	var dark := EnemyBase.flat_material(Color("#2A2C3A"))
	var mid := EnemyBase.flat_material(Color("#3C3F52"))
	var puffs := [[Vector3(0, 0, 0), 1.7], [Vector3(1.4, -0.1, 0.4), 1.2], [Vector3(-1.3, -0.05, -0.3), 1.3],
		[Vector3(0.3, 0.2, -1.2), 1.1], [Vector3(-0.4, 0.1, 1.2), 1.15], [Vector3(0.6, 0.45, 0.1), 1.0]]
	for i in puffs.size():
		var puff := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		var r := float(puffs[i][1]) * radius / 4.0
		sphere.radius = r
		sphere.height = r * 1.1
		sphere.radial_segments = 10
		sphere.rings = 5
		sphere.material = dark if i % 2 == 0 else mid
		puff.mesh = sphere
		puff.position = (puffs[i][0] as Vector3) * radius / 4.0
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_cloud.add_child(puff)
	_light = OmniLight3D.new()
	_light.light_color = storm
	_light.light_energy = 0.4
	_light.omni_range = radius + 2.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, -0.6, 0)
	_cloud.add_child(_light)
	_cloud.scale = Vector3(0.2, 0.2, 0.2)
	var grow := _cloud.create_tween()
	grow.tween_property(_cloud, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	VFX.player_ring(self, global_position, radius, duration, storm)


func _mine() -> bool:
	return source != null and is_instance_valid(source) and source.net_role == Player.NetRole.OWNER


func contains(p: Node3D) -> bool:
	var d := p.global_position - global_position
	return absf(d.y) < HEIGHT and Vector2(d.x, d.z).length() <= radius


func _process(delta: float) -> void:
	if _cloud != null:
		_cloud.rotation.y += delta * 0.3
	if _light != null:
		_light.light_energy = lerpf(_light.light_energy, 0.4, minf(delta * 6.0, 1.0))


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= duration:
		_fade()
		return
	if _mine():
		if drifts and _drift_to != Vector3.INF:
			var flat := Vector3(_drift_to.x - global_position.x, 0.0, _drift_to.z - global_position.z)
			if flat.length() > 0.2:
				var step := flat.normalized() * minf(DRIFT_SPEED * delta, flat.length())
				global_position = ZoneBase.ground_under(self, global_position + step, 0.02)
		_strike_left -= delta
		if _strike_left <= 0.0:
			_strike_left = STRIKE_EVERY
			_strike()
	elif _follow_to != Vector3.INF:
		global_position = global_position.lerp(_follow_to, minf(FOLLOW_RATE * delta, 1.0))
	_haste_left -= delta
	if _haste_left <= 0.0:
		_haste_left = HASTE_TICK
		var zone := ZoneBase.zone_of(self)
		if zone != null:
			for p in zone.players:
				if p != null and is_instance_valid(p) and p.net_role == Player.NetRole.OWNER \
						and not p.health.is_dead and contains(p):
					p.add_buff(&"move_pct", HASTE_PCT, HASTE_TICK + 0.3)


## The caster's copy: lightning on one enemy under the cloud (any of them -
## the storm does not choose).
func _strike() -> void:
	var under: Array[EnemyBase] = []
	for e in EnemyBase.all_enemies:
		if is_instance_valid(e) and e.ai_state != EnemyBase.AIState.DEAD and e.targetable and contains(e):
			under.append(e)
	if under.is_empty() or _data == null:
		return
	var e: EnemyBase = under.pick_random()
	var hit := source.roll_ability_hit(_data)
	hit.source_position = global_position
	e.take_hit(hit)
	if drifts:
		_drift_to = e.global_position
	source.hero_fx(&"thunderhead_bolt", [global_position, e.global_position])


## HeroFx "thunderhead_bolt": the bolt's look on every machine; another
## player's copy learns where the caster's cloud is.
func bolt(cloud_at: Vector3, at: Vector3) -> void:
	if not _mine():
		_follow_to = cloud_at
	var scene := get_tree().current_scene
	var color := ArtKit.color("palettes.stormwatch.lightning_hi", Color("#F2EEFF"))
	VFX.lightning_arc(scene, cloud_at + Vector3(0, HEIGHT - 0.6, 0), at + Vector3(0, 1.0, 0), color)
	VFX.shock_tick(scene, at + Vector3(0, 1.0, 0))
	if _light != null:
		_light.light_energy = 3.0
	Sfx.play("storm_bolt", at, -6.0, 0.12, 1.15)


func _fade() -> void:
	set_physics_process(false)
	if _cloud == null:
		queue_free()
		return
	var tw := _cloud.create_tween()
	tw.tween_property(_cloud, "scale", Vector3(0.1, 0.1, 0.1), 0.3)
	tw.tween_callback(queue_free)
