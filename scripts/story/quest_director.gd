class_name QuestDirector
extends Node
## M14a: the story's eyes in a zone, for this machine's hero only. It binds the
## hero's QuestLog, turns what happens here into quest events (kills near the
## hero, bosses, places reached, the zone entered, lore read, shards found,
## levels, shrines), says what changed (toasts), keeps the tracker fresh and
## hands the map, the compass and the hub its quest markers. Every machine runs
## its own: in co-op each hero counts what it was there for (STORY_DESIGN "Co-op
## and the story"); the server runs none (it has no local hero).

const REACH_TICK := 0.25
const REACH_RADIUS := 8.0
const QUEST_GOLD := Color("#E8B44A")

var zone: ZoneBase
var hero: Player
var qlog: QuestLog
## True once begin() bound a hero with an active story.
var running: bool = false

var _tick: float = 0.0
var _enemies_seen: Dictionary = {}  # instance id -> true (connected once)
## M14a phase 2: what stage.json placed in this zone (StoryNpc, StoryMarker).
var stage_nodes: Array[Node3D] = []
var _stage_dirty: bool = false


func setup(z: ZoneBase) -> void:
	zone = z
	name = "QuestDirector"


## Story checks and net tests switch the director on explicitly; a net-test
## client (it creates throwaway characters) never runs one otherwise.
static func allowed() -> bool:
	var net_test := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--story"):
			return true
		if arg.begins_with("--net-test"):
			net_test = true
	return not net_test


## After the hero was restored (ZoneBase._ready, after _discover).
func begin() -> void:
	hero = zone.player
	if hero == null or not is_instance_valid(hero):
		return
	qlog = QuestLog.of(hero)
	qlog.bind(hero)
	if not qlog.active or not allowed():
		return
	running = true
	if zone.quest_tracker != null:
		zone.quest_tracker.bind(qlog, hero)
	_build_stage()
	qlog.changed.connect(_mark_stage_dirty)
	qlog.quest_started.connect(_on_quest_started)
	qlog.quest_done.connect(_on_quest_done)
	qlog.step_done.connect(_on_step_done)
	hero.chronicle_changed.connect(_on_chronicle)
	hero.progression.leveled_up.connect(_on_level)
	hero.waypoint_discovered.connect(_on_attuned)
	zone.enemies_root.child_entered_tree.connect(_watch_enemy)
	for e in zone.enemies_root.get_children():
		_watch_enemy(e)
	var note := SaveGame.pop_note("m14_call")
	if note != "" and zone.hud != null:
		zone.hud.toast(Texts.t("story.note.sigrun_calls"), QUEST_GOLD)
		SaveGame.request_save()
	qlog.flush_pending()
	qlog.event("enter", zone_key())
	qlog.recheck_all()


func zone_key() -> String:
	return zone.scene_file_path.get_file().get_basename()


func _process(delta: float) -> void:
	if not running or hero == null or not is_instance_valid(hero):
		return
	if _stage_dirty:
		_stage_dirty = false
		refresh_stage()
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = REACH_TICK
	for qid in qlog.running():
		var goal: Dictionary = qlog.current_step(qid).get("goal", {})
		if str(goal.get("type", "")) != "reach":
			continue
		var target := goal_position(goal)
		if target == Vector3.INF:
			continue
		var radius := float(goal.get("radius", _area_radius(goal)))
		if Vector2(hero.global_position.x - target.x, hero.global_position.z - target.z).length() <= radius:
			qlog.event("reach", str(goal.get("poi", goal.get("marker", goal.get("area", "")))), {"zone": zone_key()})


# ---------------------------------------------------------------------------
# Places
# ---------------------------------------------------------------------------

## Where a goal points in this zone (Vector3.INF when elsewhere or nowhere).
func goal_position(goal: Dictionary) -> Vector3:
	if goal.has("zone") and str(goal["zone"]) != zone_key():
		return Vector3.INF
	if goal.has("poi"):
		var p := zone.poi_position(str(goal["poi"]))
		if p != Vector3.INF:
			return p
	if goal.has("at"):
		var xz: Array = goal["at"]
		return zone.ground_point(Vector3(float(xz[0]), 0.0, float(xz[1])))
	if goal.has("area"):
		var a := _area(str(goal["area"]))
		if not a.is_empty():
			return zone.ground_point(ZoneLayout.pos_of(a))
	if goal.has("marker") or goal.has("npc"):
		var key := str(goal.get("marker", goal.get("npc", "")))
		for n in get_tree().get_nodes_in_group(&"story_target"):
			if n is Node3D and is_instance_valid(n) and str(n.get_meta(&"story_id", "")) == key:
				return (n as Node3D).global_position
	return Vector3.INF


