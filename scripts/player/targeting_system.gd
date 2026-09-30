class_name TargetingSystem
extends Node3D
## Manual Tab-targeting + world-space target UI (feet ring, HP bar).
## Tab selects the enemy nearest the camera aim; pressing Tab again cycles
## through the other valid candidates. The target persists until it dies or
## leaves range. Melee auto-faces the current target (see Player).

const MAX_RANGE := 15.0
const MAX_ANGLE := 0.9   # radians off camera-forward to qualify for selection
const DROP_RANGE := 18.0  # a held target is only dropped past this distance

var player: Player
var camera_rig: CameraRig
var current: EnemyBase = null

var _ring: MeshInstance3D
var _bar: MeshInstance3D
var _bar_mat: ShaderMaterial
var _name_label: Label3D
var _pips: Array[MeshInstance3D] = []
var _pip_mats: Array[StandardMaterial3D] = []
## M11: the ally a heal would go to right now (a healer only; null otherwise
## or when it is the hero itself), marked by a green chevron over its head.
var heal_target: Player = null
var _ally_marker: MeshInstance3D

## M11: an ally counts as under the crosshair this close to the camera ray
## (metres, widening a little with distance).
const ALLY_AIM_RADIUS := 1.2

const PIP_COLORS: Array[Color] = [
	Color(1.0, 0.55, 0.15),  # burn
	Color(0.5, 0.85, 1.0),   # chill
	Color(1.0, 0.95, 0.4),   # shock
]


func _ready() -> void:
	# Feet ring: slowly rotating teal pixel ring.
	_ring = MeshInstance3D.new()
	var ring_mesh := PlaneMesh.new()
	ring_mesh.size = Vector2(1.5, 1.5)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	ring_mat.alpha_scissor_threshold = 0.3
	ring_mat.albedo_texture = load("res://assets/vfx/ring.png") if ResourceLoader.exists("res://assets/vfx/ring.png") else null
	ring_mat.albedo_color = Color(0.35, 0.95, 0.85, 0.9)
	ring_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	ring_mat.disable_receive_shadows = true
	ring_mesh.material = ring_mat
	_ring.mesh = ring_mesh
	add_child(_ring)

	# HP bar above the target's head.
	_bar = MeshInstance3D.new()
	var bar_mesh := QuadMesh.new()
	bar_mesh.size = Vector2(1.1, 0.14)
	_bar_mat = ShaderMaterial.new()
	_bar_mat.shader = load("res://shaders/hp_bar.gdshader")
	bar_mesh.material = _bar_mat
	_bar.mesh = bar_mesh
	add_child(_bar)

	# Status pips under the bar: burn / chill / shock, lit while active.
	for i in 3:
		var pip := MeshInstance3D.new()
		var pip_mesh := QuadMesh.new()
		pip_mesh.size = Vector2(0.12, 0.12)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.albedo_color = PIP_COLORS[i]
		mat.no_depth_test = true
		mat.disable_receive_shadows = true
		pip_mesh.material = mat
		pip.mesh = pip_mesh
		add_child(pip)
		_pips.append(pip)
		_pip_mats.append(mat)

	# Name plate above the bar.
	_name_label = Label3D.new()
	_name_label.font_size = 40
	_name_label.pixel_size = 0.004
	_name_label.outline_size = 12
	_name_label.outline_modulate = Color(0.05, 0.03, 0.08)
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.no_depth_test = true
	UiTheme.label3d(_name_label)
	add_child(_name_label)

	_set_marker_visible(false)

	# M11: the heal target's chevron (nature green, drawn over everything).
	_ally_marker = MeshInstance3D.new()
	var chevron := PrismMesh.new()
	chevron.size = Vector3(0.34, 0.26, 0.06)
	var cmat := StandardMaterial3D.new()
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cmat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	cmat.no_depth_test = true
	cmat.albedo_color = ArtKit.color("color_roles.nature.body", Color("#7ED957"))
	chevron.material = cmat
	_ally_marker.mesh = chevron
	_ally_marker.rotation_degrees = Vector3(0, 0, 180)  # point down at the ally
	_ally_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ally_marker.visible = false
	add_child(_ally_marker)


func _set_marker_visible(vis: bool) -> void:
	_ring.visible = vis
	_bar.visible = vis
	_name_label.visible = vis
	if not vis:
		for pip in _pips:
			pip.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"target_cycle"):
		cycle_target()


