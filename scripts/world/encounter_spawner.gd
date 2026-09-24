class_name EncounterSpawner
extends Node3D
## Camp spawner: when the player enters the trigger radius, spawns its
## composition once (per zone visit) scattered around this point.

signal cleared  # every spawned enemy died

const CLEAR_XP_PER_ENEMY := 15  # M07: camp bonus on top of the kills

var composition: Array[String] = ["rusher", "rusher"]
var trigger_radius: float = 13.0
var elite_kind: int = -1  # forwarded when composition contains "elite"

var triggered: bool = false
var _alive: int = 0


func _physics_process(_delta: float) -> void:
	if triggered:
		return
	var zone := get_tree().current_scene as ZoneBase
	if zone == null or zone.player == null:
		return
	if zone.player.global_position.distance_to(global_position) <= trigger_radius:
		trigger(zone)


func trigger(zone: ZoneBase) -> void:
	if triggered:
		return
	triggered = true
	for i in composition.size():
		var angle := TAU * float(i) / float(composition.size()) + randf() * 0.5
		var pos := global_position + Vector3(cos(angle) * randf_range(1.5, 4.0), 0.2, sin(angle) * randf_range(1.5, 4.0))
		var enemy: EnemyBase
		if composition[i] == "elite":
			enemy = zone.spawn_elite(elite_kind, pos)
		else:
			enemy = zone.spawn_by_id(composition[i], pos)
		_alive += 1
		enemy.enemy_died.connect(func(_e: EnemyBase) -> void:
			_alive -= 1
			if _alive <= 0:
				cleared.emit()
				var bonus := CLEAR_XP_PER_ENEMY * composition.size()
				if is_instance_valid(zone) and zone.player != null and is_instance_valid(zone.player):
					zone.player.progression.add_xp(bonus)
					zone.hud.toast("Camp cleared  +%d XP" % bonus, ArtKit.color("color_roles.experience.body", Color(0.62, 0.7, 1.0)))
		)
	Sfx.play("telegraph", global_position, -6.0, 0.1, 0.7)