func _layout() -> ZoneLayout:
	return zone.get(&"layout") as ZoneLayout


func _area(id: String) -> Dictionary:
	var l := _layout()
	if l == null:
		return {}
	for a in l.areas:
		if str(a.get("id", "")) == id:
			return a
	return {}


func _area_radius(goal: Dictionary) -> float:
	if goal.has("area"):
		return float(_area(str(goal["area"])).get("radius", REACH_RADIUS))
	return REACH_RADIUS


## The smallest named area around `pos` ("" outside every one).
func area_at(pos: Vector3) -> String:
	var l := _layout()
	if l == null:
		return ""
	var best := ""
	var best_r := INF
	for a in l.areas:
		var c := ZoneLayout.pos_of(a)
		var r := float(a.get("radius", 50.0))
		if Vector2(pos.x - c.x, pos.z - c.z).length() <= r and r < best_r:
			best = str(a.get("id", ""))
			best_r = r
	return best


# ---------------------------------------------------------------------------
# Events
# ---------------------------------------------------------------------------

func _watch_enemy(node: Node) -> void:
	var e := node as EnemyBase
	if e == null or _enemies_seen.has(e.get_instance_id()):
		return
	_enemies_seen[e.get_instance_id()] = true
	e.state_entered.connect(func(state: EnemyBase.AIState) -> void:
		if state == EnemyBase.AIState.DEAD:
			_on_enemy_dead(e))


## Same rule as XP: the hero gets the kill when it died within the reward
## radius (co-op: every hero near it, each on its own machine).
static func credits(hero_pos: Vector3, enemy_pos: Vector3) -> bool:
	return hero_pos.distance_to(enemy_pos) <= ZoneBase.REWARD_RADIUS


func _on_enemy_dead(e: EnemyBase) -> void:
	if not running or not is_instance_valid(e) or hero == null or not is_instance_valid(hero):
		return
	if not credits(hero.global_position, e.global_position):
		return
	if e.type_id in ZoneBase.BOSS_TYPES:
		qlog.add_beat("boss:" + e.type_id)
		qlog.event("boss", e.type_id, {"zone": zone_key()})
	qlog.event("kill", e.type_id, {"zone": zone_key(), "area": area_at(e.global_position), "elite": e.is_elite})


func _on_chronicle() -> void:
	qlog.event("collect", "")
	qlog.event("read", "")


func _on_level(_level: int) -> void:
	qlog.event("level", "")
	qlog.flush_pending()


func _on_attuned(_id: String) -> void:
	qlog.event("attune", "")


# ---------------------------------------------------------------------------
# Feedback
# ---------------------------------------------------------------------------

func _on_quest_started(id: String) -> void:
	_toast("story.toast.quest_new", id)
	_stage_dirty = true


func _on_step_done(id: String, _step: String) -> void:
	if qlog.is_running(id):
		Sfx.play_ui("pickup", -10.0)


func _on_quest_done(id: String) -> void:
	_toast("story.toast.quest_done", id)
	Sfx.play_ui("level_up", -8.0)


func _toast(key: String, qid: String) -> void:
	if zone.hud == null:
		return
	zone.hud.toast(Texts.t(key, [Texts.t(str(StoryDB.quest(qid).get("title", qid)))]), QUEST_GOLD)


## A camera pan (phase 3 plays it; until then it only counts as seen and
## runs its end effects).
func play_cutscene(id: String) -> void:
	var c := StoryDB.cutscene(id)
	if c.is_empty():
		return
	qlog.mark_seen(id)
	StoryEffects.apply(c.get("on_end", []), hero, qlog)


# ---------------------------------------------------------------------------
# Stage: story NPCs and markers, badges over the people with something to say
# ---------------------------------------------------------------------------

## Builds what stage.json places in this zone (this machine only).
func _build_stage() -> void:
	for entry: Variant in StoryDB.stage():
		if str((entry as Dictionary).get("zone", "")) == zone_key():
			place(entry as Dictionary)
	refresh_stage()


