extends Node
## Autoload "Net" (M09 co-op): the session and the only RPC endpoint.
##
## Modes (docs/ROADMAP.md M09, TECHNICAL_ARCHITECTURE "Co-op"):
##   OFFLINE  singleplayer: this machine is the authority with a local hero
##            (OfflineMultiplayerPeer, exactly the pre-M09 code path)
##   SERVER   dedicated, headless: the authority without a hero
##   CLIENT   a hero in the server's world
## Game code asks is_authority() / is_client() / is_dedicated() / has_view(),
## never DisplayServer: headless bot clients are clients too.
##
## Messages: send_to_server / send_to_peer / broadcast_zone with a NetMsg kind
## and an Array payload; handlers register with on(kind, callable(from: int,
## payload: Array)). The authority never RPCs itself: send_to_server()
## dispatches locally there, so singleplayer runs the same handlers. Zone-bound
## messages carry the zone epoch and are dropped when stale; the server sends
## zone messages to a client only after it reported ZONE_READY.
##
## Handshake: SceneMultiplayer auth (raw bytes before any RPC). The server
## sends a challenge, the client answers with its hello and a MAC made with its
## invite code (NetAuth, M09b); only a verified answer is decoded. Then the
## exact protocol, the same Godot major.minor (patch releases talk to each
## other: 4.6.1 joins a 4.6.3 server) and the player count. Every refusal
## carries a readable reason instead of failing on RPC ids.
##
## Invites (M09b): the server reads its invite list (`invites_path`, one code
## per friend, tools/server/invites.sh) every INVITES_POLL seconds; a revoked or
## changed code ends that session (KICK), and a code joining again replaces its
## older session. Without an invite list the server is open and ENet binds
## 127.0.0.1 only (tests, tools/run_godot coop).

signal session_started(welcome: Dictionary)  # client: accepted, the zone loads next
signal session_failed(reason: String)        # client: could not join
signal session_ended(reason: String)         # client: left or lost the server
signal roster_changed
signal peer_ready(peer_id: int)  # server: a client finished loading the current zone
signal peer_left(peer_id: int)   # server: a client left

enum Mode { OFFLINE, SERVER, CLIENT }

const PROTOCOL := 8
const DEFAULT_PORT := 7777
const MAX_PLAYERS := 5
const CHANNELS := 3
const CH_EVENTS := 0    # reliable, ordered: events, spawns, hits
const CH_HERO := 1      # unreliable ordered: a hero's own state
const CH_SNAPSHOT := 2  # unreliable ordered: world snapshots
const EPOCH_ANY := -1   # session messages, valid in every zone
const CONNECT_TIMEOUT := 12.0
const AUTH_TIMEOUT := 8.0
## Unverified connections at once (a scan, a flood): a new one pushes the
## oldest out, so a friend always gets a turn.
const PENDING_MAX := 8
## ENet slots beyond the party: the waiting room plus peers still saying
## goodbye after being pushed out.
const ENET_SPARE := 24
const INVITES_POLL := 2.0
const REFUSAL_LOG_PER_MIN := 5
## Protocol-7 games read the challenge's reason as their refusal.
const UPDATE_REASON := "This server runs a newer version of RUNEBOUND. Update your game (git pull)."
## Zone builds block the main loop for seconds (the laptop: ~1.5 s); ENet
## must not drop a peer for that.
const PEER_TIMEOUT_MIN_MS := 15000
const PEER_TIMEOUT_MAX_MS := 30000
const TITLE_SCENE := "res://scenes/title.tscn"
const STATS_EVERY := 60.0
const NAME_MAX := 16

var mode: Mode = Mode.OFFLINE
var max_players: int = MAX_PLAYERS
var zone_epoch: int = 0
var zone_scene: String = ""
## peer id -> {name, class_id, level} (the server's list; clients get copies).
var roster: Dictionary = {}
## Why the last session ended or failed (the title screen shows it).
var last_reason: String = ""
## Client: where the welcome says to appear (next to a party member; INF = the
## zone's own spawn). Read once by ZoneBase._spawn_player.
var pending_spawn: Vector3 = Vector3.INF
## Tests: pretend to speak another protocol (`-- --protocol=N`).
var protocol_override: int = -1
## Tests: pretend to run another Godot version (`-- --godot=4.5.2-stable`).
var godot_override: String = ""
## Tests: how this client answers the challenge (`-- --auth=`): "" normally,
## "junk" random bytes, "junk_magic" our format with a random MAC, "old" a
## protocol-7 game (hello first), "silent" never.
var auth_test: String = ""
## Server: the invite list ("" = open: no codes, ENet on 127.0.0.1 only).
var invites_path: String = ""
## Server counters (tests, the 60 s log line).
var refused_total: int = 0
var evicted_total: int = 0
var kicks: int = 0
## Server: peers told "no", dropped shortly after unless they already left.
var _refused: Dictionary = {}

## Scripts nothing works without. A new class_name script is unknown to a game
## or headless run until an import has rescanned the project (the run_godot
## wrappers and the server script import whenever project files changed); if
## one still fails to compile, the title screen and the server say so.
const REQUIRED_SCRIPTS: Array[String] = ["res://scripts/net/net_world.gd", "res://scripts/world/zone_base.gd",
	"res://scripts/player/player.gd", "res://scripts/enemies/enemy_base.gd"]
