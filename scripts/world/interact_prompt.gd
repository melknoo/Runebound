class_name InteractPrompt
extends Label3D
## "[E] Travel"-style prompt over an interactable (portals, chests). The owner
## calls `update(in_range, text)` every frame; `pressed()` is true on the frame
## the interact key goes down while the prompt shows and combat input is free.

const ACTION := &"interact"


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


## Shows the prompt while `in_range`; text is prefixed with the bound key.
func update(in_range: bool, text: String) -> void:
	visible = in_range
	if in_range:
		self.text = "[%s] %s" % [key_name(), text]


func pressed(player: Player) -> bool:
	return visible and player != null and not player.input_locked \
		and InputMap.has_action(ACTION) and Input.is_action_just_pressed(ACTION)


static func key_name() -> String:
	if not InputMap.has_action(ACTION):
		return "?"
	for ev in InputMap.action_get_events(ACTION):
		if ev is InputEventKey:
			return OS.get_keycode_string((ev as InputEventKey).physical_keycode)
	return "?"
