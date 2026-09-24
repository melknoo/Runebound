class_name EnemyBase
extends CharacterBody3D
## Shared enemy chassis: health, hurtbox, hit reactions, stagger, death.
## Subclasses implement _ai_process() and _build_body().

signal enemy_died(enemy: EnemyBase)
## Presentation hook (M06 CharacterAnimator): fires on every state entry,
## including re-entering STAGGER, which polling ai_state would miss.
signal state_entered(state: AIState)

enum AIState { IDLE, CHASE, WINDUP, ATTACK, RECOVER, STAGGER, DEAD, CIRCLE, RETREAT }

const GRAVITY := 24.0
const AGGRO_RANGE := 16.0

@export var display_name: String = "Enemy"
@export var max_health: float = 60.0
@export var move_speed: float = 4.0
@export var body_color: Color = Color(0.6, 0.3, 0.3)
## Stagger-resistant enemies flinch visually but only HEAVY hits interrupt.
@export var stagger_resist: bool = false

var ai_state: AIState = AIState.IDLE
var player: Player = null
var health: HealthComponent
var status: StatusEffectComponent
var is_elite: bool = false
## M07: set by the zone before the enemy enters the tree (1 = base balance).
var level: int = 1
## Base XP for a kill (docs/PROGRESSION_DESIGN.md); x4 for elites, +15 %/level.
var xp_value: int = 20
var visual: Node3D

const HP_PER_LEVEL := 0.08


func xp_reward() -> int:
	return int(round(float(xp_value) * (4.0 if is_elite else 1.0) * (1.0 + 0.15 * (level - 1))))


## M07b gold on death: about half the XP value, a little random, inheriting
## the elite and level scaling. One rule for every enemy (PROGRESSION_DESIGN).
const GOLD_PER_XP := 0.5


func gold_reward() -> int:
	return maxi(int(round(float(xp_reward()) * GOLD_PER_XP * randf_range(0.8, 1.25))), 1)
## Squash/death tweens scale relative to this — bosses and elites are bigger
## than 1.0, and a hit must never reset them to man-size.
var base_visual_scale: Vector3 = Vector3.ONE

var _state_timer: float = 0.0
var _knockback_velocity: Vector3 = Vector3.ZERO
var _squash_tween: Tween
var _hitstop_left: float = 0.0


## All live enemies, for O(n) separation steering (enemy-enemy physics
## collision is disabled — solver pairs from clustered capsules dominated the
## frame budget at ~30 enemies).
static var all_enemies: Array[EnemyBase] = []


## Registered on every tree entry, not just in _ready: a reparent (debug style A
## moves the whole world into a SubViewport) exits and re-enters the tree, and
## _ready never runs twice.
func _enter_tree() -> void:
	if not all_enemies.has(self):
		all_enemies.append(self)


func _ready() -> void:
	collision_layer = 0b100
	collision_mask = 0b011  # world + player; NOT other enemies
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.45
	capsule.height = 1.6
	col.shape = capsule
	col.position = Vector3(0, 0.8, 0)
	add_child(col)

	health = HealthComponent.new()
	health.max_health = max_health * (1.0 + HP_PER_LEVEL * (level - 1))
	add_child(health)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)

	status = StatusEffectComponent.new()
	status.health = health
	add_child(status)

	Hurtbox.create(self, 0b10000, 0.55, 1.7, 0.85)

	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	_build_body()


func _build_body() -> void:
	pass  # subclasses build their silhouette here


## World-space height of the target HP bar; scales with the body so bosses
## and elites don't swallow their bar.
func nameplate_height() -> float:
	return 2.05 * maxf(base_visual_scale.y, 1.0)


func apply_hitstop(duration: float) -> void:
	_hitstop_left = maxf(_hitstop_left, duration)