## Zone-bound messages dropped because their epoch was stale (tests, stats).
var dropped_stale: int = 0

var _handlers: Dictionary = {}  # kind -> Array of Callables
var _enet: ENetMultiplayerPeer = null
var _hello: Dictionary = {}         # client: what it sends in the handshake
var _welcome: Dictionary = {}       # client: the server's answer
var _pending: Dictionary = {}       # server: peer -> hello, until auth completes
var _ready_epoch: Dictionary = {}   # server: peer -> epoch it has loaded
var _join: Dictionary = {}          # client: {host, port, resolve, stage}
var _code: String = ""              # client: the invite code of this join
var _invite_keys: Dictionary = {}   # server: invite name -> HMAC key
var _invites_text: String = ""      # server: the list as last read
var _invites_loaded := false
var _invites_warned := false
var _invites_left: float = 0.0
var _challenges: Dictionary = {}    # server: peer -> {nonce, since}, until it answers
var _peer_invite: Dictionary = {}   # server: peer -> invite name
var _refusal_log: Array[int] = []   # server: msec of the refusals logged in the last minute
var _refusals: int = 0              # server: refusals since the last log line
var _connect_left: float = 0.0
## Netsim (`-- --netsim=rtt_ms,jitter_ms,loss_pct`): delays this process's
## sends and receives (half the RTT each way) and drops unreliable traffic.
var _sim_rtt: float = 0.0
var _sim_jitter: float = 0.0
var _sim_loss: float = 0.0
var _sim_queue: Array[Dictionary] = []
var _sim_last_due: Dictionary = {}  # "out0" / "in0" ... -> last due msec (keeps reliable FIFO)
var _sim_rng := RandomNumberGenerator.new()
var _tick_start_us: int = 0
var _tick_samples := PackedFloat32Array()
var _stats_left: float = STATS_EVERY


## Marks the end of the physics frame for the server's tick meter.
class TickEnd extends Node:
	var net: Node

	func _physics_process(_delta: float) -> void:
		net.call(&"_tick_end")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -1000  # first in every physics frame (tick meter)
	var end := TickEnd.new()
	end.name = "TickEnd"
	end.net = self
	end.process_physics_priority = 1000
	add_child(end)
	var sm := _scene_multiplayer()
	sm.auth_callback = _on_auth
	sm.auth_timeout = AUTH_TIMEOUT
	sm.server_relay = false  # clients talk to the server only, never through it to each other
	sm.peer_authenticating.connect(_on_peer_authenticating)
	sm.peer_authentication_failed.connect(_on_auth_failed)
	sm.peer_connected.connect(_on_peer_connected)
	sm.peer_disconnected.connect(_on_peer_disconnected)
	sm.connected_to_server.connect(_on_connected)
	sm.connection_failed.connect(_on_connection_failed)
	sm.server_disconnected.connect(_on_server_disconnected)
	on(NetMsg.ROSTER, _on_roster)
	on(NetMsg.ZONE_READY, _on_zone_ready)
	on(NetMsg.ECHO, _on_echo)
	on(NetMsg.TRAVEL_GO, _on_travel_go)
	on(NetMsg.KICK, _on_kick)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--netsim="):
			var parts := arg.trim_prefix("--netsim=").split(",")
			_sim_rtt = parts[0].to_float() if parts.size() > 0 else 0.0
			_sim_jitter = parts[1].to_float() if parts.size() > 1 else 0.0
			_sim_loss = clampf((parts[2].to_float() if parts.size() > 2 else 0.0) / 100.0, 0.0, 1.0)
			print("[net] netsim: rtt %.0f ms, jitter %.0f ms, loss %.0f %%" % [_sim_rtt, _sim_jitter, _sim_loss * 100.0])
		elif arg.begins_with("--protocol="):
			protocol_override = arg.trim_prefix("--protocol=").to_int()
		elif arg.begins_with("--godot="):
			godot_override = arg.trim_prefix("--godot=")
		elif arg.begins_with("--auth="):
			auth_test = arg.trim_prefix("--auth=")


# ---------------------------------------------------------------------------
# Roles
# ---------------------------------------------------------------------------

## This machine simulates the world (singleplayer or the dedicated server).
func is_authority() -> bool:
	return mode != Mode.CLIENT


func is_client() -> bool:
	return mode == Mode.CLIENT


func is_dedicated() -> bool:
	return mode == Mode.SERVER


func is_online() -> bool:
	return mode != Mode.OFFLINE


## This machine shows the world to a player (everything but the server).
func has_view() -> bool:
	return mode != Mode.SERVER


func my_id() -> int:
	return multiplayer.get_unique_id()


static func godot_version() -> String:
	return str(Engine.get_version_info().get("string", "?"))


## "4.6.3-stable (official)" -> "4.6": what server and clients must share.
static func godot_minor(version: String) -> String:
	var parts := version.split(".")
	if parts.size() < 2:
		return version
	return "%s.%s" % [parts[0], parts[1].get_slice("-", 0)]


## REQUIRED_SCRIPTS that failed to compile (empty = all good).
static func broken_scripts() -> Array[String]:
	var out: Array[String] = []
	for path in REQUIRED_SCRIPTS:
		var script := load(path) as GDScript
		if script == null or not script.can_instantiate():
			out.append(path)
	return out


