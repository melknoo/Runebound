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

## M09 phase 3: enemies. Server: net id -> the real enemy; client: -> puppet.
var enemies: Dictionary = {}
var _enemy_samples: Dictionary = {}  # client: id -> samples like the heroes'
var _next_enemy_id: int = 1
var _bolts: Dictionary = {}          # server: id -> EnemyBolt; client: id -> its copy
var _next_bolt_id: int = 1
var _round_robin: int = 0
## Client counters (tests): forwarded hits taken / dodged by our hero.
var hurts_taken: int = 0
var hurts_dodged: int = 0
var hits_sent: int = 0
var hurts_forwarded: int = 0  # server

## Enemies farther than this from a client's hero are sent only in the slow
## round-robin refresh.
const RELEVANCE := 150.0
const IDLE_REFRESH_PER_SNAPSHOT := 3
## A hit claimed from farther away than this is ignored (sanity, not anti-cheat).
const MAX_HIT_RANGE := 45.0
## A forwarded hit still counts this far outside its area (the proxy lags the
## owner a little; the owner's own screen decides the rest).
const HURT_MARGIN := 1.2
## Enemy health per hero beyond the first (user decision 2026-09-25: +70 %).
## Damage stays; applied at spawn and again, keeping the fraction, whenever a
## hero joins or leaves.
const HP_PER_EXTRA_HERO := 0.7
var _enemy_handlers: Dictionary = {}  # NetMsg kind -> handler (registered in setup)


func setup(z: ZoneBase) -> void:
	zone = z
	name = "NetWorld"
	Net.on(NetMsg.HERO_STATE, _on_hero_state)
	Net.on(NetMsg.SNAPSHOT, _on_snapshot)
	Net.on(NetMsg.HERO_SPAWN, _on_hero_spawn)
	Net.on(NetMsg.HERO_DESPAWN, _on_hero_despawn)
	Net.on(NetMsg.HERO_ACTION, _on_hero_action)
	Net.on(NetMsg.CHARACTER, _on_character)
	_enemy_handlers = {
		NetMsg.ENEMY_SPAWN: _on_enemy_spawn, NetMsg.ENEMY_STATE: _on_enemy_state_msg,
		NetMsg.ENEMY_HIT: _on_enemy_hit_msg, NetMsg.ENEMY_DOT: _on_enemy_dot_msg,
		NetMsg.ENEMY_DEATH: _on_enemy_death_msg, NetMsg.ENEMY_DESPAWN: _on_enemy_despawn_msg,
		NetMsg.BOLT: _on_bolt_msg, NetMsg.BOLT_POP: _on_bolt_pop_msg,
		NetMsg.HIT: _on_hit_msg, NetMsg.STATUS: _on_status_msg, NetMsg.HURT: _on_hurt_msg,
		NetMsg.ENEMY_FX: _on_enemy_fx_msg, NetMsg.HAZARD: _on_hazard_msg, NetMsg.ENEMY_SCALE: _on_enemy_scale_msg,
	}
	for kind: int in _enemy_handlers:
		Net.on(kind, _enemy_handlers[kind] as Callable)
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
	for kind: int in _enemy_handlers:
		Net.off(kind, _enemy_handlers[kind] as Callable)
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
	_rescale_enemies()
	# The newcomer gets every other hero; the others get the newcomer.
	for other: int in heroes:
		if other != peer:
			Net.send_to_peer(peer, NetMsg.HERO_SPAWN, _spawn_payload(other))
	Net.broadcast_zone(NetMsg.HERO_SPAWN, _spawn_payload(peer), Net.CH_EVENTS, peer)
	for id: int in enemies:  # the newcomer gets every enemy alive right now
		var e := enemies[id] as EnemyBase
		if is_instance_valid(e) and e.ai_state != EnemyBase.AIState.DEAD:
			Net.send_to_peer(peer, NetMsg.ENEMY_SPAWN, _enemy_spawn_payload(e))
	Net.log_line("%s's hero is in the world at %s" % [Net.peer_name(peer), proxy.global_position.round()])


