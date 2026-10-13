class_name StormStrike
extends Node3D
## M13b the Stormwatch: a bolt from the dome. A disc marks where it falls
## (`delay` seconds); it strikes every hero within `radius` there, then leaps
## on: from each hero struck to every other hero within `chain_range` that
## has not been struck yet (`chain_damage`; `chains` leaps at most, -1 = as
## long as somebody stands close) - spread out. Thrown by the Stormsworn
## Acolyte, the Stormsworn and the Last Stormcaller. The authority judges;
## a co-op client gets a copy through HAZARD (with its numbers) that draws
## the same disc and leaps between the heroes it sees.

const SKY := Vector3(0.0, 9.0, 0.0)
const LIFT := Vector3(0.0, 1.1, 0.0)
const COLOR := Color(0.78, 0.7, 1.0)

var target: Vector3 = Vector3.ZERO
var radius: float = 1.4
var delay: float = 0.8
var damage: float = 12.0
var chain_range: float = 0.0
var chain_damage: float = 0.0
var chains: int = 0
## Who threw it (a parry counters it; 0 = nobody).
var source_id: int = 0
var visual_only: bool = false
## Tests: the heroes it struck, in order (the first ones under the disc).
var struck: Array[Player] = []
var _t: float = 0.0
var _done: bool = false


static func cast(where: Node, at: Vector3, p_radius: float, p_delay: float, p_damage: float,
		p_chain_range: float = 0.0, p_chain_damage: float = 0.0, p_chains: int = 0, p_source: int = 0) -> StormStrike:
	var s := StormStrike.new()
	s.target = at
	s.radius = p_radius
	s.delay = p_delay
	s.damage = p_damage
	s.chain_range = p_chain_range
	s.chain_damage = p_chain_damage
	s.chains = p_chains
	s.source_id = p_source
	where.get_tree().current_scene.add_child(s)
	return s


func _ready() -> void:
	target = ZoneBase.ground_under(self, target + Vector3(0, 1.0, 0), 0.03)
	global_position = target
	if not visual_only:
		var zone := ZoneBase.zone_of(self)
		if zone != null and zone.net_world != null:
			zone.net_world.register_hazard(&"storm_strike", target, [radius, delay, chain_range, chains])
	if delay > 0.05:
		VFX.telegraph_disc(get_tree().current_scene, target, radius, delay)
		Sfx.play("coil_charge", target, -14.0, 0.1, 1.6)


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	if _t >= delay:
		_done = true
		_strike()


func _strike() -> void:
	var scene := get_tree().current_scene
	VFX.lightning_arc(scene, target + SKY, target + Vector3(0, 0.1, 0), COLOR)
	VFX.flash(scene, target + Vector3(0, 0.4, 0), Color(0.92, 0.88, 1.0), radius * 1.4, 0.14)
	VFX.ground_ring(scene, target, COLOR, radius, 0.3)
	Sfx.play("storm_bolt", target, -3.0, 0.12)
	var zone := ZoneBase.zone_of(self)
	if zone == null:
		queue_free()
		return
	var hit_ids: Dictionary = {}
	var frontier: Array[Player] = []
	for hero in zone.party():
		if hero.health.is_dead:
			continue
		var flat := hero.global_position - target
		if absf(flat.y) > EnemyBase.STRIKE_HEIGHT:
			continue
		flat.y = 0.0
		if flat.length() <= radius + EnemyBase.STRIKE_TOLERANCE:
			hit_ids[hero.get_instance_id()] = true
			frontier.append(hero)
			_hurt(hero, damage, target, radius + EnemyBase.STRIKE_TOLERANCE)
	var leaps := 0
	while not frontier.is_empty() and chain_range > 0.0 and (chains < 0 or leaps < chains):
		var next: Array[Player] = []
		for from in frontier:
			for hero in zone.party():
				if hero.health.is_dead or hit_ids.has(hero.get_instance_id()):
					continue
				if hero.global_position.distance_to(from.global_position) <= chain_range:
					hit_ids[hero.get_instance_id()] = true
					next.append(hero)
					VFX.lightning_arc(scene, from.global_position + LIFT, hero.global_position + LIFT, COLOR)
					_hurt(hero, chain_damage, hero.global_position, 1.2)
		frontier = next
		if not next.is_empty():
			leaps += 1
	get_tree().create_timer(1.0).timeout.connect(queue_free)  # a moment longer: tests read `struck`


## The authority hits (the hit carries a circle around the hero's own feet, so
## its owner takes it where it stood); a client's copy only shows.
func _hurt(hero: Player, amount: float, at: Vector3, area: float) -> void:
	struck.append(hero)
	if visual_only:
		return
	var hit := HitInfo.create(amount, HitInfo.DamageType.LIGHTNING, HitInfo.Weight.LIGHT, at)
	hit.area_center = at
	hit.area_radius = area
	hit.source_id = source_id
	hero.take_hit(hit)
