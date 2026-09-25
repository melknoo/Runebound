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
## server -> client, unreliable 20 Hz: [server_msec, heroes, enemy_bytes] where
## heroes is [[peer, pos, yaw, vel, state, hp, hp_max, teleports], ...] (all
## but the receiver) and enemy_bytes NetCodec.encode_enemies (several packets
## when many enemies are awake; heroes only in the first)
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
## server -> client: [id, type_id, pos, yaw, level, elite_kind (-1 none), hp, hp_max, state, seq]
const ENEMY_SPAWN := 11
## server -> client: [id, state, seq, pos, yaw] - the enemy entered a state
## (its telegraph and clip start now, from the server's pose)
const ENEMY_STATE := 12
## server -> client: [id, damage, crit, type, attacker_peer] - a hit landed
const ENEMY_HIT := 13
## server -> client: [id, amount, type, owner_peer] - burn damage ticked
const ENEMY_DOT := 14
## server -> client: [id, killer_peer]
const ENEMY_DEATH := 15
## server -> client: [id] - removed without dying
const ENEMY_DESPAWN := 16
## server -> client: [bolt_id, origin, dir, speed] - an enemy bolt flies
const BOLT := 17
## server -> client: [bolt_id, pos] - that bolt popped
const BOLT_POP := 18
## client -> server: [enemy_id, hit (NetCodec.hit_to_array)] - our hero hit it
const HIT := 19
## client -> server: [enemy_id, kind, duration, amount] - a status without a hit
const STATUS := 20
## server -> the hero's owner: [hit] - an enemy attack struck its proxy; the
## owner takes it unless its own hero dodged (i-frames) or left the area
const HURT := 21
## server -> client: [id, fx, pos, yaw] - an enemy's named action (play_fx)
const ENEMY_FX := 22
## server -> client: [kind, pos] - a ground hazard (fire_patch, shadow_rune) to copy
const HAZARD := 23
## server -> client: [id, hp_max] - health rescaled (a hero joined or left)
const ENEMY_SCALE := 24
## server -> one client: [xp, gold, piles, items (ItemData.to_dict), pos, note, float_xp]
## - that client's own reward (personal loot: its drops exist only there)
const GRANT := 25
## client -> server: [chest key] - our hero opens this chest
const CHEST_OPEN := 26
## server -> client: [chest key] - that chest is open (the lid; purses come as GRANTs)
const CHEST_OPENED := 27
## server -> client: [flag] - a world flag was set (bosses): zones react
const FLAG := 28
## client -> server: [scene, arrival poi, label] - our hero used a portal / a
## shrine into another zone: the party travels
const TRAVEL_REQUEST := 29
## server -> client: [scene, label, seconds, by_peer] - party travel counts down
const TRAVEL_COUNTDOWN := 30
## client -> server: [] - cancel the countdown
const TRAVEL_CANCEL := 31
## server -> client: [by_peer]
const TRAVEL_CANCELLED := 32
## server -> client, any epoch: [scene, epoch, arrival] - load that zone now
const TRAVEL_GO := 33