func _process(delta: float) -> void:
	if player == null or camera_rig == null:
		return
	_update_heal_target()
	_validate_current()
	if current == null:
		_set_marker_visible(false)
		return
	_set_marker_visible(true)
	var pos := current.global_position
	_ring.global_position = Vector3(pos.x, pos.y + 0.06, pos.z)
	_ring.rotate_y(delta * 1.2)
	var head := current.nameplate_height()
	_bar.global_position = pos + Vector3(0, head, 0)
	_name_label.global_position = pos + Vector3(0, head + 0.2, 0)
	_name_label.text = current.display_name if current.level <= 1 else "%s   Lv %d" % [current.display_name, current.level]
	if current is AshveinColossus or current is ShatteredVessel:
		_name_label.modulate = Color(1.0, 0.6, 0.3)
	elif current.is_elite:
		_name_label.modulate = Color(1.0, 0.82, 0.35)
	else:
		_name_label.modulate = Color(0.95, 0.92, 0.85)
	_bar_mat.set_shader_parameter(&"fill",
		clampf(current.health.current_health / current.health.max_health, 0.0, 1.0))
	_bar_mat.set_shader_parameter(&"fill_color",
		Vector3(1.0, 0.78, 0.25) if current.is_elite else Vector3(0.88, 0.25, 0.2))
	var active: Array[bool] = [current.status.has_burn(), current.status.has_chill(), current.status.has_shock()]
	var shown := 0
	for i in 3:
		_pips[i].visible = active[i]
		if active[i]:
			_pips[i].global_position = pos + Vector3(-0.4 + shown * 0.18, head - 0.18, 0)
			shown += 1


func _score(enemy: EnemyBase, cam_pos: Vector3, cam_fwd: Vector3) -> float:
	# Lower is better: angle off aim dominates, distance breaks ties.
	var to_enemy := enemy.global_position + Vector3(0, 0.9, 0) - cam_pos
	var dist := to_enemy.length()
	if dist < 0.5:
		return INF
	var angle := acos(clampf(cam_fwd.dot(to_enemy / dist), -1.0, 1.0))
	if angle > MAX_ANGLE:
		return INF
	if enemy.global_position.distance_to(player.global_position) > MAX_RANGE:
		return INF
	return angle + dist * 0.02


## Drop the held target only when it dies or gets genuinely far away —
## a Tab-selected target should survive camera turns and repositioning.
func _validate_current() -> void:
	if current == null:
		return
	if not is_instance_valid(current) or current.ai_state == EnemyBase.AIState.DEAD \
			or current.global_position.distance_to(player.global_position) > DROP_RANGE:
		current = null


## Valid selection candidates, sorted by aim proximity (best first).
func gather_candidates() -> Array[EnemyBase]:
	var cam_pos := camera_rig.camera.global_position
	var cam_fwd := -camera_rig.camera.global_transform.basis.z
	var candidates: Array[EnemyBase] = []
	var scores: Dictionary = {}
	for enemy in EnemyBase.all_enemies:
		if not is_instance_valid(enemy) or enemy.ai_state == EnemyBase.AIState.DEAD:
			continue
		var s := _score(enemy, cam_pos, cam_fwd)
		if s < INF:
			candidates.append(enemy)
			scores[enemy] = s
	candidates.sort_custom(func(a: EnemyBase, b: EnemyBase) -> bool:
		return scores[a] < scores[b])
	return candidates


## Best enemy near the aim right now (for abilities needing a target when
## nothing is Tab-selected). Does not change the held target.
func best_candidate() -> EnemyBase:
	var candidates := gather_candidates()
	return candidates[0] if not candidates.is_empty() else null


## Tab: no target → pick the candidate nearest the aim; with a target →
## cycle to the next candidate (sorted by aim proximity), wrapping around.
func cycle_target() -> void:
	# Input events can arrive before _process validated the held target;
	# a freed enemy in `current` breaks the typed-array find below.
	_validate_current()
	var candidates := gather_candidates()
	if candidates.is_empty():
		current = null
		return
	# Manual scan instead of find(): a typed-array find validates its argument
	# and errors on a reference freed this very frame (co-op despawns will do that).
	var idx := -1
	for i in candidates.size():
		if candidates[i] == current:
			idx = i
			break
	current = candidates[(idx + 1) % candidates.size()] if idx >= 0 else candidates[0]


# ---------------------------------------------------------------------------
# M11: friendly targets (the druid's heals)
# ---------------------------------------------------------------------------

## The ally (never the hero itself) nearest the camera's aim ray within
## `max_range` of the hero and in sight of the camera; null when none is.
## Remote heroes have no collision layer, so this is geometry, not a raycast.
func ally_under_aim(max_range: float) -> Player:
	var zone := ZoneBase.zone_of(player)
	if zone == null or camera_rig == null:
		return null
	var cam_pos := camera_rig.camera.global_position
	var cam_fwd := -camera_rig.camera.global_transform.basis.z
	var best: Player = null
	var best_off := INF
	for ally in zone.players_within(player.global_position, max_range):
		if ally == player:
			continue
		var chest := ally.global_position + Vector3(0, 1.1, 0)
		var rel := chest - cam_pos
		var along := rel.dot(cam_fwd)
		if along <= 0.5:
			continue
		var off := (rel - cam_fwd * along).length()
		if off > ALLY_AIM_RADIUS + along * 0.02 or off >= best_off:
			continue
		var q := PhysicsRayQueryParameters3D.create(cam_pos, chest, 1)  # world only
		if not player.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			continue
		best = ally
		best_off = off
	return best


func _update_heal_target() -> void:
	heal_target = null
	if player.shows_heal_target():
		var t := player.pick_heal_target()
		if t != player:
			heal_target = t
	_ally_marker.visible = heal_target != null
	if heal_target != null:
		_ally_marker.global_position = heal_target.global_position + Vector3(0, 2.45, 0)
