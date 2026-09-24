class_name Player
extends CharacterBody3D
## The Runebreaker. Movement, dodge, Rune Cleave (melee), Ember Lance
## (fire projectile), Earthbreaker (Resonance-fueled slam).

signal health_changed(current: float, maximum: float)
signal resonance_changed(current: float, maximum: float)
signal cooldowns_changed
signal player_died
## Presentation hook (M06 CharacterAnimator): an ability just started.
signal action_started(action: StringName)
## M07b: the set of known abilities changed (learned at the trainer, restored
## from the save, or a talent unlock toggled).
signal abilities_changed
signal ability_learned(id: StringName)
signal gold_changed(total: int, delta: int)

enum State { MOVE, DODGE, MELEE, CAST, SLAM, STORM_STEP }

const MAX_SPEED := 6.8
const ACCEL := 60.0
const DECEL := 55.0
const ROTATION_SPEED := 14.0
const GRAVITY := 24.0

const DODGE_SPEED := 15.0
const DODGE_DURATION := 0.24
const DODGE_RECOVERY := 0.08
const DODGE_COOLDOWN := 0.55
const DODGE_IFRAMES := 0.26  # user-tuned: a touch past the dash itself

## Default class resource cap; the live value is max_resource() (ClassData).
const MAX_RESONANCE := 100.0
const INPUT_BUFFER := 0.22

const EmberProjectile := preload("res://scripts/projectiles/ember_lance_projectile.gd")

var state: State = State.MOVE
var resonance: float = 0.0
var god_mode: bool = false
## Set by InventoryUI while its panel is open: combat input ignored.
var input_locked: bool = false

var camera_rig: CameraRig = null
var targeting: TargetingSystem = null
var health: HealthComponent
var equipment: Equipment
var progression: Progression

## M07b class as data. ZoneBase sets it before add_child; tests that build a
## bare Player.new() get the default class in _ready.
var class_data: ClassData = null
## id -> AbilityData for every ability of the class (HUD order in class_data).
var abilities: Dictionary = {}
## Ability ids this character has learned (START + trainer). TALENT abilities
## are known through their power instead; dodge is always known. See knows().
var known_abilities: Array[StringName] = []
var gold: int = 0
## action id -> Callable that tries to start it (built in _register_actions).
var _actions: Dictionary = {}
## M07b input seam: Player reads only `intent`, which `input_source` fills
## once per physics tick (LocalInputSource = this machine's keyboard/mouse;
## a scripted or network source drives the same code).
var input_source: InputSource = null
var intent: PlayerIntent = PlayerIntent.new()
## M07b: this machine's hero. Presentation that belongs to *a* player (camera
## shake, impulses, denied clicks, pickup toasts) checks it; world presentation
## (boss slams, positional SFX) does not. Remote heroes will be spawned false.
var is_local: bool = true
## Reserved for co-op (Godot's high-level multiplayer: 1 = server / local).
var peer_id: int = 1

# Ability tuning: derived caches of `abilities`, kept because the Runebreaker
# code and the tests read them by name (player.cleave.startup ...).
var cleave: AbilityData
var ember: AbilityData
var earthbreaker: AbilityData
var storm_step: AbilityData
var chain_spark: AbilityData
var fracture_rune: AbilityData
var runic_guard: AbilityData        # M07 talent ability 7 (key 5)
var resonance_burst: AbilityData    # M07 talent ability 8 (key 6)

## M07 barrier (Runic Guard, Unbroken): absorbs damage before health.
var barrier: float = 0.0
var _barrier_time: float = 0.0
const UNBROKEN_BARRIER := 15.0
const UNBROKEN_COOLDOWN := 8.0

var _cooldowns: Dictionary = {}  # id -> seconds remaining
var _state_timer: float = 0.0
var _dodge_dir: Vector3 = Vector3.ZERO
var _melee_flip: bool = false
var _melee_did_hit_window: bool = false
var _buffered_action: StringName = &""
var _buffer_timer: float = 0.0
var _footstep_accum: float = 0.0
var _knockback_velocity: Vector3 = Vector3.ZERO
var _hitstop_left: float = 0.0

var _visual: Node3D
var _weapon_pivot: Node3D


func _ready() -> void:
	collision_layer = 0b10
	collision_mask = 0b101
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.42
	capsule.height = 1.7
	col.shape = capsule
	col.position = Vector3(0, 0.85, 0)
	add_child(col)

	health = HealthComponent.new()
	health.max_health = 100.0
	add_child(health)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	health.health_changed.connect(func(c: float, m: float) -> void: health_changed.emit(c, m))

	equipment = Equipment.new()
	equipment.name = "Equipment"
	equipment.player = self
	add_child(equipment)
	progression = Progression.new()
	progression.name = "Progression"
	add_child(progression)
	progression.talents_changed.connect(equipment._apply_max_hp)  # levels + Runic Plate

	Hurtbox.create(self, 0b1000, 0.5, 1.75, 0.85)

	if class_data == null:
		class_data = ClassData.default_class()
	progression.class_id = class_data.id
	if input_source == null:
		input_source = LocalInputSource.new()
	_load_abilities()
	_register_actions()
	if known_abilities.is_empty():
		known_abilities = class_data.starting_abilities.duplicate()
	_build_visual()
	floor_snap_length = 0.4


func _load_abilities() -> void:
	abilities.clear()
	for data in class_data.abilities:
		if data != null:
			abilities[data.id] = data
	cleave = ability(&"rune_cleave")
	ember = ability(&"ember_lance")
	earthbreaker = ability(&"earthbreaker")
	storm_step = ability(&"storm_step")
	chain_spark = ability(&"chain_spark")
	fracture_rune = ability(&"fracture_rune")
	runic_guard = ability(&"runic_guard")
	resonance_burst = ability(&"resonance_burst")


## The Runebreaker's action table. A second class overrides this (and
## _load_abilities / _anim_profile) and inherits the chassis.
func _register_actions() -> void:
	_actions = {
		&"dodge": try_dodge,
		&"rune_cleave": try_melee,
		&"ember_lance": try_ember,
		&"earthbreaker": try_earthbreaker,
		&"storm_step": try_storm_step,
		&"chain_spark": try_chain_spark,
		&"fracture_rune": try_fracture_rune,
		&"runic_guard": try_runic_guard,
		&"resonance_burst": try_resonance_burst,
	}


func ability(id: StringName) -> AbilityData:
	return abilities.get(id) as AbilityData


func max_resource() -> float:
	return class_data.max_resource if class_data != null else MAX_RESONANCE


