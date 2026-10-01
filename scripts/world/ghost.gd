class_name Ghost
extends Interactable
## M12: a ghost of the Highlands - a pale, see-through figure that floats
## where it died and tells its story ([E] Listen: the lore window). No
## outline and no collider: the outline means "can act" (ART_BIBLE), and a
## ghost never fights. It fades in as a hero comes near and turns to face
## them. The words are lore (`<lore_id>.title/.body`), the first listen goes
## into the chronicle.

const LISTEN_XP := 20
const SEEN_RANGE := 16.0
const PALE := Color(0.78, 0.86, 0.92)

var lore_id: String = ""
var _visual: Node3D
var _materials: Array[StandardMaterial3D] = []
var _bob: float = 0.0
var _alpha: float = 0.0


static func build(zone: ZoneBase, poi: Dictionary) -> Ghost:
	var ghost := Ghost.new()
	ghost.name = "Ghost_" + String(poi.get("id", ""))
	ghost.id = String(poi.get("id", ""))
	ghost.lore_id = String(poi.get("text", ""))
	ghost.reach = 3.0
	ghost.prompt_height = 2.3
	var pos := ZoneLayout.pos_of(poi)
	pos.y = zone.ground_y(pos)
	zone.world.add_child(ghost)
	ghost.global_position = pos
	ghost.rotation.y = PoiBuilder.yaw_of(poi)
	ghost._build_visual(String(poi.get("rig", "druid")))
	return ghost


func _build_visual(rig: String) -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	var path := "res://assets/models/chars/%s.glb" % rig
	var scene := ArtKit.rig_scene(path)
	if scene == null or DisplayServer.get_name() == "headless":
		return
	var model := scene.instantiate() as Node3D
	model.rotation.y = PI
	_visual.add_child(model)
	ArtKit.dress_rig(model, rig, PALE, PALE, 0.6)
	for mi: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := mi as MeshInstance3D
		for s in mesh.mesh.get_surface_count():
			var mat := mesh.get_surface_override_material(s) as StandardMaterial3D
			if mat == null:
				continue
			mat = mat.duplicate() as StandardMaterial3D
			mat.next_pass = null  # no outline: a ghost does not act
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = Color(PALE, 0.0)
			mat.emission = PALE
			mat.emission_energy_multiplier = 0.35
			mat.set_meta(ArtKit.KEEP_EMISSION, true)
			mesh.set_surface_override_material(s, mat)
			_materials.append(mat)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var anims := model.find_children("*", "AnimationPlayer", true, false)
	if not anims.is_empty():
		var anim := anims[0] as AnimationPlayer
		if anim.has_animation(&"idle"):
			anim.play(&"idle")
			anim.speed_scale = 0.5
			anim.animation_finished.connect(func(_n: StringName) -> void: anim.play(&"idle"))


func prompt_text(_hero: Player) -> String:
	return Texts.t("ui.prompt.listen")


func interact(hero: Player) -> void:
	var zone := ZoneBase.zone_of(self)
	if zone == null:
		return
	if zone.lore_ui != null:
		zone.lore_ui.open(lore_id, "lore.kind.ghost", hero)
	if hero.read_lore(lore_id):
		zone.receive_reward(hero, LISTEN_XP, 0, 0, [], global_position, "", true)


func _process(delta: float) -> void:
	super._process(delta)
	var zone := ZoneBase.zone_of(self)
	var hero := zone.player if zone != null else null
	var d := global_position.distance_to(hero.global_position) if hero != null else INF
	var target := clampf((SEEN_RANGE - d) / 6.0, 0.0, 1.0) * 0.5  # never more than half there
	_alpha = move_toward(_alpha, target, delta * 0.6)
	for mat in _materials:
		mat.albedo_color.a = _alpha
	_visual.visible = _alpha > 0.01
	_bob += delta
	_visual.position.y = 0.3 + sin(_bob * 1.2) * 0.08
	if hero != null and d < SEEN_RANGE:
		var to := hero.global_position - global_position
		var want := atan2(to.x, to.z)
		rotation.y = rotate_toward(rotation.y, want, delta * 1.5)