# ---------------------------------------------------------------------------
# Session: host / join / leave
# ---------------------------------------------------------------------------

## Dedicated server at `port`. With an invite list it listens on every
## interface (IPv4 + IPv6) and lets in listed codes only; without one it is
## open and binds 127.0.0.1 (only this machine can join).
func host(port: int, players: int = MAX_PLAYERS, invites: String = "") -> Error:
	_close()
	var peer := ENetMultiplayerPeer.new()
	var bind := "*" if invites != "" else "127.0.0.1"
	peer.set_bind_ip(bind)
	var err := peer.create_server(port, players + ENET_SPARE, CHANNELS)
	if err != OK:
		return err
	_enet = peer
	multiplayer.multiplayer_peer = peer
	mode = Mode.SERVER
	max_players = players
	invites_path = invites
	roster.clear()
	log_line("listening on %s:%d/udp, up to %d players, protocol %d, Godot %s" % [bind, port, players,
		PROTOCOL, godot_version()])
	if invites == "":
		log_line("open: no invite list, only this machine can join")
	else:
		_reload_invites()
	return OK


## Client: join the server at `address` ("host", "host:port", "[v6]:port")
## with the invite code the host gave us ("" for an open server). The answer
## comes as session_started or session_failed.
func join(address: String, player_name: String, class_id: StringName, level: int, invite: String = "") -> void:
	_close()
	last_reason = ""
	_code = invite
	var parsed := NetAddress.parse(address, DEFAULT_PORT)
	if String(parsed["error"]) != "":
		_fail(String(parsed["error"]))
		return
	var host_name := String(parsed["host"])
	var port := int(parsed["port"])
	_hello = {"protocol": PROTOCOL if protocol_override < 0 else protocol_override,
		"godot": godot_version() if godot_override == "" else godot_override,
		"name": clean_name(player_name), "class_id": String(class_id), "level": level}
	_join = {"host": host_name, "port": port, "resolve": -1, "stage": "resolve"}
	mode = Mode.CLIENT
	_connect_left = CONNECT_TIMEOUT
	if host_name.is_valid_ip_address():
		_open_client(host_name, port)
	else:
		_join["resolve"] = IP.resolve_hostname_queue_item(host_name, IP.TYPE_ANY)
		log_line("resolving %s ..." % host_name)


## Client: leave on purpose (back to the title screen).
func leave() -> void:
	_end_session("You left the server.")


## True while a join is resolving / connecting / waiting for the handshake.
func is_joining() -> bool:
	return not _join.is_empty()


func join_stage() -> String:
	return String(_join.get("stage", ""))


static func clean_name(text: String) -> String:
	var s := text.strip_edges().replace("\n", " ")
	if s == "":
		s = "Hero"
	return s.substr(0, NAME_MAX)


func _open_client(ip: String, port: int) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port, CHANNELS)
	if err != OK:
		_fail("Could not open a connection (%s)." % error_string(err))
		return
	_enet = peer
	multiplayer.multiplayer_peer = peer
	_join["stage"] = "connect"
	_connect_left = CONNECT_TIMEOUT
	log_line("connecting to %s ..." % NetAddress.format(ip, port))


func _process(delta: float) -> void:
	if not _join.is_empty():
		_poll_join(delta)
	if not _sim_queue.is_empty():
		_flush_sim()
	if mode == Mode.SERVER:
		_stats_left -= delta
		if _stats_left <= 0.0:
			_stats_left = STATS_EVERY
			_log_stats()
		if invites_path != "":
			_invites_left -= delta
			if _invites_left <= 0.0:
				_invites_left = INVITES_POLL
				_reload_invites()


func _poll_join(delta: float) -> void:
	_connect_left -= delta
	var target := NetAddress.format(String(_join["host"]), int(_join["port"]))
	if String(_join["stage"]) == "resolve":
		var id := int(_join["resolve"])
		match IP.get_resolve_item_status(id):
			IP.RESOLVER_STATUS_DONE:
				var ip := IP.get_resolve_item_address(id)
				IP.erase_resolve_item(id)
				if ip == "":
					_fail("Could not find the server \"%s\"." % String(_join["host"]))
				else:
					_open_client(ip, int(_join["port"]))
				return
			IP.RESOLVER_STATUS_ERROR, IP.RESOLVER_STATUS_NONE:
				IP.erase_resolve_item(id)
				_fail("Could not find the server \"%s\"." % String(_join["host"]))
				return
	if _connect_left <= 0.0:
		_fail("No answer from %s. Is the server running, and is the address right?" % target)


func _on_peer_authenticating(id: int) -> void:
	var sm := _scene_multiplayer()
	if mode == Mode.SERVER:
		if _challenges.size() >= PENDING_MAX:
			_evict_oldest_pending()
		var nonce := NetAuth.new_nonce()
		_challenges[id] = {"nonce": nonce, "since": Time.get_ticks_msec()}
		sm.send_auth(id, var_to_bytes({"challenge": nonce, "reason": UPDATE_REASON}))
	elif mode == Mode.CLIENT and id == 1:
		_join["stage"] = "handshake"
		if auth_test == "old":  # a protocol-7 game sends its hello first
			sm.send_auth(1, var_to_bytes(_hello))


