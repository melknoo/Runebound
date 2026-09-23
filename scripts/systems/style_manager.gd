class_name StyleManager
extends Node
## Runtime switch between the three M01 art-direction experiments:
##  A LOW-RES   — world rendered at 1/4 resolution, nearest-upscaled
##  B NATIVE    — full res, strong posterize + dither post
##  C HYBRID    — full res, pixel textures/VFX, gentle posterize (default)

enum Style { HYBRID, NATIVE_PIXEL, LOW_RES }

const POST_SHADER := preload("res://shaders/pixel_post.gdshader")

var style: Style = Style.HYBRID

var _lab_root: Node
var _world: Node3D
var _post_rect: ColorRect
var _post_layer: CanvasLayer
var _viewport_container: SubViewportContainer
var _sub_viewport: SubViewport


func setup(lab_root: Node, world: Node3D) -> void:
	_lab_root = lab_root
	_world = world
	_post_layer = CanvasLayer.new()
	_post_layer.layer = 1
	_lab_root.add_child(_post_layer)
	_post_rect = ColorRect.new()
	_post_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_post_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = POST_SHADER
	_post_rect.material = mat
	_post_layer.add_child(_post_rect)
	apply_style(Style.HYBRID)


func style_name() -> String:
	match style:
		Style.LOW_RES:
			return "A low-res"
		Style.NATIVE_PIXEL:
			return "B native-pixel"
		_:
			return "C hybrid"


func cycle() -> void:
	apply_style(((style + 1) % 3) as Style)


func apply_style(new_style: Style) -> void:
	style = new_style
	var mat := _post_rect.material as ShaderMaterial
	match style:
		Style.LOW_RES:
			_enter_low_res()
			_post_rect.visible = false
		Style.NATIVE_PIXEL:
			_exit_low_res()
			_post_rect.visible = true
			mat.set_shader_parameter(&"levels", 7.0)
			mat.set_shader_parameter(&"dither_strength", 0.06)
			mat.set_shader_parameter(&"saturation_boost", 1.15)
		Style.HYBRID:
			_exit_low_res()
			_post_rect.visible = true
			mat.set_shader_parameter(&"levels", 14.0)
			mat.set_shader_parameter(&"dither_strength", 0.02)
			mat.set_shader_parameter(&"saturation_boost", 1.06)


func _enter_low_res() -> void:
	if _viewport_container != null:
		return
	_viewport_container = SubViewportContainer.new()
	_viewport_container.stretch = true
	_viewport_container.stretch_shrink = 4
	_viewport_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_viewport_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sub_viewport = SubViewport.new()
	_sub_viewport.handle_input_locally = false
	_viewport_container.add_child(_sub_viewport)
	_lab_root.add_child(_viewport_container)
	_lab_root.move_child(_viewport_container, 0)
	_world.reparent(_sub_viewport)


func _exit_low_res() -> void:
	if _viewport_container == null:
		return
	_world.reparent(_lab_root)
	_viewport_container.queue_free()
	_viewport_container = null
	_sub_viewport = null