func _on_peer_left(peer: int) -> void:
	var proxy := heroes.get(peer) as Player
	heroes.erase(peer)
	_last_seq.erase(peer)
	if proxy != null and is_instance_valid(proxy):
		zone.remove_player(proxy)
		proxy.queue_free()
	Net.broadcast_zone(NetMsg.HERO_DESPAWN, [peer])
	_rescale_enemies()


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
	var idle: Array[EnemyBase] = []
	var awake: Array[EnemyBase] = []
	for id: int in enemies:
		var e := enemies[id] as EnemyBase
		if not is_instance_valid(e) or e.ai_state == EnemyBase.AIState.DEAD:
			continue
		if e.sleeping:
			idle.append(e)
		else:
			awake.append(e)
	# A few sleeping enemies per snapshot keep far puppets fresh.
	var refresh: Array[EnemyBase] = []
	for i in mini(IDLE_REFRESH_PER_SNAPSHOT, idle.size()):
		_round_robin = (_round_robin + 1) % idle.size()
		refresh.append(idle[_round_robin])
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
		var me := heroes.get(peer) as Player
		var rows: Array[Dictionary] = []
		for e in awake:
			if me == null or e.global_position.distance_to(me.global_position) <= RELEVANCE:
				rows.append(_enemy_row(e))
		for e in refresh:
			rows.append(_enemy_row(e))
		if entries.is_empty() and rows.is_empty():
			continue
		var first := true
		var start := 0
		while first or start < rows.size():
			var chunk := rows.slice(start, start + NetCodec.ENEMIES_PER_PACKET)
			Net.send_to_peer(peer, NetMsg.SNAPSHOT, [now, entries if first else [], NetCodec.encode_enemies(chunk)],
				Net.CH_SNAPSHOT)
			first = false
			start += NetCodec.ENEMIES_PER_PACKET


func _enemy_row(e: EnemyBase) -> Dictionary:
	return {"id": e.net_id, "pos": e.global_position, "yaw": e.visual.rotation.y, "vel": e.velocity,
		"state": int(e.ai_state), "seq": e.state_seq, "hp": e.health.current_health, "bits": e.net_status_bits()}


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
	if payload.size() >= 3 and payload[2] is PackedByteArray:
		for row in NetCodec.decode_enemies(payload[2] as PackedByteArray):
			var id := int(row["id"])
			if not _enemy_samples.has(id):
				continue
			row["t"] = server_ms
			row["tp"] = 0
			var samples: Array = _enemy_samples[id]
			samples.append(row)
			while samples.size() > 2 and server_ms - float((samples[0] as Dictionary)["t"]) > BUFFER_MS:
				samples.pop_front()
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
	for id: int in enemies:
		var e := enemies[id] as EnemyBase
		if e == null or not is_instance_valid(e):
			continue
		var es := sample_at(_enemy_samples.get(id, []) as Array, render_t)
		if not es.is_empty():
			e.apply_net_pose(es["pos"] as Vector3, float(es["yaw"]), es["vel"] as Vector3, float(es["hp"]), int(es["bits"]))


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


# ---------------------------------------------------------------------------
# Enemies (M09 phase 3)
# ---------------------------------------------------------------------------

## Server: ZoneBase._spawn_enemy (deferred, so an elite's modifier exists).
func register_enemy(e: EnemyBase) -> void:
	if not is_instance_valid(e) or e.ai_state == EnemyBase.AIState.DEAD or e.net_id != 0:
		return
	e.net_id = _next_enemy_id
	_next_enemy_id = _next_enemy_id % 65000 + 1  # u16 on the wire, reused only after 65k spawns
	enemies[e.net_id] = e
	_scale_health(e, false)
	e.state_entered.connect(_on_enemy_state.bind(e))
	e.fx_played.connect(_on_enemy_fx.bind(e))
	e.health.damaged.connect(_on_enemy_damaged.bind(e))
	e.health.dot_damaged.connect(_on_enemy_dot.bind(e))
	e.enemy_died.connect(_on_enemy_killed)
	e.tree_exiting.connect(_on_enemy_gone.bind(e))
	Net.broadcast_zone(NetMsg.ENEMY_SPAWN, _enemy_spawn_payload(e))