func _physics_process(delta: float) -> void:
	if _hitstop_left > 0.0:
		_hitstop_left -= delta
		return
	_state_timer += delta
	if ai_state != AIState.DEAD:
		_ai_process(delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	var separation := _separation_push() * 5.0
	velocity += _knockback_velocity + separation
	move_and_slide()
	velocity -= _knockback_velocity + separation
	_knockback_velocity = _knockback_velocity.lerp(Vector3.ZERO, minf(6.0 * delta, 1.0))


func _exit_tree() -> void:
	all_enemies.erase(self)


func _separation_push() -> Vector3:
	var push := Vector3.ZERO
	for other in all_enemies:
		if other == self or other.ai_state == AIState.DEAD:
			continue
		var d := global_position - other.global_position
		d.y = 0.0
		var dist := d.length()
		if dist < 1.0 and dist > 0.001:
			push += (d / dist) * (1.0 - dist)
	return push


func _ai_process(_delta: float) -> void:
	pass


func _enter_state(new_state: AIState) -> void:
	ai_state = new_state
	_state_timer = 0.0
	state_entered.emit(new_state)


func distance_to_player() -> float:
	if player == null or not is_instance_valid(player):
		return INF
	return global_position.distance_to(player.global_position)


func dir_to_player() -> Vector3:
	if player == null or not is_instance_valid(player):
		return Vector3.FORWARD
	var d := player.global_position - global_position
	d.y = 0
	return d.normalized()


func face_player(delta: float, turn_speed: float = 10.0) -> void:
	var dir := dir_to_player()
	var target_yaw := atan2(-dir.x, -dir.z)
	visual.rotation.y = lerp_angle(visual.rotation.y, target_yaw, minf(turn_speed * delta, 1.0))


func move_towards(dir: Vector3, speed: float, delta: float) -> void:
	var effective := speed * status.speed_multiplier()
	velocity.x = move_toward(velocity.x, dir.x * effective, 30.0 * delta)
	velocity.z = move_toward(velocity.z, dir.z * effective, 30.0 * delta)


func brake(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0, 28.0 * delta)
	velocity.z = move_toward(velocity.z, 0, 28.0 * delta)


func take_hit(hit: HitInfo) -> bool:
	if ai_state == AIState.DEAD:
		return false
	if hit.from_player and player != null and is_instance_valid(player):
		hit.damage *= player.talent_damage_mult(hit, self)  # M07: Galvanize, Fuel the Fire, Searing Lance
	hit.damage *= status.damage_taken_multiplier()
	if not health.apply_hit(hit):
		return false
	status.apply_from_hit(hit)
	# Conductor's Oath: lightning damage on a Conductor arcs to all other
	# Conductors. Splash hits are flagged so they never chain again.
	if hit.type == HitInfo.DamageType.LIGHTNING and not hit.is_conductor_arc and status.is_conductor():
		_conductor_arc_out()
	return true


func _conductor_arc_out() -> void:
	var scene := get_tree().current_scene
	var my_chest := global_position + Vector3(0, 1.0, 0)
	# Duplicate: an arc kill mutates all_enemies mid-iteration.
	for other in all_enemies.duplicate():
		if other == self or not is_instance_valid(other) or other.ai_state == AIState.DEAD:
			continue
		if not other.status.is_conductor():
			continue
		if other.global_position.distance_to(global_position) > 14.0:
			continue
		VFX.lightning_arc(scene, my_chest, other.global_position + Vector3(0, 1.0, 0))
		var arc_hit := HitInfo.create(8.0, HitInfo.DamageType.LIGHTNING, HitInfo.Weight.LIGHT, global_position)
		arc_hit.is_conductor_arc = true
		other.take_hit(arc_hit)


func _on_damaged(hit: HitInfo) -> void:
	var color := HitInfo.type_color(hit.type)
	GameFeel.damage_number(global_position + Vector3(0, 1.8, 0), hit.damage, color, hit.is_crit)
	VFX.enemy_hit(get_tree().current_scene, global_position + Vector3(0, 1.0, 0))
	Sfx.play("enemy_hurt", global_position, -6.0, 0.15)

	var push := global_position - hit.source_position
	push.y = 0
	_knockback_velocity += push.normalized() * hit.knockback

	_squash()
	_flash_white()
	match hit.weight:
		HitInfo.Weight.MEDIUM:
			if not stagger_resist:
				_stagger(0.3)
		HitInfo.Weight.HEAVY:
			_stagger(0.6)


func _squash() -> void:
	if _squash_tween != null and _squash_tween.is_running():
		_squash_tween.kill()
	visual.scale = base_visual_scale * Vector3(1.15, 0.85, 1.15)
	_squash_tween = visual.create_tween()
	_squash_tween.tween_property(visual, "scale", base_visual_scale, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


var _flash_tween: Tween
var _flash_mats: Array[StandardMaterial3D] = []


## Instance a GLB body under `visual`, giving every surface a per-instance
## material (imported materials are shared across all instances of the model —
## without duplication one enemy's hit-flash would light up all of them).
## Returns false when the model file is absent so callers keep primitives.
func _setup_model_visual(path: String) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var model := (load(path) as PackedScene).instantiate() as Node3D
	# Blender -Y front maps to Godot +Z; our facing convention is -Z.
	model.rotation.y = PI
	visual.add_child(model)
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if mat == null:
				continue
			var dup := mat.duplicate() as StandardMaterial3D
			mi.set_surface_override_material(s, dup)
			if not dup.emission_enabled:
				_flash_mats.append(dup)
	return true


## M06 rigged body: instances the GLB under `visual` (same space as the old
## models), binds the per-instance atlas material (hit-flash list) and glow
## material (never flashed), and starts a CharacterAnimator. Surface 2, if
## present, is the telegraph weapon: returned for the subclass to own (its
## glow ramp must never be switched off by a hit flash). Returns null when the
## GLB is missing so callers keep their legacy visuals.
var animator: CharacterAnimator = null
## Weak list of live rig meshes for the "enemy_shadows" look/perf switch.
static var _rig_meshes: Array[WeakRef] = []
static var _shadow_switch_ready: bool = false


static func _apply_enemy_shadows(on: bool) -> void:
	var live: Array[WeakRef] = []
	for ref in _rig_meshes:
		var m := ref.get_ref() as MeshInstance3D
		if m != null:
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			live.append(ref)
	_rig_meshes = live


func _setup_rigged_visual(path: String, atlas_id: String, clip_profile: Dictionary, glow: Color) -> MeshInstance3D:
	var scene := ArtKit.rig_scene(path)
	if scene == null:
		return null
	var model := scene.instantiate() as Node3D
	model.rotation.y = PI
	var rig_root := Node3D.new()
	rig_root.name = "RigRoot"  # flinches go here, never on `visual` (gameplay facing)
	visual.add_child(rig_root)
	rig_root.add_child(model)
	var mesh := model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var body_mat := ArtKit.character_material(atlas_id)
	mesh.set_surface_override_material(0, body_mat)
	_flash_mats.append(body_mat)
	if mesh.mesh.get_surface_count() > 1:
		mesh.set_surface_override_material(1, ArtKit.glow_material(glow, ArtKit.number("emissive_caps.character_eyes", 3.0)))
	animator = CharacterAnimator.create(self, model, clip_profile)
	if not _shadow_switch_ready:
		_shadow_switch_ready = true
		LookDev.register(&"enemy_shadows", func(v: Variant) -> void: EnemyBase._apply_enemy_shadows(bool(v)), true)
	_rig_meshes.append(weakref(mesh))
	_apply_enemy_shadows(bool(LookDev.get_value(&"enemy_shadows", true)))
	return mesh


func _flash_white() -> void:
	# Pop every non-emissive body material to white for a few frames.
	if _flash_tween != null and _flash_tween.is_running():
		return
	var mats: Array[StandardMaterial3D] = _flash_mats
	if mats.is_empty():
		for child in visual.find_children("*", "MeshInstance3D", true, false):
			var mesh := (child as MeshInstance3D).mesh as PrimitiveMesh
			if mesh == null:
				continue
			var mat := mesh.material as StandardMaterial3D
			if mat == null or mat.emission_enabled:
				continue
			mats.append(mat)
	if mats.is_empty():
		return
	for mat in mats:
		mat.emission_enabled = true
		mat.emission = Color(1, 1, 1)
		mat.emission_energy_multiplier = 1.1
	_flash_tween = create_tween()
	_flash_tween.tween_interval(0.06)
	_flash_tween.tween_callback(func() -> void:
		for mat in mats:
			mat.emission_energy_multiplier = 0.0
			if not mat.has_meta(ArtKit.KEEP_EMISSION):
				mat.emission_enabled = false
	)


func _stagger(duration: float) -> void:
	# Interrupt whatever the enemy was doing, including attack wind-ups.
	_enter_state(AIState.STAGGER)
	_state_timer = -duration  # counts up to 0, then subclass logic resumes
	_on_interrupted()


func _on_interrupted() -> void:
	pass  # subclasses clean up telegraphs etc.


func _on_died() -> void:
	# M07 Wildfire: a Burning enemy's death spreads its Burn.
	if status.has_burn() and player != null and is_instance_valid(player) and player.has_power(&"wildfire"):
		_spread_burn()
	_enter_state(AIState.DEAD)
	collision_layer = 0
	set_physics_process(false)
	VFX.death_burst(get_tree().current_scene, global_position + Vector3(0, 0.9, 0), body_color)
	Sfx.play("enemy_death", global_position, -3.0, 0.12)
	enemy_died.emit(self)
	# Quick shrink-out instead of a corpse; keeps the lab readable.
	var tw := create_tween()
	tw.tween_property(visual, "scale", base_visual_scale * 0.05, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)


const WILDFIRE_RADIUS := 3.0


func _spread_burn() -> void:
	VFX.ground_ring(get_tree().current_scene, global_position, ArtKit.color("color_roles.fire.body"), WILDFIRE_RADIUS, 0.3)
	var dps := StatusEffectComponent.BURN_DPS * (1.0 + player.stat(&"burn_pct") / 100.0)
	for other in all_enemies:
		if other != self and is_instance_valid(other) and other.ai_state != AIState.DEAD \
				and other.global_position.distance_to(global_position) <= WILDFIRE_RADIUS:
			other.status.apply_burn(dps)


## Shared helper: chunky material.
static func flat_material(color: Color, emissive: bool = false, energy: float = 1.5) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.75
	if emissive:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = energy
	return mat
