class_name ConsumableDrop
extends WorldPickup
## M10b: a consumable lying on the ground (a Healing Draught: a small red
## flask). Glides to its hero like gold and goes into the bag without an
## inventory slot - while the bag has room. With a full bag it stays where it
## lies (no magnet) and says so once, so the hero can come back for it.

signal picked_up(id: StringName, amount: int)

const MAGNET_RANGE := 3.0
const MAGNET_SPEED := 7.0

var id: StringName = Consumables.HEALING_DRAUGHT
var amount: int = 1
var _taken := false
var _told_full := false


func _ready() -> void:
	_bob_height = 0.4
	_bob_amount = 0.06
	_spin = 1.6
	_shape = Node3D.new()
	_shape.scale = Vector3.ONE * 1.8  # rare loot: it has to catch the eye from a few metres
	add_child(_shape)
	var red := ArtKit.color("color_roles.health.body", Color("#D8404A"))
	var glass := MeshInstance3D.new()
	var body := SphereMesh.new()
	body.radius = 0.12
	body.height = 0.22
	body.radial_segments = 8
	body.rings = 4
	body.material = ArtKit.glow_material(red, 1.1)
	glass.mesh = body
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shape.add_child(glass)
	var neck := MeshInstance3D.new()
	var neck_mesh := CylinderMesh.new()
	neck_mesh.top_radius = 0.04
	neck_mesh.bottom_radius = 0.05
	neck_mesh.height = 0.1
	neck_mesh.radial_segments = 6
	neck_mesh.rings = 1
	neck_mesh.material = ArtKit.glow_material(ArtKit.color("color_roles.health.hot", Color("#FF9C9C")), 0.6)
	neck.mesh = neck_mesh
	neck.position.y = 0.14
	neck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shape.add_child(neck)
	var cork := MeshInstance3D.new()
	var cork_mesh := CylinderMesh.new()
	cork_mesh.top_radius = 0.05
	cork_mesh.bottom_radius = 0.045
	cork_mesh.height = 0.05
	cork_mesh.radial_segments = 6
	cork_mesh.rings = 1
	var cork_mat := StandardMaterial3D.new()
	cork_mat.albedo_color = Color("#7A5436")
	cork_mesh.material = cork_mat
	cork.mesh = cork_mesh
	cork.position.y = 0.21
	cork.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shape.add_child(cork)


func _has_room() -> bool:
	return player.consumable_count(id) < Consumables.cap(id)


## Glide towards the hero inside MAGNET_RANGE while the bag has room.
func _pickup_motion(delta: float) -> void:
	if not _has_room():
		return
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	if dist > MAGNET_RANGE or dist < 0.01:
		return
	var speed := MAGNET_SPEED * (1.0 + (MAGNET_RANGE - dist) / MAGNET_RANGE)
	global_position += to_player.normalized() * minf(speed * delta, dist)


func _try_pickup() -> void:
	if _taken:
		return
	var taken := player.add_consumable(id, amount)
	if taken <= 0:
		if not _told_full:
			_told_full = true
			GameFeel.float_text(global_position + Vector3(0, 1.0, 0), "Bag full", UiTheme.MUTED)
		return
	amount -= taken
	Sfx.play("potion_pickup", global_position, -6.0, 0.06)
	GameFeel.float_text(global_position + Vector3(0, 1.1, 0), "+%d %s" % [taken, Consumables.display_name(id)],
		ArtKit.color("color_roles.health.hot", Color("#FF9C9C")))
	picked_up.emit(id, taken)
	if amount <= 0:
		_taken = true
		queue_free()
