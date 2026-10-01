class_name BoulderPuzzle
extends PoiPuzzle
## M12 puzzle: a boulder on a short track; push it (walk into it, or [E])
## step by step onto the pressure plate at the track's end and what it locks
## opens (the tome grotto's door). The boulder moves in fixed steps along a
## fixed track, so it can never stick in a corner, and the server needs no
## physics for it: a push is a request, the step is the state.

const STEP := 0.8
const PUSH_EVERY := 0.4
const SOLVE_XP := 80

## Track in world space: the boulder sits at start + dir * step * STEP.
var start: Vector3 = Vector3.ZERO
var dir: Vector3 = Vector3.RIGHT
var steps: int = 7
## Called once on every machine when the boulder reaches the plate.
var on_open: Callable = Callable()

var _rock: StaticBody3D
var _plate: Node3D
var _push_left: float = 0.0
var _switch: PuzzleSwitch


static func create(zone: ZoneBase, puzzle_id: String, track_start: Vector3, track_dir: Vector3, track_steps: int,
		opens: Callable = Callable()) -> BoulderPuzzle:
	var puzzle := BoulderPuzzle.new()
	puzzle.name = "Boulder_" + puzzle_id
	puzzle.id = puzzle_id
	puzzle.start = Vector3(track_start.x, zone.ground_y(track_start), track_start.z)
	puzzle.dir = Vector3(track_dir.x, 0.0, track_dir.z).normalized()
	puzzle.steps = track_steps
	puzzle.act_range = 5.0
	puzzle.state = {"step": 0, "solved": false}
	puzzle.on_open = opens
	puzzle.position = puzzle.start
	zone.world.add_child(puzzle)  # loads a saved state (and opens what it locks)
	puzzle._build(zone)
	puzzle._present()
	return puzzle


func _build(zone: ZoneBase) -> void:
	var rock_mat := zone._zone_material(&"highlands_rock", "res://assets/textures/ash_rock.png", Color(0.42, 0.36, 0.32), 2.5)
	_rock = zone._add_box(start + Vector3(0, 0.8, 0), Vector3(1.6, 1.6, 1.6), rock_mat, Vector3(0, 20, 0), &"highlands_rock")
	_rock.name = "Boulder"
	var end := start + dir * STEP * steps
	if PoiBuilder.has_art(zone):
		_plate = PoiBuilder.prop(zone, "rune_seal", end, atan2(dir.x, dir.z), 0.75)
	_switch = PuzzleSwitch.new()
	_switch.text_key = "ui.prompt.push"
	_switch.reach = 2.6
	_switch.on_use = func(hero: Player) -> void: request("push", 0, hero)
	_switch.usable = func(_hero: Player) -> bool: return not is_solved()
	_rock.add_child(_switch)
	_switch.position = Vector3(0, 0.2, 0)


func boulder_position(step: int) -> Vector3:
	var p := start + dir * STEP * float(clampi(step, 0, steps))
	var zone := ZoneBase.zone_of(self)
	if zone != null:
		p.y = zone.ground_y(p)
	return p + Vector3(0, 0.8, 0)


func act(action: String, _arg: Variant, _hero: Player) -> void:
	if action != "push" or is_solved():
		return
	state["step"] = mini(int(state.get("step", 0)) + 1, steps)
	if int(state["step"]) >= steps:
		state["solved"] = true
		reward_party(SOLVE_XP, "ui.puzzle.solved")
	commit()


func _process(delta: float) -> void:
	# The local hero pushes by walking into the boulder (from behind it).
	_push_left = maxf(_push_left - delta, 0.0)
	if is_solved() or _push_left > 0.0 or _rock == null:
		return
	var zone := ZoneBase.zone_of(self)
	var hero := zone.player if zone != null else null
	if hero == null or not is_instance_valid(hero) or hero.input_locked:
		return
	var to_rock := _rock.global_position - hero.global_position
	to_rock.y = 0.0
	if to_rock.length() > 1.9 or to_rock.normalized().dot(dir) < 0.7:
		return
	if hero.intent.move_dir.dot(dir) < 0.6:
		return
	_push_left = PUSH_EVERY
	request("push", 0, hero)


func _present() -> void:
	if _rock == null:
		return
	var target := boulder_position(int(state.get("step", 0)))
	if _rock.global_position.distance_to(target) > 0.05:
		var tw := _rock.create_tween()
		tw.tween_property(_rock, "global_position", target, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		var spin := _rock.rotation + Vector3(0, 0, -STEP / 0.8)
		tw.parallel().tween_property(_rock, "rotation", spin, 0.35)
		Sfx.play("earthbreaker_impact", target, -16.0, 0.1, 0.7)


func _on_solved() -> void:
	if _plate != null:
		VFX.light_pop(ZoneBase.zone_of(self), _plate.global_position + Vector3(0, 0.4, 0),
			ArtKit.color("color_roles.player_accent.hot", Color("#9FF2E6")), 2.5, 6.0, 0.5)
	if on_open.is_valid():
		on_open.call()
