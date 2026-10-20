class_name PortraitView
extends PanelContainer
## M14a: the speaker's face in the dialogue window, live: a small viewport
## that shares the zone's 3D world and looks at the NPC's head from the front,
## rendered at a quarter of its size and scaled up without smoothing (the
## pixel look). Headless or without an NPC it shows the speaker's frame only.

const HEAD_HEIGHT := 1.55
const DISTANCE := 1.15

var _container: SubViewportContainer = null
var _vp: SubViewport = null
var _cam: Camera3D = null
var _target: Node3D = null


func _ready() -> void:
	add_theme_stylebox_override("panel", UiTheme.nine("slot.png", 10, 6))
	if DisplayServer.get_name() == "headless":
		return
	_container = SubViewportContainer.new()
	_container.stretch = true
	_container.stretch_shrink = 4
	_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_container)
	_vp = SubViewport.new()
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.transparent_bg = false
	_container.add_child(_vp)
	_cam = Camera3D.new()
	_cam.fov = 30.0
	_cam.near = 0.05
	_cam.far = 60.0
	_vp.add_child(_cam)


## Looks at `npc` (null: nothing, the frame stays empty).
func show_npc(npc: Node3D) -> void:
	_target = npc if npc != null and is_instance_valid(npc) else null
	if _vp == null:
		return
	if _target == null:
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_container.visible = false
		return
	_vp.world_3d = get_tree().root.world_3d
	_cam.current = true
	_container.visible = true
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_place()


func _process(_delta: float) -> void:
	if _target != null and is_instance_valid(_target) and _vp != null:
		_place()


func _place() -> void:
	var head := _target.global_position + Vector3(0, HEAD_HEIGHT, 0)
	var front := -_target.global_transform.basis.z  # an Npc turns its -Z side towards the hero
	front.y = 0.0
	front = front.normalized() if front.length() > 0.01 else Vector3.FORWARD
	_cam.global_position = head + front * DISTANCE + Vector3(0, 0.08, 0)
	_cam.look_at(head, Vector3.UP)