func _on_auth(id: int, data: PackedByteArray) -> void:
	if mode == Mode.SERVER:
		_server_check_join(id, data)
		return
	if mode != Mode.CLIENT or id != 1:
		return
	var decoded: Variant = bytes_to_var(data)  # from the server we chose; never _with_objects
	var msg: Dictionary = decoded if decoded is Dictionary else {}
	if msg.has("challenge"):
		if auth_test == "old":  # a protocol-7 game: an answer without "ok" is a refusal
			_fail(str(msg.get("reason", "The server refused the connection.")))
		elif auth_test != "silent":
			var nonce: PackedByteArray = msg["challenge"] if msg["challenge"] is PackedByteArray else PackedByteArray()
			_scene_multiplayer().send_auth(1, _join_answer(nonce))
	elif bool(msg.get("ok", false)):
		_welcome = msg
		_scene_multiplayer().complete_auth(1)
	else:
		_fail(str(msg.get("reason", "The server refused the connection.")))


func _join_answer(nonce: PackedByteArray) -> PackedByteArray:
	var crypto := Crypto.new()
	match auth_test:
		"junk":
			return crypto.generate_random_bytes(200)
		"junk_magic":
			var out := NetAuth.MAGIC.to_ascii_buffer()
			out.append(NetAuth.FLAG_HAS_CODE)
			out.append_array(crypto.generate_random_bytes(NetAuth.MAC_SIZE + 64))
			return out
	return NetAuth.build_join(_code, nonce, _hello)


## Server: a join answer. Nothing in it is decoded before its MAC checks out
## (or the server is open, which only this machine can reach).
func _server_check_join(id: int, data: PackedByteArray) -> void:
	var challenge: Dictionary = _challenges.get(id, {})
	_challenges.erase(id)  # one answer per challenge
	if challenge.is_empty():
		_refuse(id, UPDATE_REASON, "an answer without a challenge")
		return
	var check := NetAuth.verify_join(data, challenge["nonce"] as PackedByteArray, _invite_keys, invites_path == "")
	var verdict := int(check["verdict"])
	if verdict == NetAuth.Verdict.MALFORMED or verdict == NetAuth.Verdict.OLD_CLIENT:
		_refuse(id, UPDATE_REASON, "not a protocol-%d join (an older game, or noise)" % PROTOCOL)
		return
	if verdict == NetAuth.Verdict.NO_CODE:
		_refuse(id, "This server needs an invite code. Ask the host for yours.", "no invite code")
		return
	if verdict == NetAuth.Verdict.BAD_CODE:
		_refuse(id, "Invite code not accepted. Check it for typos, or ask the host for a new one.", "unknown invite code")
		return
	var decoded: Variant = bytes_to_var(check["hello"] as PackedByteArray)  # verified: never _with_objects
	if decoded is not Dictionary:
		_refuse(id, UPDATE_REASON, "an unreadable hello")
		return
	_server_check_hello(id, decoded as Dictionary, str(check.get("invite", "")))


func _server_check_hello(id: int, hello: Dictionary, invite: String) -> void:
	# A code joining again replaces its older session (a crashed game, or a
	# second PC): that seat does not count against "full".
	var replaced: Array[int] = []
	if invite != "":
		for other: int in _peer_invite:
			if other != id and str(_peer_invite[other]) == invite:
				replaced.append(other)
	var seated := 0
	for other: int in replaced:
		if roster.has(other):
			seated += 1
	var reason := ""
	var their_protocol := int(hello.get("protocol", -1))
	if their_protocol != PROTOCOL:
		reason = "Version mismatch: the server speaks protocol %d, your game %d. Update your game (git pull)." % [
			PROTOCOL, their_protocol]
	elif godot_minor(str(hello.get("godot", "?"))) != godot_minor(godot_version()):
		reason = "Version mismatch: the server runs Godot %s, you run %s. Use Godot %s.x." % [
			godot_version(), str(hello.get("godot", "?")), godot_minor(godot_version())]
	elif roster.size() - seated >= max_players:
		reason = "The server is full (%d/%d)." % [roster.size(), max_players]
	var sm := _scene_multiplayer()
	if reason != "":
		_refuse(id, reason)
		return
	for other: int in replaced:
		kick(other, "You joined this server from another game with the same invite code.")
	if invite != "":
		_peer_invite[id] = invite
	if str(hello.get("godot", "")) != godot_version():
		log_line("note: peer %d runs Godot %s (server %s)" % [id, str(hello.get("godot", "?")), godot_version()])
	hello["name"] = _unique_name(clean_name(str(hello.get("name", ""))))
	hello["invite"] = invite
	_pending[id] = hello
	var spawn_at := Vector3.INF  # late joiners appear next to the party
	var zone := get_tree().current_scene as ZoneBase
	if zone != null and zone.net_world != null:
		spawn_at = zone.net_world.spawn_hint()
	sm.send_auth(id, var_to_bytes({"ok": true, "peer_id": id, "zone": zone_scene, "epoch": zone_epoch,
		"flags": SaveGame.flags.duplicate(true), "name": hello["name"], "spawn_at": spawn_at}))
	sm.complete_auth(id)


