class_name EliteModifier
extends Node
## Turns any enemy into an elite: more health, bigger, glowing aura, named,
## plus one behavior that changes the encounter. Added as a child right after
## the enemy enters the tree.

enum Kind { EMBERBOUND, STORMTOUCHED }

const NOVA_INTERVAL := 6.0
const NOVA_TELEGRAPH := 1.0
const NOVA_RADIUS := 4.0
const NOVA_DAMAGE := 10.0
const PATCH_INTERVAL := 2.0

var kind: Kind = Kind.EMBERBOUND
var enemy: EnemyBase

var _timer: float = 0.0
var _nova_charging: bool = false


static func kind_name(k: Kind) -> String:
	return "EMBERBOUND" if k == Kind.EMBERBOUND else "STORMTOUCHED"


static func kind_color(k: Kind) -> Color:
	return Color(1.0, 0.5, 0.15) if k == Kind.EMBERBOUND else Color(1.0, 0.95, 0.4)


func _ready() -> void:
	enemy = get_parent() as EnemyBase
	if enemy == null:
		queue_free()
		return
	enemy.is_elite = true
	enemy.display_name = kind_name(kind).capitalize() + " " + enemy.display_name
	enemy.health.max_health *= 3.0
	enemy.health.current_health = enemy.health.max_health
	enemy.visual.scale *= 1.25
	enemy.base_visual_scale = enemy.visual.scale

	var color := kind_color(kind)
	var aura := OmniLight3D.new()
	aura.light_color = color
	aura.light_energy = 1.4
	aura.omni_range = 3.5
	aura.shadow_enabled = false
	aura.position = Vector3(0, 1.0, 0)
	enemy.add_child(aura)

	var label := Label3D.new()
	label.text = kind_name(kind)
	label.font_size = 40
	label.pixel_size = 0.004
	label.modulate = color
	label.outline_size = 12
	label.outline_modulate = Color(0.05, 0.03, 0.08)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	UiTheme.label3d(label)
	# Above the target name plate so both stay readable when Tab-selected.
	label.position = Vector3(0, enemy.nameplate_height() + 0.5, 0)
	enemy.add_child(label)
	_add_aura(color)


## M06 C5 elite read: eyes burn in the affix's element colour and element
## motes rise off the body (no ground shape: discs and rings are taken).
func _add_aura(color: Color) -> void:
	var rig_root := enemy.visual.get_node_or_null("RigRoot")
	if rig_root != null:
		var meshes := rig_root.find_children("*", "MeshInstance3D", true, false)
		if not meshes.is_empty() and (meshes[0] as MeshInstance3D).mesh.get_surface_count() > 1:
			(meshes[0] as MeshInstance3D).set_surface_override_material(1,
				ArtKit.glow_material(color, ArtKit.number("emissive_caps.character_eyes", 3.0)))
	var motes := CPUParticles3D.new()
	motes.name = "EliteMotes"
	motes.amount = 14
	motes.lifetime = 1.3
	motes.local_coords = false
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	motes.emission_box_extents = Vector3(0.35, 0.7, 0.35)
	motes.direction = Vector3.UP
	motes.spread = 12.0
	motes.gravity = Vector3(0, 0.9, 0)
	motes.initial_velocity_min = 0.2
	motes.initial_velocity_max = 0.6
	motes.scale_amount_min = 0.6
	motes.scale_amount_max = 1.0
	motes.color_ramp = (VFX._gradient([Color(color, 0.0), Color(color, 1.0), Color(color.lightened(0.4), 0.0)]
		as Array[Color]) as GradientTexture1D).gradient
	var quad := QuadMesh.new()
	quad.size = Vector2(0.08, 0.08)
	quad.material = VFX._particle_material(VFX._tex("ember" if kind == Kind.EMBERBOUND else "spark"))
	motes.mesh = quad
	motes.position = Vector3(0, 1.0, 0)
	enemy.add_child(motes)


func _physics_process(delta: float) -> void:
	if enemy == null or enemy.ai_state == EnemyBase.AIState.DEAD:
		return
	_timer += delta
	match kind:
		Kind.EMBERBOUND:
			# Drops on a fixed interval even when standing: a stationary elite
			# pooling fire under itself forces melee players to reposition.
			if _timer >= PATCH_INTERVAL:
				_timer = 0.0
				_drop_fire_patch()
		Kind.STORMTOUCHED:
			if not _nova_charging and _timer >= NOVA_INTERVAL:
				_timer = 0.0
				_charge_nova()


func _drop_fire_patch() -> void:
	var patch := FirePatch.new()
	patch.position = Vector3(enemy.global_position.x, 0.02, enemy.global_position.z)
	enemy.get_tree().current_scene.add_child(patch)


func _charge_nova() -> void:
	_nova_charging = true
	var scene := enemy.get_tree().current_scene
	VFX.telegraph_disc(scene, Vector3(enemy.global_position.x, 0, enemy.global_position.z),
		NOVA_RADIUS, NOVA_TELEGRAPH)
	Sfx.play("caster_charge", enemy.global_position, -6.0, 0.1, 1.3)
	await enemy.get_tree().create_timer(NOVA_TELEGRAPH).timeout
	_nova_charging = false
	if enemy == null or not is_instance_valid(enemy) or enemy.ai_state == EnemyBase.AIState.DEAD:
		return
	var pos := enemy.global_position
	VFX.ground_ring(scene, pos, Color(1.0, 0.95, 0.5), NOVA_RADIUS, 0.3)
	for i in 5:
		var a := randf() * TAU
		VFX.lightning_arc(scene, pos + Vector3(0, 1.0, 0),
			pos + Vector3(cos(a) * NOVA_RADIUS, 0.3, sin(a) * NOVA_RADIUS))
	Sfx.play("bolt_impact", pos, -2.0, 0.1, 0.8)
	# M07b: every hero inside the nova, not only the enemy's target.
	var zone := enemy.get_tree().current_scene as ZoneBase
	var victims: Array[Player] = zone.players_within(pos, NOVA_RADIUS) if zone != null else []
	if zone == null and enemy.player != null and is_instance_valid(enemy.player) \
			and enemy.player.global_position.distance_to(pos) <= NOVA_RADIUS:
		victims.append(enemy.player)
	for victim in victims:
		var hit := HitInfo.create(NOVA_DAMAGE, HitInfo.DamageType.LIGHTNING, HitInfo.Weight.MEDIUM, pos)
		hit.knockback = 3.0
		victim.take_hit(hit)
