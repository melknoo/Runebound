class_name Hurtbox
extends Area3D
## Damage-receiving area that points back at its owning entity.

var owner_entity: Node = null


static func create(entity: Node3D, layer_bits: int, radius: float, height: float, y_offset: float) -> Hurtbox:
	var hb := Hurtbox.new()
	hb.owner_entity = entity
	hb.collision_layer = layer_bits
	hb.collision_mask = 0
	hb.monitoring = false
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = height
	col.shape = capsule
	col.position = Vector3(0, y_offset, 0)
	hb.add_child(col)
	entity.add_child(hb)
	return hb
