class_name InteractPrompt
extends Label3D
## "[E] Travel"-style prompt over an interactable (portals, chests). The owner
## calls `update(in_range, text)` every frame; `pressed()` is true on the frame
## the interact key goes down while the prompt shows and combat input is free.
## M12 focus: of the prompts in range only the one nearest the local hero
## shows (and fires), so a grave beside a chest never opens both.

const ACTION := &"interact"

## instance id -> [process frame, distance to the local hero] of the prompts
## that were in range lately (ids, not nodes: statics must not hold nodes).
static var _in_range: Dictionary = {}


static func create(parent: Node3D, height: float) -> InteractPrompt:
	var p := InteractPrompt.new()
	p.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	p.no_depth_test = true
	p.modulate = Color(0.93, 0.9, 0.84)
	p.position = Vector3(0, height, 0)
	p.visible = false
	UiTheme.label3d(p)
	parent.add_child(p)
	return p


## Shows the prompt while `in_range` and it is the nearest one in range;
## text is prefixed with the bound key.
func update(in_range: bool, text: String) -> void:
	var id := get_instance_id()
	if not in_range:
		_in_range.erase(id)
		visible = false
		return
	var frame := Engine.get_process_frames()
	var d := _hero_distance()
	_in_range[id] = [frame, d]
	var nearest := true
	for other: int in _in_range:
		if other == id:
			continue
		var e: Array = _in_range[other]
		if frame - int(e[0]) <= 1 and float(e[1]) < d - 0.01:
			nearest = false
			break
	visible = nearest
	if visible:
		self.text = "[%s] %s" % [key_name(), text]


func _exit_tree() -> void:
	_in_range.erase(get_instance_id())


func _hero_distance() -> float:
	var zone := ZoneBase.zone_of(self)
	if zone == null or zone.player == null or not is_inside_tree():
		return 0.0
	var owner_node := get_parent() as Node3D
	return owner_node.global_position.distance_to(zone.player.global_position) if owner_node != null else 0.0


func pressed(player: Player) -> bool:
	return visible and player != null and player.is_local and not player.input_locked \
		and InputMap.has_action(ACTION) and Input.is_action_just_pressed(ACTION)


static func key_name() -> String:
	return InputSetup.key_label(ACTION)  # M17a: rebindable
