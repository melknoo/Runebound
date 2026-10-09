class_name DungeonBoss
extends EnemyBase
## M13: the base of the dungeons' mid-bosses and end bosses (a BossArena
## spawns them). The boss bar follows `boss_health_changed` on every machine
## (puppets too, ZoneBase.setup_enemy_puppet); the authority keeps the boss
## inside its arena room (`arena_rect`), so leaving the room means leaving
## the fight - the arena resets once nobody alive is left in it. Bosses drop
## like bosses (`loot_kind`), scatter their gold and never leash home.
##
## As itself ("dungeon_boss") it is the phase-1 placeholder every arena uses
## until its own boss arrives: a slow stone giant with one telegraphed slam.

signal boss_health_changed(current: float, maximum: float)

const ARENA_MARGIN := 1.2

## The arena room on XZ (authority; empty = unbounded).
var arena_rect: Rect2 = Rect2()

const ATTACK_RANGE := 3.0
const SLAM_RADIUS := 3.2
const SLAM_AHEAD := 1.8
const WINDUP_TIME := 1.0
const RECOVER_TIME := 1.4
const SLAM_DAMAGE := 26.0

var _telegraph_disc: MeshInstance3D


func _init() -> void:
	xp_value = 400
	display_name = "Arena Warden"
	max_health = 900.0
	move_speed = 2.4
	body_color = Color(0.36, 0.42, 0.46)
	stagger_resist = true
	loot_kind = &"boss"
	gold_piles = 3


func _ready() -> void:
	if Texts.has("enemy." + type_id):  # the bar and the nameplate in the player's language
		display_name = Texts.t("enemy." + type_id)
	super()
	for child in get_children():
		if child is CollisionShape3D:
			var capsule := (child as CollisionShape3D).shape as CapsuleShape3D
			capsule.radius = 0.85
			capsule.height = 2.8
			(child as CollisionShape3D).position.y = 1.4
		elif child is Hurtbox:
			var hb_col := (child as Hurtbox).get_child(0) as CollisionShape3D
			var hb_capsule := hb_col.shape as CapsuleShape3D
			hb_capsule.radius = 1.0
			hb_capsule.height = 3.0
			hb_col.position.y = 1.5
	health.health_changed.connect(func(c: float, m: float) -> void: boss_health_changed.emit(c, m))


func nameplate_height() -> float:
	return 3.6


## Placeholder body: a hulking stone figure (subclasses bring their rigs).
func _build_body() -> void:
	var torso := MeshInstance3D.new()
	var torso_mesh := BoxMesh.new()
	torso_mesh.size = Vector3(1.6, 1.8, 1.0)
	torso_mesh.material = flat_material(body_color)
	torso.mesh = torso_mesh
	torso.position = Vector3(0, 1.3, 0)
	visual.add_child(torso)
	var head := MeshInstance3D.new()
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.6, 0.5, 0.55)
	head_mesh.material = flat_material(body_color.darkened(0.3))
	head.mesh = head_mesh
	head.position = Vector3(0, 2.45, -0.1)
	visual.add_child(head)
	var eyes := MeshInstance3D.new()
	var eyes_mesh := BoxMesh.new()
	eyes_mesh.size = Vector3(0.4, 0.08, 0.06)
	eyes_mesh.material = flat_material(Color(0.4, 0.95, 1.0), true, 2.2)
	eyes.mesh = eyes_mesh
	eyes.position = Vector3(0, 2.5, -0.39)
	visual.add_child(eyes)
	visual.scale = Vector3.ONE * 1.25
	base_visual_scale = visual.scale


func _physics_process(delta: float) -> void:
	super(delta)
	if net_puppet or not arena_rect.has_area() or ai_state == AIState.DEAD:
		return
	var inner := arena_rect.grow(-ARENA_MARGIN)
	var p := global_position
	var clamped := Vector2(clampf(p.x, inner.position.x, inner.end.x), clampf(p.z, inner.position.y, inner.end.y))
	if not is_equal_approx(clamped.x, p.x) or not is_equal_approx(clamped.y, p.z):
		global_position = Vector3(clamped.x, p.y, clamped.y)


func _ai_process(delta: float) -> void:
	match ai_state:
		AIState.IDLE:
			brake(delta)
			if player != null and distance_to_player() < AGGRO_RANGE * 2.0:
				_enter_state(AIState.CHASE)
		AIState.CHASE:
			face_player(delta, 4.0)
			move_towards(dir_to_player(), move_speed, delta)
			if distance_to_player() <= ATTACK_RANGE:
				lock_strike()
				_enter_state(AIState.WINDUP)
				_present_windup()
		AIState.WINDUP:
			brake(delta)
			if _state_timer >= WINDUP_TIME:
				_enter_state(AIState.RECOVER)
				play_fx(&"slam")
				strike_circle(strike_point(SLAM_AHEAD), SLAM_RADIUS, SLAM_DAMAGE, HitInfo.DamageType.PHYSICAL,
					HitInfo.Weight.HEAVY, 8.0)
		AIState.RECOVER:
			brake(delta)
			if _state_timer >= RECOVER_TIME:
				_enter_state(AIState.CHASE)
		AIState.STAGGER:
			brake(delta)
			if _state_timer >= 0.0:
				_enter_state(AIState.CHASE)


func _present_state(s: AIState) -> void:
	super(s)
	if s == AIState.WINDUP:
		_present_windup()


func _present_windup() -> void:
	_telegraph_disc = VFX.telegraph_disc(get_tree().current_scene, present_origin() + present_forward() * SLAM_AHEAD,
		SLAM_RADIUS, WINDUP_TIME)
	Sfx.play("earthbreaker_windup", global_position, -5.0, 0.1, 0.75)


func _present_fx(fx: StringName) -> void:
	if fx != &"slam":
		return
	var at := present_origin() + present_forward() * SLAM_AHEAD
	VFX.earthbreaker_slam(get_tree().current_scene, at, SLAM_RADIUS)
	Sfx.play("earthbreaker_impact", at, -3.0, 0.1, 0.8)
	GameFeel.camera_shake(0.3)


func _on_interrupted() -> void:
	if _telegraph_disc != null and is_instance_valid(_telegraph_disc):
		_telegraph_disc.queue_free()
