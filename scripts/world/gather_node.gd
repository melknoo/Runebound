class_name GatherNode
extends Interactable
## M12 food: a patch of ember tubers in the ash, or the cooking pot of a
## raider camp. [E] puts food into the hero's bag; the node grows back (the
## pot refills) RESPAWN_S later. Personal and local (user decision: food is
## gathered): each character remembers when it took from which node
## (`Player.gathered`), and in co-op every machine has its own nodes.

const RESPAWN_S := 900.0  # 15 min

## Persistence key per character (deterministic from the layout).
var key: String = ""
var item: StringName = Consumables.EMBER_TUBER
var amount: int = 1
## "tuber" (a plant in the ground) or "pot" (a camp's cooking pot).
var look: String = "tuber"
var _visual: Node3D


static func create(zone: ZoneBase, node_key: String, pos: Vector3, yaw: float, node_look: String = "tuber",
		node_amount: int = 1) -> GatherNode:
	var node := GatherNode.new()
	node.name = "Gather_" + node_key
	node.key = node_key
	node.id = node_key
	node.look = node_look
	node.amount = node_amount
	node.reach = 2.0
	node.prompt_height = 1.0
	var p := pos
	p.y = zone.ground_y(pos)
	zone.world.add_child(node)
	node.global_position = p
	node.rotation.y = yaw
	if PoiBuilder.has_art(zone):
		node._visual = SetPieces.prop(node, "cook_pot" if node_look == "pot" else "ember_tuber_plant", p, yaw, 1.0)
	return node


func ready_for(hero: Player) -> bool:
	return Time.get_unix_time_from_system() - hero.gathered_at(key) >= RESPAWN_S


func prompt_text(hero: Player) -> String:
	if not ready_for(hero):
		return ""
	if hero.consumable_count(item) >= Consumables.cap(item):
		return Texts.t("ui.prompt.bag_full")
	return Texts.t("ui.prompt.take_food" if look == "pot" else "ui.prompt.gather")


func interact(hero: Player) -> void:
	var zone := ZoneBase.zone_of(self)
	var taken := hero.add_consumable(item, amount)
	if taken <= 0:
		Sfx.play_ui("ui_denied", -8.0)
		return
	hero.mark_gathered(key)
	Sfx.play_ui("pickup", -6.0)
	if zone != null and zone.hud != null and hero.is_local:
		zone.hud.toast("+%d %s" % [taken, Consumables.display_name(item)],
			ArtKit.color("palettes.burnt_forest.ember.2", Color("#D86A2C")))
	SaveGame.request_save()


func _process(delta: float) -> void:
	super._process(delta)
	if _visual == null or look == "pot":
		return  # the pot stays; it only refills
	var zone := ZoneBase.zone_of(self)
	if zone != null and zone.player != null:
		_visual.visible = ready_for(zone.player)
