class_name ImpBurst
extends Node3D
## M13 the Ember Warrens: what a dying kiln imp leaves - its belly furnace
## cracks, a ring fills on the ground, and then it bursts. Whoever still
## stands in the ring burns (the authority judges, each hero through its
## owner); a co-op client gets a copy through HAZARD for the look.

const DELAY := 0.9
const RADIUS := 2.2
const DAMAGE := 16.0

var visual_only: bool = false
var _t: float = 0.0
var _core: MeshInstance3D


func _ready() -> void:
	global_position = ZoneBase.ground_under(self, global_position + Vector3(0, 1.0, 0), 0.03)
	if not visual_only:
		var zone := ZoneBase.zone_of(self)
		if zone != null and zone.net_world != null:
			zone.net_world.register_hazard(&"imp_burst", global_position)
	VFX.telegraph_disc(get_tree().current_scene, global_position, RADIUS, DELAY)
	_core = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.4, 0.3, 0.4)
	box.material = EnemyBase.flat_material(ArtKit.color("palettes.warrens.lava_hi", Color(1.0, 0.69, 0.25)), true, 3.0)
	_core.mesh = box
	_core.position = Vector3(0, 0.2, 0)
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_core)
	Sfx.play("caster_charge", global_position, -6.0, 0.1, 1.4)


func _process(delta: float) -> void:
	_t += delta
	_core.scale = Vector3.ONE * (1.0 + _t / DELAY * 0.8 + sin(_t * 30.0) * 0.08)
	if _t >= DELAY:
		_burst()


func _burst() -> void:
	set_process(false)
	var scene := get_tree().current_scene
	VFX.ember_impact(scene, global_position + Vector3(0, 0.5, 0))
	VFX.flash(scene, global_position + Vector3(0, 0.6, 0), Color(1.0, 0.6, 0.2), RADIUS, 0.18)
	Sfx.play("ember_impact", global_position, 0.0, 0.1, 0.6)
	if not visual_only:
		var zone := ZoneBase.zone_of(self)
		if zone != null:
			for hero in zone.players:
				if hero == null or not is_instance_valid(hero) or hero.health.is_dead:
					continue
				var flat := hero.global_position - global_position
				flat.y = 0.0
				if flat.length() <= RADIUS + EnemyBase.STRIKE_TOLERANCE:
					var hit := HitInfo.create(DAMAGE, HitInfo.DamageType.FIRE, HitInfo.Weight.MEDIUM, global_position)
					hit.area_center = global_position
					hit.area_radius = RADIUS + EnemyBase.STRIKE_TOLERANCE
					hit.knockback = 4.0
					hero.take_hit(hit)
	queue_free()
