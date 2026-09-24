class_name MusicDirector
extends Node
## Zone music (M06 audio track): an exploration and a combat layer in one key,
## tempo and length (tools/musicgen), played in sync by AudioStreamSynchronized.
## The combat layer swells in while an enemy near the player is engaged and
## ebbs away after the fight; travel fades everything out.
## Lives under the Sfx autoload (created there), so project.godot needs no new
## autoload entry. Zones without music tracks simply stop it.

const MUSIC_DIR := "res://assets/music/"
const ENGAGE_RANGE := 22.0
const SWELL_IN := 1.2    # seconds from silence to the full combat layer
const EBB_OUT := 4.0     # ...and back after the last engaged enemy
const SILENT_DB := -60.0

static var instance: MusicDirector

var combat_mix: float = 0.0  # 0 = exploration only, 1 = full combat layer
var _player: AudioStreamPlayer
var _sync: AudioStreamSynchronized
var _zone_key: String = ""
var _fade: Tween


func _ready() -> void:
	instance = self
	_player = AudioStreamPlayer.new()
	_player.name = "Music"
	_player.bus = &"Music"
	add_child(_player)


func _exit_tree() -> void:
	if instance == self:
		instance = null


func zone_key() -> String:
	return _zone_key


func is_playing() -> bool:
	return _player.playing


## Start the zone's music (`<key>_explore` + optional `<key>_combat`).
func play_zone(key: String) -> void:
	if key == _zone_key and _player.playing:
		return
	var explore := _track(key + "_explore")
	if explore == null:
		stop()
		return
	_zone_key = key
	_sync = AudioStreamSynchronized.new()
	var combat := _track(key + "_combat")
	_sync.stream_count = 2 if combat != null else 1
	_sync.set_sync_stream(0, explore)
	if combat != null:
		_sync.set_sync_stream(1, combat)
		_sync.set_sync_stream_volume(1, SILENT_DB)
	combat_mix = 0.0
	_player.stream = _sync
	_player.volume_db = SILENT_DB
	_player.play()
	_fade_to(0.0, 2.5)


func stop(fade: float = 0.6) -> void:
	_zone_key = ""
	if _player.playing:
		_fade_to(SILENT_DB, fade, true)


var _stinger: AudioStreamPlayer


## One-shot musical cue over the zone music (tools/musicgen: stinger_<key>),
## e.g. "victory" when a boss falls; the zone layers duck under it.
func stinger(key: String) -> void:
	var stream := _track("stinger_" + key)
	if stream == null:
		return
	if _stinger == null:
		_stinger = AudioStreamPlayer.new()
		_stinger.name = "Stinger"
		_stinger.bus = &"Music"
		add_child(_stinger)
	_stinger.stream = stream
	_stinger.volume_db = -2.0
	_stinger.play()
	if _player.playing:
		_fade_to(-12.0, 0.25)
		get_tree().create_timer(3.4).timeout.connect(func() -> void:
			if _player.playing and _zone_key != "":
				_fade_to(0.0, 2.0)
		)


func _track(name: String) -> AudioStream:
	var path := MUSIC_DIR + name + ".wav"
	return load(path) if ResourceLoader.exists(path) else null


func _fade_to(db: float, seconds: float, stop_after: bool = false) -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(_player, "volume_db", db, seconds)
	if stop_after:
		_fade.tween_callback(_player.stop)


func _process(delta: float) -> void:
	if _sync == null or _sync.stream_count < 2 or not _player.playing:
		return
	var target := 1.0 if _engaged() else 0.0
	combat_mix = move_toward(combat_mix, target, delta / (SWELL_IN if target > combat_mix else EBB_OUT))
	_sync.set_sync_stream_volume(1, linear_to_db(maxf(combat_mix, 0.001)))


## True while any live enemy near the player has left IDLE (chasing, winding
## up, attacking, staggered...): the fight is on.
func _engaged() -> bool:
	var scene := get_tree().current_scene
	var player: Node3D = scene.get(&"player") if scene != null else null
	if player == null or not is_instance_valid(player):
		return false
	for enemy in EnemyBase.all_enemies:
		if not is_instance_valid(enemy) or enemy.ai_state == EnemyBase.AIState.IDLE \
				or enemy.ai_state == EnemyBase.AIState.DEAD or not enemy.is_inside_tree():
			continue
		if enemy.global_position.distance_to(player.global_position) <= ENGAGE_RANGE:
			return true
	return false
