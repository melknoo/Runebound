class_name ThornField
extends Node3D
## M11 druid: Thornfield - thorns cover a patch of ground (`radius`) for
## `duration`. Every TICK they bite each enemy inside through the caster's
## roll and Chill it (they hinder: slower). A puppet's copy on a co-op client
## bristles for show only (the owner's field deals the damage).

const TICK := 0.5
const CHILL := 1.0

var radius: float = 4.0
var duration: float = 6.0
## M09-style copy on another player's screen: thorns only.
var visual_only: bool = false
var _data: AbilityData
var _source: Player
var _age: float = 0.0
var _tick_left: float = 0.0


func setup(data: AbilityData, source: Player) -> void:
	_data = data
	_source = source


func _ready() -> void:
	Sfx.play("thornfield", global_position, -2.0, 0.08)
	if not Net.has_view():
		return
	var bark := ArtKit.color("palettes.druid.bark.3", Color("#6C4A38"))
	var green := ArtKit.color("color_roles.nature.body", Color("#7ED957"))
	var hot := ArtKit.color("color_roles.nature.hot", Color("#E4FFC4"))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(global_position.x * 73.0 + global_position.z * 131.0))
	var spike_mat := StandardMaterial3D.new()
	spike_mat.albedo_color = bark
	spike_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	var tip_mat := StandardMaterial3D.new()
	tip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tip_mat.albedo_color = green
	var count := int(clampf(radius * radius * 2.2, 12.0, 60.0))
	for i in count:
		var r := sqrt(rng.randf()) * radius * 0.92
		var a := rng.randf() * TAU
		var h := rng.randf_range(0.25, 0.6)
		var spike := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.05
		cone.height = h
		cone.radial_segments = 4
		cone.rings = 1
		cone.material = spike_mat if i % 4 != 0 else tip_mat
		spike.mesh = cone
		spike.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		spike.position = Vector3(cos(a) * r, h * 0.5 - 0.05, sin(a) * r)
		spike.rotation = Vector3(rng.randf_range(-0.35, 0.35), 0.0, rng.randf_range(-0.35, 0.35))
		spike.scale = Vector3(1, 0.01, 1)
		add_child(spike)
		var grow := spike.create_tween()  # the thorns bristle up out of the ground
		grow.tween_interval(rng.randf() * 0.15)
		grow.tween_property(spike, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# a player mark (a broken ring in the nature green), never the enemies' red disc
	VFX.player_ring(self, global_position, radius, duration, green)
	VFX.flash(get_tree().current_scene, global_position + Vector3(0, 0.3, 0), hot, 1.2, 0.12)
	var fade := create_tween()
	fade.tween_interval(maxf(duration - 0.35, 0.0))
	fade.tween_property(self, "scale", Vector3(1, 0.01, 1), 0.35)


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
		var d := e.global_position - global_position
		if absf(d.y) > 2.5 or Vector2(d.x, d.z).length() > radius:
			continue
		var hit := _source.roll_ability_hit(_data)
		hit.source_position = global_position
		if e.take_hit(hit):
			e.status.apply_chill(CHILL)