## Server: say no (the reason is what the player reads) and drop the peer.
## The log keeps the first REFUSAL_LOG_PER_MIN a minute; the 60 s line counts
## the rest.
func _refuse(id: int, reason: String, why: String = "") -> void:
	_refusals += 1
	refused_total += 1
	var now := Time.get_ticks_msec()
	while not _refusal_log.is_empty() and now - _refusal_log[0] > 60000:
		_refusal_log.pop_front()
	if _refusal_log.size() < REFUSAL_LOG_PER_MIN:
		_refusal_log.append(now)
		log_line("refused peer %d%s: %s" % [id, _peer_from(id), why if why != "" else reason])
	_scene_multiplayer().send_auth(id, var_to_bytes({"ok": false, "reason": reason}))
	_drop_later(id)


## Server: disconnect half a second from now, so a reason sent right before
## arrives first.
func _drop_later(id: int) -> void:
	_refused[id] = true
	get_tree().create_timer(0.5, true, false, true).timeout.connect(func() -> void:
		# The client usually hangs up by itself first (then ENet has forgotten
		# the peer and a disconnect would only log an error).
		if _refused.has(id) and _enet != null and mode == Mode.SERVER:
			_refused.erase(id)
			_enet.disconnect_peer(id)
	)


## Server: the waiting room is full; the connection waiting longest goes.
func _evict_oldest_pending() -> void:
	var oldest := -1
	var since := 0
	for id: int in _challenges:
		var t := int((_challenges[id] as Dictionary)["since"])
		if oldest < 0 or t < since:
			oldest = id
			since = t
	if oldest < 0:
		return
	_challenges.erase(oldest)
	evicted_total += 1
	_refusals += 1
	_scene_multiplayer().disconnect_peer(oldest)


## Server: " from 1.2.3.4" for the log ("" when unknown).
func _peer_from(id: int) -> String:
	if _enet == null:
		return ""
	var p := _enet.get_peer(id)
	return " from %s" % p.get_remote_address() if p != null else ""


## Server: tell a client why, then drop it (M09b: a revoked invite, or its
## code joined from another game).
func kick(peer_id: int, reason: String) -> void:
	if mode != Mode.SERVER:
		return
	kicks += 1
	log_line("kicked %s (peer %d): %s" % [peer_name(peer_id), peer_id, reason])
	_peer_invite.erase(peer_id)
	if roster.has(peer_id):
		send_to_peer(peer_id, NetMsg.KICK, [reason], CH_EVENTS, false)
	_drop_later(peer_id)


func _on_kick(_from: int, payload: Array) -> void:
	if mode == Mode.CLIENT:
		_end_session(str(payload[0]) if not payload.is_empty() else "The server removed you.")


## Server: (re)reads the invite list. A code that is gone or changed ends that
## friend's session; an unreadable list keeps the last one.
func _reload_invites() -> void:
	var text := ""
	var exists := FileAccess.file_exists(invites_path)
	if exists:
		var f := FileAccess.open(invites_path, FileAccess.READ)
		if f == null:
			if not _invites_warned:
				_invites_warned = true
				log_line("cannot read the invite list %s (%s): keeping the last one" % [invites_path,
					error_string(FileAccess.get_open_error())])
			return
		text = f.get_as_text()
		f.close()
	if _invites_loaded and text == _invites_text:
		return
	_invites_loaded = true
	_invites_warned = false
	_invites_text = text
	var parsed := NetAuth.parse_invites(text)
	var old := _invite_keys
	_invite_keys = parsed["keys"]
	if not exists:
		log_line("no invite list at %s: nobody can join until you add one (tools/server/invites.sh add NAME)" % invites_path)
	else:
		var bad := int(parsed["bad"])
		log_line("invites: %d loaded from %s%s" % [_invite_keys.size(), invites_path,
			(" (%d unreadable lines skipped)" % bad) if bad > 0 else ""])
	for id: int in _peer_invite.keys():
		var invite := str(_peer_invite[id])
		if not _invite_keys.has(invite):
			kick(id, "The host revoked your invite code.")
		elif old.has(invite) and old[invite] != _invite_keys[invite]:
			kick(id, "The host changed your invite code. Ask for the new one.")


func _unique_name(wanted: String) -> String:
	var taken: Array[String] = []
	for entry: Dictionary in roster.values():
		taken.append(str(entry.get("name", "")))
	for entry: Dictionary in _pending.values():
		taken.append(str(entry.get("name", "")))
	if not taken.has(wanted):
		return wanted
	var n := 2
	while taken.has("%s %d" % [wanted, n]):
		n += 1
	return "%s %d" % [wanted, n]


func _on_auth_failed(id: int) -> void:
	_pending.erase(id)
	_refused.erase(id)
	_challenges.erase(id)
	_peer_invite.erase(id)
	if mode == Mode.CLIENT and id == 1 and last_reason == "":
		_fail("The handshake with the server timed out. Do you both run the same game version?")


func _on_peer_connected(id: int) -> void:
	if mode != Mode.SERVER:
		return
	var hello: Dictionary = _pending.get(id, {})
	_pending.erase(id)
	roster[id] = {"name": str(hello.get("name", "Hero")), "class_id": str(hello.get("class_id", "")),
		"level": int(hello.get("level", 1))}
	_tune_peer(id)
	var invite := str(hello.get("invite", ""))
	log_line("%s joined (peer %d%s, %d/%d)" % [roster[id]["name"], id,
		(", invite " + invite) if invite != "" else "", roster.size(), max_players])
	_broadcast_roster()


