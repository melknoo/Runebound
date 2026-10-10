class_name DrownedPuddle
extends Area3D
## M13: the water a Drowned Thrall bursts into. For a few seconds whoever
## wades in is chilled (the enemy-hit Chill: slowed) and nipped by the cold.
## The authority judges (every hero standing in it, each through its owner);
## clients get a copy for the look (HAZARD).

const LIFETIME := 5.0
const RADIUS := 1.7
const TICK_DAMAGE := 1.0
const TICK_INTERVAL := 0.5

var visual_only: bool = false
var _age: float = 0.0
var _tick_accum: float = 0.0
var _mesh: MeshInstance3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 0 if visual_only else 0b1000  # player hurtbox
	monitoring = not visual_only
	if not visual_only:
		var zone := ZoneBase.zone_of(self)
		if zone != null and zone.net_world != null:
			zone.net_world.register_hazard(&"drowned_puddle", global_position)
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = RADIUS
	shape.height = 1.2
	col.shape = shape
	col.position = Vector3(0, 0.6, 0)
	add_child(col)
	global_position = ZoneBase.ground_under(self, global_position, 0.03)
	_mesh = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = RADIUS
	disc.bottom_radius = RADIUS
	disc.height = 0.02
	disc.radial_segments = 12
	var mat := EnemyBase.flat_material(ArtKit.color("palettes.cistern.water_hi", Color(0.18, 0.4, 0.44)), true, 0.5)
	disc.material = mat
	_mesh.mesh = disc
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	VFX.frost_burst(get_tree().current_scene, global_position, RADIUS)
	Sfx.play("water_splash", global_position, -4.0, 0.1, 0.8)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return
	if _age > LIFETIME - 1.0 and _mesh != null:
		_mesh.scale = Vector3.ONE * maxf(LIFETIME - _age, 0.05)
	_tick_accum += delta
	if _tick_accum < TICK_INTERVAL or visual_only:
		return
	_tick_accum = 0.0
	for area in get_overlapping_areas():
		var hb := area as Hurtbox
		if hb == null or not hb.owner_entity is Player:
			continue
		var hero := hb.owner_entity as Player
		var flat := hero.global_position - global_position
		flat.y = 0.0
		if flat.length() > RADIUS + EnemyBase.STRIKE_TOLERANCE:
			continue
		var hit := HitInfo.create(TICK_DAMAGE, HitInfo.DamageType.FROST, HitInfo.Weight.LIGHT, global_position)
		hit.applies_chill = true  # an enemy hit with Chill slows the hero
		hit.area_center = global_position
		hit.area_radius = RADIUS + EnemyBase.STRIKE_TOLERANCE
		hero.take_hit(hit)
