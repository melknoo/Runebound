class_name NetMsg
extends Object
## M09: message kinds carried by Net (payloads are plain Arrays; the handler
## registered with Net.on(kind, ...) knows the layout). Bump Net.PROTOCOL
## whenever a kind or a payload layout changes.

## server -> clients: [roster Dictionary peer_id -> {name, class_id, level}]
const ROSTER := 1
## client -> server: [scene path] - this client finished building the zone
const ZONE_READY := 2
## server -> one client: [text] - a line for the HUD toast
const NOTICE := 3
## client -> server -> the same client, unreliable: [seq, sent_usec, padding]
## (connection test: round-trip time and loss, tests/net_client.gd "echo")
const ECHO := 4
## client -> server, unreliable 30 Hz: [seq, pos, yaw, vel, state, hp, hp_max, teleports]
const HERO_STATE := 5
## server -> client, unreliable 20 Hz: [server_msec, heroes] where heroes is
## [[peer, pos, yaw, vel, state, hp, hp_max, teleports], ...] (all but the receiver)
const SNAPSHOT := 6
## server -> client: [peer, name, class_id, level, pos, yaw] - a hero to show
const HERO_SPAWN := 7
## server -> client: [peer] - that hero is gone
const HERO_DESPAWN := 8
## client -> server: [action]; server -> other clients: [peer, action]
## (the owner's action_started, so puppets play the clip)
const HERO_ACTION := 9
## client -> server: [character dict] (SaveGame.character_dict), on join and
## after changes: the proxy's stats, talents and level
const CHARACTER := 10