func _on_peer_disconnected(id: int) -> void:
	_pending.erase(id)
	_refused.erase(id)
	_challenges.erase(id)
	_peer_invite.erase(id)
	if mode != Mode.SERVER or not roster.has(id):
		return
	var who := str((roster[id] as Dictionary).get("name", "?"))
	roster.erase(id)
	_ready_epoch.erase(id)
	log_line("%s left (peer %d, %d/%d)" % [who, id, roster.size(), max_players])
	peer_left.emit(id)
	_broadcast_roster()


func _on_connected() -> void:
	if mode != Mode.CLIENT:
		return
	_join.clear()
	_tune_peer(1)
	log_line("joined as %s (peer %d)" % [str(_welcome.get("name", "?")), my_id()])
	var flags: Dictionary = _welcome.get("flags", {})
	SaveGame.begin_online_session(flags)
	var spawn_at: Variant = _welcome.get("spawn_at", Vector3.INF)
	pending_spawn = spawn_at as Vector3 if spawn_at is Vector3 else Vector3.INF
	session_started.emit(_welcome)
	_enter_zone(str(_welcome.get("zone", "")), int(_welcome.get("epoch", 0)))


func _on_connection_failed() -> void:
	if mode == Mode.CLIENT and last_reason == "":
		var target := NetAddress.format(String(_join.get("host", "?")), int(_join.get("port", DEFAULT_PORT)))
		_fail("No answer from %s. Is the server running, and is the address right?" % target)


func _on_server_disconnected() -> void:
	_end_session("Lost the connection to the server.")


## Per-peer ENet tuning: long timeouts (zone builds block the main loop) and
## no packet throttling. ENet's throttle reads the 60 fps frame quantisation of
## both ends as congestion and silently drops unreliable packets (23 % of the
## echo test on localhost); our traffic is small, so it always goes out.
func _tune_peer(id: int) -> void:
	if _enet == null:
		return
	var p := _enet.get_peer(id)
	if p != null:
		p.set_timeout(32, PEER_TIMEOUT_MIN_MS, PEER_TIMEOUT_MAX_MS)
		p.throttle_configure(5000, 32, 0)  # interval, acceleration, deceleration 0 = never throttle down


## Client: loading the server's zone (the welcome, later party travel).
func _enter_zone(scene_path: String, epoch: int, arrival: String = "") -> void:
	if scene_path == "" or not ResourceLoader.exists(scene_path):
		_end_session("The server is in a zone this game does not know (%s). Update your game." % scene_path)
		return
	zone_epoch = epoch
	zone_scene = scene_path
	SaveGame.pending_arrival = arrival
	get_tree().change_scene_to_file(scene_path)


## Server: the party travels. A new zone epoch starts right now (before the
## scene changes), so a client that loads faster than the server still
## reports into the right zone; the new zone adopts peers already ready.
func change_zone(scene_path: String, arrival: String) -> void:
	if mode != Mode.SERVER:
		return
	zone_epoch += 1
	zone_scene = scene_path
	_ready_epoch.clear()
	for id: int in roster:
		send_to_peer(id, NetMsg.TRAVEL_GO, [scene_path, zone_epoch, arrival], CH_EVENTS, false)
	SaveGame.current_zone = scene_path
	SaveGame.save_now()
	log_line("party travels to %s (epoch %d)" % [scene_path, zone_epoch])
	get_tree().change_scene_to_file.call_deferred(scene_path)


func _on_travel_go(_from: int, payload: Array) -> void:
	if mode != Mode.CLIENT or payload.size() < 3:
		return
	var scene_path := str(payload[0])
	var epoch := int(payload[1])
	var arrival := str(payload[2])
	var zone := get_tree().current_scene as ZoneBase
	if zone != null:
		zone.party_travel_go(func() -> void: _enter_zone(scene_path, epoch, arrival))
	else:
		_enter_zone(scene_path, epoch, arrival)


func _fail(reason: String) -> void:
	last_reason = reason
	log_line("join failed: " + reason)
	_close()
	session_failed.emit(reason)


## Client: the session is over (left, kicked, server gone): keep the
## character, restore the singleplayer world, back to the title screen.
func _end_session(reason: String) -> void:
	if mode != Mode.CLIENT:
		return
	var was_in_game := _join.is_empty()
	last_reason = reason
	log_line("session ended: " + reason)
	if was_in_game:
		SaveGame.save_now()
		SaveGame.end_online_session()
	_close()
	session_ended.emit(reason)
	if was_in_game:
		get_tree().change_scene_to_file.call_deferred(TITLE_SCENE)


func _close() -> void:
	if not _join.is_empty() and int(_join.get("resolve", -1)) >= 0:
		IP.erase_resolve_item(int(_join["resolve"]))
	_join.clear()
	if _enet != null:
		_enet.close()
		_enet = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.OFFLINE
	roster.clear()
	_pending.clear()
	_refused.clear()
	_challenges.clear()
	_peer_invite.clear()
	_invite_keys.clear()
	_invites_loaded = false
	_invites_text = ""
	invites_path = ""
	_ready_epoch.clear()
	_sim_queue.clear()
	_sim_last_due.clear()