## Builds one stage entry: a StoryNpc ({"npc": id}) or a StoryMarker
## ({"marker": id}) at its place. Null for anything else.
func place(e: Dictionary) -> Node3D:
	var node: Node3D = null
	if e.has("npc"):
		node = StoryNpc.create(str(e["npc"]))
		(node as StoryNpc).stage = e
	elif e.has("marker"):
		node = StoryMarker.create(e)
	if node == null:
		return null
	node.position = stage_position(e)
	node.rotation.y = deg_to_rad(float(e.get("yaw", 0.0)))
	zone.world.add_child(node)
	stage_nodes.append(node)
	if e.has("prop") and PoiBuilder.has_art(zone):
		PoiBuilder.prop(zone, str(e["prop"]), node.position, node.rotation.y)
	return node


## Where a stage entry stands: `at` [x, z], or a POI plus an `offset` [x, z].
func stage_position(e: Dictionary) -> Vector3:
	var p := Vector3.ZERO
	if e.has("poi"):
		var poi := zone.poi_position(str(e["poi"]))
		if poi != Vector3.INF:
			p = poi
	if e.has("at"):
		var xz: Array = e["at"]
		p = Vector3(float(xz[0]), 0.0, float(xz[1]))
	if e.has("offset"):
		var off: Array = e["offset"]
		p += Vector3(float(off[0]), 0.0, float(off[1]))
	return zone.ground_point(p)


func _mark_stage_dirty() -> void:
	_stage_dirty = true


## Shows or hides the stage by its conditions and refreshes the badges.
func refresh_stage() -> void:
	for node in stage_nodes:
		if not is_instance_valid(node):
			continue
		var e: Dictionary = node.get(&"stage")
		var on := StoryCond.check(e.get("show_if", {}), qlog, hero) 			and (not e.has("hide_if") or not StoryCond.check(e["hide_if"], qlog, hero))
		node.call(&"set_shown", on)
	refresh_badges()


## "?" over whom a running quest wants talked to, "!" over whom has a story
## topic now; nothing otherwise.
func refresh_badges() -> void:
	for n in get_tree().get_nodes_in_group(&"story_npc"):
		var npc := n as Node3D
		if npc == null or not is_instance_valid(npc) or ZoneBase.zone_of(npc) != zone:
			continue
		var id := str(npc.get_meta(&"story_id", ""))
		set_badge(npc, badge_for(id, npc))


func badge_for(id: String, npc: Node3D) -> String:
	if not running or id == "":
		return ""
	for qid in qlog.running():
		var goal: Dictionary = qlog.current_step(qid).get("goal", {})
		if str(goal.get("type", "")) == "talk" and str(goal.get("npc", "")) == id:
			return "?"
	if zone.dialogue_ui != null and zone.dialogue_ui.entry_for(id, npc, true) != "":
		return "!"
	return ""


static func set_badge(npc: Node3D, text: String) -> void:
	var badge := npc.get_node_or_null(^"StoryBadge") as Label3D
	if badge == null:
		if text == "":
			return
		badge = Label3D.new()
		badge.name = "StoryBadge"
		badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		badge.no_depth_test = true
		badge.modulate = QUEST_GOLD
		badge.outline_size = 12
		badge.outline_modulate = Color(0.05, 0.03, 0.08)
		badge.position = Vector3(0, 2.55, 0)
		UiTheme.label3d(badge, UiTheme.BIG, true)
		npc.add_child(badge)
	badge.text = text
	badge.visible = text != ""


# ---------------------------------------------------------------------------
# Markers
# ---------------------------------------------------------------------------

## Map and compass markers for the shown quest's current step in this zone:
## [{id, pos, icon, label, kind}].
func markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not running:
		return out
	var qid := qlog.shown_quest()
	if qid == "":
		return out
	var st := qlog.current_step(qid)
	var goal: Dictionary = st.get("goal", {})
	var pos := goal_position(goal)
	if pos == Vector3.INF:
		return out
	var icon := "quest_turnin" if str(goal.get("type", "")) == "talk" else "quest"
	out.append({"id": "quest:" + qid, "pos": pos, "icon": icon, "label": Texts.t(str(st.get("text", ""))),
		"kind": "quest", "max_dist": 400.0})
	return out
