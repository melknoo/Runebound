extends Node
## M09: entry scene of the dedicated co-op server (tools/server/server.env ->
## RUNEBOUND_SCENE). Headless and without a hero: opens the ENet port
## (RUNEBOUND_PORT, or `-- --port=`), loads the server's own world save and
## enters the zone that save is in; from then on it is the zone running in
## Net's SERVER mode.
##   godot --headless --path . res://scenes/dedicated_server.tscn -- [--port=7777] [--max-players=5]
##     [--save=user://x.json] [--zone=res://scenes/<zone>.tscn]


func _ready() -> void:
	Engine.max_fps = 60  # a headless main loop is uncapped: it would spin a core at 100 %
	var port := Net.DEFAULT_PORT
	var env_port := OS.get_environment("RUNEBOUND_PORT")
	if env_port.is_valid_int():
		port = env_port.to_int()
	var players := Net.MAX_PLAYERS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = arg.trim_prefix("--port=").to_int()
		elif arg.begins_with("--max-players="):
			players = clampi(arg.trim_prefix("--max-players=").to_int(), 1, Net.MAX_PLAYERS)
	SaveGame.use_server_save()
	var err := Net.host(port, players)
	if err != OK:
		printerr("[net] cannot listen on port %d: %s" % [port, error_string(err)])
		get_tree().quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--net-test="):  # tests/net_test.gd: the server's side of a scenario
			var probe: Node = (load("res://tests/net_server_probe.gd") as GDScript).new()
			get_tree().root.add_child.call_deferred(probe)
	var zone := SaveGame.current_zone
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--zone="):  # tests: start in this zone
			zone = arg.trim_prefix("--zone=")
	if not ResourceLoader.exists(zone):
		zone = "res://scenes/hub.tscn"
	Net.log_line("world save %s" % ProjectSettings.globalize_path(SaveGame.save_path))
	get_tree().change_scene_to_file.call_deferred(zone)
