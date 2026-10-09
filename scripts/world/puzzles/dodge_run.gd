class_name DodgeRun
extends Node3D
## M12 trap run (the bone field): a lane of bone-spike strips that burst
## out of the dust in a rolling wave - a red strip telegraph, then the
## spikes. Timing and Dodge get a hero through; a hit costs health but never
## the last point (no death needed). A chest waits at the end (an ordinary
## TreasureChest). Nothing to share: every machine runs the wave on the
## server's clock and judges only its own hero.

const STRIPS := 6
const PERIOD := 3.0       # one wave
const STAGGER := 0.42     # strip k bursts k * STAGGER after strip 0
const WARN := 0.75        # the telegraph before a burst
const UP := 0.45          # spikes out
const DAMAGE := 14.0
const STRIP_WIDTH := 3.0  # across the lane
const STRIP_DEPTH := 1.3  # along it

var start: Vector3
var end: Vector3
var _dir: Vector3
var _side: Vector3
var _spikes: Array[Node3D] = []
var _last_phase: Array[float] = []


static func build(zone: ZoneBase, poi: Dictionary) -> Dictionary:
	var lane: Array = poi.get("lane", [])
	var run := DodgeRun.new()
	run.name = "DodgeRun_" + String(poi.get("id", ""))
	var a := Vector3(float(lane[0][0]), 0.0, float(lane[0][1])) if lane.size() >= 2 else ZoneLayout.pos_of(poi)
	var b := Vector3(float(lane[1][0]), 0.0, float(lane[1][1])) if lane.size() >= 2 else ZoneLayout.pos_of(poi)
	run.start = a
	run.end = b
	zone.world.add_child(run)
	run.global_position = Vector3(a.x, zone.ground_y(a), a.z)
	run._build(zone)
	var chest := PoiBuilder.chest(zone, poi, Vector3.INF, true)  # the reward at the far end (M13: opens once)
	return {"run": run, "chest": chest}


func _build(zone: ZoneBase) -> void:
	_dir = Vector3(end.x - start.x, 0.0, end.z - start.z).normalized()
	_side = Vector3(_dir.z, 0.0, -_dir.x)
	for k in STRIPS:
		var c := strip_centre(k)
		c.y = zone.ground_y(c)
		var holder := Node3D.new()
		holder.name = "Spikes%d" % k
		add_child(holder)
		holder.global_position = c
		holder.rotation.y = atan2(_side.x, _side.z) + PI * 0.5
		if PoiBuilder.has_art(zone):
			var spikes := SetPieces.prop(holder, "bn_spikes", c, 0.0, 1.0)
			if spikes != null:
				spikes.position = Vector3(0, -1.0, 0)  # under the dust until they burst
				spikes.rotation = Vector3.ZERO
				_spikes.append(spikes)
		_last_phase.append(-1.0)


func strip_centre(k: int) -> Vector3:
	var t := (float(k) + 0.5) / float(STRIPS)
	return start.lerp(end, 0.12 + t * 0.76)


## Seconds into the wave for strip k (0 = it bursts now).
func strip_phase(k: int, now_s: float) -> float:
	return fposmod(now_s - float(k) * STAGGER, PERIOD)


func _now_s() -> float:
	var zone := ZoneBase.zone_of(self)
	if zone != null and zone.net_world != null:
		return zone.net_world.server_msec() / 1000.0
	return float(Time.get_ticks_msec()) / 1000.0


## Whether `pos` stands on strip k.
func on_strip(k: int, pos: Vector3) -> bool:
	var rel := pos - strip_centre(k)
	return absf(rel.dot(_dir)) <= STRIP_DEPTH * 0.5 and absf(rel.dot(_side)) <= STRIP_WIDTH * 0.5


func _process(_delta: float) -> void:
	var zone := ZoneBase.zone_of(self)
	var hero := zone.player if zone != null else null
	if hero == null or not is_instance_valid(hero) or hero.global_position.distance_to(global_position) > 45.0:
		return
	var now := _now_s()
	for k in STRIPS:
		var ph := strip_phase(k, now)
		var last := _last_phase[k]
		_last_phase[k] = ph
		if last < 0.0:
			continue
		# telegraph WARN before the burst (the wave wraps at PERIOD)
		var warn_at := PERIOD - WARN
		if last < warn_at and ph >= warn_at and PoiBuilder.has_art(zone):
			var c := strip_centre(k)
			c.y = zone.ground_y(c)
			VFX.telegraph_lane(zone, c - _side * STRIP_WIDTH * 0.5, _side, STRIP_WIDTH, STRIP_DEPTH, WARN)
		if ph < last:  # wrapped: the burst
			_burst(k, hero)


func _burst(k: int, hero: Player) -> void:
	var zone := ZoneBase.zone_of(self)
	if k < _spikes.size():
		var s := _spikes[k]
		var tw := s.create_tween()
		tw.tween_property(s, "position:y", 0.0, 0.08).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		tw.tween_interval(UP)
		tw.tween_property(s, "position:y", -1.0, 0.35)
		Sfx.play("earthbreaker_impact", s.global_position, -14.0, 0.1, 1.4)
	if hero.is_local and on_strip(k, hero.global_position) and not hero.health.is_dead:
		var dmg := minf(DAMAGE, hero.health.current_health - 1.0)  # never the last point
		if dmg > 0.0:
			var hit := HitInfo.create(dmg, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.MEDIUM, strip_centre(k))
			hero.take_hit(hit)
	if zone == null:
		return
