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
