class_name Npc
extends Node3D
## M07b: a friendly character standing in a zone. Nameplate, "[E] Talk"
## prompt, turns towards a nearby player; `interacted` fires on the interact
## key. Visual: a class rig re-tinted (a proper NPC model comes with M11), a
## capsule when the GLB is missing. Subclasses set the name, prompt and what
## talking does.

signal interacted(player: Player)

const TALK_RANGE := 2.4
const TURN_SPEED := 5.0

@export var npc_name: String = "Stranger"
@export var prompt_text: String = "Talk"
## Rig and atlas to borrow (default: the Runebreaker's) plus a tint over its body.
@export var rig_path: String = "res://assets/models/chars/runebreaker.glb"
@export var material_id: String = "runebreaker"
@export var body_tint: Color = Color(0.86, 0.66, 0.42)
@export var rune_color: Color = Color("#E8B23A")

var _prompt: InteractPrompt
var _visual: Node3D
var _anim: AnimationPlayer
var _home_yaw: float = 0.0


func _ready() -> void:
	_home_yaw = rotation.y
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	if not _build_rig():
		_build_capsule()
	# A body the player bumps into (world layer), no hurtbox: NPCs aren't targets.
	var body := StaticBody3D.new()
	body.collision_layer = 0b1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.42
	capsule.height = 1.7
	col.shape = capsule
	col.position = Vector3(0, 0.85, 0)
	body.add_child(col)
	add_child(body)
	var plate := Label3D.new()
	plate.text = npc_name
	plate.modulate = ArtKit.color("color_roles.resonance.hot", Color("#FFD97A"))
	plate.outline_size = 10
	plate.outline_modulate = Color(0.05, 0.03, 0.08)
	plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	plate.no_depth_test = true
	plate.position = Vector3(0, 2.1, 0)
	UiTheme.label3d(plate)
	add_child(plate)
	_prompt = InteractPrompt.create(self, 2.45)


func _build_rig() -> bool:
	var scene := ArtKit.rig_scene(rig_path)
	if scene == null:
		return false
	var model := scene.instantiate() as Node3D
	model.rotation.y = PI  # Blender front lands at Godot +Z
	_visual.add_child(model)
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	if not meshes.is_empty():
		var mesh := meshes[0] as MeshInstance3D
		var mat := ArtKit.character_material(material_id)  # a fresh material per call
		mat.albedo_color = body_tint
		mesh.set_surface_override_material(0, mat)
		if mesh.mesh.get_surface_count() > 1:
			mesh.set_surface_override_material(1, ArtKit.glow_material(rune_color, 1.0))
		for s in range(2, mesh.mesh.get_surface_count()):  # weapon surfaces: plain steel
			mesh.set_surface_override_material(s, ArtKit.character_material(material_id))
	var anims := model.find_children("*", "AnimationPlayer", true, false)
	if not anims.is_empty():
		_anim = anims[0] as AnimationPlayer
		if _anim.has_animation(&"idle"):
			_anim.play(&"idle")
			_anim.animation_finished.connect(func(_name: StringName) -> void: _anim.play(&"idle"))
	return true


func _build_capsule() -> void:
	var mi := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = 1.7
	var mat := StandardMaterial3D.new()
	mat.albedo_color = body_tint
	capsule.material = mat
	mi.mesh = capsule
	mi.position = Vector3(0, 0.85, 0)
	_visual.add_child(mi)


func _process(delta: float) -> void:
	var zone := get_tree().current_scene as ZoneBase
	if zone == null or zone.player == null or not is_instance_valid(zone.player):
		_prompt.update(false, "")
		return
	var player := zone.player
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	var near := to_player.length() <= TALK_RANGE
	# Face whoever comes close, settle back home when they leave.
	var target_yaw := _home_yaw
	if to_player.length() <= TALK_RANGE * 2.0 and to_player.length() > 0.05:
		target_yaw = atan2(-to_player.x, -to_player.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, minf(TURN_SPEED * delta, 1.0))
	_prompt.update(near, prompt_text)
	if _prompt.pressed(player):
		interacted.emit(player)