# ---------------------------------------------------------------------------
# M07b: known abilities and gold
# ---------------------------------------------------------------------------

## Can this character use `id` right now (ignoring cooldown and state)?
## Dodge always; TALENT abilities while their power is held; the rest once
## learned (start kit or trainer).
func knows(id: StringName) -> bool:
	if id == &"dodge":
		return true
	var data := ability(id)
	if data == null:
		return false
	if data.unlock == AbilityData.Unlock.TALENT:
		return data.unlock_power != &"" and has_power(data.unlock_power)
	return known_abilities.has(id)


## Learn a START/TRAINER ability of this class. False if unknown id, a TALENT
## ability, or already known.
func learn_ability(id: StringName) -> bool:
	var data := ability(id)
	if data == null or data.unlock == AbilityData.Unlock.TALENT or known_abilities.has(id):
		return false
	known_abilities.append(id)
	abilities_changed.emit()
	ability_learned.emit(id)
	return true


## Tests, captures and the debug overlay: know the whole trainer kit at once.
func debug_learn_all() -> void:
	var changed := false
	for data in class_data.trainer_abilities():
		if not known_abilities.has(data.id):
			known_abilities.append(data.id)
			changed = true
	if changed:
		abilities_changed.emit()


# ---------------------------------------------------------------------------
# M07b: presentation that belongs to this player only
# ---------------------------------------------------------------------------

func feel_shake(amount: float) -> void:
	if is_local:
		GameFeel.camera_shake(amount)


func feel_impulse(dir: Vector3, strength: float) -> void:
	if is_local:
		GameFeel.camera_impulse(dir, strength)


func ui_denied() -> void:
	if is_local:
		Sfx.play_ui("ui_denied", -8.0)


func add_gold(amount: int) -> void:
	if amount == 0:
		return
	gold = maxi(gold + amount, 0)
	gold_changed.emit(gold, amount)


func spend_gold(amount: int) -> bool:
	if amount < 0 or gold < amount:
		return false
	gold -= amount
	gold_changed.emit(gold, -amount)
	return true


func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	if _build_rigged_visual():
		return

	const MODEL_PATH := "res://assets/models/player_runebreaker.glb"
	if ResourceLoader.exists(MODEL_PATH):
		var model := (load(MODEL_PATH) as PackedScene).instantiate() as Node3D
		model.rotation.y = PI  # Blender -Y front → Godot +Z; we face -Z
		_visual.add_child(model)
		_build_weapon()
		return

	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.32, 0.34, 0.44)
	iron.roughness = 0.7
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(0.16, 0.55, 0.55)
	accent.roughness = 0.5
	var rune_glow := StandardMaterial3D.new()
	rune_glow.albedo_color = Color(1.0, 0.6, 0.25)
	rune_glow.emission_enabled = true
	rune_glow.emission = Color(1.0, 0.55, 0.2)
	rune_glow.emission_energy_multiplier = 1.6
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.85, 0.68, 0.55)

	# Chunky armored silhouette: wide torso, big pauldrons, small head.
	var torso := MeshInstance3D.new()
	var torso_mesh := BoxMesh.new()
	torso_mesh.size = Vector3(0.72, 0.62, 0.44)
	torso_mesh.material = iron
	torso.mesh = torso_mesh
	torso.position = Vector3(0, 1.05, 0)
	_visual.add_child(torso)

	var belt := MeshInstance3D.new()
	var belt_mesh := BoxMesh.new()
	belt_mesh.size = Vector3(0.5, 0.28, 0.36)
	belt_mesh.material = accent
	belt.mesh = belt_mesh
	belt.position = Vector3(0, 0.68, 0)
	_visual.add_child(belt)

	var legs := MeshInstance3D.new()
	var legs_mesh := BoxMesh.new()
	legs_mesh.size = Vector3(0.44, 0.55, 0.3)
	legs_mesh.material = iron
	legs.mesh = legs_mesh
	legs.position = Vector3(0, 0.3, 0)
	_visual.add_child(legs)

	for side: float in [-1.0, 1.0]:
		var pauldron := MeshInstance3D.new()
		var pmesh := BoxMesh.new()
		pmesh.size = Vector3(0.28, 0.24, 0.34)
		pmesh.material = accent
		pauldron.mesh = pmesh
		pauldron.position = Vector3(side * 0.48, 1.32, 0)
		_visual.add_child(pauldron)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.17
	head_mesh.height = 0.34
	head_mesh.material = skin
	head.mesh = head_mesh
	head.position = Vector3(0, 1.56, 0)
	_visual.add_child(head)

	# Rune sigil on the chest — the class identity glow.
	var sigil := MeshInstance3D.new()
	var sigil_mesh := BoxMesh.new()
	sigil_mesh.size = Vector3(0.16, 0.22, 0.05)
	sigil_mesh.material = rune_glow
	sigil.mesh = sigil_mesh
	sigil.position = Vector3(0, 1.08, -0.23)
	_visual.add_child(sigil)
	_build_weapon()


## Legacy alias; the live rig comes from class_data.rig_path.
const RIG_PATH := "res://assets/models/chars/runebreaker.glb"
var animator: CharacterAnimator = null
var _rune_glow: StandardMaterial3D


## M06 rigged Runebreaker (sword is part of the skinned mesh on hand.R). The
## rig sits on a RigRoot below `_visual` — flinches go there, never on
## `_visual`, whose yaw is the gameplay facing. `_weapon_pivot` becomes an
## invisible stand-in so the legacy ability tweens stay untouched. Returns
## false when the GLB is missing (legacy visuals then).
func _build_rigged_visual() -> bool:
	var scene := ArtKit.rig_scene(class_data.rig_path if class_data.rig_path != "" else RIG_PATH)
	if scene == null:
		return false
	var model := scene.instantiate() as Node3D
	model.rotation.y = PI
	var rig_root := Node3D.new()
	rig_root.name = "RigRoot"
	_visual.add_child(rig_root)
	rig_root.add_child(model)
	var mesh := model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	_body_mat = ArtKit.character_material(class_data.material_id if class_data.material_id != "" else "runebreaker")
	mesh.set_surface_override_material(0, _body_mat)
	_rune_glow = ArtKit.glow_material(ArtKit.color("color_roles.resonance.body"), 1.2)
	mesh.set_surface_override_material(1, _rune_glow)
	if mesh.mesh.get_surface_count() > 2:
		_rig_mesh = mesh
		equipment.changed.connect(_refresh_blade)
		_refresh_blade()
	resonance_changed.connect(_on_resonance_glow)
	animator = CharacterAnimator.create(self, model, _anim_profile())
	if animator != null:
		animator.full_rate = true  # the hero never drops animation rate
		health.damaged.connect(func(_hit: HitInfo) -> void: animator.flinch())
	_weapon_pivot = Node3D.new()
	_weapon_pivot.name = "WeaponPivotStandIn"
	_visual.add_child(_weapon_pivot)
	return true