func _enemy_spawn_payload(e: EnemyBase) -> Array:
	var modifier := e.get_node_or_null(^"EliteModifier") as EliteModifier
	return [e.net_id, e.type_id, e.global_position, e.visual.rotation.y, e.level,
		int(modifier.kind) if modifier != null else -1, e.health.current_health, e.health.max_health,
		int(e.ai_state), e.state_seq]


func _on_enemy_state(state: EnemyBase.AIState, e: EnemyBase) -> void:
	if state == EnemyBase.AIState.DEAD:
		return  # ENEMY_DEATH says it
	Net.broadcast_zone(NetMsg.ENEMY_STATE, [e.net_id, int(state), e.state_seq, e.global_position, e.visual.rotation.y])


func _on_enemy_damaged(hit: HitInfo, e: EnemyBase) -> void:
	Net.broadcast_zone(NetMsg.ENEMY_HIT, [e.net_id, hit.damage, hit.is_crit, int(hit.type), _peer_of(hit.attacker_id)])


func _on_enemy_dot(amount: float, type: HitInfo.DamageType, e: EnemyBase) -> void:
	Net.broadcast_zone(NetMsg.ENEMY_DOT, [e.net_id, amount, int(type), _peer_of(e.status.burn_source_id)])


func _on_enemy_killed(e: EnemyBase) -> void:
	Net.broadcast_zone(NetMsg.ENEMY_DEATH, [e.net_id, _peer_of(e.last_attacker_id)])


func _on_enemy_gone(e: EnemyBase) -> void:
	if not enemies.has(e.net_id):
		return
	enemies.erase(e.net_id)
	if e.ai_state != EnemyBase.AIState.DEAD:
		Net.broadcast_zone(NetMsg.ENEMY_DESPAWN, [e.net_id])


## The co-op peer behind a player instance id (0: the world, or unknown).
func _peer_of(instance_id: int) -> int:
	if instance_id == 0:
		return 0
	var obj := instance_from_id(instance_id)
	var hero := obj as Player if obj != null and is_instance_valid(obj) else null
	return hero.peer_id if hero != null and hero.net_role == Player.NetRole.PROXY else 0


## Server: an enemy bolt came to life (EnemyBolt._ready).
func register_bolt(b: EnemyBolt) -> void:
	if not Net.is_dedicated():
		return
	b.net_id = _next_bolt_id
	_next_bolt_id += 1
	_bolts[b.net_id] = b
	Net.broadcast_zone(NetMsg.BOLT, [b.net_id, b.global_position, b.direction(), b.speed])


func bolt_popped(b: EnemyBolt) -> void:
	if Net.is_dedicated() and _bolts.has(b.net_id):
		_bolts.erase(b.net_id)
		Net.broadcast_zone(NetMsg.BOLT_POP, [b.net_id, b.global_position])


## Server: an enemy attack struck a client's proxy; its owner decides.
func forward_hurt(proxy: Player, hit: HitInfo) -> void:
	hurts_forwarded += 1
	Net.send_to_peer(proxy.peer_id, NetMsg.HURT, [NetCodec.hit_to_array(hit)])


## Client: our hero hit an enemy puppet.
func send_hit(e: EnemyBase, hit: HitInfo) -> void:
	hits_sent += 1
	Net.send_to_server(NetMsg.HIT, [e.net_id, NetCodec.hit_to_array(hit)])


## Client: a status applied to a puppet without a hit.
func send_status(e: EnemyBase, kind: StringName, duration: float, amount: float) -> void:
	Net.send_to_server(NetMsg.STATUS, [e.net_id, String(kind), duration, amount])


# --- server: what clients tell us ------------------------------------------

func _on_hit_msg(from: int, payload: Array) -> void:
	if not Net.is_dedicated() or payload.size() < 2 or payload[1] is not Array:
		return
	var e := enemies.get(int(payload[0])) as EnemyBase
	var proxy := heroes.get(from) as Player
	if e == null or not is_instance_valid(e) or e.ai_state == EnemyBase.AIState.DEAD 			or proxy == null or not is_instance_valid(proxy):
		return
	if proxy.global_position.distance_to(e.global_position) > MAX_HIT_RANGE:
		return
	var hit := NetCodec.hit_from_array(payload[1] as Array)
	hit.attacker_id = proxy.get_instance_id()  # talents, kill credit and loot follow the proxy
	hit.from_player = true
	e.take_hit(hit)


