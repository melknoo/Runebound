class_name NetWorld
extends Node
## M09: per-zone co-op replication, created by ZoneBase while Net is online.
##
## Server: one PROXY Player per client (position and HP from its owner, a
## hurtbox for the enemies, the client's character for stat math) and a 20 Hz
## snapshot of every hero to every client that has loaded the zone.
## Client: sends its own hero at 30 Hz (plus its actions and, when it
## changes, its character), keeps a PUPPET Player for every other hero and
## poses it from the snapshots INTERP_DELAY_MS in the past: interpolated
## between two samples, briefly extrapolated when none is newer, snapped when
## the owner teleported.

const SNAPSHOT_EVERY := 1.0 / 20.0  # seconds between server snapshots
const HERO_SEND_EVERY := 2          # physics ticks (60 Hz -> 30 Hz)
const INTERP_DELAY_MS := 100.0
const MAX_EXTRAPOLATE_MS := 150.0
const BUFFER_MS := 1000.0
## Further than this between two sends (1/30 s) is a jump, not a walk.
const TELEPORT_DISTANCE := 6.0
const CHARACTER_RESEND := 1.0       # seconds, debounced
const NAMEPLATE_HEIGHT := 2.3

var zone: ZoneBase
## peer -> Player (server: proxies; client: puppets).
var heroes: Dictionary = {}
## Client: peer -> Array of samples {t, pos, yaw, vel, state, hp, hp_max, tp}.
var _samples: Dictionary = {}
## Server: peer -> newest HERO_STATE seq applied (older ones are dropped).
var _last_seq: Dictionary = {}
## Client: server clock minus local clock in ms (least-delayed estimate).
var _clock_offset: float = 0.0
var _clock_ready: bool = false
var _snap_left: float = 0.0
var _tick: int = 0
var _seq: int = 0
var _last_sent_pos: Vector3 = Vector3.INF
var _char_dirty: bool = false
var _char_left: float = 0.0
## Actions a puppet replayed (tests).
var replayed_actions: int = 0


func setup(z: ZoneBase) -> void:
	zone = z
	name = "NetWorld"
	Net.on(NetMsg.HERO_STATE, _on_hero_state)
	Net.on(NetMsg.SNAPSHOT, _on_snapshot)
	Net.on(NetMsg.HERO_SPAWN, _on_hero_spawn)
	Net.on(NetMsg.HERO_DESPAWN, _on_hero_despawn)
	Net.on(NetMsg.HERO_ACTION, _on_hero_action)
	Net.on(NetMsg.CHARACTER, _on_character)
	if Net.is_dedicated():
		Net.peer_ready.connect(_on_peer_ready)
		Net.peer_left.connect(_on_peer_left)


## Client: hook the local hero once the zone has spawned it.
func watch_local_hero(hero: Player) -> void:
	if hero == null or not Net.is_client():
		return
	hero.action_started.connect(func(action: StringName) -> void:
		Net.send_to_server(NetMsg.HERO_ACTION, [String(action)]))
	var dirty := func() -> void: _char_dirty = true
	hero.equipment.changed.connect(dirty)
	hero.abilities_changed.connect(dirty)
	hero.progression.talents_changed.connect(dirty)
	hero.progression.leveled_up.connect(func(_level: int) -> void: _char_dirty = true)
	_send_character()


func _exit_tree() -> void:
	for kind: int in [NetMsg.HERO_STATE, NetMsg.SNAPSHOT, NetMsg.HERO_SPAWN, NetMsg.HERO_DESPAWN,
			NetMsg.HERO_ACTION, NetMsg.CHARACTER]:
		for handler: Callable in [_on_hero_state, _on_snapshot, _on_hero_spawn, _on_hero_despawn,
				_on_hero_action, _on_character]:
			Net.off(kind, handler)
	if Net.peer_ready.is_connected(_on_peer_ready):
		Net.peer_ready.disconnect(_on_peer_ready)
	if Net.peer_left.is_connected(_on_peer_left):
		Net.peer_left.disconnect(_on_peer_left)


func _physics_process(delta: float) -> void:
	if Net.is_dedicated():
		_snap_left -= delta
		if _snap_left <= 0.0:
			_snap_left += SNAPSHOT_EVERY
			_send_snapshots()
	elif Net.is_client():
		_tick += 1
		if _tick % HERO_SEND_EVERY == 0:
			_send_hero_state()
		if _char_dirty:
			_char_left -= delta
			if _char_left <= 0.0:
				_send_character()


func _process(_delta: float) -> void:
	if Net.is_client():
		_pose_puppets()


# ---------------------------------------------------------------------------
# Server
# ---------------------------------------------------------------------------

func _on_peer_ready(peer: int) -> void:
	var proxy := _ensure_proxy(peer)
	# The newcomer gets every other hero; the others get the newcomer.
	for other: int in heroes:
		if other != peer:
			Net.send_to_peer(peer, NetMsg.HERO_SPAWN, _spawn_payload(other))
	Net.broadcast_zone(NetMsg.HERO_SPAWN, _spawn_payload(peer), Net.CH_EVENTS, peer)
	Net.log_line("%s's hero is in the world at %s" % [Net.peer_name(peer), proxy.global_position.round()])