## CharacterAnimator profile of this class's rig: action_started names -> clips.
## A second class overrides this together with _register_actions.
func _anim_profile() -> Dictionary:
	return {
		"idle": &"idle", "run": &"run", "run_speed": MAX_SPEED, "layered": true,
		"actions": {&"dodge": &"dodge", &"cleave_l": &"cleave_l", &"cleave_r": &"cleave_r",
			&"ember": &"ember", &"earthbreaker": &"earthbreaker_rise",
			&"earthbreaker_impact": &"earthbreaker_impact", &"storm_step": &"storm_step",
			&"resonance_burst": &"resonance_burst"},
		# instant casts keep the legs running: upper-body layer only
		"upper": {&"chain_spark": &"chain_spark", &"fracture_rune": &"fracture_rune", &"runic_guard": &"runic_guard"},
		"flinch": &"flinch",
		# back in MOVE and moving: the run takes over an action's follow-through
		"free": func() -> bool: return state == State.MOVE,
	}


var _body_mat: StandardMaterial3D
var _rig_mesh: MeshInstance3D
var _cindermaw_mat: StandardMaterial3D


## M06 C6: the blade surface shows the equipped legendary weapon — Cindermaw's
## basalt blade with a molten, breathing edge; any other weapon the rune steel.
func _refresh_blade() -> void:
	if _rig_mesh == null:
		return
	var weapon: ItemData = equipment.equipped.get(ItemData.Slot.WEAPON)
	if weapon != null and weapon.legendary_id == &"cindermaw":
		if _cindermaw_mat == null:
			_cindermaw_mat = StandardMaterial3D.new()
			_cindermaw_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
			_cindermaw_mat.albedo_color = ArtKit.color("palettes.highlands.basalt.2")
			_cindermaw_mat.emission_enabled = true
			_cindermaw_mat.emission = ArtKit.color("color_roles.fire.body")
			_cindermaw_mat.emission_energy_multiplier = 0.9
			_cindermaw_mat.set_meta(ArtKit.KEEP_EMISSION, true)
			var breathe := create_tween().set_loops()
			breathe.tween_property(_cindermaw_mat, "emission_energy_multiplier", 1.5, 0.8).set_trans(Tween.TRANS_SINE)
			breathe.tween_property(_cindermaw_mat, "emission_energy_multiplier", 0.7, 0.9).set_trans(Tween.TRANS_SINE)
		_rig_mesh.set_surface_override_material(2, _cindermaw_mat)
	else:
		_rig_mesh.set_surface_override_material(2, _body_mat)


## The armor runes are the in-world Resonance meter: dim when empty, bright
## rune gold when full.
func _on_resonance_glow(current: float, maximum: float) -> void:
	if _rune_glow != null:
		_rune_glow.emission_energy_multiplier = lerpf(0.9, 3.2, clampf(current / maximum, 0.0, 1.0))