func _on_status_msg(from: int, payload: Array) -> void:
	if not Net.is_dedicated() or payload.size() < 4:
		return
	var e := enemies.get(int(payload[0])) as EnemyBase
	var proxy := heroes.get(from) as Player
	if e == null or not is_instance_valid(e) or e.ai_state == EnemyBase.AIState.DEAD or proxy == null:
		return
	var duration := clampf(float(payload[2]), 0.0, 30.0)
	match str(payload[1]):
		"burn":
			e.status.apply_burn(maxf(float(payload[3]), 0.0), duration, proxy.get_instance_id())
		"chill":
			e.status.apply_chill(duration)
		"shock":
			e.status.apply_shock(duration)
		"conductor":
			e.status.apply_conductor(duration)


# --- client: what the server tells us --------------------------------------

func _on_enemy_spawn(_from: int, payload: Array) -> void:
	if not Net.is_client() or payload.size() < 10:
		return
	var id := int(payload[0])
	if enemies.has(id):
		return
	var e := ZoneBase.make_enemy(str(payload[1]))
	e.net_puppet = true
	e.net_id = id
	e.level = int(payload[4])
	zone.enemies_root.add_child(e)
	var kind := int(payload[5])
	if kind >= 0:
		var modifier := EliteModifier.new()
		modifier.name = "EliteModifier"
		modifier.kind = kind as EliteModifier.Kind
		e.add_child(modifier)
	e.global_position = payload[2] as Vector3
	e.visual.rotation.y = float(payload[3])
	e.health.max_health = maxf(float(payload[7]), 1.0)
	e.health.current_health = clampf(float(payload[6]), 0.0, e.health.max_health)
	e.ai_state = clampi(int(payload[8]), 0, EnemyBase.AIState.size() - 1) as EnemyBase.AIState
	e.state_seq = int(payload[9])
	enemies[id] = e
	_enemy_samples[id] = []
	zone.setup_enemy_puppet(e)


func _puppet(payload: Array) -> EnemyBase:
	if not Net.is_client() or payload.is_empty():
		return null
	var entry: Variant = enemies.get(int(payload[0]))
	return entry as EnemyBase if is_instance_valid(entry) else null  # never cast a freed node


func _on_enemy_state_msg(_from: int, payload: Array) -> void:
	var e := _puppet(payload)
	if e != null and payload.size() >= 5:
		e.net_enter_state(clampi(int(payload[1]), 0, EnemyBase.AIState.size() - 1) as EnemyBase.AIState,
			int(payload[2]), payload[3] as Vector3, float(payload[4]))


func _on_enemy_hit_msg(_from: int, payload: Array) -> void:
	var e := _puppet(payload)
	if e != null and payload.size() >= 5:
		e.present_hit(float(payload[1]), bool(payload[2]), clampi(int(payload[3]), 0, 3) as HitInfo.DamageType,
			int(payload[4]) == Net.my_id())


func _on_enemy_dot_msg(_from: int, payload: Array) -> void:
	var e := _puppet(payload)
	if e != null and payload.size() >= 4:
		e.present_dot(float(payload[1]), clampi(int(payload[2]), 0, 3) as HitInfo.DamageType, int(payload[3]) == Net.my_id())


func _on_enemy_death_msg(_from: int, payload: Array) -> void:
	var e := _puppet(payload)
	if e == null:
		return
	enemies.erase(e.net_id)
	_enemy_samples.erase(e.net_id)
	e.present_death()


func _on_enemy_despawn_msg(_from: int, payload: Array) -> void:
	var e := _puppet(payload)
	if e == null:
		return
	enemies.erase(e.net_id)
	_enemy_samples.erase(e.net_id)
	e.queue_free()


func _on_bolt_msg(_from: int, payload: Array) -> void:
	if not Net.is_client() or payload.size() < 4:
		return
	var bolt := EnemyBolt.new()
	bolt.visual_only = true
	bolt.setup(payload[2] as Vector3, float(payload[3]), 0.0)
	bolt.position = payload[1] as Vector3  # before add_child, like every projectile
	zone.add_child(bolt)
	_bolts[int(payload[0])] = bolt


