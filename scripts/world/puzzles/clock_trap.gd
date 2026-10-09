class_name ClockTrap
extends Node3D
## M13: a timing trap across a dungeon corridor - blades that scythe up out
## of the floor, or fire jets - in strips along a lane, bursting in a rolling
## wave on the server's clock (the M12 dodge run's pattern): a red strip
## telegraph, then the burst. Every machine runs the wave and judges only its
## own hero: a hit costs health but never the last point. Dodge's i-frames
## carry a hero through like any other hit.

const WARN := 0.7
const UP := 0.4
const STRIP_DEPTH := 1.3

var look: String = "blades"
var strips: int = 5
var period: float = 3.0
var stagger: float = 0.42
var damage: float = 14.0
var width: float = 5.4
var start: Vector3
var end: Vector3
var _dir: Vector3
var _side: Vector3
var _parts: Array[MeshInstance3D] = []
var _last_phase: Array[float] = []
## Tests: bursts that struck this machine's hero.
var hits_dealt: int = 0


static func build(zone: ZoneBase, poi: Dictionary) -> ClockTrap:
	var t := ClockTrap.new()
	t.name = "Trap_" + String(poi.get("id", ""))
	t.look = String(poi.get("look", "blades"))
	t.strips = int(poi.get("strips", 5))
	t.period = float(poi.get("period", 3.0))
	t.stagger = float(poi.get("stagger", t.period / float(t.strips + 2)))
	t.damage = float(poi.get("damage", 14.0))
	t.width = float(poi.get("width", 5.4))
	var lane: Array = poi.get("lane", [])
	t.start = Vector3(float(lane[0][0]), 0.0, float(lane[0][1]))
	t.end = Vector3(float(lane[1][0]), 0.0, float(lane[1][1]))
	t.start.y = zone.ground_y(t.start)
	t.end.y = zone.ground_y(t.end)
	t.set_meta(&"poi_id", String(poi.get("id", "")))
	t.position = t.start
	zone.world.add_child(t)
	return t


func _ready() -> void:
	_dir = Vector3(end.x - start.x, 0.0, end.z - start.z).normalized()
	_side = Vector3(_dir.z, 0.0, -_dir.x)
	var mat := EnemyBase.flat_material(Color(0.55, 0.58, 0.6)) if look == "blades" \
		else EnemyBase.flat_material(ElementCharge.color(HitInfo.DamageType.FIRE), true, 2.5)
	for k in strips:
		var part := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(width, 1.3, 0.12) if look == "blades" else Vector3(width, 2.2, 0.8)
		box.material = mat
		part.mesh = box
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(part)
		part.global_position = strip_centre(k) + Vector3(0, -1.5, 0)
		part.rotation.y = atan2(_dir.x, _dir.z)
		part.visible = false
		_parts.append(part)
		_last_phase.append(-1.0)


func strip_centre(k: int) -> Vector3:
	var t := (float(k) + 0.5) / float(strips)
	return start.lerp(end, t)


func strip_phase(k: int, now_s: float) -> float:
	return fposmod(now_s - float(k) * stagger, period)


func _now_s() -> float:
	var zone := ZoneBase.zone_of(self)
	if zone != null and zone.net_world != null:
		return zone.net_world.server_msec() / 1000.0
	return float(Time.get_ticks_msec()) / 1000.0


func on_strip(k: int, pos: Vector3) -> bool:
	var rel := pos - strip_centre(k)
	return absf(rel.dot(_dir)) <= STRIP_DEPTH * 0.5 and absf(rel.dot(_side)) <= width * 0.5 \
		and absf(rel.y) < 1.6


func _process(_delta: float) -> void:
	var zone := ZoneBase.zone_of(self)
	var hero := zone.player if zone != null else null
	if hero == null or not is_instance_valid(hero) or hero.global_position.distance_to(global_position) > 50.0:
		return
	var now := _now_s()
	for k in strips:
		var ph := strip_phase(k, now)
		var last := _last_phase[k]
		_last_phase[k] = ph
		if last < 0.0:
			continue
		var warn_at := period - WARN
		if last < warn_at and ph >= warn_at:
			VFX.telegraph_lane(zone, strip_centre(k) - _side * width * 0.5, _side, width, STRIP_DEPTH, WARN)
		if ph < last:
			burst(k, hero)


## Strip k bursts: the look, and the local hero struck if it stands there.
func burst(k: int, hero: Player) -> void:
	var part := _parts[k]
	part.visible = true
	var c := strip_centre(k)
	var top := c.y + (0.65 if look == "blades" else 1.1)
	var tw := part.create_tween()
	tw.tween_property(part, "global_position:y", top, 0.07).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_interval(UP)
	tw.tween_property(part, "global_position:y", c.y - 1.5, 0.3)
	tw.tween_callback(func() -> void: part.visible = false)
	if look == "jets":
		VFX.flash(get_tree().current_scene, c + Vector3(0, 1.0, 0), ElementCharge.color(HitInfo.DamageType.FIRE), 2.0, 0.25)
		Sfx.play("ember_fire", c, -10.0, 0.1, 0.8)
	else:
		Sfx.play("swing", c, -8.0, 0.1, 0.7)
	if hero != null and hero.is_local and on_strip(k, hero.global_position) and not hero.health.is_dead:
		var dmg := minf(damage, hero.health.current_health - 1.0)  # never the last point
		if dmg > 0.0:
			var kind := HitInfo.DamageType.FIRE if look == "jets" else HitInfo.DamageType.PHYSICAL
			if hero.take_hit(HitInfo.create(dmg, kind, HitInfo.Weight.MEDIUM, c)):
				hits_dealt += 1