## Broad rune blade on the right hand, swung via pivot tweens. Always
## code-built: abilities animate this pivot directly.
func _build_weapon() -> void:
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.32, 0.34, 0.44)
	iron.roughness = 0.7
	var rune_glow := StandardMaterial3D.new()
	rune_glow.albedo_color = Color(1.0, 0.6, 0.25)
	rune_glow.emission_enabled = true
	rune_glow.emission = Color(1.0, 0.55, 0.2)
	rune_glow.emission_energy_multiplier = 1.6

	_weapon_pivot = Node3D.new()
	_weapon_pivot.name = "WeaponPivot"
	_weapon_pivot.position = Vector3(0.45, 1.15, 0)
	_visual.add_child(_weapon_pivot)

	var blade := MeshInstance3D.new()
	var blade_mesh := BoxMesh.new()
	blade_mesh.size = Vector3(0.1, 0.05, 1.15)
	blade_mesh.material = iron
	blade.mesh = blade_mesh
	blade.position = Vector3(0, 0, -0.65)
	_weapon_pivot.add_child(blade)
	var edge := MeshInstance3D.new()
	var edge_mesh := BoxMesh.new()
	edge_mesh.size = Vector3(0.04, 0.06, 0.9)
	edge_mesh.material = rune_glow
	edge.mesh = edge_mesh
	edge.position = Vector3(0, 0, -0.7)
	_weapon_pivot.add_child(edge)
	_weapon_pivot.rotation_degrees = Vector3(-25, 15, 0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_cursor"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func apply_hitstop(duration: float) -> void:
	_hitstop_left = maxf(_hitstop_left, duration)


func _physics_process(delta: float) -> void:
	if _hitstop_left > 0.0:
		_hitstop_left -= delta
		return
	for key: StringName in _cooldowns.keys():
		_cooldowns[key] = maxf(_cooldowns[key] - delta, 0.0)
	if _barrier_time > 0.0:
		_barrier_time -= delta
		if _barrier_time <= 0.0:
			barrier = 0.0
	if _buffer_timer > 0.0:
		_buffer_timer -= delta
		if _buffer_timer <= 0.0:
			_buffered_action = &""

	intent.clear()
	if input_source != null:
		input_source.poll(intent, self)
	_read_action_input()

	match state:
		State.MOVE:
			_process_move(delta)
		State.DODGE:
			_process_dodge(delta)
		State.MELEE:
			_process_melee(delta)
		State.CAST:
			_process_cast(delta)
		State.SLAM:
			_process_slam(delta)
		State.STORM_STEP:
			_process_storm_step(delta)

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	velocity += _knockback_velocity
	move_and_slide()
	velocity -= _knockback_velocity
	_knockback_velocity = _knockback_velocity.lerp(Vector3.ZERO, minf(8.0 * delta, 1.0))


## Central ability hit roll: applies equipment damage and crit bonuses.
## Summed value of a stat key from equipment and progression (level bonuses,
## talents). Every ability hook reads stats through here.
func stat(key: StringName) -> float:
	return equipment.stat(key) + (progression.stat(key) if progression != null else 0.0)


## Legendary power (equipment) or behavior talent (progression).
func has_power(id: StringName) -> bool:
	return equipment.has_power(id) or (progression != null and progression.has_power(id))


func roll_ability_hit(data: AbilityData) -> HitInfo:
	var damage_mult := 1.0 + stat(&"damage_pct") / 100.0
	var bonus_crit := stat(&"crit_pct") / 100.0
	var hit := data.roll_hit(global_position, damage_mult, bonus_crit)
	hit.from_player = true
	hit.attacker_id = get_instance_id()  # M07b: talent mults, XP and loot follow the attacker
	hit.ability = data.id
	hit.burn_mult = 1.0 + stat(&"burn_pct") / 100.0
	return hit


## M07 conditional talent damage, applied when a player hit lands.
func talent_damage_mult(hit: HitInfo, enemy: EnemyBase) -> float:
	var pct := 0.0
	if enemy.status.has_shock():
		pct += stat(&"shocked_dmg_pct")
	if enemy.status.has_burn():
		pct += stat(&"burning_dmg_pct")
	if hit.ability == &"ember_lance":
		pct += stat(&"ember_dmg_pct")
	return 1.0 + pct / 100.0


## Effective cooldown of `id` with a base of `base` seconds: global reduction,
## plus the dodge / Storm Step specific ones, clamped to 35-100 %. Pure, so
## the character sheet shows the same number the game uses.
func cooldown_for(id: StringName, base: float) -> float:
	var mult := 1.0 - stat(&"cooldown_pct") / 100.0
	if id == &"dodge":
		mult *= 1.0 - stat(&"dodge_cd_pct") / 100.0
	elif id == &"storm_step":
		mult *= 1.0 - stat(&"storm_cd_pct") / 100.0
	return base * clampf(mult, 0.35, 1.0)


## Central cooldown setter.
func _set_cooldown(id: StringName, base: float) -> void:
	_cooldowns[id] = cooldown_for(id, base)


func earthbreaker_cost() -> float:
	return maxf(earthbreaker.resonance_cost - stat(&"eb_cost_reduce"), 10.0)


## This tick's pressed actions (from the intent) -> try or buffer. Unknown
## abilities never reach the buffer, so a locked key can't queue an action.
func _read_action_input() -> void:
	if input_locked:
		return
	for action in intent.pressed:
		_try_or_buffer(action)


func _try_or_buffer(action: StringName) -> void:
	if not knows(action):
		return
	if not _try_action(action):
		_buffered_action = action
		_buffer_timer = INPUT_BUFFER


func _consume_buffer() -> void:
	if _buffered_action != &"":
		var action := _buffered_action
		_buffered_action = &""
		_buffer_timer = 0.0
		_try_action(action)


func _try_action(action: StringName) -> bool:
	if not knows(action) or not _actions.has(action):
		return false
	return (_actions[action] as Callable).call()


# ---------------------------------------------------------------------------
# Movement
# ---------------------------------------------------------------------------

## Movement direction of the current tick (world-space, flat), as polled
## into the intent by the input source.
func _move_input_dir() -> Vector3:
	return intent.move_dir


func _process_move(delta: float) -> void:
	var dir := _move_input_dir()
	var target_vel := dir * MAX_SPEED * (1.0 + stat(&"move_pct") / 100.0)
	var rate := ACCEL if dir != Vector3.ZERO else DECEL
	velocity.x = move_toward(velocity.x, target_vel.x, rate * delta)
	velocity.z = move_toward(velocity.z, target_vel.z, rate * delta)
	if dir != Vector3.ZERO:
		_face_direction(dir, delta)
		_footsteps(delta)


func _face_direction(dir: Vector3, delta: float) -> void:
	var target_yaw := atan2(-dir.x, -dir.z)
	_visual.rotation.y = lerp_angle(_visual.rotation.y, target_yaw, minf(ROTATION_SPEED * delta, 1.0))


func _face_aim_instant() -> void:
	var aim := aim_direction()
	_visual.rotation.y = atan2(-aim.x, -aim.z)


## Melee snaps to the soft target when one is in reach — swinging at the
## marker the player can see beats swinging at the camera ray.
func _face_melee_target() -> void:
	var t: EnemyBase = targeting.current if targeting != null else null
	if t != null and is_instance_valid(t) \
			and t.global_position.distance_to(global_position) <= 4.0:
		var dir := t.global_position - global_position
		dir.y = 0.0
		if dir.length() > 0.05:
			dir = dir.normalized()
			_visual.rotation.y = atan2(-dir.x, -dir.z)
			return
	_face_aim_instant()


func facing() -> Vector3:
	return -_visual.global_transform.basis.z


func aim_direction() -> Vector3:
	if camera_rig == null:
		return facing()
	var exclude: Array[RID] = [get_rid()]
	var aim_point := camera_rig.get_aim_point(exclude)
	# The camera looks down at the hero, so its ray meets the floor a few
	# metres ahead: aim at muzzle height above that spot instead of into it
	# (user feedback 2026-09-24). Level on flat ground, follows slopes.
	if camera_rig.last_aim_on_floor:
		aim_point.y += MUZZLE_HEIGHT
	var from := muzzle_position()
	var dir := aim_point - from
	if dir.length() < 1.0:
		dir = -camera_rig.camera.global_transform.basis.z
	dir.y = clampf(dir.y / maxf(dir.length(), 0.01), -0.6, 0.6) * dir.length()
	return dir.normalized()


const MUZZLE_HEIGHT := 1.2


func muzzle_position() -> Vector3:
	return global_position + Vector3(0, MUZZLE_HEIGHT, 0) + facing() * 0.5


func _footsteps(delta: float) -> void:
	_footstep_accum += delta * velocity.length()
	if _footstep_accum >= 2.6:
		_footstep_accum = 0.0
		Sfx.play("footstep", global_position, -12.0, 0.15)


# ---------------------------------------------------------------------------
# Dodge
# ---------------------------------------------------------------------------

func try_dodge() -> bool:
	if state == State.DODGE or _cooldowns.get(&"dodge", 0.0) > 0.0:
		return false
	# Dodge cancels melee recovery and cast startup — the trust rule.
	if state == State.SLAM and _state_timer < earthbreaker.startup + earthbreaker.active:
		return false
	# Dodging out of a Storm Step still ends the dash properly (collision mask,
	# path zap) — otherwise the player kept phasing through enemies.
	if state == State.STORM_STEP:
		_resolve_storm_step()
	var dir := _move_input_dir()
	if dir == Vector3.ZERO:
		dir = facing()
	_dodge_dir = dir
	state = State.DODGE
	_state_timer = 0.0
	_set_cooldown(&"dodge", DODGE_COOLDOWN)
	health.invulnerable = true
	_visual.rotation.y = atan2(-dir.x, -dir.z)
	VFX.dodge_dust(get_tree().current_scene, global_position, dir)
	Sfx.play("dodge", global_position, -4.0)
	cooldowns_changed.emit()
	action_started.emit(&"dodge")
	return true


func _process_dodge(delta: float) -> void:
	_state_timer += delta
	if _state_timer >= DODGE_IFRAMES:
		health.invulnerable = god_mode
	if _state_timer < DODGE_DURATION:
		# Ease-out dash: strong start, soft landing.
		var t := _state_timer / DODGE_DURATION
		var speed := DODGE_SPEED * (1.0 - t * t * 0.7)
		velocity.x = _dodge_dir.x * speed
		velocity.z = _dodge_dir.z * speed
	elif _state_timer < DODGE_DURATION + DODGE_RECOVERY:
		velocity.x = move_toward(velocity.x, 0, DECEL * delta)
		velocity.z = move_toward(velocity.z, 0, DECEL * delta)
	else:
		state = State.MOVE
		_consume_buffer()


# ---------------------------------------------------------------------------
# Rune Cleave (melee)
# ---------------------------------------------------------------------------

func try_melee() -> bool:
	if state != State.MOVE:
		return false
	state = State.MELEE
	_state_timer = 0.0
	_melee_did_hit_window = false
	_melee_flip = not _melee_flip
	_face_melee_target()
	_animate_cleave()
	Sfx.play("swing", global_position, -2.0, 0.1)
	action_started.emit(&"cleave_l" if _melee_flip else &"cleave_r")
	return true


func _animate_cleave() -> void:
	var side := 1.0 if _melee_flip else -1.0
	_weapon_pivot.rotation_degrees = Vector3(-10, side * 70.0, 0)
	var tw := _weapon_pivot.create_tween()
	tw.tween_property(_weapon_pivot, "rotation_degrees:y", -side * 80.0, cleave.startup + cleave.active) \
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	tw.tween_property(_weapon_pivot, "rotation_degrees", Vector3(-25, 15, 0), cleave.recovery) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _process_melee(delta: float) -> void:
	_state_timer += delta
	# Slight forward drift keeps swings aggressive without lunging.
	var fwd := facing()
	velocity.x = fwd.x * 1.6
	velocity.z = fwd.z * 1.6
	if not _melee_did_hit_window and _state_timer >= cleave.startup:
		_melee_did_hit_window = true
		_do_cleave_hit()
	if _state_timer >= cleave.startup + cleave.active + cleave.recovery:
		state = State.MOVE
		_consume_buffer()


func _do_cleave_hit() -> void:
	var fwd := facing()
	var center := global_position + Vector3(0, 1.0, 0) + fwd * 1.2
	var radius := 1.5 * (1.0 + stat(&"cleave_radius_pct") / 100.0)
	var hits := _query_hurtboxes(center, radius)
	var scene := get_tree().current_scene
	# Slash arc regardless of contact — the swing itself must read.
	VFX.melee_slash(scene, global_position + Vector3(0, 1.1, 0) + fwd * 0.9, fwd, _melee_flip)
	var any_hit := false
	for enemy: Node in hits:
		var hit := roll_ability_hit(cleave)
		if enemy.has_method(&"take_hit") and enemy.call(&"take_hit", hit):
			any_hit = true
			gain_resonance(cleave.resonance_gain_per_hit)
			VFX.melee_impact(scene, (enemy as Node3D).global_position + Vector3(0, 1.0, 0), fwd)
	if any_hit:
		Sfx.play("impact_flesh", center, 0.0, 0.12)
		var stop_targets: Array = [self]
		stop_targets.append_array(hits)
		GameFeel.hitstop(stop_targets, 0.045)
		feel_impulse(fwd, 0.08)
	cooldowns_changed.emit()


func _query_hurtboxes(center: Vector3, radius: float) -> Array[Node]:
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), center)
	query.collision_mask = 0b10000  # enemy hurtboxes
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var found: Array[Node] = []
	for result: Dictionary in space.intersect_shape(query, 16):
		var hb := result["collider"] as Hurtbox
		if hb != null and hb.owner_entity != null and not found.has(hb.owner_entity):
			found.append(hb.owner_entity)
	return found


