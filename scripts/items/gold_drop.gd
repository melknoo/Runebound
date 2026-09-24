class_name GoldDrop
extends WorldPickup
## M07b currency pickup: a small stack of rune-gold coins that glides to the
## player once they come close and is always picked up (no inventory slot).
## Kept cheap on purpose (no light, no label): every kill drops one.

signal picked_up(amount: int)

const MAGNET_RANGE := 3.0
const MAGNET_SPEED := 7.0
const COIN_RADIUS := 0.13
const COIN_HEIGHT := 0.035

var amount: int = 1
var _taken := false


func _ready() -> void:
	_bob_height = 0.22
	_bob_amount = 0.04
	_spin = 2.2
	_shape = Node3D.new()
	add_child(_shape)
	var gold := ArtKit.color("color_roles.resonance.body", Color("#E8B23A"))
	var hot := ArtKit.color("color_roles.resonance.hot", Color("#FFD97A"))
	var coins := 3 if amount >= 20 else (2 if amount >= 6 else 1)
	for i in coins:
		var coin := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = COIN_RADIUS
		mesh.bottom_radius = COIN_RADIUS
		mesh.height = COIN_HEIGHT
		mesh.radial_segments = 10
		mesh.rings = 1
		mesh.material = ArtKit.glow_material(hot if i == coins - 1 else gold, 1.1)
		coin.mesh = mesh
		coin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a := TAU * float(i) / float(coins)
		coin.position = Vector3(cos(a), 0.0, sin(a)) * (0.06 if coins > 1 else 0.0) + Vector3(0, COIN_HEIGHT * float(i), 0)
		coin.rotation.y = a
		_shape.add_child(coin)


## Glide towards the player inside MAGNET_RANGE (faster the closer it gets).
func _pickup_motion(delta: float) -> void:
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
	_taken = true
	player.add_gold(amount)
	Sfx.play("coin_pickup", global_position, -6.0, 0.06, 1.0 + minf(float(amount), 60.0) / 300.0)
	GameFeel.float_text(global_position + Vector3(0, 1.2, 0), "+%d gold" % amount,
		ArtKit.color("color_roles.resonance.hot", Color("#FFD97A")))
	picked_up.emit(amount)
	queue_free()
