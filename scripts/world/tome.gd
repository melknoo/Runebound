class_name Tome
extends Interactable
## M12: the great secret of the Highlands - an old tome on a stone lectern at
## the back of the Charwood's sealed grotto (the boulder on the ledge opens
## it). Reading it teaches the reader the tome ability of their own class
## (AbilityData.Unlock.TOME: one per class) and opens its text in the lore
## window; every character reads it for itself (it is the owner's: the
## known abilities are per character). The ability then waits in the
## loadout (K). M13: the dungeons' big secrets hold tomes of their own
## (`tome_id`, AbilityData.tome_id): one more ability per class each, and
## their own text (`lore.tome.<id>`).

const READ_XP := 150
const LORE_ID := "lore.tome"

## "" = the Charwood grotto's tome; else the dungeon whose tome this is.
var tome_id: StringName = &""
var _light: OmniLight3D


static func build(zone: ZoneBase, pos: Vector3, yaw: float, which: StringName = &"") -> Tome:
	var tome := Tome.new()
	tome.tome_id = which
	tome.name = "Tome" if which == &"" else "Tome_" + String(which)
	tome.id = "tome" if which == &"" else "tome_" + String(which)
	tome.reach = 2.6
	tome.prompt_height = 1.7
	zone.world.add_child(tome)
	tome.global_position = Vector3(pos.x, zone.ground_y(pos), pos.z)
	tome.rotation.y = yaw
	PoiBuilder.prop(zone, "tome_lectern", tome.global_position, yaw)
	PoiBuilder.blocker(zone, tome.global_position, Vector3(0.6, 1.1, 0.5), yaw)
	tome._light = OmniLight3D.new()
	tome._light.light_color = ArtKit.color("color_roles.player_accent.hot", Color("#9FF2E6"))
	tome._light.light_energy = 0.9
	tome._light.omni_range = 3.0
	tome._light.position = Vector3(0, 1.4, 0)
	tome.add_child(tome._light)
	return tome


## The ability tome `which` teaches `hero`'s class (null: none).
static func ability_for(hero: Player, which: StringName = &"") -> AbilityData:
	if hero == null or hero.class_data == null:
		return null
	for data in hero.class_data.abilities:
		if data != null and data.unlock == AbilityData.Unlock.TOME and data.tome_id == which:
			return data
	return null


## This tome's text in the lore window.
func lore_id() -> String:
	return LORE_ID if tome_id == &"" else "%s.%s" % [LORE_ID, tome_id]


func prompt_text(_hero: Player) -> String:
	return Texts.t("ui.prompt.read_tome")


func interact(hero: Player) -> void:
	var zone := ZoneBase.zone_of(self)
	if zone == null:
		return
	if zone.lore_ui != null:
		zone.lore_ui.open(lore_id(), "lore.kind.tome", hero)
	var data := ability_for(hero, tome_id)
	if data != null and hero.learn_ability(data.id):
		zone.receive_reward(hero, READ_XP, 0, 0, [], global_position, "", true)
		if zone.hud != null:
			zone.hud.toast(Texts.t("ui.tome.learned", [data.title(), InputSetup.key_label(&"loadout_toggle")]),
				ArtKit.color("color_roles.player_accent.hot", Color("#9FF2E6")))
		Sfx.play_ui("ability_learned", -4.0)
		SaveGame.request_save()
	hero.read_lore(lore_id())
