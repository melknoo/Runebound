extends Node
## Autoload "Sfx": pooled positional sound playback with automatic variation.
## Scans res://assets/sfx at startup and groups files by prefix: "swing_01.wav",
## "swing_02.wav" both register under "swing" and play() picks a random variant.

const SFX_DIR := "res://assets/sfx"
const POOL_SIZE := 24

var _library: Dictionary = {}
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _pool_ui: Array[AudioStreamPlayer] = []
var _next_3d: int = 0
var _next_ui: int = 0


func _ready() -> void:
	_scan_library()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 60.0
		p.unit_size = 8.0
		p.bus = &"Master"
		add_child(p)
		_pool_3d.append(p)
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool_ui.append(p)


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
