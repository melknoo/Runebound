class_name CurseLantern
extends EnemyBase
## M12 the cursed graveyard: one of the three lanterns Ashwick's priest lit to
## keep the dead in their graves - now they keep them from rest. It neither
## moves nor fights; while one still burns, the dead rise around it
## (CursedGround). Break all three and the curse lifts.

const PROP := "curse_lantern"
const GLOW := Color("#C8D86A")


func _init() -> void:
	xp_value = 14
	display_name = Texts.t("enemy.curse_lantern")
	max_health = 70.0
	move_speed = 0.0
	body_color = Color(0.5, 0.45, 0.38)
	immobile = true
	stagger_resist = true
	loot_kind = &"none"


func nameplate_height() -> float:
	return 2.25


func _build_body() -> void:
	if _setup_prop_visual(PROP):
		return
	var post := MeshInstance3D.new()  # fallback (and the dedicated server): a post with a light
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.15, 1.8, 0.15)
	mesh.material = flat_material(body_color)
	post.mesh = mesh
	post.position = Vector3(0, 0.9, 0)
	visual.add_child(post)
	var flame := MeshInstance3D.new()
	var fmesh := BoxMesh.new()
	fmesh.size = Vector3(0.2, 0.25, 0.2)
	fmesh.material = flat_material(GLOW, true, 2.0)
	flame.mesh = fmesh
	flame.position = Vector3(0.44, 1.37, 0)
	visual.add_child(flame)


func _ai_process(delta: float) -> void:
	brake(delta)
	if ai_state == AIState.STAGGER and _state_timer >= 0.0:
		_enter_state(AIState.IDLE)


func _death_presentation() -> void:
	var scene := get_tree().current_scene
	var at := global_position + Vector3(0.44, 1.37, 0).rotated(Vector3.UP, visual.rotation.y)
	VFX.burst(scene, at, {"tex": "ember", "amount": 22, "size": 0.12, "vel_min": 1.5, "vel_max": 4.0,
		"gravity": Vector3(0, -3.0, 0), "colors": [GLOW, Color(GLOW, 0.0)] as Array[Color], "emission_radius": 0.2})
	VFX.flash(scene, at, GLOW, 1.4, 0.2)
	Sfx.play("shatter_burst", global_position, -6.0, 0.1, 1.5)
	super()