func _exit_tree() -> void:
	if mode == Mode.SERVER and _enet != null:
		for id: int in roster:
			_enet.disconnect_peer(id)  # clients hear "gone" now, not after the 15-30 s timeout
		if _enet.host != null:
			_enet.host.flush()


func _scene_multiplayer() -> SceneMultiplayer:
	return multiplayer as SceneMultiplayer


# ---------------------------------------------------------------------------
# Zones
# ---------------------------------------------------------------------------

## ZoneBase calls this at the end of its bootstrap. The server starts a new
## zone epoch; a client reports that it has loaded the zone.
func zone_entered(scene_path: String) -> void:
	match mode:
		Mode.SERVER:
			if scene_path != zone_scene:  # the first zone; change_zone already started a travel's epoch
				zone_epoch += 1
				zone_scene = scene_path
				_ready_epoch.clear()
			log_line("zone %s (epoch %d)" % [scene_path, zone_epoch])
		Mode.CLIENT:
			zone_scene = scene_path
			send_to_server(NetMsg.ZONE_READY, [scene_path])


## Server: has this client loaded the current zone?
func is_peer_ready(peer_id: int) -> bool:
	return int(_ready_epoch.get(peer_id, -1)) == zone_epoch


## Server: peers that have loaded the current zone.
func ready_peers() -> Array[int]:
	var out: Array[int] = []
	for id: int in _ready_epoch:
		if int(_ready_epoch[id]) == zone_epoch:
			out.append(id)
	return out


func _on_zone_ready(from: int, payload: Array) -> void:
	if mode != Mode.SERVER or payload.is_empty():
		return
	if str(payload[0]) != zone_scene:
		return  # a late report from the previous zone
	_ready_epoch[from] = zone_epoch
	log_line("%s is in %s" % [peer_name(from), zone_scene.get_file().get_basename()])
	peer_ready.emit(from)


## Connection test: the server bounces the packet straight back.
func _on_echo(from: int, payload: Array) -> void:
	if mode == Mode.SERVER:
		send_to_peer(from, NetMsg.ECHO, payload, CH_SNAPSHOT, false)


## Server: a client's level changed (its character arrived or it levelled).
func set_peer_level(peer_id: int, level: int) -> void:
	if mode != Mode.SERVER or not roster.has(peer_id):
		return
	var entry := roster[peer_id] as Dictionary
	if int(entry.get("level", 0)) == level:
		return
	entry["level"] = level
	_broadcast_roster()


func peer_name(peer_id: int) -> String:
	return str((roster.get(peer_id, {}) as Dictionary).get("name", "peer %d" % peer_id))


func _broadcast_roster() -> void:
	roster_changed.emit()
	for id: int in roster:
		send_to_peer(id, NetMsg.ROSTER, [roster.duplicate(true)], CH_EVENTS, false)


func _on_roster(_from: int, payload: Array) -> void:
	if mode != Mode.CLIENT or payload.is_empty() or payload[0] is not Dictionary:
		return
	roster = (payload[0] as Dictionary).duplicate(true)
	roster_changed.emit()


# ---------------------------------------------------------------------------
# Messages
# ---------------------------------------------------------------------------

## Register `handler(from: int, payload: Array)` for a NetMsg kind.
func on(kind: int, handler: Callable) -> void:
	if not _handlers.has(kind):
		_handlers[kind] = []
	var list: Array = _handlers[kind]
	if not list.has(handler):
		list.append(handler)


func off(kind: int, handler: Callable) -> void:
	if _handlers.has(kind):
		(_handlers[kind] as Array).erase(handler)


## To the authority. Runs the handler right here when this machine is it.
func send_to_server(kind: int, payload: Array = [], channel: int = CH_EVENTS, zone_bound: bool = true) -> void:
	var epoch := zone_epoch if zone_bound else EPOCH_ANY
	if is_authority():
		_dispatch(my_id(), epoch, kind, payload)
	else:
		_send(1, channel, epoch, kind, payload)


## Server -> one client (runs locally when `peer_id` is this machine).
func send_to_peer(peer_id: int, kind: int, payload: Array = [], channel: int = CH_EVENTS, zone_bound: bool = true) -> void:
	var epoch := zone_epoch if zone_bound else EPOCH_ANY
	if peer_id == my_id():
		_dispatch(peer_id, epoch, kind, payload)
	elif mode == Mode.SERVER:
		if zone_bound and not is_peer_ready(peer_id):
			return  # still loading: it gets the full state after ZONE_READY
		_send(peer_id, channel, epoch, kind, payload)


## Server -> every client that has loaded the current zone (except one).
func broadcast_zone(kind: int, payload: Array = [], channel: int = CH_EVENTS, except_peer: int = 0) -> void:
	if mode != Mode.SERVER:
		return
	for id in ready_peers():
		if id != except_peer:
			_send(id, channel, zone_epoch, kind, payload)


func _send(to: int, channel: int, epoch: int, kind: int, payload: Array) -> void:
	if _sim_rtt > 0.0 or _sim_loss > 0.0:
		_sim_enqueue("out", to, channel, epoch, kind, payload)
		return
	_send_now(to, channel, epoch, kind, payload)


