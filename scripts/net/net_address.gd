class_name NetAddress
extends Object
## M09: the co-op server address as the player types it. Accepted:
##   host            -> default port        melvin-laptop.tail94658b.ts.net
##   host:port                              100.101.57.51:7777
##   [v6]:port / [v6]                       [2a0d:3341::1]:7777
##   bare IPv6 (two or more colons)         2a0d:3341::1  (default port)
## Never a hard-coded server: the title screen keeps the last used one.


## {"host": String, "port": int, "error": String} ("" = valid).
static func parse(text: String, default_port: int) -> Dictionary:
	var s := text.strip_edges()
	if s == "":
		return _bad("Enter a server address (host or host:port).")
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
	return {"host": host, "port": port, "error": ""}


## Back to text (IPv6 in brackets).
static func format(host: String, port: int) -> String:
	return ("[%s]:%d" if host.contains(":") else "%s:%d") % [host, port]


static func _bad(reason: String) -> Dictionary:
	return {"host": "", "port": 0, "error": reason}
