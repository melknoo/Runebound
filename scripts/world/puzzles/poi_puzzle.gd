class_name PoiPuzzle
extends Node3D
## M12: the base of puzzles and secrets that change the shared world - the
## braziers, the boulder, the monoliths, the tome cave's door (and the M13
## dungeon puzzles after them). Hybrid authority like the chests: a hero acts
## (`request`), the authority (offline: this machine; online: the server)
## changes `state` (`act`), persists it in the world (SaveGame.pois) and
## tells everyone (POI_STATE); every machine shows it (`apply_state`).
## Subclasses override `act` and `_present`, and `_on_solved` for what
## opens. Late joiners get the state when they arrive (NetWorld).

## M13: after every state change on this machine (dungeon gates listen).
signal state_applied

## How far beyond its own reach a client's claim may come from (latency).
const NET_MARGIN := 4.0

var id: String = ""
## The shared state (subclasses define the keys; "solved" is common).
var state: Dictionary = {}
## How close a hero must be to act (metres from this node).
var act_range: float = 6.0
var _solved_shown: bool = false


func _ready() -> void:
	var zone := ZoneBase.zone_of(self)
	if zone != null and zone.net_world != null:
		zone.net_world.register_poi(self)
	if not Net.is_client():
		var saved := SaveGame.poi_state(id)
		if not saved.is_empty():
			state = saved
	apply_state(state)


func is_solved() -> bool:
	return bool(state.get("solved", false))


## M13: does this puzzle hold its gates open right now? (Solved, unless a
## subclass knows better: a plate only while something stands on it.)
func is_active() -> bool:
	return is_solved()


func in_reach(hero: Player, margin: float = 0.0) -> bool:
	return hero != null and global_position.distance_to(hero.global_position) <= act_range + margin


## A hero did something here: the authority acts, a client asks the server.
func request(action: String, arg: Variant, hero: Player) -> void:
	if Net.is_client():
		var zone := ZoneBase.zone_of(self)
		if zone != null and zone.net_world != null:
			zone.net_world.send_poi_act(id, action, arg)
		return
	act(action, arg, hero)


## Authority: change `state` for `action` and `commit()` (override).
func act(_action: String, _arg: Variant, _hero: Player) -> void:
	pass


## Authority: the state changed - keep it, tell everyone, show it here.
func commit() -> void:
	SaveGame.set_poi_state(id, state)
	var zone := ZoneBase.zone_of(self)
	if zone != null and zone.net_world != null:
		zone.net_world.broadcast_poi_state(id, state)
	apply_state(state)


## Every machine: show `new_state` (the server's on a client).
func apply_state(new_state: Dictionary) -> void:
	state = new_state.duplicate(true)
	_present()
	if is_solved() and not _solved_shown:
		_solved_shown = true
		_on_solved()
	state_applied.emit()


## Show the state (fire on the braziers, the boulder's place...).
func _present() -> void:
	pass


## Once, on every machine, when it is (or loads) solved.
func _on_solved() -> void:
	pass


## Authority: the reward for solving - XP for every hero near, the puzzle's
## chest opens on its own (a TreasureChest the subclass places).
func reward_party(xp: int, note_key: String) -> void:
	var zone := ZoneBase.zone_of(self)
	if zone == null:
		return
	for hero in zone.players_within(global_position, 25.0):
		zone.give_reward(hero, xp, 0, 0, [], global_position, "@" + note_key, true)
