class_name NetAddress
extends Object
## M09: the co-op server address as the player types it. Accepted:
##   name            -> WebSocket (M09b)   melvin-laptop.tail94658b.ts.net = wss://<name>/
##   wss:// / https:// / ws://              wss://melvin-laptop.tail94658b.ts.net/
##   host:port       -> ENet (UDP)         100.101.57.51:7777
##   bare IP         -> ENet, default port 127.0.0.1
##   [v6]:port / [v6]                       [2a0d:3341::1]:7777
##   bare IPv6 (two or more colons)         2a0d:3341::1  (default port)
## A bare name is a Tailscale Funnel address (HTTPS on 443, the way friends
## reach the laptop); LAN and test servers give a port or an IP.
## Never a hard-coded server: the title screen keeps the last used one.


## {"host": String, "port": int, "url": String, "error": String} ("" = valid);
## "url" is set when the server is reached over WebSocket.
static func parse(text: String, default_port: int) -> Dictionary:
	var s := text.strip_edges()
	if s == "":
		return _bad("Enter a server address (host or host:port).")
	var lower := s.to_lower()
	for scheme: String in ["wss://", "https://", "ws://"]:
		if lower.begins_with(scheme):
			var rest := s.substr(scheme.length())
			var host_port := rest.get_slice("/", 0)
			if host_port == "" or host_port.contains(" "):
				return _bad("That is not a server address.")
			var secure: bool = scheme != "ws://"
			var url := ("wss://" if secure else "ws://") + rest + ("" if rest.contains("/") else "/")
			return {"host": host_port, "port": 443 if secure else 80, "url": url, "error": ""}
	var host := s
	var port_text := ""
	if s.begins_with("["):
		var close := s.find("]")
		if close < 0:
			return _bad("Missing ] in the IPv6 address.")
		host = s.substr(1, close - 1)
		var rest := s.substr(close + 1)
		if rest.begins_with(":"):
			port_text = rest.substr(1)
		elif rest != "":
			return _bad("Unexpected text after the IPv6 address.")
	elif s.count(":") == 1:
		host = s.get_slice(":", 0)
		port_text = s.get_slice(":", 1)
	var port := default_port
	if port_text != "":
		if not port_text.is_valid_int():
			return _bad("The port must be a number (like 7777).")
		port = port_text.to_int()
	if port < 1 or port > 65535:
		return _bad("The port must be between 1 and 65535.")
	if host == "" or host.contains(" "):
		return _bad("That is not a server address.")
	if port_text == "" and not host.is_valid_ip_address():
		return {"host": host, "port": 443, "url": "wss://%s/" % host, "error": ""}  # a Funnel name
	return {"host": host, "port": port, "url": "", "error": ""}


## Back to text (IPv6 in brackets).
static func format(host: String, port: int) -> String:
	return ("[%s]:%d" if host.contains(":") else "%s:%d") % [host, port]


static func _bad(reason: String) -> Dictionary:
	return {"host": "", "port": 0, "url": "", "error": reason}