# ---------------------------------------------------------------------------
# Ember Lance
# ---------------------------------------------------------------------------

func try_ember() -> bool:
	if not knows(&"ember_lance") or state != State.MOVE or _cooldowns.get(&"ember_lance", 0.0) > 0.0:
		return false
	state = State.CAST
	_state_timer = 0.0
	_set_cooldown(&"ember_lance", ember.cooldown)
	_face_aim_instant()
	VFX.ember_cast(get_tree().current_scene, muzzle_position())
	Sfx.play("ember_cast", global_position, -3.0)
	cooldowns_changed.emit()
	action_started.emit(&"ember")
	return true


func _process_cast(delta: float) -> void:
	_state_timer += delta
	velocity.x = move_toward(velocity.x, 0, DECEL * 2.0 * delta)
	velocity.z = move_toward(velocity.z, 0, DECEL * 2.0 * delta)
	_face_aim_instant()
	if _state_timer >= ember.startup:
		_fire_ember()
		state = State.MOVE
		_consume_buffer()


func _fire_ember() -> void:
	var proj := EmberProjectile.new()
	proj.setup(ember, aim_direction(), self)
	# Position before add_child: spawning at the scene origin for even one
	# frame overlaps the floor and detonates the projectile instantly.
	proj.position = muzzle_position()
	get_tree().current_scene.add_child(proj)
	feel_impulse(-aim_direction(), 0.05)
	Sfx.play("ember_fire", muzzle_position(), -2.0, 0.1)


# ---------------------------------------------------------------------------
# Earthbreaker
# ---------------------------------------------------------------------------

func try_earthbreaker() -> bool:
	if not knows(&"earthbreaker") or state != State.MOVE or _cooldowns.get(&"earthbreaker", 0.0) > 0.0:
		return false
	if resonance < earthbreaker_cost():
		ui_denied()
		return false
	state = State.SLAM
	_state_timer = 0.0
	_set_cooldown(&"earthbreaker", earthbreaker.cooldown)
	spend_resonance(earthbreaker_cost())
	# Anticipation: rise + weapon raised overhead.
	var tw := _weapon_pivot.create_tween()
	tw.tween_property(_weapon_pivot, "rotation_degrees", Vector3(-120, 0, 0), earthbreaker.startup) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	velocity.y = 7.0
	Sfx.play("earthbreaker_windup", global_position, -3.0)
	cooldowns_changed.emit()
	action_started.emit(&"earthbreaker")
	return true


