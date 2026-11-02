class_name StoryNpc
extends Npc
## M14a: someone the story places (Edda by the hearth, a deserter at a ruin):
## built by the QuestDirector from `resources/story/stage.json` on this
## machine only (the server builds none; every player talks on their own
## machine). Looks come from `npcs.json` (a class rig, a tint, gear looks);
## talking opens its dialogue. A hidden one (its stage entry's `show_if` /
## `hide_if`) neither draws, collides nor listens. M14b: `"ghost": true` in
## npcs.json makes an echo (Aldric at the anchors): pale and see-through like
## the Highlands' ghosts, no outline, no body to bump into, a slow float.

const GHOST_TINT := Color(0.62, 0.86, 0.9)

## npcs.json id; also the dialogue file's name.
var story_id: String = ""
## The stage entry that placed it ({} for a test NPC).
var stage: Dictionary = {}
var shown: bool = true
## M14b: an echo (see the header).
var ghost: bool = false

var _body: StaticBody3D = null
var _float: float = 0.0


## A story NPC from its npcs.json entry (not yet in the tree).
static func create(id: String) -> StoryNpc:
	var n := StoryNpc.new()
	n.story_id = id
	n.name = "StoryNpc_" + id
	var d := StoryDB.npc(id)
	n.npc_name = str(d.get("name", id))  # a text key: the nameplate translates itself
	n.prompt_text = Texts.t("ui.prompt.talk")
	var rig := str(d.get("rig", "runebreaker"))
	n.rig_path = "res://assets/models/chars/%s.glb" % rig
	n.material_id = rig
	if d.has("tint"):
		n.body_tint = Color(str(d["tint"]))
	if d.has("rune"):
		n.rune_color = Color(str(d["rune"]))
	var looks: Variant = d.get("looks", {})
	if looks is Dictionary:
		n.looks = (looks as Dictionary).duplicate()
	n.ghost = bool(d.get("ghost", false))
	return n


func _ready() -> void:
	super()
	add_to_group(&"story_npc")
	add_to_group(&"story_target")
	set_meta(&"story_id", story_id)
	for child in get_children():
		if child is StaticBody3D:
			_body = child as StaticBody3D
	if ghost:
		_ghostify()
	interacted.connect(_on_interacted)


## An echo: every surface pale and see-through, no outline, no shadow, no body.
func _ghostify() -> void:
	if _body != null:
		_body.collision_layer = 0
	if _visual == null:
		return
	for node in _visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for i in mesh.mesh.get_surface_count():
			var src := mesh.get_active_material(i) as StandardMaterial3D
			if src == null:
				continue
			var mat := src.duplicate() as StandardMaterial3D
			mat.next_pass = null  # no outline: an echo does not act
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = Color(GHOST_TINT, 0.5)
			mat.emission_enabled = true
			mat.emission = GHOST_TINT
			mat.emission_energy_multiplier = 0.45
			mat.set_meta(ArtKit.KEEP_EMISSION, true)
			mesh.set_surface_override_material(i, mat)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(delta: float) -> void:
	super(delta)
	if ghost and _visual != null:
		_float += delta
		_visual.position.y = 0.25 + sin(_float * 1.3) * 0.08


func set_shown(on: bool) -> void:
	if on == shown:
		return
	shown = on
	visible = on
	if not on:
		_prompt.update(false, "")
	set_process(on)
	if _body != null:
		_body.collision_layer = 0b1 if on and not ghost else 0


func _on_interacted(player: Player) -> void:
	var zone := ZoneBase.zone_of(self)
	if zone != null and zone.get(&"dialogue_ui") != null:
		zone.dialogue_ui.try_open(story_id, self, player)
