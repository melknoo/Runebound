class_name EmberLump
extends Node3D
## M13 the Ember Warrens: a glowing lump of slag lobbed by a kiln imp (or
## spewed by the Slag Reeve). A disc marks where it will land; it flies in
## an arc and bursts there, leaving burning ground (a FirePatch). The
## authority judges the burst; a co-op client gets a copy through HAZARD
## that drops from above onto the same disc (it never learns the thrower).

const FLIGHT := 0.85
const RADIUS := 1.3
const DAMAGE := 7.0
const ARC := 2.6
const DROP_FROM := Vector3(0.0, 7.0, 0.0)

var from: Vector3 = Vector3.ZERO
var target: Vector3 = Vector3.ZERO
var visual_only: bool = false
var _t: float = 0.0
var _mesh: MeshInstance3D


func _ready() -> void:
	target = ZoneBase.ground_under(self, target + Vector3(0, 1.0, 0), 0.03)
	if not visual_only:
		var zone := ZoneBase.zone_of(self)
		if zone != null and zone.net_world != null:
			zone.net_world.register_hazard(&"ember_lump", target)
	VFX.telegraph_disc(get_tree().current_scene, target, RADIUS, FLIGHT)
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.32
	box.material = EnemyBase.flat_material(ArtKit.color("palettes.warrens.lava_hi", Color(1.0, 0.69, 0.25)), true, 2.4)
	_mesh.mesh = box
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	global_position = from


func _process(delta: float) -> void:
	_t += delta
	var k := clampf(_t / FLIGHT, 0.0, 1.0)
	var p := from.lerp(target, k)
	p.y += sin(k * PI) * ARC
	global_position = p
	_mesh.rotation += Vector3(7.0, 5.0, 0.0) * delta
	if k >= 1.0:
		_land()


func _land() -> void:
	set_process(false)
	var scene := get_tree().current_scene
	VFX.ember_impact(scene, target + Vector3(0, 0.3, 0))
	Sfx.play("ember_impact", target, -4.0, 0.15, 0.8)
	if not visual_only:
		var patch := FirePatch.new()
		patch.position = target
		scene.add_child(patch)
		var zone := ZoneBase.zone_of(self)
		if zone != null:
			for hero in zone.players:
				if hero == null or not is_instance_valid(hero) or hero.health.is_dead:
					continue
				var flat := hero.global_position - target
				flat.y = 0.0
				if flat.length() <= RADIUS + EnemyBase.STRIKE_TOLERANCE:
					var hit := HitInfo.create(DAMAGE, HitInfo.DamageType.FIRE, HitInfo.Weight.LIGHT, target)
					hit.area_center = target
					hit.area_radius = RADIUS + EnemyBase.STRIKE_TOLERANCE
					hero.take_hit(hit)
	queue_free()