func _on_peer_left(peer: int) -> void:
	var proxy := heroes.get(peer) as Player
	heroes.erase(peer)
	_last_seq.erase(peer)
	if proxy != null and is_instance_valid(proxy):
		zone.remove_player(proxy)
		proxy.queue_free()
	Net.broadcast_zone(NetMsg.HERO_DESPAWN, [peer])


func _ensure_proxy(peer: int) -> Player:
	var existing := heroes.get(peer) as Player
	if existing != null and is_instance_valid(existing):
		return existing
	var entry: Dictionary = Net.roster.get(peer, {})
	var p := Player.new()
	p.name = "Hero_%d" % peer
	p.net_role = Player.NetRole.PROXY
	p.is_local = false
	p.peer_id = peer
	p.class_data = ClassData.load_by_id(StringName(str(entry.get("class_id", ClassData.DEFAULT_ID))))
	zone.add_player(p)
	p.global_position = zone._arrival_point("")  # until the owner's first state arrives
	heroes[peer] = p
	return p


func _spawn_payload(peer: int) -> Array:
	var hero := heroes[peer] as Player
	var entry: Dictionary = Net.roster.get(peer, {})
	return [peer, str(entry.get("name", "Hero")), str(entry.get("class_id", ClassData.DEFAULT_ID)),
		int(entry.get("level", 1)), hero.global_position, hero.facing_yaw()]


func _on_hero_state(from: int, payload: Array) -> void:
	if not Net.is_dedicated() or payload.size() < 8:
		return
	var proxy := heroes.get(from) as Player
	if proxy == null or not is_instance_valid(proxy):
		return
	var seq := int(payload[0])
	if seq <= int(_last_seq.get(from, -1)):
		return  # an older state overtaken by a newer one
	_last_seq[from] = seq
	proxy.apply_net_state(payload[1] as Vector3, float(payload[2]), payload[3] as Vector3, int(payload[4]),
		float(payload[5]), float(payload[6]))
	proxy.teleports = int(payload[7])


func _on_character(from: int, payload: Array) -> void:
	if not Net.is_dedicated() or payload.is_empty() or payload[0] is not Dictionary:
		return
	var proxy := _ensure_proxy(from) if Net.is_peer_ready(from) else heroes.get(from) as Player
	if proxy == null or not is_instance_valid(proxy):
		return
	SaveGame.apply_character(proxy, payload[0] as Dictionary)
	Net.set_peer_level(from, proxy.progression.level)


func _on_hero_action(from: int, payload: Array) -> void:
	if payload.is_empty():
		return
	if Net.is_dedicated():
		if heroes.has(from):
			Net.broadcast_zone(NetMsg.HERO_ACTION, [from, str(payload[0])], Net.CH_EVENTS, from)
	elif Net.is_client() and payload.size() >= 2:
		var puppet := heroes.get(int(payload[0])) as Player
		if puppet != null and is_instance_valid(puppet):
			puppet.action_started.emit(StringName(str(payload[1])))
			replayed_actions += 1


func _send_snapshots() -> void:
	var now := Time.get_ticks_msec()
	for peer in Net.ready_peers():
		var entries: Array = []
		for other: int in heroes:
			if other == peer:
				continue
			var h := heroes[other] as Player
			if h == null or not is_instance_valid(h):
				continue
			entries.append([other, h.global_position, h.facing_yaw(), h.velocity, int(h.state),
				h.health.current_health, h.health.max_health, h.teleports])
		if not entries.is_empty():
			Net.send_to_peer(peer, NetMsg.SNAPSHOT, [now, entries], Net.CH_SNAPSHOT)


# ---------------------------------------------------------------------------
# Client
# ---------------------------------------------------------------------------

func _send_hero_state() -> void:
	var hero := zone.player
	if hero == null or not is_instance_valid(hero):
		return
	if _last_sent_pos != Vector3.INF and hero.global_position.distance_to(_last_sent_pos) > TELEPORT_DISTANCE:
		hero.teleports += 1  # respawn, fast travel: puppets snap instead of sliding
	_last_sent_pos = hero.global_position
	_seq += 1
	Net.send_to_server(NetMsg.HERO_STATE, [_seq, hero.global_position, hero.facing_yaw(), hero.velocity,
		int(hero.state), hero.health.current_health, hero.health.max_health, hero.teleports], Net.CH_HERO)


func _send_character() -> void:
	_char_dirty = false
	_char_left = CHARACTER_RESEND
	var hero := zone.player
	if hero != null and is_instance_valid(hero):
		Net.send_to_server(NetMsg.CHARACTER, [SaveGame.character_dict(hero)])


