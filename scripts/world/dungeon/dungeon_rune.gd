class_name DungeonRune
extends PoiPuzzle
## M13: a rune stone in a dungeon. A hero who comes within ATTUNE_RANGE wakes
## it for the whole party (shared state, kept in the world like a puzzle);
## from then on a hero who falls in this dungeon wakes at the nearest lit
## rune instead of the entrance (DungeonZone._on_player_died runs on the
## hero's own machine and reads the shared state).

const ATTUNE_RANGE := 3.0
const RESPAWN_AHEAD := 1.8

var _requested_at: int = -100000
var _loaded: bool = false
var _glow: MeshInstance3D
var _glow_mat: StandardMaterial3D
var _light: OmniLight3D


static func build(zone: ZoneBase, poi: Dictionary) -> DungeonRune:
	var r := DungeonRune.new()
	r.id = String(poi.get("id", ""))
	r.name = "Rune_" + r.id
	r.act_range = 5.0
	r.state = {"solved": false}
	r.set_meta(&"poi_id", r.id)
	zone.world.add_child(r)
	r.global_position = ZoneLayout.pos_of(poi)
	r.rotation.y = float(poi.get("yaw", 0.0))
	return r


func _ready() -> void:
	_build_stone()
	super()
	_loaded = true


## Greybox: a squat stone on its own collider (foliage layer: heroes bump it,
## the camera passes), a rune face that lights up.
func _build_stone() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Grove.FOLIAGE_LAYER
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.9, 1.5, 0.9)
	col.shape = shape
	col.position = Vector3(0, 0.75, 0)
	body.add_child(col)
	add_child(body)
	var stone := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.9, 1.5, 0.9)
	mesh.material = EnemyBase.flat_material(Color(0.26, 0.3, 0.32))
	stone.mesh = mesh
	stone.position = Vector3(0, 0.75, 0)
	add_child(stone)
	_glow = MeshInstance3D.new()
	var face := BoxMesh.new()
	face.size = Vector3(0.5, 0.5, 0.06)
	_glow_mat = EnemyBase.flat_material(Color(0.3, 0.9, 0.95), true, 0.3)
	face.material = _glow_mat
	_glow.mesh = face
	_glow.position = Vector3(0, 1.0, 0.47)
	add_child(_glow)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.35, 0.95, 0.95)
	_light.omni_range = 5.0
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, 1.4, 0.8)
	add_child(_light)


## Where a fallen hero wakes: a step in front of the stone.
func respawn_point() -> Vector3:
	return global_position + global_transform.basis.z * RESPAWN_AHEAD + Vector3(0, 0.2, 0)


func _process(_delta: float) -> void:
	if is_solved():
		return
	var zone := ZoneBase.zone_of(self)
	var hero := zone.player if zone != null else null
	if hero == null or not is_instance_valid(hero) or hero.health.is_dead:
		return
	if hero.global_position.distance_to(global_position) <= ATTUNE_RANGE \
			and Time.get_ticks_msec() - _requested_at > 2000:
		_requested_at = Time.get_ticks_msec()
		request("light", 0, hero)


func act(action: String, _arg: Variant, _hero: Player) -> void:
	if action != "light" or is_solved():
		return
	state["solved"] = true
	commit()


func _present() -> void:
	var lit := is_solved()
	if _glow_mat != null:
		_glow_mat.emission_energy_multiplier = 2.4 if lit else 0.3
	if _light != null:
		_light.light_energy = 1.2 if lit else 0.0


func _on_solved() -> void:
	if not _loaded:
		return  # lit in an earlier visit: no fanfare
	VFX.light_pop(self, global_position + Vector3(0, 1.2, 0), Color(0.4, 1.0, 1.0), 3.0, 5.0, 0.3)
	Sfx.play("waypoint_attune", global_position, -6.0)
	var zone := ZoneBase.zone_of(self)
	if zone != null and zone.hud != null and zone.player != null \
			and zone.player.global_position.distance_to(global_position) < 20.0:
		zone.hud.toast(Texts.t("ui.dungeon.rune_lit"), Color(0.4, 0.95, 0.95))
