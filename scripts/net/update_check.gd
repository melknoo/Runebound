class_name UpdateCheck
extends Node
## Player builds (2026-10-13): the title screen asks GitHub once per start
## for the newest release and offers its download page when it is newer
## than this build (docs/dev-notes/release-builds.md). Only in an exported
## build (`OS.has_feature("template")`), never headless or in a test run,
## and only while the setting is on. Silent on every error: no network, no
## answer within TIMEOUT, rate-limited.

signal found(version: String, url: String)

const API := "https://api.github.com/repos/melknoo/Runebound/releases/latest"
## Where a version mismatch sends the player.
const RELEASES_PAGE := "https://github.com/melknoo/Runebound/releases/latest"
const TIMEOUT := 8.0

## Once per process: the title screen comes back after every session.
static var _asked: bool = false
static var _newer: Dictionary = {}  # {version, url} once a newer release is known


static func enabled() -> bool:
	return OS.has_feature("template") and DisplayServer.get_name() != "headless" \
		and not SaveGame.is_test_run() and GameSettings.update_check()


## True when release `a` (0.15.2, v0.15.2) is newer than `b`; a suffix
## (0.15.0-local) is ignored, "dev" counts as the oldest.
static func is_newer(a: String, b: String) -> bool:
	var pa := _numbers(a)
	var pb := _numbers(b)
	for i in 3:
		if pa[i] != pb[i]:
			return pa[i] > pb[i]
	return false


static func _numbers(v: String) -> Array[int]:
	var out: Array[int] = [-1, -1, -1]
	var parts := v.trim_prefix("v").get_slice("-", 0).split(".")
	if parts.size() != 3:
		return out
	for part in parts:
		if not part.is_valid_int():
			return out
	for i in 3:
		out[i] = parts[i].to_int()
	return out


func _ready() -> void:
	if not enabled():
		return
	if _asked:
		if not _newer.is_empty():
			found.emit.call_deferred(str(_newer["version"]), str(_newer["url"]))
		return
	_asked = true
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	add_child(http)
	http.request_completed.connect(_on_answer)
	var err := http.request(API, ["Accept: application/vnd.github+json", "User-Agent: RUNEBOUND/" + Net.game_version()])
	if err != OK:
		http.queue_free()


func _on_answer(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary:
		return
	var tag := str((data as Dictionary).get("tag_name", ""))
	var url := str((data as Dictionary).get("html_url", RELEASES_PAGE))
	if not url.begins_with("https://github.com/"):
		url = RELEASES_PAGE
	if is_newer(tag, Net.game_version()):
		_newer = {"version": tag.trim_prefix("v"), "url": url}
		found.emit(str(_newer["version"]), url)
