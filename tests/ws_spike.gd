extends SceneTree
## M09b Phase 0: how does a WebSocket through Tailscale Funnel behave? Engine
## classes only (no autoloads, no project scripts), so the server side runs
## from a scratch folder on the laptop without touching the server's clone:
##   server:  godot --headless --path <dir> --script res://ws_spike.gd -- --serve=7780 [--for=1200]
##   client:  godot --headless --path . --script res://tests/ws_spike.gd -- --url=wss://<laptop>.ts.net/
##              [--via=<ingress ip>] [--seconds=300] [--download=60] [--out=<json>]
## (tools\run_godot.cmd wsspike <url> finds the Funnel address and passes --via)
## Echo: 30 messages/s of 900 bytes (snapshot-sized) bounced by the server:
## round-trip times, stalls (no answer for > 250 ms), losses. Download: the
## server pushes 200 KB/s (five players' worth) and the client counts what
## arrives each second. `--via` connects to that IP but keeps the name for TLS
## (SNI): a PC that is in the tailnet itself would otherwise take the direct
## tailnet path instead of the Funnel relay.

const ECHO := 1
const DOWNLOAD := 2
const CHUNK := 3
const HEADER := 13  # type u8, seq u32, usec u64
const ECHO_HZ := 30.0
const ECHO_SIZE := 900
const CHUNK_SIZE := 10240
const DOWNLOAD_RATE := 200 * 1024
const STALL_MS := 250.0