func _on_hero_spawn(_from: int, payload: Array) -> void:
	if not Net.is_client() or payload.size() < 6:
		return
	var peer := int(payload[0])
	if peer == Net.my_id():
		return
	var old := heroes.get(peer) as Player
	if old != null and is_instance_valid(old):
		return  # already shown
	var p := Player.new()
	p.name = "Hero_%d" % peer
	p.net_role = Player.NetRole.PUPPET
	p.is_local = false
	p.peer_id = peer
	p.class_data = ClassData.load_by_id(StringName(str(payload[2])))
	zone.add_player(p)
	p.global_position = payload[4] as Vector3
	p.apply_net_state(payload[4] as Vector3, float(payload[5]), Vector3.ZERO, 0, 1.0, 1.0)
	p.health.current_health = p.health.max_health
	p.health.is_dead = false
	heroes[peer] = p
	_samples[peer] = []
	_add_nameplate(p, peer)


func _on_hero_despawn(_from: int, payload: Array) -> void:
	if not Net.is_client() or payload.is_empty():
		return
	var peer := int(payload[0])
	var p := heroes.get(peer) as Player
	heroes.erase(peer)
	_samples.erase(peer)
	if p != null and is_instance_valid(p):
		zone.remove_player(p)
		p.queue_free()


func _on_snapshot(_from: int, payload: Array) -> void:
	if not Net.is_client() or payload.size() < 2:
		return
	var server_ms := float(payload[0])
	var offset := server_ms - float(Time.get_ticks_msec())
	# The least-delayed packet is the best clock estimate; drift slowly back
	# down so a one-off early estimate cannot stick forever.
	if not _clock_ready or offset > _clock_offset:
		_clock_offset = offset
		_clock_ready = true
	else:
		_clock_offset -= 0.5  # ~10 ms per second at 20 Hz
	for e: Array in payload[1] as Array:
		if e.size() < 8:
			continue
		var peer := int(e[0])
		if not _samples.has(peer):
			continue  # not spawned yet (the spawn is reliable and follows)
		var buffer: Array = _samples[peer]
		buffer.append({"t": server_ms, "pos": e[1] as Vector3, "yaw": float(e[2]), "vel": e[3] as Vector3,
			"state": int(e[4]), "hp": float(e[5]), "hp_max": float(e[6]), "tp": int(e[7])})
		while buffer.size() > 2 and server_ms - float((buffer[0] as Dictionary)["t"]) > BUFFER_MS:
			buffer.pop_front()


func _pose_puppets() -> void:
	if not _clock_ready:
		return
	var render_t := float(Time.get_ticks_msec()) + _clock_offset - INTERP_DELAY_MS
	for peer: int in heroes:
		var p := heroes[peer] as Player
		if p == null or not is_instance_valid(p):
			continue
		var s := sample_at(_samples.get(peer, []) as Array, render_t)
		if s.is_empty():
			continue
		p.apply_net_state(s["pos"] as Vector3, float(s["yaw"]), s["vel"] as Vector3, int(s["state"]),
			float(s["hp"]), float(s["hp_max"]))


## The pose at server time `t` from time-ordered samples: interpolated between
## the two around it (never across a teleport), extrapolated along the last
## velocity for up to MAX_EXTRAPOLATE_MS past the newest, else held.
static func sample_at(samples: Array, t: float) -> Dictionary:
	if samples.is_empty():
		return {}
	var first := samples[0] as Dictionary
	if t <= float(first["t"]):
		return first
	for i in range(samples.size() - 1):
		var a := samples[i] as Dictionary
		var b := samples[i + 1] as Dictionary
		var ta := float(a["t"])
		var tb := float(b["t"])
		if t > tb:
			continue
		if int(a["tp"]) != int(b["tp"]) or tb <= ta:
			return b  # teleported in between: snap
		var k := (t - ta) / (tb - ta)
		var out := b.duplicate()
		out["pos"] = (a["pos"] as Vector3).lerp(b["pos"] as Vector3, k)
		out["yaw"] = lerp_angle(float(a["yaw"]), float(b["yaw"]), k)
		out["vel"] = (a["vel"] as Vector3).lerp(b["vel"] as Vector3, k)
		out["state"] = int(a["state"]) if k < 0.5 else int(b["state"])
		return out
	var last := (samples[samples.size() - 1] as Dictionary).duplicate()
	var ahead := minf(t - float(last["t"]), MAX_EXTRAPOLATE_MS) / 1000.0
	var vel := last["vel"] as Vector3
	last["pos"] = (last["pos"] as Vector3) + Vector3(vel.x, 0.0, vel.z) * ahead
	return last


## Name and level over a remote hero (the roster keeps both current).
func _add_nameplate(p: Player, peer: int) -> void:
	var label := Label3D.new()
	label.name = "Nameplate"
	UiTheme.label3d(label)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = ArtKit.color("color_roles.player_accent.hot", Color(0.62, 0.95, 0.9))
	label.position = Vector3(0, NAMEPLATE_HEIGHT, 0)
	p.add_child(label)
	var refresh := func() -> void:
		var entry: Dictionary = Net.roster.get(peer, {})
		label.text = "%s  Lv%d" % [str(entry.get("name", "Hero")), int(entry.get("level", 1))]
	refresh.call()
	Net.roster_changed.connect(refresh)
	label.tree_exiting.connect(func() -> void:
		if Net.roster_changed.is_connected(refresh):
			Net.roster_changed.disconnect(refresh))