func _process_slam(delta: float) -> void:
	_state_timer += delta
	velocity.x = move_toward(velocity.x, 0, DECEL * delta)
	velocity.z = move_toward(velocity.z, 0, DECEL * delta)
	if _state_timer >= earthbreaker.startup and _state_timer - delta < earthbreaker.startup:
		velocity.y = -22.0  # slam down hard
		var tw := _weapon_pivot.create_tween()
		tw.tween_property(_weapon_pivot, "rotation_degrees", Vector3(30, 0, 0), 0.08)
		tw.tween_property(_weapon_pivot, "rotation_degrees", Vector3(-25, 15, 0), 0.4) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if _state_timer >= earthbreaker.startup + earthbreaker.active:
		if is_on_floor() or _state_timer > earthbreaker.startup + 0.5:
			_do_slam_hit()
			state = State.MOVE
			_consume_buffer()


func _do_slam_hit() -> void:
	action_started.emit(&"earthbreaker_impact")  # presentation: landing clip
	var scene := get_tree().current_scene
	var pos := global_position
	VFX.earthbreaker_slam(scene, pos, earthbreaker.aoe_radius)
	Sfx.play("earthbreaker_impact", pos, 2.0, 0.06)
	feel_shake(0.55)
	var hits := _query_hurtboxes(pos + Vector3(0, 0.5, 0), earthbreaker.aoe_radius)
	for enemy: Node in hits:
		var hit := roll_ability_hit(earthbreaker)
		hit.source_position = pos
		if has_power(&"molten_core"):
			hit.applies_burn = true  # M07 Molten Core
		enemy.call(&"take_hit", hit)
	if not hits.is_empty():
		GameFeel.hitstop(hits, 0.07)
	# Glacier Heart: the slam leaves a chilling frost field.
	if has_power(&"glacier_heart"):
		var field := FrostField.new()
		field.position = ZoneBase.ground_under(self, pos, 0.02)
		scene.add_child(field)


# ---------------------------------------------------------------------------
# Storm Step
# ---------------------------------------------------------------------------

const STORM_STEP_SPEED := 50.0  # ~6m over the 0.12s active window

var _dash_dir: Vector3 = Vector3.ZERO
var _dash_start: Vector3 = Vector3.ZERO
var _dash_time: float = 0.12  # active window; shorter for close gap-closes


func try_storm_step() -> bool:
	if not knows(&"storm_step") or state != State.MOVE or _cooldowns.get(&"storm_step", 0.0) > 0.0:
		return false
	# Direction priority (user-tuned):
	# 1. Held movement input — steering wins ("I'm dashing where I'm running").
	# 2. Tab target the camera is looking at — gap-closer that lands in melee
	#    range instead of overshooting through the enemy.
	# 3. Camera aim direction.
	var dash_dist := storm_step.active * STORM_STEP_SPEED
	var dir := _move_input_dir()
	if dir == Vector3.ZERO:
		var target: EnemyBase = targeting.current if targeting != null else null
		if target != null and is_instance_valid(target) and target.ai_state != EnemyBase.AIState.DEAD:
			var to_target := target.global_position - global_position
			to_target.y = 0.0
			var cam_fwd := -(camera_rig.get_flat_basis().z) if camera_rig != null else facing()
			if to_target.length() > 0.5 and cam_fwd.dot(to_target.normalized()) > 0.4:
				dir = to_target.normalized()
				dash_dist = clampf(to_target.length() - 1.3, 1.5, dash_dist)
	if dir == Vector3.ZERO:
		var aim := aim_direction()
		dir = Vector3(aim.x, 0, aim.z).normalized()
	if dir == Vector3.ZERO and camera_rig != null:
		dir = -(camera_rig.get_flat_basis().z)
	if dir == Vector3.ZERO:
		dir = facing()
	_dash_dir = dir
	_dash_time = dash_dist / STORM_STEP_SPEED
	_dash_start = global_position
	state = State.STORM_STEP
	_state_timer = 0.0
	_set_cooldown(&"storm_step", storm_step.cooldown)
	collision_mask = 0b001  # phase through enemies during the dash
	_visual.rotation.y = atan2(-dir.x, -dir.z)
	VFX.flash(get_tree().current_scene, global_position + Vector3(0, 1.0, 0), Color(0.8, 0.9, 1.0), 1.0, 0.1)
	Sfx.play("storm_step", global_position, -1.0, 0.08)
	cooldowns_changed.emit()
	action_started.emit(&"storm_step")
	return true


func _process_storm_step(delta: float) -> void:
	_state_timer += delta
	if _state_timer < _dash_time:
		velocity.x = _dash_dir.x * STORM_STEP_SPEED
		velocity.z = _dash_dir.z * STORM_STEP_SPEED
		velocity.y = 0.0
	elif _state_timer < _dash_time + storm_step.recovery:
		if _state_timer - delta < _dash_time:
			# Hard stop at the end of the active window: letting 50 m/s decay
			# through normal deceleration added ~11m of ice-skating overshoot.
			velocity.x = _dash_dir.x * 4.0
			velocity.z = _dash_dir.z * 4.0
		velocity.x = move_toward(velocity.x, 0, DECEL * 2.0 * delta)
		velocity.z = move_toward(velocity.z, 0, DECEL * 2.0 * delta)
	else:
		_finish_storm_step()


func _finish_storm_step() -> void:
	state = State.MOVE
	_resolve_storm_step()
	_consume_buffer()


