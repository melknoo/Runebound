class_name LoreObject
extends Interactable
## M12: something to read in the world - a grave's inscription, a note, a
## carved stone. [E] opens the lore window with `<lore_id>.title/.body` from
## the text table (DE/EN); the first read puts it into the hero's chronicle
## (per character) and pays a little XP.

const READ_XP := 15
## Prop per kind (solid ones stand on a blocker of `SOLID[kind]`).
const PROPS := {"grave": "vl_grave", "note": "lore_note", "letter": "lore_note", "inscription": "lore_tablet"}
const SOLID := {"grave": Vector3(0.6, 0.95, 0.35), "inscription": Vector3(1.0, 1.2, 0.4)}

var lore_id: String = ""
var kind: String = "note"


## Builds the layout POI {id, kind, text} on the ground.
static func build(zone: ZoneBase, poi: Dictionary) -> LoreObject:
	var obj := LoreObject.new()
	obj.name = "Lore_" + String(poi.get("id", ""))
	obj.id = String(poi.get("id", ""))
	obj.lore_id = String(poi.get("text", ""))
	obj.kind = String(poi.get("kind", "note"))
	obj.reach = 2.2
	obj.prompt_height = 1.3
	var pos := ZoneLayout.pos_of(poi)
	pos.y = zone.ground_y(pos)
	zone.world.add_child(obj)
	obj.global_position = pos
	obj.rotation.y = PoiBuilder.yaw_of(poi)
	if SOLID.has(obj.kind):
		PoiBuilder.blocker(zone, pos, SOLID[obj.kind], obj.rotation.y)
	if PoiBuilder.has_art(zone):
		PoiBuilder.prop(zone, String(PROPS.get(obj.kind, "lore_note")), pos, obj.rotation.y)
	return obj


func prompt_text(_hero: Player) -> String:
	return Texts.t("ui.prompt.read")


func interact(hero: Player) -> void:
	var zone := ZoneBase.zone_of(self)
	if zone == null:
		return
	if zone.lore_ui != null:
		zone.lore_ui.open(lore_id, "lore.kind." + kind, hero)
	if hero.read_lore(lore_id):
		zone.receive_reward(hero, READ_XP, 0, 0, [], global_position, "", true)
