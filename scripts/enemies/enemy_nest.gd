class_name EnemyNest
extends EnemyBase
## M12: a nest of a sub-biome's family - the Charwood's smouldering stump,
## the bone field's jackal den. It does not move or fight; it breeds: while a
## hero is near and fewer than MAX_BROOD of its brood live, it swells (smoke
## and a glow for PULSE_TIME - the tell) and lets one out, BROOD_TOTAL in
## all. Break it and that ends. A nest is a camp of its own: it comes back
## after the camps' respawn time.

const PULSE_TIME := 1.2
const BREED_EVERY := 7.0
const FIRST_BREED := 1.0
const MAX_BROOD := 3
const BROOD_TOTAL := 8
const NEAR := 18.0

var brood_id: String = "smoulder_wisp"
var prop_name: String = "wisp_nest"
var smoke: Color = Color(0.3, 0.27, 0.26)
var brood: Array[EnemyBase] = []
var bred: int = 0
var _wait: float = FIRST_BREED


func _init() -> void:
	xp_value = 60
	max_health = 240.0
	move_speed = 0.0
	body_color = Color(0.3, 0.26, 0.22)
	immobile = true
	stagger_resist = true
	loot_kind = &"brute"


func nameplate_height() -> float:
	return 2.0


func _build_body() -> void:
	if _setup_prop_visual(prop_name):
		return
	var mound := MeshInstance3D.new()  # fallback (and the dedicated server): a low mound
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.4
	mesh.bottom_radius = 0.8
	mesh.height = 1.2
	mesh.material = flat_material(body_color)
	mound.mesh = mesh
	mound.position = Vector3(0, 0.6, 0)
	visual.add_child(mound)


func living_brood() -> int:
	var live: Array[EnemyBase] = []
	for e in brood:
		if is_instance_valid(e) and e.ai_state != AIState.DEAD:
			live.append(e)
	brood = live
	return brood.size()


func _ai_process(delta: float) -> void:
	brake(delta)
	match ai_state:
		AIState.IDLE:
			_wait -= delta
			if _wait > 0.0 or bred >= BROOD_TOTAL:
				return
			var zone := ZoneBase.zone_of(self)
			if zone == null or zone.players_within(global_position, NEAR).is_empty() or living_brood() >= MAX_BROOD:
				return
			_enter_state(AIState.WINDUP)
			_present_pulse()
		AIState.WINDUP:
			if _state_timer >= PULSE_TIME:
				_breed()
				_wait = BREED_EVERY
				_enter_state(AIState.IDLE)
		AIState.STAGGER:
			if _state_timer >= 0.0:
				_enter_state(AIState.IDLE)


func _breed() -> void:
	var zone := ZoneBase.zone_of(self)
	if zone == null:
		return
	var a := randf() * TAU
	var pos := zone.ground_point(global_position + Vector3(cos(a), 0.0, sin(a)) * randf_range(2.2, 3.2), 0.2)
	var e := zone.spawn_by_id(brood_id, pos)
	e.home = global_position
	e.leash = 28.0
	if e.has_method(&"wake"):
		e.call(&"wake")
	brood.append(e)
	bred += 1
	play_fx(&"breed")


func _present_state(s: AIState) -> void:
	super(s)
	if s == AIState.WINDUP:
		_present_pulse()


## The tell: it swells with smoke and glows from inside.
func _present_pulse() -> void:
	var scene := get_tree().current_scene
	VFX.burst(scene, global_position + Vector3(0, 1.1, 0), {"tex": "ember", "amount": 18, "size": 0.2, "vel_min": 0.6,
		"vel_max": 1.6, "gravity": Vector3(0, 1.2, 0), "colors": [smoke, Color(smoke, 0.0)] as Array[Color], "emission_radius": 0.6})
	VFX.flash(scene, global_position + Vector3(0, 0.7, 0), Color(1.0, 0.55, 0.25), 1.0, PULSE_TIME * 0.5)
	Sfx.play("caster_charge", global_position, -6.0, 0.1, 0.55)


func _present_fx(fx: StringName) -> void:
	if fx == &"breed":
		VFX.dodge_dust(get_tree().current_scene, present_origin(), Vector3.UP)
		Sfx.play("earthbreaker_impact", global_position, -12.0, 0.1, 1.4)


func _death_presentation() -> void:
	var scene := get_tree().current_scene
	VFX.burst(scene, global_position + Vector3(0, 0.8, 0), {"tex": "ember", "amount": 30, "size": 0.18, "vel_min": 1.5,
		"vel_max": 4.5, "gravity": Vector3(0, -4.0, 0), "colors": [smoke, Color(smoke, 0.0)] as Array[Color], "emission_radius": 0.8})
	Sfx.play("earthbreaker_impact", global_position, -4.0, 0.1, 0.8)
	super()