## Ends the dash itself: restores collision and zaps everything on the path.
## Shared by the normal finish and a dodge cancel (which must not consume the
## input buffer mid-dodge).
func _resolve_storm_step() -> void:
	collision_mask = 0b101
	var scene := get_tree().current_scene
	VFX.storm_trail(scene, _dash_start, global_position)
	# Everything the dash passed through gets zapped and shocked.
	var path := global_position - _dash_start
	var center := _dash_start + path * 0.5 + Vector3(0, 1.0, 0)
	var hits := _query_hurtboxes(center, maxf(path.length() * 0.5 + 0.5, 1.0))
	var zapped := 0
	for enemy: Node in hits:
		var enemy_3d := enemy as Node3D
		# Radius covers a sphere; keep only enemies near the actual dash line.
		var to_enemy := enemy_3d.global_position - _dash_start
		var along := clampf(to_enemy.dot(path.normalized()), 0.0, path.length())
		var closest := _dash_start + path.normalized() * along
		if enemy_3d.global_position.distance_to(closest) > 1.4:
			continue
		var hit := roll_ability_hit(storm_step)
		hit.source_position = _dash_start
		if enemy.has_method(&"take_hit") and enemy.call(&"take_hit", hit):
			zapped += 1
			gain_resonance(storm_step.resonance_gain_per_hit, true)
			VFX.lightning_arc(scene, global_position + Vector3(0, 1.0, 0),
				enemy_3d.global_position + Vector3(0, 1.0, 0), Color(0.8, 0.9, 1.0))
	# M07 Overload: the landing point Shocks everything around it.
	if has_power(&"overload"):
		VFX.ground_ring(scene, global_position, ArtKit.color("color_roles.lightning.body"), OVERLOAD_RADIUS, 0.25)
		for other in EnemyBase.all_enemies:
			if is_instance_valid(other) and other.ai_state != EnemyBase.AIState.DEAD \
					and other.global_position.distance_to(global_position) <= OVERLOAD_RADIUS:
				other.status.apply_shock()
	# M07 Eye of the Storm: every enemy on the path refunds 20 % of the cooldown.
	if has_power(&"eye_of_the_storm") and zapped > 0:
		_cooldowns[&"storm_step"] = maxf(float(_cooldowns.get(&"storm_step", 0.0)) - storm_step.cooldown * 0.2 * zapped, 0.0)
		cooldowns_changed.emit()


# ---------------------------------------------------------------------------
# Chain Spark
# ---------------------------------------------------------------------------

func try_chain_spark() -> bool:
	if not knows(&"chain_spark") or state != State.MOVE or _cooldowns.get(&"chain_spark", 0.0) > 0.0:
		return false
	var first: EnemyBase = null
	if targeting != null:
		var held := targeting.current
		if held != null and is_instance_valid(held) and held.ai_state != EnemyBase.AIState.DEAD \
				and held.global_position.distance_to(global_position) <= 14.0:
			first = held
		else:
			first = targeting.best_candidate()
	if first == null:
		ui_denied()
		return false
	_set_cooldown(&"chain_spark", chain_spark.cooldown)
	_face_aim_instant()
	var scene := get_tree().current_scene
	var from := muzzle_position()
	var hit_enemies: Array[EnemyBase] = []
	var next: EnemyBase = first
	var bonus_jump := false
	while next != null:
		if next.status.has_shock():
			bonus_jump = true
		var chest := next.global_position + Vector3(0, 1.0, 0)
		VFX.lightning_arc(scene, from, chest)
		VFX.flash(scene, chest, Color(1.0, 1.0, 0.75), 0.6, 0.1)
		var hit := roll_ability_hit(chain_spark)
		if next.take_hit(hit):
			gain_resonance(chain_spark.resonance_gain_per_hit, true)
			# Conductor's Oath: struck enemies stay charged; later lightning
			# damage on any Conductor arcs to all others (see EnemyBase).
			if has_power(&"conductors_oath"):
				next.status.apply_conductor()
		hit_enemies.append(next)
		from = chest
		var max_targets := 3 + int(stat(&"chain_jumps")) + (1 if bonus_jump else 0)
		next = null
		if hit_enemies.size() < max_targets:
			next = _nearest_chain_candidate(from, hit_enemies)
	# M07 Thunderclap: the last target bursts onto its neighbours.
	if has_power(&"thunderclap") and not hit_enemies.is_empty() and is_instance_valid(hit_enemies[-1]):
		var last := hit_enemies[-1]
		VFX.ground_ring(scene, last.global_position, ArtKit.color("color_roles.lightning.body"), THUNDERCLAP_RADIUS, 0.25)
		for other in EnemyBase.all_enemies.duplicate():
			if other == last or not is_instance_valid(other) or other.ai_state == EnemyBase.AIState.DEAD:
				continue
			if other.global_position.distance_to(last.global_position) <= THUNDERCLAP_RADIUS:
				var splash := roll_ability_hit(chain_spark)
				splash.damage *= 0.6
				splash.source_position = last.global_position
				other.take_hit(splash)
	Sfx.play("chain_spark", global_position, -1.0, 0.1)
	feel_impulse(aim_direction(), 0.04)
	# Weapon flourish: quick raise, snap back.
	var tw := _weapon_pivot.create_tween()
	tw.tween_property(_weapon_pivot, "rotation_degrees", Vector3(-70, 20, 0), 0.07)
	tw.tween_property(_weapon_pivot, "rotation_degrees", Vector3(-25, 15, 0), 0.25) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	cooldowns_changed.emit()
	action_started.emit(&"chain_spark")
	return true


func _nearest_chain_candidate(from: Vector3, exclude: Array[EnemyBase]) -> EnemyBase:
	var best: EnemyBase = null
	var best_dist := chain_spark.aoe_radius  # jump range
	for enemy in EnemyBase.all_enemies:
		if not is_instance_valid(enemy) or enemy.ai_state == EnemyBase.AIState.DEAD or exclude.has(enemy):
			continue
		var d := enemy.global_position.distance_to(from)
		if d < best_dist:
			best_dist = d
			best = enemy
	return best


# ---------------------------------------------------------------------------
# Fracture Rune
# ---------------------------------------------------------------------------

const FRACTURE_RUNE_MAX_RANGE := 12.0


func try_fracture_rune() -> bool:
	if not knows(&"fracture_rune") or state != State.MOVE or _cooldowns.get(&"fracture_rune", 0.0) > 0.0:
		return false
	_set_cooldown(&"fracture_rune", fracture_rune.cooldown)
	var exclude: Array[RID] = [get_rid()]
	var aim_point := camera_rig.get_aim_point(exclude) if camera_rig != null else global_position + facing() * 6.0
	var offset := Vector3(aim_point.x - global_position.x, 0.0, aim_point.z - global_position.z)
	if offset.length() > FRACTURE_RUNE_MAX_RANGE:
		offset = offset.normalized() * FRACTURE_RUNE_MAX_RANGE
	var rune := FractureRune.new()
	rune.setup(fracture_rune, self)
	rune.arm_time = maxf(FractureRune.ARM_TIME - stat(&"rune_arm_reduce"), 0.5)
	# M08: on the ground under the aim spot (slopes, ledges), never at y 0
	rune.position = ZoneBase.ground_under(self, global_position + offset, 0.02)
	get_tree().current_scene.add_child(rune)
	_face_aim_instant()
	# Casting gesture: brief point with the blade.
	var tw := _weapon_pivot.create_tween()
	tw.tween_property(_weapon_pivot, "rotation_degrees", Vector3(-60, 0, 0), 0.08)
	tw.tween_property(_weapon_pivot, "rotation_degrees", Vector3(-25, 15, 0), 0.3) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	cooldowns_changed.emit()
	action_started.emit(&"fracture_rune")
	return true


