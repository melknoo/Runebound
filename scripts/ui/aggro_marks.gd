class_name AggroMarks
extends Node
## M10: a small mark over every enemy that is after this machine's hero - in a
## party, so a tank sees what it holds and a caster what is coming for it.
## Alone every enemy is after you, so the marks only show with two or more
## heroes in the zone. Co-op clients know an enemy's target from ENEMY_TARGET
## (EnemyBase.target_peer); offline the enemy's own target.

const REFRESH := 0.2

var zone: ZoneBase
var _marks: Dictionary = {}  # enemy instance id -> Label3D
var _left: float = 0.0


func setup(z: ZoneBase) -> void:
	zone = z


## Is `e` hunting `hero` (this machine's)?
static func targets_hero(e: EnemyBase, hero: Player) -> bool:
	if e.net_puppet:
		return e.target_peer != 0 and e.target_peer == Net.my_id()
	return e.target == hero


func mark_count() -> int:
	var n := 0
	for id: int in _marks:
		if is_instance_valid(_marks[id]):
			n += 1
	return n


func _process(delta: float) -> void:
	_left -= delta
	if _left > 0.0 or zone == null:
		return
	_left = REFRESH
	var hero := zone.local_player
	var seen := {}
	if hero != null and is_instance_valid(hero) and zone.players.size() > 1:
		for e in EnemyBase.all_enemies:
			if not is_instance_valid(e) or e.ai_state == EnemyBase.AIState.DEAD or not targets_hero(e, hero):
				continue
			var id := e.get_instance_id()
			seen[id] = true
			var mark: Variant = _marks.get(id)  # untyped: it may have been freed with its enemy
			if mark == null or not is_instance_valid(mark):
				_marks[id] = _make(e)
	for id: int in _marks.keys():
		if seen.has(id):
			continue
		var old: Variant = _marks[id]
		if old != null and is_instance_valid(old):
			(old as Node).queue_free()
		_marks.erase(id)


func _make(e: EnemyBase) -> Label3D:
	var label := Label3D.new()
	label.name = "AggroMark"
	label.text = "!"
	UiTheme.label3d(label, UiTheme.BIG)
	label.modulate = ArtKit.color("color_roles.threat.body", Color("#E8283C"))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0, e.nameplate_height() + 0.45, 0)
	e.add_child(label)
	return label
