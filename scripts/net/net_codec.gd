class_name NetCodec
extends Object
## M09: wire formats that must stay small or exact.
##  * HitInfo <-> Array (hits a client lands on an enemy puppet, hits the
##    server forwards to the hero's owner).
##  * Enemy snapshot entries <-> PackedByteArray, ENEMY_BYTES each, so a full
##    snapshot of 30+ enemies stays under the ~900-byte packet budget
##    (Tailscale MTU 1280; a lost fragment would drop the whole packet).

const ENEMY_BYTES := 27
## Enemies per snapshot packet (32 x 27 B = 864 B plus a few heroes).
const ENEMIES_PER_PACKET := 32

## Status bits in the enemy snapshot.
const ST_BURN := 1
const ST_CHILL := 2
const ST_SHOCK := 4
const ST_CONDUCTOR := 8
const ST_INVULNERABLE := 16

const _HIT_BURN := 1
const _HIT_CHILL := 2
const _HIT_SHOCK := 4
const _HIT_CRIT := 8
const _HIT_CONDUCTOR_ARC := 16
const _HIT_FROM_PLAYER := 32


static func hit_to_array(h: HitInfo) -> Array:
	var flags := 0
	if h.applies_burn:
		flags |= _HIT_BURN
	if h.applies_chill:
		flags |= _HIT_CHILL
	if h.applies_shock:
		flags |= _HIT_SHOCK
	if h.is_crit:
		flags |= _HIT_CRIT
	if h.is_conductor_arc:
		flags |= _HIT_CONDUCTOR_ARC
	if h.from_player:
		flags |= _HIT_FROM_PLAYER
	return [h.damage, int(h.type), int(h.weight), flags, h.knockback, h.source_position, String(h.ability),
		h.burn_mult, h.area_center, h.area_radius]


## The attacker is not on the wire (an instance id means nothing on another
## machine): the receiver fills it in.
static func hit_from_array(a: Array) -> HitInfo:
	var h := HitInfo.new()
	if a.size() < 10:
		return h
	h.damage = maxf(float(a[0]), 0.0)
	h.type = clampi(int(a[1]), 0, HitInfo.DamageType.size() - 1) as HitInfo.DamageType
	h.weight = clampi(int(a[2]), 0, HitInfo.Weight.size() - 1) as HitInfo.Weight
	var flags := int(a[3])
	h.applies_burn = flags & _HIT_BURN != 0
	h.applies_chill = flags & _HIT_CHILL != 0
	h.applies_shock = flags & _HIT_SHOCK != 0
	h.is_crit = flags & _HIT_CRIT != 0
	h.is_conductor_arc = flags & _HIT_CONDUCTOR_ARC != 0
	h.from_player = flags & _HIT_FROM_PLAYER != 0
	h.knockback = float(a[4])
	h.source_position = a[5] as Vector3
	h.ability = StringName(str(a[6]))
	h.burn_mult = float(a[7])
	h.area_center = a[8] as Vector3
	h.area_radius = float(a[9])
	return h


## Snapshot entries {id, pos, yaw, vel, state, seq, hp, bits} -> bytes.
static func encode_enemies(entries: Array[Dictionary]) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(entries.size() * ENEMY_BYTES)
	var o := 0
	for e in entries:
		var pos := e["pos"] as Vector3
		var vel := e["vel"] as Vector3
		out.encode_u16(o, int(e["id"]) & 0xFFFF)
		out.encode_float(o + 2, pos.x)
		out.encode_float(o + 6, pos.y)
		out.encode_float(o + 10, pos.z)
		out.encode_u16(o + 14, int(round(wrapf(float(e["yaw"]), 0.0, TAU) / TAU * 65535.0)) & 0xFFFF)
		out.encode_half(o + 16, vel.x)
		out.encode_half(o + 18, vel.z)
		out.encode_u8(o + 20, int(e["state"]) & 0xFF)
		out.encode_u8(o + 21, int(e["seq"]) & 0xFF)
		out.encode_float(o + 22, float(e["hp"]))
		out.encode_u8(o + 26, int(e["bits"]) & 0xFF)
		o += ENEMY_BYTES
	return out


static func decode_enemies(bytes: PackedByteArray) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var n := bytes.size() / ENEMY_BYTES
	for i in n:
		var o := i * ENEMY_BYTES
		out.append({
			"id": bytes.decode_u16(o),
			"pos": Vector3(bytes.decode_float(o + 2), bytes.decode_float(o + 6), bytes.decode_float(o + 10)),
			"yaw": float(bytes.decode_u16(o + 14)) / 65535.0 * TAU,
			"vel": Vector3(bytes.decode_half(o + 16), 0.0, bytes.decode_half(o + 18)),
			"state": bytes.decode_u8(o + 20),
			"seq": bytes.decode_u8(o + 21),
			"hp": bytes.decode_float(o + 22),
			"bits": bytes.decode_u8(o + 26),
		})
	return out
