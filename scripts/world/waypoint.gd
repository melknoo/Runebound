class_name Waypoint
extends Node3D
## M08 waypoint shrine: a rune plinth with a crystal brazier. Walking up to
## it attunes it for every hero in range (per character, saved), lights the
## crystals and pays a little XP; `[E] Travel` then opens the zone's
## WaypointUI (every attuned shrine, Runehold included). Keys are
## "<zone scene basename>:<poi id>" (WaypointRegistry).

const DISCOVER_RANGE := 6.0
const INTERACT_RANGE := 2.6
const DISCOVER_XP := 40
const PROP := "waypoint_shrine"

var id: String = ""
var display_name: String = "Waypoint"
## The hub's shrine: every character knows it.
var always_known: bool = false

var _body: StaticBody3D
var _prompt: InteractPrompt
var _label: Label3D
var _light: OmniLight3D
var _lit: bool = false
var _glow_surfaces: Array = []  # [MeshInstance3D, surface, lit material]
var _dim_material: Material


func _ready() -> void:
	name = "Waypoint_" + id.get_slice(":", 1) if name.begins_with("@") or name == "" else name
	var accent := ArtKit.color("color_roles.player_accent.body", Color(0.37, 0.88, 0.91))
	# Collider the shrine wraps (box mesh hidden by the kit prop; greybox otherwise).
	_body = StaticBody3D.new()
	_body.collision_layer = 1
	_body.collision_mask = 0
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.2, 2.2, 1.2)
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.3, 0.3, 0.36)
	box.material = grey
	mesh.mesh = box
	_body.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	col.shape = shape
	_body.add_child(col)
	add_child(_body)
	_body.position = Vector3(0, 1.1, 0)
	var zone := ZoneBase.zone_of(self)
	if zone != null and zone.look != null and zone.look.art_pass:
		var inst := SetPieces.wrap_collider(_body, PROP)
		if inst != null:
			_collect_glow(inst, accent)
	_light = OmniLight3D.new()
	_light.light_color = accent
	_light.light_energy = 0.0
	_light.omni_range = 6.0
	_light.shadow_enabled = false
	add_child(_light)
	_light.position = Vector3(0, 2.2, 0)
	_label = Label3D.new()
	_label.text = display_name
	_label.modulate = accent
	_label.outline_size = 10
	_label.outline_modulate = Color(0.05, 0.03, 0.08)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0, 3.0, 0)
	UiTheme.label3d(_label)
	_label.visibility_range_end = 90.0  # a guide nearby, not clutter across the zone
	_label.visibility_range_end_margin = 10.0
	add_child(_label)
	_prompt = InteractPrompt.create(self, 2.6)


func _collect_glow(inst: Node3D, accent: Color) -> void:
	_dim_material = ArtKit.glow_material(accent.darkened(0.65), 0.12)
	for child in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var imported := mi.mesh.surface_get_material(s)
			if imported != null and imported.resource_name.ends_with("_glow"):
				_glow_surfaces.append([mi, s, mi.get_surface_override_material(s)])
				mi.set_surface_override_material(s, _dim_material)


## Attuned by this hero (the hub's shrine always is).
func is_known(p: Player) -> bool:
	return always_known or (p != null and is_instance_valid(p) and p.knows_waypoint(id))


func _process(_delta: float) -> void:
	var zone := ZoneBase.zone_of(self)
	if zone == null:
		_prompt.update(false, "")
		return
	var lp := zone.player
	var known := is_known(lp)
	if not always_known:
		for p in zone.players_within(global_position, DISCOVER_RANGE):
			if p.discover_waypoint(id, display_name) and p.is_local:
				var scene := get_tree().current_scene
				var accent := ArtKit.color("color_roles.player_accent.body", Color(0.37, 0.88, 0.91))
				VFX.flash(scene, global_position + Vector3(0, 2.0, 0), accent, 1.6, 0.3)
				VFX.ground_ring(scene, global_position, accent, 3.2, 0.5)
		known = is_known(lp)
	_set_lit(known)
	if lp == null or not is_instance_valid(lp):
		_prompt.update(false, "")
		return
	var near := lp.global_position.distance_to(global_position) <= INTERACT_RANGE
	_prompt.update(near and known, "Travel")
	if _prompt.pressed(lp):
		zone.open_waypoints(self)


func _set_lit(lit: bool) -> void:
	if lit == _lit:
		return
	_lit = lit
	_light.light_energy = 1.3 if lit else 0.0
	for entry: Array in _glow_surfaces:
		(entry[0] as MeshInstance3D).set_surface_override_material(int(entry[1]), entry[2] if lit else _dim_material)


func is_lit() -> bool:
	return _lit
