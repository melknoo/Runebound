class_name ReviveSystem
extends Node
## M13b: downed heroes and revives in the co-op dungeon (DungeonRegistry
## "revive"; the user's decision of 2026-10-13). A hero who falls there lies
## downed for DOWNED_SECONDS instead of waking at the rune at once; an ally
## who holds [E] beside it for HOLD_SECONDS brings it back with
## REVIVE_HEALTH of its health. When the time runs out, or nobody of the
## party is left standing (a wipe), it wakes at the nearest lit rune, healed,
## as in every other dungeon.
## Hybrid authority, no message of its own:
##   * the hero's owner runs its downed time; the hero's health stays 0, so
##     the server's proxy and the other clients' puppets see it dead -
##     enemies leave it, boss arenas count it out (they reset after a wipe)
##   * every machine with a view lays dead heroes down and marks them (a
##     ring, a countdown, the revive prompt for its own hero)
##   * the reviver's machine sends HeroFx `ally_revive` [ref, health]; only
##     the target's owner applies it (`revived`), like the druid's heals.

const DOWNED_SECONDS := 30.0
## A wipe: nobody standing for WIPE_CONFIRM seconds sets it going, and
## WIPE_DELAY after the last fall every machine wakes its own heroes - also
## when the last one already stood up again over there (each machine sees the
## others' falls and wakes a network delay late, so the wipe must not need
## the whole party on the floor until the end).
const WIPE_CONFIRM := 0.3
const WIPE_DELAY := 1.2
const HOLD_SECONDS := 3.0
const RANGE := 2.2
const REVIVE_HEALTH := 0.3
const MARK_COLOR := Color(0.72, 0.62, 1.0)

var zone: DungeonZone
## Owner side: hero instance id -> seconds left on the ground.
var _down_left: Dictionary = {}
## Every machine with a view: hero instance id -> Marker.
var _markers: Dictionary = {}
## The local hero's revive in progress (seconds held, on whom).
var progress: float = 0.0
var _progress_target: int = 0
var _wipe_seen: float = 0.0
var _wipe_left: float = -1.0
var _wait_text: String = ""
## Tests: revives this machine sent, heroes it got back up, wipes it saw.
var revives_sent: int = 0
var revives_taken: int = 0
var wipes: int = 0


## A dead hero's marker: a pulsing ring on the floor, the seconds left, the
## revive prompt (a child of the hero, beside its tilted `_visual`).
class Marker extends Node3D:
	var hero: Player
	var label: Label3D
	var prompt: InteractPrompt
	var ring_mat: StandardMaterial3D
	var seen_at: float = 0.0
	var _t: float = 0.0
	var _ring: MeshInstance3D

	func build(color: Color) -> void:
		name = "DownedMarker"
		_ring = MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.9
		torus.outer_radius = 1.05
		torus.rings = 24
		torus.ring_segments = 4
		_ring.mesh = torus
		ring_mat = StandardMaterial3D.new()
		ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring_mat.albedo_color = Color(color, 0.7)
		_ring.material_override = ring_mat
		_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ring.position = Vector3(0, 0.06, 0)
		_ring.scale = Vector3(1.0, 0.15, 1.0)
		add_child(_ring)
		label = Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.position = Vector3(0, 1.5, 0)
		label.modulate = color
		UiTheme.label3d(label)
		add_child(label)
		prompt = InteractPrompt.create(self, 1.0)

	func _process(delta: float) -> void:
		_t += delta
		var s := 1.0 + 0.08 * sin(_t * 5.0)
		_ring.scale = Vector3(s, 0.15, s)


static func create(z: DungeonZone) -> ReviveSystem:
	var r := ReviveSystem.new()
	r.name = "ReviveSystem"
	r.zone = z
	z.add_child(r)
	return r


## The owner's hero fell (DungeonZone._on_player_died): down on the floor.
## With nobody else standing (alone, the last) the wipe follows WIPE_DELAY
## later (`_physics_process`).
func on_died(p: Player) -> void:
	if p.net_role != Player.NetRole.OWNER:
		return
	p.downed = true
	p.velocity = Vector3.ZERO
	_down_left[p.get_instance_id()] = DOWNED_SECONDS
	p.feel_shake(0.5)
	Sfx.play("shatter_burst", p.global_position, -10.0, 0.05, 0.7)


## Owner: an ally's revive arrived (HeroFx `ally_revive`).
func revived(p: Player, fraction: float, by: Player) -> void:
	if p.net_role != Player.NetRole.OWNER or not p.health.is_dead:
		return
	p.downed = false
	_down_left.erase(p.get_instance_id())
	p.health.revive(fraction)
	revives_taken += 1
	p.feel_shake(0.25)
	if p.is_local and zone.hud != null:
		zone.hud.toast(Texts.t("ui.revive.back"), MARK_COLOR)
	if by != null:
		Net.log_line("%s revived by %s" % [p.name, by.name])


## Seconds this downed hero has left (its owner's count; elsewhere counted
## from when this machine saw it fall).
func seconds_left(p: Player) -> float:
	var id := p.get_instance_id()
	if _down_left.has(id):
		return float(_down_left[id])
	var m := _markers.get(id) as Marker
	if m != null and is_instance_valid(m):
		return maxf(DOWNED_SECONDS - (_now() - m.seen_at), 0.0)
	return DOWNED_SECONDS


## Owner: a downed hero's time is up - at the rune, healed (the M13 rule).
func _wake(p: Player) -> void:
	p.downed = false
	_down_left.erase(p.get_instance_id())
	zone.respawn_at_rune(p)


