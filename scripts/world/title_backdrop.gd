class_name TitleBackdrop
extends ZoneBase
## M17a: the living scene behind the title screen (user, 2026-10-01: a
## campfire at night, the selected character beside it in its own rig). A
## camp at the edge of the Ashen Highlands: bonfire, log seats, charred
## trees, a rune monolith, ash falling; a slow camera drift; Runehold's
## music. Built with the zone kit (look, props, StyleManager grading), but as
## a backdrop: no hero, UI or network (ZoneBase._is_backdrop).

const FIRE_POS := Vector3(0, 0, 0)
## The menu panel covers the left third: the camera looks left of the fire,
## so the fire sits right of centre and the hero beside it, further right.
const HERO_POS := Vector3(1.2, 0, 0.7)
const CAM_POS := Vector3(0.5, 1.5, 6.0)
const CAM_LOOK := Vector3(-1.3, 0.9, 0.0)
const DRIFT_PERIOD := 28.0

var hero: HeroPreview
var camera: Camera3D
var _cam_holder: Node3D
var _t: float = 0.0


func _is_backdrop() -> bool:
	return true


func _zone_look() -> ZoneLook:
	return ZoneLook.title_night()


func _zone_music() -> String:
	return "runehold"


func _build_zone() -> void:
	var art := look != null and look.art_pass
	var ground: Material = ArtKit.material(&"highlands_ground") if art else StandardMaterial3D.new()
	_add_box(Vector3(0, -0.5, 0), Vector3(400, 1.0, 400), ground)  # its edge sinks into the fog

	var fire := SetPieces.bonfire(self, FIRE_POS)
	if fire != null:  # night: the fire is the key light
		for light in fire.find_children("*", "OmniLight3D", true, false):
			(light as OmniLight3D).omni_range = 11.0
			(light as OmniLight3D).light_energy = 2.6
	var d := dressing()
	SetPieces.prop(d, "log_seat", FIRE_POS + Vector3(-1.7, 0, 0.5), 1.35)
	SetPieces.prop(d, "log_seat", FIRE_POS + Vector3(-0.4, 0, -1.8), 0.15)
	SetPieces.prop(d, "stone_cluster", FIRE_POS + Vector3(2.9, 0, -1.4), 0.6)
	SetPieces.prop(d, "stone_cluster", FIRE_POS + Vector3(-3.4, 0, -2.6), 2.1)
	SetPieces.prop(d, "bone_pile", FIRE_POS + Vector3(-2.6, 0, 1.9), 0.9)
	SetPieces.prop(d, "banner_pole", FIRE_POS + Vector3(-3.8, 0, -2.6), 0.35)
	SetPieces.prop(d, "rune_monolith", FIRE_POS + Vector3(-2.6, 0, -8.5), 0.3)
	for spot: Vector3 in [Vector3(-7.5, 0, -6.0), Vector3(6.5, 0, -10.5), Vector3(-12.0, 0, -12.5),
			Vector3(11.0, 0, -4.0), Vector3(-4.5, 0, -15.0), Vector3(15.0, 0, -14.0)]:
		SetPieces.prop(d, "charred_tree", spot, fposmod(spot.x * 1.3 + spot.z, TAU), 1.0 + fposmod(spot.x, 0.3))
	for i in 26:
		var a := TAU * float(i) / 26.0 + fposmod(float(i) * 2.399, 0.5)
		var r := 2.6 + fposmod(float(i) * 1.618, 1.0) * 5.5
		var spot := FIRE_POS + Vector3(cos(a) * r, 0, sin(a) * r)
		if spot.distance_to(HERO_POS) < 1.0 or spot.distance_to(CAM_POS) < 2.0:
			continue
		SetPieces.prop(d, "ash_tuft", spot, a * 3.0, 0.8 + fposmod(float(i) * 0.37, 0.5))
	_add_ambience("wind_loop", Vector3.INF, -20.0)

	hero = HeroPreview.new()
	hero.name = "HeroPreview"
	world.add_child(hero)
	hero.position = HERO_POS
	# Facing between the camera and the fire (a three-quarter view); a node
	# faces along its -Z (the rig inside is turned to match).
	var to_cam := Vector3(CAM_POS.x - HERO_POS.x, 0, CAM_POS.z - HERO_POS.z).normalized()
	var to_fire := Vector3(FIRE_POS.x - HERO_POS.x, 0, FIRE_POS.z - HERO_POS.z).normalized()
	var facing := to_cam.lerp(to_fire, 0.4).normalized()
	hero.rotation.y = atan2(-facing.x, -facing.z)

	_cam_holder = Node3D.new()
	_cam_holder.name = "TitleCamera"
	world.add_child(_cam_holder)
	camera = Camera3D.new()
	camera.fov = 46.0
	_cam_holder.add_child(camera)
	camera.make_current()
	_place_camera()


func _backdrop_ready() -> void:
	style_manager = StyleManager.new()
	add_child(style_manager)
	style_manager.setup(self, world)
	if look != null:
		style_manager.apply_look(look)
		if look.ash_fall > 0.0:
			_add_ash_fall(look.ash_fall, _cam_holder)
	if MusicDirector.instance != null:
		MusicDirector.instance.play_zone(_zone_music())


func _process(delta: float) -> void:
	_t += delta
	_place_camera()


## A slow sway around the rest pose (one loop every DRIFT_PERIOD seconds).
func _place_camera() -> void:
	if _cam_holder == null:
		return
	var a := TAU * _t / DRIFT_PERIOD
	_cam_holder.position = CAM_POS + Vector3(sin(a) * 0.4, sin(a * 2.0) * 0.05, cos(a) * 0.25 - 0.25)
	_cam_holder.look_at(CAM_LOOK + Vector3(sin(a * 0.5) * 0.12, 0.0, 0.0), Vector3.UP)