func _on_bolt_pop_msg(_from: int, payload: Array) -> void:
	if not Net.is_client() or payload.size() < 2:
		return
	var entry: Variant = _bolts.get(int(payload[0]))
	_bolts.erase(int(payload[0]))
	if not is_instance_valid(entry):
		return  # the copy already popped against a wall on its own
	var bolt := entry as EnemyBolt
	if bolt != null:
		bolt.global_position = payload[1] as Vector3
		bolt.net_pop()


## An enemy attack struck our hero's proxy on the server. We take it the way
## our own screen saw it: dodge i-frames refuse it inside Player.take_hit, and
## a hero that already left the struck area is not hit.
func _on_hurt_msg(_from: int, payload: Array) -> void:
	if not Net.is_client() or payload.is_empty() or payload[0] is not Array:
		return
	var hero := zone.player
	if hero == null or not is_instance_valid(hero) or hero.health.is_dead:
		return
	var hit := NetCodec.hit_from_array(payload[0] as Array)
	if hit.area_radius > 0.0 and hit.area_center != Vector3.INF:
		var chest := hero.global_position + Vector3(0, 0.9, 0)
		if chest.distance_to(hit.area_center) > hit.area_radius + HURT_MARGIN:
			hurts_dodged += 1
			return
	if hero.take_hit(hit):
		hurts_taken += 1
	else:
		hurts_dodged += 1


# ---------------------------------------------------------------------------
# M09 phase 3b: named actions, hazards, health scaling
# ---------------------------------------------------------------------------

func _on_enemy_fx(fx: StringName, e: EnemyBase) -> void:
	Net.broadcast_zone(NetMsg.ENEMY_FX, [e.net_id, String(fx), e.global_position, e.visual.rotation.y])


## Server: a ground hazard appeared (FirePatch / ShadowRune _ready).
func register_hazard(kind: StringName, pos: Vector3) -> void:
	if Net.is_dedicated():
		Net.broadcast_zone(NetMsg.HAZARD, [String(kind), pos])


func _hp_scale() -> float:
	return 1.0 + HP_PER_EXTRA_HERO * float(maxi(heroes.size() - 1, 0))


## Scales an enemy's health to the party size, keeping its fraction.
func _scale_health(e: EnemyBase, announce: bool) -> void:
	if not e.has_meta(&"base_max_health"):
		e.set_meta(&"base_max_health", e.health.max_health)
	var target := float(e.get_meta(&"base_max_health")) * _hp_scale()
	if is_equal_approx(target, e.health.max_health):
		return
	var fraction := e.health.current_health / maxf(e.health.max_health, 1.0)
	e.health.max_health = target
	e.health.current_health = target * fraction
	e.health.health_changed.emit(e.health.current_health, target)
	if announce:
		Net.broadcast_zone(NetMsg.ENEMY_SCALE, [e.net_id, target])


func _rescale_enemies() -> void:
	for id: int in enemies:
		var e := enemies[id] as EnemyBase
		if is_instance_valid(e) and e.ai_state != EnemyBase.AIState.DEAD:
			_scale_health(e, true)


func _on_enemy_fx_msg(_from: int, payload: Array) -> void:
	var e := _puppet(payload)
	if e == null or payload.size() < 4:
		return
	var fx := StringName(str(payload[1]))
	var pos := payload[2] as Vector3
	if fx == &"blink_in":
		_enemy_samples[e.net_id] = []  # snap to the new spot instead of sliding there
		e.global_position = pos
	e.net_play_fx(fx, pos, float(payload[3]))


func _on_hazard_msg(_from: int, payload: Array) -> void:
	if not Net.is_client() or payload.size() < 2:
		return
	var pos := payload[1] as Vector3
	match str(payload[0]):
		"fire_patch":
			var patch := FirePatch.new()
			patch.visual_only = true
			patch.position = pos
			zone.add_child(patch)
		"shadow_rune":
			var rune := ShadowRune.new()
			rune.visual_only = true
			rune.position = pos
			zone.add_child(rune)


func _on_enemy_scale_msg(_from: int, payload: Array) -> void:
	var e := _puppet(payload)
	if e != null and payload.size() >= 2:
		e.health.max_health = maxf(float(payload[1]), 1.0)
		e.health.health_changed.emit(e.health.current_health, e.health.max_health)
