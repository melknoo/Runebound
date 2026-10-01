class_name Grove
extends Object
## M12 forests: rule-placed trees (the burnt forest of the Highlands). Like
## Scatter, nothing is hand-placed and every tree is a MultiMesh instance,
## but trees are big: they cast shadows, show far (fog hides the end) and
## each gets a thin cylinder collider. The colliders sit on their own
## physics layer FOLIAGE, which heroes and enemies collide with but the
## camera's spring arm ignores (a trunk between camera and hero must not
## yank the camera in). Placement: one candidate per cell of a jittered grid
## (`spacing`), kept with the chance `weight(x, z) * density`, never on a
## pad, a keep-clear circle or a route corridor.

const CHUNK := 32.0
const FOLIAGE_LAYER := 0b1000000  # physics layer 7 "foliage"
## Meta on each chunk node: PackedVector3Array of the trees' world positions.
const POINTS_META := &"grove_points"

## rules:
##   prop        prop name (SetPieces kit)
##   area        Rect2 on XZ
##   weight      Callable(x, z) -> 0..1 (a sub-biome's mask weight)
##   density     0..1, chance per cell at full weight
##   spacing     cell size in metres
##   scale       Vector2 (min, max)
##   lean        max tilt in radians
##   exclude     [Vector3(x, z, radius)] keep-clear circles
##   avoid       Callable(Vector2) -> bool (true = no tree here, e.g. routes)
##   height_at   Callable(x, z) -> float
##   collider    Vector2(radius, height)
##   range       visibility range in metres
##   seed        int
## Returns the number of trees.
static func plant(zone: ZoneBase, rules: Dictionary) -> int:
	var mesh := Scatter._item_mesh(String(rules["prop"]))
	if mesh == null:
		return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(rules.get("seed", 1))
	var area: Rect2 = rules["area"]
	var weight: Callable = rules.get("weight", Callable())
	var density := float(rules.get("density", 0.5))
	var spacing := float(rules.get("spacing", 5.0))
	var scale_range: Vector2 = rules.get("scale", Vector2(0.9, 1.3))
	var lean := float(rules.get("lean", 0.12))
	var exclude: Array = rules.get("exclude", [])
	var avoid: Callable = rules.get("avoid", Callable())
	var height_at: Callable = rules["height_at"]
	var collider: Vector2 = rules.get("collider", Vector2(0.3, 3.0))
	var visible_range := float(rules.get("range", 140.0))
	var chunks := {}  # Vector2i -> Array of Transform3D
	var cells := Vector2i(ceili(area.size.x / spacing), ceili(area.size.y / spacing))
	for cz in cells.y:
		for cx in cells.x:
			var p := area.position + (Vector2(cx, cz) + Vector2(rng.randf(), rng.randf())) * spacing
			var chance := rng.randf()
			var w := float(weight.call(p.x, p.y)) if weight.is_valid() else 1.0
			if chance >= w * density or not area.has_point(p):
				continue
			if Scatter._excluded(p, exclude) or (avoid.is_valid() and bool(avoid.call(p))):
				continue
			var s := rng.randf_range(scale_range.x, scale_range.y)
			var tilt := Basis(Vector3.RIGHT.rotated(Vector3.UP, rng.randf() * TAU), rng.randf() * lean)
			var basis := tilt * Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * s)
			var key := Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK))
			if not chunks.has(key):
				chunks[key] = []
			(chunks[key] as Array).append(Transform3D(basis, Vector3(p.x, float(height_at.call(p.x, p.y)) - 0.05, p.y)))
	var count := 0
	for key: Vector2i in chunks:
		count += _emit(zone, key, chunks[key], mesh, String(rules["prop"]), collider, visible_range)
	return count


static func _emit(zone: ZoneBase, key: Vector2i, transforms: Array, mesh: Mesh, prop_name: String,
		collider: Vector2, visible_range: float) -> int:
	var origin := Vector3((key.x + 0.5) * CHUNK, 0.0, (key.y + 0.5) * CHUNK)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	var points := PackedVector3Array()
	var body := StaticBody3D.new()
	body.name = "GroveBody_%s_%d_%d" % [prop_name, key.x, key.y]
	body.collision_layer = FOLIAGE_LAYER
	body.collision_mask = 0
	for i in transforms.size():
		var t: Transform3D = transforms[i]
		points.append(t.origin)
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		var s := t.basis.get_scale().x
		cyl.radius = collider.x * s
		cyl.height = collider.y * s
		shape.shape = cyl
		shape.position = t.origin - origin + Vector3(0, cyl.height * 0.5, 0)
		body.add_child(shape)
		t.origin -= origin
		mm.set_instance_transform(i, t)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Grove_%s_%d_%d" % [prop_name, key.x, key.y]
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mmi.visibility_range_end = visible_range
	mmi.visibility_range_end_margin = 8.0
	mmi.set_meta(POINTS_META, points)
	zone.dressing().add_child(mmi)
	mmi.global_position = origin
	zone.world.add_child(body)
	body.global_position = origin
	return transforms.size()
