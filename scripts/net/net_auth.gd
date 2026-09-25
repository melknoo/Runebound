class_name NetAuth
extends Object
## M09b: invite codes and the join handshake. Friends reach the laptop server
## without Tailscale, so the game itself decides who gets in: every friend has
## a personal invite code (tools/server/invites.sh), the server reads them from
## an invite list outside the repo (RUNEBOUND_INVITES / `--invites=`).
##
## Handshake (SceneMultiplayer auth, before any RPC):
##   server -> client  var_to_bytes({"challenge": 16 random bytes, "reason": update hint})
##   client -> server  "RBJ1" | flags | HMAC-SHA256(key, "RBJ1" + nonce + hello) | hello bytes
##   server            size and magic, then the MAC against every invite; only a
##                     verified answer is decoded (bytes_to_var) and checked as
##                     before (protocol, Godot, full) -> welcome
## The code never travels, a recorded answer is useless against the next
## challenge, and nothing a stranger sends reaches the Variant decoder.
## Protocol-7 clients take the challenge (no "ok") as a refusal and show its
## "reason": update your game.

const MAGIC := "RBJ1"
const CODE_ALPHABET := "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"  # RFC 4648 base32
const CODE_LENGTH := 16  # 80 bits: no rate limit needed against guessing
const NONCE_SIZE := 16
const MAC_SIZE := 32
const HEADER_SIZE := 4 + 1 + MAC_SIZE  # magic, flags, MAC
const MAX_JOIN_SIZE := 2048
const FLAG_HAS_CODE := 1
const KEY_SALT := "runebound-invite-v1:"
const NAME_MAX := 24

## What the server makes of a join answer.
enum Verdict {
	OK,          # a listed code: "invite" names the friend
	OPEN,        # an open server (no invite list): anyone on this machine
	MALFORMED,   # too short or too long
	OLD_CLIENT,  # no magic: an older game (or noise)
	NO_CODE,     # the player entered no code
	BAD_CODE,    # no invite matches (typo, revoked, or a stranger)
}

static var _crypto: Crypto = null


## "k7qm-2xrp vb4t 5nhl" -> "K7QM2XRPVB4T5NHL": case, dashes and spaces do not
## matter, and the look-alikes 0/1/8 (never in a code) read as O/I/B.
static func normalize_code(text: String) -> String:
	var out := ""
	for ch in text.to_upper():
		var c := ch
		match ch:
			"0":
				c = "O"
			"1":
				c = "I"
			"8":
				c = "B"
		if CODE_ALPHABET.contains(c):
			out += c
	return out


static func is_valid_code(text: String) -> bool:
	return normalize_code(text).length() == CODE_LENGTH


## "K7QM2XRPVB4T5NHL" -> "K7QM-2XRP-VB4T-5NHL".
static func pretty_code(text: String) -> String:
	var n := normalize_code(text)
	var parts := PackedStringArray()
	for i in range(0, n.length(), 4):
		parts.append(n.substr(i, 4))
	return "-".join(parts)


## A fresh random code (tests; the host uses tools/server/invites.sh).
static func generate_code() -> String:
	var s := ""
	for b in _get_crypto().generate_random_bytes(CODE_LENGTH):
		s += CODE_ALPHABET[b % CODE_ALPHABET.length()]  # 256 is a multiple of 32: uniform
	return pretty_code(s)


## The HMAC key both sides derive from a code.
static func code_key(text: String) -> PackedByteArray:
	return (KEY_SALT + normalize_code(text)).sha256_buffer()


static func new_nonce() -> PackedByteArray:
	return _get_crypto().generate_random_bytes(NONCE_SIZE)


static func mac(key: PackedByteArray, nonce: PackedByteArray, hello_bytes: PackedByteArray) -> PackedByteArray:
	var msg := MAGIC.to_ascii_buffer()
	msg.append_array(nonce)
	msg.append_array(hello_bytes)
	return _get_crypto().hmac_digest(HashingContext.HASH_SHA256, key, msg)


## Client: the answer to the server's challenge (no code = a zero MAC, fine
## for an open server).
static func build_join(code: String, nonce: PackedByteArray, hello: Dictionary) -> PackedByteArray:
	var hello_bytes := var_to_bytes(hello)
	var has_code := is_valid_code(code)
	var out := MAGIC.to_ascii_buffer()
	out.append(FLAG_HAS_CODE if has_code else 0)
	if has_code:
		out.append_array(mac(code_key(code), nonce, hello_bytes))
	else:
		var zeros := PackedByteArray()
		zeros.resize(MAC_SIZE)
		zeros.fill(0)
		out.append_array(zeros)
	out.append_array(hello_bytes)
	return out


## Server: judges a join answer without decoding anything in it. Returns
## {"verdict": Verdict, "invite": name, "hello": PackedByteArray}; "hello" only
## for OK and OPEN (the caller decodes it then).
static func verify_join(data: PackedByteArray, nonce: PackedByteArray, keys: Dictionary, open: bool) -> Dictionary:
	if data.size() < HEADER_SIZE or data.size() > MAX_JOIN_SIZE:
		return {"verdict": Verdict.MALFORMED}
	if data.slice(0, 4) != MAGIC.to_ascii_buffer():
		return {"verdict": Verdict.OLD_CLIENT}
	var hello_bytes := data.slice(HEADER_SIZE)
	if open:
		return {"verdict": Verdict.OPEN, "invite": "", "hello": hello_bytes}
	if (data[4] & FLAG_HAS_CODE) == 0:
		return {"verdict": Verdict.NO_CODE}
	var received := data.slice(5, HEADER_SIZE)
	for invite: String in keys:
		if _get_crypto().constant_time_compare(mac(keys[invite] as PackedByteArray, nonce, hello_bytes), received):
			return {"verdict": Verdict.OK, "invite": invite, "hello": hello_bytes}
	return {"verdict": Verdict.BAD_CODE}


## The invite list: one friend per line, `name  code  [added]` (tabs or
## spaces), `#` comments. Returns {"keys": {name: key}, "bad": skipped lines}.
static func parse_invites(text: String) -> Dictionary:
	var keys: Dictionary = {}
	var bad := 0
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var fields := line.replace("\t", " ").split(" ", false)
		if fields.size() < 2 or not is_valid_name(fields[0]) or not is_valid_code(fields[1]):
			bad += 1
			continue
		keys[fields[0]] = code_key(fields[1])
	return {"keys": keys, "bad": bad}


## Invite names: letters, digits, `_ . -`, at most NAME_MAX.
static func is_valid_name(text: String) -> bool:
	if text.is_empty() or text.length() > NAME_MAX:
		return false
	for ch in text:
		var letter := (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z")
		if not letter and not ch in "0123456789_.-":
			return false
	return true


static func _get_crypto() -> Crypto:
	if _crypto == null:
		_crypto = Crypto.new()
	return _crypto
