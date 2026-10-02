class_name TrialShrine
extends PoiPuzzle
## M12: a trial shrine of a sub-biome. [E] at its altar wakes the trial: the
## sub-biome's family comes in waves around the altar; clear them within the
## time and, struck at most `hits` times, the shrine's rune blessing is yours.
## Every hero's owner counts its own hits (in co-op the one who took the hits
## misses out, the others still get it); every hero near gets the clear's XP.
## A trial that ended (cleared or out of time) rests REARM s, then anyone can
## take it again - also to help a friend who has not got it yet. The server
## runs the waves and the clock (world state), the blessing is the owner's.

const DEFS := {
	"trial_v": {"blessing": &"ashwick", "time": 70.0, "hits": 4, "xp": 90,
		"waves": [["grave_shambler", "grave_shambler", "mourner"], ["grave_shambler", "mourner", "mourner"]]},
	"trial_f": {"blessing": &"charwood", "time": 75.0, "hits": 4, "xp": 110,
		"waves": [["smoulder_wisp", "smoulder_wisp", "smoulder_wisp"], ["cinderbark", "smoulder_wisp", "smoulder_wisp"]]},
	"trial_b": {"blessing": &"emberfall", "time": 70.0, "hits": 4, "xp": 110,
		"waves": [["ash_jackal", "ash_jackal", "ash_jackal"], ["ash_jackal", "ash_jackal", "carrion_vulture"]]},
}
const REARM := 20.0
const RING := Vector2(5.0, 8.0)
## A hero this close takes part (and keeps the trial going).
const NEAR := 30.0
## Seconds with no hero near before a running trial gives up.
const ABANDON := 6.0
const LEASH := 26.0

var def: Dictionary = {}
var switch: PuzzleSwitch
var wave_alive: Array[EnemyBase] = []   # the authority's current wave
var hits: int = 0                       # the local hero's, in the run it takes part in
var joined_seq: int = -1
var _rest_left: float = 0.0
var _empty_for: float = 0.0
var _watched: Player = null
var _light: OmniLight3D


static func build(zone: ZoneBase, poi: Dictionary) -> TrialShrine:
	var t := TrialShrine.new()
	t.id = String(poi.get("id", ""))
	t.name = "Trial_" + t.id
	t.def = DEFS.get(t.id, DEFS["trial_v"])
	t.act_range = 4.0
	t.state = {"phase": "idle", "seq": 0}
	var pos := ZoneLayout.pos_of(poi)
	pos.y = zone.ground_y(pos)
	zone.world.add_child(t)
	t.global_position = pos
	t.rotation.y = PoiBuilder.yaw_of(poi)
	PoiBuilder.prop(zone, "trial_altar", pos, PoiBuilder.yaw_of(poi))
	PoiBuilder.blocker(zone, pos, Vector3(1.9, 0.45, 1.9), PoiBuilder.yaw_of(poi))
	PoiBuilder.blocker(zone, pos, Vector3(0.5, 1.75, 0.4), PoiBuilder.yaw_of(poi))
	t._light = OmniLight3D.new()
	t._light.light_color = ArtKit.color("color_roles.player_accent.body", Color("#3CBEB4"))
	t._light.omni_range = 5.0
	t._light.position = Vector3(0, 1.4, -0.4)
	t.add_child(t._light)
	t.switch = PuzzleSwitch.new()
	t.switch.name = "Altar"
	t.switch.id = t.id
	t.switch.text_key = "ui.prompt.trial"
	t.switch.reach = 3.2
	t.switch.prompt_height = 2.1
	t.switch.usable = func(_hero: Player) -> bool: return t.phase() == "idle"
	t.switch.on_use = func(hero: Player) -> void: t.request("start", 0, hero)
	t.add_child(t.switch)
	t.apply_state(t.state)
	return t


func _ready() -> void:
	super()
	if not Net.is_client() and phase() != "idle":
		# a trial does not outlive the server that ran it
		state = {"phase": "idle", "seq": int(state.get("seq", 0))}
		SaveGame.set_poi_state(id, state)
		apply_state(state)


func phase() -> String:
	return String(state.get("phase", "idle"))


func blessing() -> StringName:
	return StringName(def.get("blessing", &""))


func time_limit() -> float:
	return float(def.get("time", 60.0))


func max_hits() -> int:
	return int(def.get("hits", 4))


func _now_ms() -> int:
	var zone := ZoneBase.zone_of(self)
	if zone != null and zone.net_world != null:
		return int(zone.net_world.server_msec())
	return Time.get_ticks_msec()


## Seconds left in a running trial (every machine: the server's clock).
func time_left() -> float:
	if phase() != "running":
		return 0.0
	return maxf(time_limit() - float(_now_ms() - int(state.get("t0", 0))) / 1000.0, 0.0)


func act(action: String, _arg: Variant, hero: Player) -> void:
	if action != "start" or phase() != "idle" or not in_reach(hero, NET_MARGIN if Net.is_online() else 0.0):
		return
	state = {"phase": "running", "seq": int(state.get("seq", 0)) + 1, "t0": _now_ms(), "wave": 0}
	_empty_for = 0.0
	_spawn_wave(0)
	commit()


