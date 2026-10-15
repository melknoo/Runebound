class_name HeroPreview
extends Node3D
## M17a: the selected character in its own class rig, standing by the title
## screen's campfire (idle). A new pick plays the class's signature move
## once (the war cry, a frost nova, a bloom), then it settles into idle again.

## Signature clip per class (tools/modelgen generate_characters_v2 clip names).
const FLOURISH := {&"runebreaker": &"challenge", &"elementalist": &"frost_nova", &"druid": &"bloom"}

var class_id: StringName = &""
var _model: Node3D
var _anim: AnimationPlayer
var _look: HeroLook = null


## Shows `cls` (null hides the figure); `flourish` plays its signature move.
func show_class(cls: ClassData, flourish: bool = false) -> void:
	if cls == null:
		_clear()
		class_id = &""
		return
	if cls.id != class_id or _model == null:
		_clear()
		class_id = cls.id
		_build(cls)
	if flourish:
		play_flourish()


## Rig v3: a saved character's class in its saved gear (the start kit for a
## character saved before the kit existed).
func show_character(ch: Dictionary, flourish: bool = false) -> void:
	if ch.is_empty():
		show_class(null)
		return
	var cls := ClassData.load_by_id(StringName(str(ch.get("class_id", ClassData.DEFAULT_ID))))
	show_class(cls, flourish)
	if _look == null:
		return
	var equipped: Dictionary = (ch.get("equipped", {}) as Dictionary).duplicate()
	if not bool(ch.get("kit", false)):
		for item in ItemGenerator.starter_kit(cls.id):
			if not equipped.has(str(int(item.slot))):
				equipped[str(int(item.slot))] = item.to_dict()
	_look.apply(HeroLook.looks_for(equipped, GameSettings.hide_helm()))


## The look shown now (tests): region -> look, empty without a Rig v3 class.
func looks_shown() -> Dictionary:
	var out := {}
	if _look != null:
		for region: StringName in HeroLook.REGIONS:
			out[region] = _look.look_of(region)
	return out


func play_flourish() -> void:
	if _anim == null:
		return
	var clip: StringName = FLOURISH.get(class_id, &"")
	if clip != &"" and _anim.has_animation(clip):
		_anim.play(clip, 0.15)


func _build(cls: ClassData) -> void:
	var glow := ArtKit.color("color_roles.%s.body" % cls.resource_color_role, Color("#3CBEB4"))
	if HeroLook.available(cls.id):  # Rig v3: the modular hero, in the start kit until show_character
		_look = HeroLook.create(self, cls.id, glow, 1.2, cls.body_tint)
		_look.apply(HeroLook.KIT_LOOKS)
		_model = _look.model
	else:
		var scene := ArtKit.rig_scene(cls.rig_path)
		if scene == null:
			return
		_model = scene.instantiate() as Node3D
		_model.rotation.y = PI  # Blender front lands at Godot +Z
		add_child(_model)
		ArtKit.dress_rig(_model, cls.material_id if cls.material_id != "" else "runebreaker", cls.body_tint, glow, 1.2)
	var anims := _model.find_children("*", "AnimationPlayer", true, false)
	if anims.is_empty():
		return
	_anim = anims[0] as AnimationPlayer
	if _anim.has_animation(&"idle"):
		_anim.play(&"idle")
	# Like Npc: the imported clips don't loop (shared resources, left as they are).
	_anim.animation_finished.connect(func(_clip: StringName) -> void:
		if _anim != null and _anim.has_animation(&"idle"):
			_anim.play(&"idle", 0.25)
	)


func _clear() -> void:
	if _model != null:
		# Drop the materials before the rig goes: freed together, the outlined
		# body material vanished under its live instance ("material is null").
		for mi: Node in _model.find_children("*", "MeshInstance3D", true, false):
			var mesh := mi as MeshInstance3D
			for i in mesh.get_surface_override_material_count():
				mesh.set_surface_override_material(i, null)
		remove_child(_model)
		_model.queue_free()
	_model = null
	_anim = null
	_look = null