func _send_now(to: int, channel: int, epoch: int, kind: int, payload: Array) -> void:
	if _enet == null:
		return
	var peer := _enet.get_peer(to)
	if peer == null or peer.get_state() != ENetPacketPeer.STATE_CONNECTED:
		return  # leaving (ENet is tearing it down): sending would only log errors
	match channel:
		CH_HERO:
			_rx_hero.rpc_id(to, epoch, kind, payload)
		CH_SNAPSHOT:
			_rx_snapshot.rpc_id(to, epoch, kind, payload)
		_:
			_rx_event.rpc_id(to, epoch, kind, payload)


@rpc("any_peer", "call_remote", "reliable", 0)
func _rx_event(epoch: int, kind: int, payload: Array) -> void:
	_receive(CH_EVENTS, epoch, kind, payload)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _rx_hero(epoch: int, kind: int, payload: Array) -> void:
	_receive(CH_HERO, epoch, kind, payload)


@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _rx_snapshot(epoch: int, kind: int, payload: Array) -> void:
	_receive(CH_SNAPSHOT, epoch, kind, payload)


func _receive(channel: int, epoch: int, kind: int, payload: Array) -> void:
	var from := multiplayer.get_remote_sender_id()
	if mode == Mode.CLIENT and from != 1:
		return  # clients only listen to the server
	if mode == Mode.SERVER and not roster.has(from):
		return
	if _sim_rtt > 0.0 or _sim_loss > 0.0:
		_sim_enqueue("in", from, channel, epoch, kind, payload)
		return
	_dispatch(from, epoch, kind, payload)


func _dispatch(from: int, epoch: int, kind: int, payload: Array) -> void:
	if epoch != EPOCH_ANY and epoch != zone_epoch:
		dropped_stale += 1
		return
	if not _handlers.has(kind):
		return
	for handler: Callable in (_handlers[kind] as Array).duplicate():
		if handler.is_valid():
			handler.call(from, payload)


func _sim_enqueue(dir: String, peer: int, channel: int, epoch: int, kind: int, payload: Array) -> void:
	if channel != CH_EVENTS and _sim_rng.randf() < _sim_loss:
		return  # unreliable traffic is simply lost
	var now := float(Time.get_ticks_msec())
	var due := now + _sim_rtt * 0.5 + _sim_rng.randf_range(-0.5, 0.5) * _sim_jitter
	if channel == CH_EVENTS:
		if _sim_rng.randf() < _sim_loss:
			due += _sim_rtt  # a lost reliable packet costs a resend
		var key := dir + str(channel)
		due = maxf(due, float(_sim_last_due.get(key, 0.0)))  # reliable stays in order
		_sim_last_due[key] = due
	_sim_queue.append({"due": due, "dir": dir, "peer": peer, "channel": channel, "epoch": epoch,
		"kind": kind, "payload": payload})


func _flush_sim() -> void:
	var now := float(Time.get_ticks_msec())
	var keep: Array[Dictionary] = []
	var due_now: Array[Dictionary] = []
	for m in _sim_queue:
		if float(m["due"]) <= now:
			due_now.append(m)
		else:
			keep.append(m)
	_sim_queue = keep
	for m in due_now:
		if String(m["dir"]) == "out":
			_send_now(int(m["peer"]), int(m["channel"]), int(m["epoch"]), int(m["kind"]), m["payload"] as Array)
		else:
			_dispatch(int(m["peer"]), int(m["epoch"]), int(m["kind"]), m["payload"] as Array)


# ---------------------------------------------------------------------------
# Server log + tick meter (journalctl on the laptop)
# ---------------------------------------------------------------------------

func log_line(text: String) -> void:
	var t := Time.get_datetime_dict_from_system()
	print("[net %02d:%02d:%02d] %s" % [int(t["hour"]), int(t["minute"]), int(t["second"]), text])


func _physics_process(_delta: float) -> void:
	_tick_start_us = Time.get_ticks_usec()


func _tick_end() -> void:
	if mode != Mode.SERVER or _tick_start_us == 0:
		return
	_tick_samples.append(float(Time.get_ticks_usec() - _tick_start_us) / 1000.0)


## Round-trip time to the server in ms (clients; -1 when unknown).
func ping_ms() -> int:
	if mode != Mode.CLIENT or _enet == null:
		return -1
	var p := _enet.get_peer(1)
	return int(p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)) if p != null else -1


func _log_stats() -> void:
	var sorted := _tick_samples.duplicate()
	_tick_samples.clear()
	sorted.sort()
	var n := sorted.size()
	var p50 := sorted[int(n * 0.5)] if n > 0 else 0.0
	var p95 := sorted[mini(int(n * 0.95), n - 1)] if n > 0 else 0.0
	var worst := sorted[n - 1] if n > 0 else 0.0
	var asleep := 0
	for e in EnemyBase.all_enemies:
		if is_instance_valid(e) and e.sleeping:
			asleep += 1
	var sent := 0.0
	var received := 0.0
	if _enet != null and _enet.host != null:
		sent = float(_enet.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)) / STATS_EVERY / 1024.0
		received = float(_enet.host.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA)) / STATS_EVERY / 1024.0
	var refused := (" | refused %d" % _refusals) if _refusals > 0 else ""
	_refusals = 0
	log_line("tick p50 %.2f / p95 %.2f / max %.2f ms | players %d | enemies %d (%d asleep) | out %.1f KB/s, in %.1f KB/s%s" % [
		p50, p95, worst, roster.size(), EnemyBase.all_enemies.size(), asleep, sent, received, refused])