## Owner: nobody stands - every hero this machine owns that lies dead wakes.
func _wipe() -> void:
	wipes += 1
	var told := false
	for h in zone.party():
		if h.net_role == Player.NetRole.OWNER and h.health.is_dead:
			_wake(h)
			if h.is_local and zone.party_size() > 1 and zone.hud != null and not told:
				told = true
				zone.hud.toast(Texts.t("ui.revive.wiped"), MARK_COLOR)


func _anyone_standing(except: Player) -> bool:
	for h in zone.party():
		if h != except and not h.health.is_dead:
			return true
	return false


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


# ---------------------------------------------------------------------------
# Owner: the downed time
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var lying: Array[Player] = []
	for h in zone.party():
		if h.net_role != Player.NetRole.OWNER or not h.downed:
			continue
		if not h.health.is_dead:  # healed some other way: up again
			h.downed = false
			_down_left.erase(h.get_instance_id())
			continue
		lying.append(h)
	if lying.is_empty():
		_wipe_seen = 0.0
		_wipe_left = -1.0
		return
	if _wipe_left >= 0.0:  # a wipe on its way
		_wipe_left -= delta
		if _wipe_left <= 0.0:
			_wipe_left = -1.0
			_wipe_seen = 0.0
			_wipe()
			return
	elif not _anyone_standing(null):
		_wipe_seen += delta
		if _wipe_seen >= WIPE_CONFIRM:
			_wipe_left = WIPE_DELAY - WIPE_CONFIRM
	else:
		_wipe_seen = 0.0
	for h in lying:
		var id := h.get_instance_id()
		var left := float(_down_left.get(id, DOWNED_SECONDS)) - delta
		if left <= 0.0:
			_wake(h)
			if h.is_local and zone.hud != null:
				zone.hud.toast(Texts.t("ui.revive.timeout"), MARK_COLOR)
		else:
			_down_left[id] = left


# ---------------------------------------------------------------------------
# Every machine with a view: poses, markers, the local hero's revive
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not Net.has_view():
		return
	var local := zone.player if zone.player != null and is_instance_valid(zone.player) else null
	var best: Player = null
	var best_d := RANGE
	for h in zone.party():
		var id := h.get_instance_id()
		var dead := h.health.is_dead
		h.set_lying(dead)
		if dead and not _markers.has(id):
			var m := Marker.new()
			m.hero = h
			m.seen_at = _now()
			h.add_child(m)
			m.build(MARK_COLOR)
			_markers[id] = m
		elif not dead and _markers.has(id):
			var gone := _markers[id] as Marker
			if is_instance_valid(gone):
				gone.queue_free()
			_markers.erase(id)
		if dead and local != null and h != local and not local.health.is_dead:
			var d := h.global_position.distance_to(local.global_position)
			if d <= best_d:
				best_d = d
				best = h
	for id: int in _markers.keys():
		var m := _markers[id] as Marker
		if not is_instance_valid(m):
			_markers.erase(id)
			continue
		m.label.text = "%d" % ceili(seconds_left(m.hero))
		var text := Texts.t("ui.revive.prompt") if progress <= 0.0 or _progress_target != id \
			else Texts.t("ui.revive.progress", [int(progress / HOLD_SECONDS * 100.0)])
		m.prompt.update(m.hero == best, text)
		m.ring_mat.albedo_color = Color(MARK_COLOR, 0.7 + (0.3 * progress / HOLD_SECONDS if _progress_target == id else 0.0))
	_tick_revive(local, best, delta)
	_tick_bot_revives(delta)
	if zone.hud != null:
		if local != null and local.downed:
			if _wait_text == "":  # the bound key, looked up once per fall
				_wait_text = Texts.t("ui.revive.wait", [InteractPrompt.key_name()])
			zone.hud.downed_status(Texts.t("ui.revive.downed", [ceili(seconds_left(local))]) + "\n" + _wait_text)
		elif _wait_text != "":
			_wait_text = ""
			zone.hud.downed_status("")


## Offline helper bots (the party check; co-op bots are their machine's local
## hero): an owned, non-local hero whose bot holds interact beside a downed
## ally revives it like a person would.
var _bot_progress: Dictionary = {}


func _tick_bot_revives(delta: float) -> void:
	for h in zone.party():
		if h.is_local or h.net_role != Player.NetRole.OWNER or h.health.is_dead or not h.intent.interact_held:
			_bot_progress.erase(h.get_instance_id())
			continue
		var target: Player = null
		for other in zone.party():
			if other != h and other.health.is_dead and other.global_position.distance_to(h.global_position) <= RANGE:
				target = other
				break
		if target == null:
			_bot_progress.erase(h.get_instance_id())
			continue
		var held := float(_bot_progress.get(h.get_instance_id(), 0.0)) + delta
		if held >= HOLD_SECONDS:
			held = 0.0
			revives_sent += 1
			h.hero_fx(&"ally_revive", [zone.hero_ref(target), REVIVE_HEALTH])
		_bot_progress[h.get_instance_id()] = held


## The local hero holds [E] beside a downed ally: after HOLD_SECONDS the
## revive goes out (released or moved off, the count starts over).
func _tick_revive(local: Player, target: Player, delta: float) -> void:
	if local == null or target == null:
		progress = 0.0
		_progress_target = 0
		return
	var m := _markers.get(target.get_instance_id()) as Marker
	if m == null or not m.prompt.held(local):
		progress = 0.0
		return
	if _progress_target != target.get_instance_id():
		_progress_target = target.get_instance_id()
		progress = 0.0
	progress += delta
	if progress >= HOLD_SECONDS:
		progress = 0.0
		revives_sent += 1
		local.hero_fx(&"ally_revive", [zone.hero_ref(target), REVIVE_HEALTH])