var _args: Dictionary = {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			_args[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	Engine.max_fps = 500  # fine-grained polling: measure the network, not our frame
	if _args.has("serve"):
		_serve(int(_args["serve"]), float(_args.get("for", "1200")))
	elif _args.has("url"):
		_client(str(_args["url"]))
	else:
		printerr("usage: -- --serve=PORT [--for=SECONDS] | --url=wss://host/ [--via=IP]")
		quit(2)


# ---------------------------------------------------------------------------
# Server: echo, and a download stream on request
# ---------------------------------------------------------------------------

func _serve(port: int, lifetime: float) -> void:
	var tcp := TCPServer.new()
	var err := tcp.listen(port, "127.0.0.1")
	if err != OK:
		printerr("[spike] cannot listen on 127.0.0.1:%d (%s)" % [port, error_string(err)])
		quit(1)
		return
	print("[spike] WebSocket echo on 127.0.0.1:%d for %.0f s" % [port, lifetime])
	var peers: Array[Dictionary] = []
	var end := Time.get_ticks_msec() + int(lifetime * 1000.0)
	var last := Time.get_ticks_usec()
	while Time.get_ticks_msec() < end:
		await process_frame
		var now := Time.get_ticks_usec()
		var dt := float(now - last) / 1e6
		last = now
		while tcp.is_connection_available():
			var conn := tcp.take_connection()
			conn.set_no_delay(true)
			var ws := WebSocketPeer.new()
			ws.outbound_buffer_size = 4 << 20
			ws.inbound_buffer_size = 1 << 20
			ws.accept_stream(conn)
			peers.append({"ws": ws, "since": Time.get_ticks_msec(), "dl_left": 0.0, "dl_acc": 0.0,
				"dl_rate": 0.0, "dl_seq": 0, "dl_fail": 0})
			print("[spike] connection from %s" % conn.get_connected_host())
		for p in peers.duplicate():
			var ws: WebSocketPeer = p["ws"]
			ws.poll()
			var state := ws.get_ready_state()
			if state == WebSocketPeer.STATE_CLOSED:
				print("[spike] closed after %.1f s (code %d %s), %d download sends failed" % [
					float(Time.get_ticks_msec() - int(p["since"])) / 1000.0, ws.get_close_code(),
					ws.get_close_reason(), int(p["dl_fail"])])
				peers.erase(p)
				continue
			if state != WebSocketPeer.STATE_OPEN:
				continue
			while ws.get_available_packet_count() > 0:
				var pkt := ws.get_packet()
				if pkt.is_empty():
					continue
				if pkt[0] == ECHO:
					ws.send(pkt)
				elif pkt[0] == DOWNLOAD and pkt.size() >= 9:
					p["dl_left"] = float(pkt.decode_u32(1))
					p["dl_rate"] = float(pkt.decode_u32(5))
					print("[spike] download: %.0f s at %.0f KB/s" % [float(p["dl_left"]), float(p["dl_rate"]) / 1024.0])
			if float(p["dl_left"]) > 0.0:
				p["dl_left"] = float(p["dl_left"]) - dt
				p["dl_acc"] = float(p["dl_acc"]) + float(p["dl_rate"]) * dt
				while float(p["dl_acc"]) >= CHUNK_SIZE:
					p["dl_acc"] = float(p["dl_acc"]) - CHUNK_SIZE
					var chunk := PackedByteArray()
					chunk.resize(CHUNK_SIZE)
					chunk.fill(0)
					chunk[0] = CHUNK
					chunk.encode_u32(1, int(p["dl_seq"]))
					chunk.encode_u64(5, Time.get_ticks_usec())
					p["dl_seq"] = int(p["dl_seq"]) + 1
					if ws.send(chunk) != OK:
						p["dl_fail"] = int(p["dl_fail"]) + 1
	print("[spike] done")
	quit(0)


# ---------------------------------------------------------------------------
# Client: echo phase, then download phase
# ---------------------------------------------------------------------------

func _client(url: String) -> void:
	var seconds := float(_args.get("seconds", "300"))
	var download := float(_args.get("download", "60"))
	var host := url.get_slice("://", 1).get_slice("/", 0)
	var target := url
	var tls := TLSOptions.client()
	var via := str(_args.get("via", ""))
	if via != "":
		target = url.replace(host, ("[%s]" % via) if via.contains(":") else via)
		tls = TLSOptions.client(null, host.get_slice(":", 0))  # the name stays the TLS name (SNI)
	var ws := WebSocketPeer.new()
	ws.inbound_buffer_size = 8 << 20
	ws.outbound_buffer_size = 1 << 20
	var t0 := Time.get_ticks_msec()
	var err := ws.connect_to_url(target, tls)
	if err != OK:
		printerr("[spike] cannot connect to %s (%s)" % [target, error_string(err)])
		quit(1)
		return
	while ws.get_ready_state() == WebSocketPeer.STATE_CONNECTING and Time.get_ticks_msec() - t0 < 15000:
		ws.poll()
		await process_frame
	if ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		printerr("[spike] no WebSocket to %s (state %d, close %d %s)" % [target, ws.get_ready_state(),
			ws.get_close_code(), ws.get_close_reason()])
		quit(1)
		return
	var result := {"url": url, "via": via, "connect_ms": Time.get_ticks_msec() - t0}
	print("[spike] connected to %s%s in %d ms" % [url, (" via " + via) if via != "" else "", int(result["connect_ms"])])

	# Echo
	var rtts: Array[float] = []
	var arrivals: Array[int] = []
	var sent := 0
	var pad := PackedByteArray()
	pad.resize(ECHO_SIZE - HEADER)
	pad.fill(0)
	var step := int(1e6 / ECHO_HZ)
	var next_send := Time.get_ticks_usec()
	var echo_start := Time.get_ticks_msec()
	var echo_end := echo_start + int(seconds * 1000.0)
	var lost_at := -1
	while Time.get_ticks_msec() < echo_end + 3000:
		ws.poll()
		if ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
			lost_at = Time.get_ticks_msec() - echo_start
			break
		var now := Time.get_ticks_usec()
		if Time.get_ticks_msec() < echo_end and now >= next_send:
			next_send += step
			var pkt := PackedByteArray()
			pkt.resize(HEADER)
			pkt[0] = ECHO
			pkt.encode_u32(1, sent)
			pkt.encode_u64(5, now)
			pkt.append_array(pad)
			ws.send(pkt)
			sent += 1
		while ws.get_available_packet_count() > 0:
			var r := ws.get_packet()
			if r.size() >= HEADER and r[0] == ECHO:
				rtts.append(float(Time.get_ticks_usec() - r.decode_u64(5)) / 1000.0)
				arrivals.append(Time.get_ticks_msec())
		await process_frame
	var stalls := 0
	var worst_gap := 0.0
	for i in range(1, arrivals.size()):
		var gap := float(arrivals[i] - arrivals[i - 1])
		worst_gap = maxf(worst_gap, gap)
		if gap > STALL_MS:
			stalls += 1
	var sorted := rtts.duplicate()
	sorted.sort()
	result["echo"] = {"seconds": seconds, "sent": sent, "back": rtts.size(), "p50": _pct(sorted, 0.5),
		"p95": _pct(sorted, 0.95), "p99": _pct(sorted, 0.99), "max": _pct(sorted, 1.0),
		"over_250ms": sorted.filter(func(v: float) -> bool: return v > STALL_MS).size(),
		"stalls": stalls, "worst_gap_ms": worst_gap, "lost_connection_at_ms": lost_at}
	print("[spike] echo: %d sent, %d back | rtt p50 %.0f / p95 %.0f / p99 %.0f / max %.0f ms | %d answers over 250 ms | %d stalls, worst gap %.0f ms%s" % [
		sent, rtts.size(), _pct(sorted, 0.5), _pct(sorted, 0.95), _pct(sorted, 0.99), _pct(sorted, 1.0),
		int((result["echo"] as Dictionary)["over_250ms"]), stalls, worst_gap,
		(" | CONNECTION LOST after %.0f s" % (lost_at / 1000.0)) if lost_at >= 0 else ""])

	# Download
	if lost_at < 0 and download > 0.0:
		var req := PackedByteArray()
		req.resize(9)
		req[0] = DOWNLOAD
		req.encode_u32(1, int(download))
		req.encode_u32(5, DOWNLOAD_RATE)
		ws.send(req)
		var per_second: Array[int] = []
		per_second.resize(int(download) + 4)
		per_second.fill(0)
		var dl_start := Time.get_ticks_msec()
		var last_chunk := -1
		var chunk_gap := 0.0
		var chunks := 0
		while Time.get_ticks_msec() - dl_start < int((download + 3.0) * 1000.0):
			ws.poll()
			if ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
				lost_at = Time.get_ticks_msec() - echo_start
				break
			while ws.get_available_packet_count() > 0:
				var r := ws.get_packet()
				if r.size() >= HEADER and r[0] == CHUNK:
					var now_ms := Time.get_ticks_msec()
					var slot := clampi(int(float(now_ms - dl_start) / 1000.0), 0, per_second.size() - 1)
					per_second[slot] += r.size()
					if last_chunk >= 0:
						chunk_gap = maxf(chunk_gap, float(now_ms - last_chunk))
					last_chunk = now_ms
					chunks += 1
			await process_frame
		var steady := per_second.slice(1, int(download))  # skip the ramp-up second
		var kbs: Array[float] = []
		for b in steady:
			kbs.append(float(b) / 1024.0)
		var kbs_sorted := kbs.duplicate()
		kbs_sorted.sort()
		var avg := 0.0
		for v in kbs:
			avg += v
		avg /= maxf(kbs.size(), 1.0)
		result["download"] = {"seconds": download, "target_kbs": DOWNLOAD_RATE / 1024.0, "avg_kbs": avg,
			"min_kbs": _pct(kbs_sorted, 0.0), "chunks": chunks, "worst_gap_ms": chunk_gap}
		print("[spike] download: target %.0f KB/s | avg %.0f / min %.0f KB/s over %d s | %d chunks, worst gap %.0f ms%s" % [
			DOWNLOAD_RATE / 1024.0, avg, _pct(kbs_sorted, 0.0), kbs.size(), chunks, chunk_gap,
			(" | CONNECTION LOST") if lost_at >= 0 else ""])
	var out := str(_args.get("out", ""))
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(result, "  "))
			f.close()
	ws.close()
	for i in 20:
		ws.poll()
		await process_frame
	quit(0 if lost_at < 0 else 1)


static func _pct(sorted: Array, q: float) -> float:
	if sorted.is_empty():
		return 0.0
	return float(sorted[clampi(int(float(sorted.size() - 1) * q), 0, sorted.size() - 1)])