# ---------------------------------------------------------------------------
# Resonance / damage intake
# ---------------------------------------------------------------------------

func gain_resonance(amount: float, lightning: bool = false) -> void:
	amount *= 1.0 + (stat(&"resonance_pct") + (stat(&"lightning_res_pct") if lightning else 0.0)) / 100.0
	resonance = minf(resonance + amount, max_resource())
	resonance_changed.emit(resonance, max_resource())


func spend_resonance(amount: float) -> void:
	resonance = maxf(resonance - amount, 0.0)
	resonance_changed.emit(resonance, max_resource())


func take_hit(hit: HitInfo) -> bool:
	if god_mode:
		return false
	# M07 Unbroken: an attack met inside the dodge's i-frames grants a barrier.
	if health.invulnerable and not health.is_dead and has_power(&"unbroken") \
			and float(_cooldowns.get(&"unbroken", 0.0)) <= 0.0:
		_cooldowns[&"unbroken"] = UNBROKEN_COOLDOWN
		grant_barrier(UNBROKEN_BARRIER, 3.0)
	if barrier > 0.0 and not health.invulnerable and not health.is_dead:
		var absorbed := minf(barrier, hit.damage)
		barrier -= absorbed
		hit.damage -= absorbed
		_on_barrier_absorbed(absorbed)
		if hit.damage <= 0.01:
			return false
	if not health.apply_hit(hit):
		return false
	var push := (global_position - hit.source_position)
	push.y = 0
	_knockback_velocity += push.normalized() * hit.knockback
	Sfx.play("player_hurt", global_position, -2.0)
	feel_shake(0.25)
	return true


func _on_damaged(hit: HitInfo) -> void:
	GameFeel.damage_number(global_position + Vector3(0, 1.9, 0), hit.damage, Color(1.0, 0.3, 0.25))


func _on_died() -> void:
	player_died.emit()


# ---------------------------------------------------------------------------
# M07 talent abilities + barrier
# ---------------------------------------------------------------------------

const OVERLOAD_RADIUS := 2.5
const THUNDERCLAP_RADIUS := 2.0
const BULWARK_RADIUS := 3.0


## Absorbs damage before health for `duration` s (the larger barrier wins).
func grant_barrier(amount: float, duration: float) -> void:
	barrier = maxf(barrier, amount)
	_barrier_time = maxf(_barrier_time, duration)
	VFX.player_ring(self, global_position, 1.1, duration, ArtKit.color("color_roles.player_accent.hot"))
	VFX.flash(get_tree().current_scene, global_position + Vector3(0, 1.1, 0), ArtKit.color("color_roles.player_accent.hot"), 1.0, 0.12)


func _on_barrier_absorbed(amount: float) -> void:
	var scene := get_tree().current_scene
	VFX.flash(scene, global_position + Vector3(0, 1.1, 0), ArtKit.color("color_roles.player_accent.body"), 0.8, 0.08)
	Sfx.play("bolt_impact", global_position, -6.0, 0.1, 1.4)
	GameFeel.damage_number(global_position + Vector3(0, 2.0, 0), amount, ArtKit.color("color_roles.player_accent.hot"))
	# M07 Glacial Bulwark: whoever struck the guard up close is Chilled.
	if has_power(&"glacial_bulwark"):
		for enemy in EnemyBase.all_enemies:
			if is_instance_valid(enemy) and enemy.ai_state != EnemyBase.AIState.DEAD \
					and enemy.global_position.distance_to(global_position) <= BULWARK_RADIUS:
				enemy.status.apply_chill()


func try_runic_guard() -> bool:
	if not knows(&"runic_guard") or state != State.MOVE or float(_cooldowns.get(&"runic_guard", 0.0)) > 0.0:
		return false
	if resonance < runic_guard.resonance_cost:
		ui_denied()
		return false
	spend_resonance(runic_guard.resonance_cost)
	_set_cooldown(&"runic_guard", runic_guard.cooldown)
	grant_barrier(runic_guard.damage + float(progression.level), runic_guard.active)
	Sfx.play("runic_guard", global_position, -2.0, 0.05)
	cooldowns_changed.emit()
	action_started.emit(&"runic_guard")
	return true


func try_resonance_burst() -> bool:
	if not knows(&"resonance_burst") or state != State.MOVE or float(_cooldowns.get(&"resonance_burst", 0.0)) > 0.0:
		return false
	if resonance < resonance_burst.resonance_cost:
		ui_denied()
		return false
	var spent := resonance
	spend_resonance(spent)
	_set_cooldown(&"resonance_burst", resonance_burst.cooldown)
	var scene := get_tree().current_scene
	var pos := global_position
	var gold := ArtKit.color("color_roles.resonance.body")
	VFX.flash(scene, pos + Vector3(0, 1.0, 0), ArtKit.color("color_roles.resonance.hot"), 2.4, 0.18)
	VFX.ground_ring(scene, pos, gold, resonance_burst.aoe_radius, 0.35)
	VFX.burst(scene, pos + Vector3(0, 0.8, 0), {"tex": "shard", "amount": 14, "lifetime": 0.5, "size": 0.16,
		"spread": 90.0, "vel_min": 4.0, "vel_max": 8.0, "colors": [ArtKit.color("color_roles.resonance.hot"), Color(gold, 0.0)] as Array[Color]})
	Sfx.play("resonance_burst", pos, 0.0, 0.05)
	feel_shake(0.45)
	var hits := _query_hurtboxes(pos + Vector3(0, 0.8, 0), resonance_burst.aoe_radius)
	for enemy: Node in hits:
		var hit := roll_ability_hit(resonance_burst)
		hit.damage *= spent  # 0.7 per point of Resonance spent
		hit.source_position = pos
		enemy.call(&"take_hit", hit)
	if not hits.is_empty():
		GameFeel.hitstop(hits, 0.08)
	cooldowns_changed.emit()
	action_started.emit(&"resonance_burst")
	return true


func cooldown_fraction(id: StringName) -> float:
	var total: float = DODGE_COOLDOWN if id == &"dodge" else 1.0
	var data := ability(id)
	if data != null and data.cooldown > 0.0:
		total = data.cooldown
	return clampf(_cooldowns.get(id, 0.0) / total, 0.0, 1.0)


func reset_cooldowns() -> void:
	_cooldowns.clear()
	cooldowns_changed.emit()
