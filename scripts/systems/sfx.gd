extends Node
## Autoload "Sfx": pooled positional sound playback with automatic variation.
## Scans res://assets/sfx at startup and groups files by prefix: "swing_01.wav",
## "swing_02.wav" both register under "swing" and play() picks a random variant.
## M06 audio track: builds the mix buses at startup (Master <- Music, SFX,
## Telegraph, Ambience, UI; telegraph sounds duck the music through a
## sidechain compressor) and hosts the MusicDirector.

const SFX_DIR := "res://assets/sfx"
const POOL_SIZE := 24
## Bus -> start volume (dB). Tuned at the listening checkpoint.
const BUSES := {"Music": -7.0, "SFX": 0.0, "Telegraph": 1.0, "Ambience": -3.0, "UI": -2.0}
## Enemy tells: always heard over the music (ART_BIBLE mix priority).
const TELEGRAPH_KEYS: Array[String] = ["telegraph", "caster_charge", "charge_horn", "boss_roar", "vessel_roar"]

var music: MusicDirector

var _library: Dictionary = {}
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _pool_ui: Array[AudioStreamPlayer] = []
var _next_3d: int = 0
var _next_ui: int = 0


func _ready() -> void:
	_setup_buses()
	_scan_library()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 60.0
		p.unit_size = 8.0
		p.bus = &"SFX"
		add_child(p)
		_pool_3d.append(p)
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.bus = &"UI"
		add_child(p)
		_pool_ui.append(p)
	music = MusicDirector.new()
	music.name = "MusicDirector"
	add_child(music)


static func _setup_buses() -> void:
	for bus_name: String in BUSES:
		if AudioServer.get_bus_index(bus_name) != -1:
			continue
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, bus_name)
		AudioServer.set_bus_send(i, &"Master")
		AudioServer.set_bus_volume_db(i, BUSES[bus_name])
	var music_bus := AudioServer.get_bus_index("Music")
	if AudioServer.get_bus_effect_count(music_bus) == 0:
		var duck := AudioEffectCompressor.new()
		duck.sidechain = &"Telegraph"
		duck.threshold = -30.0
		duck.ratio = 6.0
		duck.attack_us = 15000.0
		duck.release_ms = 450.0
		AudioServer.add_bus_effect(music_bus, duck)


static func bus_for(key: String) -> StringName:
	if TELEGRAPH_KEYS.has(key):
		return &"Telegraph"
	if key.contains("_loop"):
		return &"Ambience"
	return &"SFX"


func _scan_library() -> void:
	var dir := DirAccess.open(SFX_DIR)
	if dir == null:
		push_warning("Sfx: no sfx directory at %s" % SFX_DIR)
		return
	for f in dir.get_files():
		var fname := f
		if fname.ends_with(".import"):
			fname = fname.trim_suffix(".import")
		if not (fname.ends_with(".wav") or fname.ends_with(".ogg")):
			continue
		var base := fname.get_basename()
		var key := base
		var parts := base.rsplit("_", true, 1)
		if parts.size() == 2 and parts[1].is_valid_int():
			key = parts[0]
		var stream: AudioStream = load(SFX_DIR + "/" + fname)
		if stream == null:
			continue
		if not _library.has(key):
			_library[key] = []
		(_library[key] as Array).append(stream)


func has_sound(key: String) -> bool:
	return _library.has(key)


func play(key: String, pos: Vector3, volume_db: float = 0.0, pitch_variation: float = 0.08, pitch_base: float = 1.0) -> void:
	var variants: Array = _library.get(key, [])
	if variants.is_empty():
		return
	var player := _pool_3d[_next_3d]
	_next_3d = (_next_3d + 1) % POOL_SIZE
	player.stop()
	player.stream = variants.pick_random()
	player.bus = bus_for(key)
	player.global_position = pos
	player.volume_db = volume_db
	player.pitch_scale = pitch_base * randf_range(1.0 - pitch_variation, 1.0 + pitch_variation)
	player.play()


func play_ui(key: String, volume_db: float = 0.0, pitch_variation: float = 0.05) -> void:
	var variants: Array = _library.get(key, [])
	if variants.is_empty():
		return
	var player := _pool_ui[_next_ui]
	_next_ui = (_next_ui + 1) % _pool_ui.size()
	player.stop()
	player.stream = variants.pick_random()
	player.volume_db = volume_db
	player.pitch_scale = randf_range(1.0 - pitch_variation, 1.0 + pitch_variation)
	player.play()