func _physics_process(delta: float) -> void:
	if Net.is_client():
		return
	match phase():
		"running":
			var zone := ZoneBase.zone_of(self)
			if zone == null:
				return
			_empty_for = _empty_for + delta if zone.players_within(global_position, NEAR).is_empty() else 0.0
			if time_left() <= 0.0 or _empty_for > ABANDON:
				_end("failed")
				return
			var live: Array[EnemyBase] = []
			for e in wave_alive:
				if is_instance_valid(e) and e.ai_state != EnemyBase.AIState.DEAD:
					live.append(e)
			wave_alive = live
			if not wave_alive.is_empty():
				return
			var next := int(state.get("wave", 0)) + 1
			if next < (def["waves"] as Array).size():
				state["wave"] = next
				_spawn_wave(next)
				commit()
			else:
				_end("cleared")
				reward_party(int(def.get("xp", 80)), "ui.trial.passed")
		"cleared", "failed":
			_rest_left -= delta
			if _rest_left <= 0.0:
				state = {"phase": "idle", "seq": int(state.get("seq", 0))}
				commit()


func _spawn_wave(index: int) -> void:
	var zone := ZoneBase.zone_of(self)
	if zone == null:
		return
	var comp: Array = (def["waves"] as Array)[index]
	for i in comp.size():
		var a := TAU * float(i) / float(comp.size()) + randf() * 0.6
		var pos := zone.ground_point(global_position + Vector3(cos(a), 0.0, sin(a)) * randf_range(RING.x, RING.y), 0.2)
		var e := zone.spawn_by_id(String(comp[i]), pos)
		e.home = global_position
		e.leash = LEASH
		if e.has_method(&"wake"):
			e.call(&"wake")  # a trial's cinderbark comes at you
		wave_alive.append(e)


func _end(result: String) -> void:
	for e in wave_alive:
		if is_instance_valid(e):
			e.dismiss()
	wave_alive.clear()
	state["phase"] = result
	_rest_left = REARM
	commit()


func _present() -> void:
	var p := phase()
	if _light != null:
		_light.light_energy = 2.2 if p == "running" else (1.6 if p == "cleared" else 0.6)
	var zone := ZoneBase.zone_of(self)
	var hero: Player = zone.player if zone != null else null
	var seq := int(state.get("seq", 0))
	match p:
		"running":
			if joined_seq != seq and hero != null and is_instance_valid(hero) \
					and hero.global_position.distance_to(global_position) <= NEAR:
				_join(hero, seq)
			if zone != null and Net.has_view() and int(state.get("wave", 0)) > 0:
				VFX.ground_ring(zone, global_position, ArtKit.color("color_roles.player_accent.hot", Color("#9FF2E6")), 6.0, 0.5)
		"cleared":
			if joined_seq == seq:
				_judge(hero)
		"failed":
			if joined_seq == seq:
				_leave()
				if zone != null and zone.hud != null:
					zone.hud.toast(Texts.t("ui.trial.failed"), UiTheme.MUTED)
		_:
			_leave()


## This machine's hero takes part in run `seq`: its own hits count from now.
func _join(hero: Player, seq: int) -> void:
	_leave()
	joined_seq = seq
	hits = 0
	_watched = hero
	hero.health.damaged.connect(_on_hero_hit)
	var zone := ZoneBase.zone_of(self)
	if zone != null and zone.hud != null:
		zone.hud.toast("%s: %s" % [Texts.t("trial." + id), Texts.t("ui.trial.rule", [int(time_limit()), max_hits()])],
			ArtKit.color("color_roles.player_accent.hot", Color("#9FF2E6")))


func _leave() -> void:
	if _watched != null and is_instance_valid(_watched) and _watched.health.damaged.is_connected(_on_hero_hit):
		_watched.health.damaged.disconnect(_on_hero_hit)
	_watched = null
	joined_seq = -1
	var zone := ZoneBase.zone_of(self)
	if zone != null and zone.hud != null:
		zone.hud.trial_status("")


func _on_hero_hit(_hit: HitInfo) -> void:
	if phase() == "running":
		hits += 1


## The trial was cleared with this machine's hero in it: the blessing, if it
## was struck no more than allowed.
func _judge(hero: Player) -> void:
	var struck := hits
	_leave()
	var zone := ZoneBase.zone_of(self)
	if hero == null or not is_instance_valid(hero) or zone == null:
		return
	if struck > max_hits():
		if zone.hud != null:
			zone.hud.toast(Texts.t("ui.trial.struck"), UiTheme.MUTED)
	elif hero.grant_blessing(blessing()):
		zone.blessing_toast(hero, blessing())
	elif zone.hud != null:
		zone.hud.toast(Texts.t("ui.trial.carried", [Blessings.title(blessing())]), UiTheme.MUTED)


func _process(_delta: float) -> void:
	if joined_seq < 0 or phase() != "running":
		return
	var zone := ZoneBase.zone_of(self)
	if zone != null and zone.hud != null:
		zone.hud.trial_status(Texts.t("ui.trial.status", [Texts.t("trial." + id), int(ceilf(time_left())), hits, max_hits()]))


func _exit_tree() -> void:
	_leave()
