class_name DungeonGatePortal
extends Portal
## M13: a dungeon's gate in the Highlands. Sealed until a hero of this
## character first comes close: then the seal breaks (a burst, a toast with
## the recommended level, remembered per character) and it is an ordinary
## gate into the dungeon. A dungeon not built yet keeps its gate sealed. The
## label names the dungeon and its recommended level in the player's language.

const BREAK_RANGE := 4.5

## DungeonRegistry id ("cistern", "warrens").
var dungeon_id: String = ""
## The gate's POI id (the seal memory and the way back arrive here).
var gate_id: String = ""


static func seal_key(gate: String) -> String:
	return "seal:" + gate


func _ready() -> void:
	var dinfo := DungeonRegistry.info(dungeon_id)
	destination_scene = String(dinfo.get("scene", ""))
	arrival = String(dinfo.get("exit", ""))
	label_text = Texts.t("ui.dungeon.gate", [DungeonRegistry.title(dungeon_id).to_upper(), int(dinfo.get("recommended", 1))])
	locked = true
	super()


func is_open() -> bool:
	return DungeonRegistry.is_open(dungeon_id)


## Has this hero broken the seal before?
func seal_broken(hero: Player) -> bool:
	return hero != null and hero.map_discovered.has(seal_key(gate_id))


func _apply_lock_visuals() -> void:
	super()
	_label.text = label_text  # no English "[SEALED]": the name and level say it


func _process(delta: float) -> void:
	if not locked:
		super(delta)
		return
	var zone := get_tree().current_scene as ZoneBase
	var hero := zone.player if zone != null else null
	if hero == null or not is_instance_valid(hero):
		_prompt.update(false, "")
		return
	var near := hero.global_position.distance_to(global_position)
	if is_open() and seal_broken(hero):
		set_locked(false)
	elif is_open() and near <= BREAK_RANGE:
		break_seal(hero)
	else:
		_prompt.update(near <= TRIGGER_RANGE, Texts.t("ui.dungeon.sealed"))


## The first time this character comes close: the seal shatters.
func break_seal(hero: Player) -> void:
	hero.discover_poi(seal_key(gate_id))
	set_locked(false)
	var zone := ZoneBase.zone_of(self)
	VFX.light_pop(self, global_position + Vector3(0, 1.4, 0), ArtKit.color("color_roles.player_accent.hot", Color("#9FF2E6")), 4.0, 7.0, 0.35)
	VFX.flash(self, global_position + Vector3(0, 1.4, 0), Color(0.6, 1.0, 0.95), 2.4, 0.3)
	Sfx.play("shatter_burst", global_position, -6.0)
	hero.feel_shake(0.25)
	if zone != null and zone.hud != null:
		var dinfo := DungeonRegistry.info(dungeon_id)
		zone.hud.toast(Texts.t("ui.dungeon.seal_broken", [DungeonRegistry.title(dungeon_id), int(dinfo.get("recommended", 1))]),
			Color(0.7, 0.55, 1.0))
	SaveGame.request_save()
