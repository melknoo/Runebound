class_name RuneShard
extends Interactable
## M12 collectible: a shard of the Shattered Rune, hidden off the paths
## (twelve in the Highlands). [E] takes it - a little XP and gold, a line in
## the chronicle; per character (each hero in co-op finds their own). Once
## taken it is gone for that character.

const TOTAL := 12
const TAKE_XP := 25
const TAKE_GOLD := 15

## 1..TOTAL: which chronicle line this shard carries (`shard.<n>`).
var index: int = 1
var _visual: Node3D
var _light: OmniLight3D
var _bob: float = 0.0


static func build(zone: ZoneBase, poi: Dictionary) -> RuneShard:
	var shard := RuneShard.new()
	shard.name = "Shard_" + String(poi.get("id", ""))
	shard.id = String(poi.get("id", ""))
	shard.index = int(poi.get("index", 1))
	shard.reach = 2.0
	shard.prompt_height = 1.1
	var pos := ZoneLayout.pos_of(poi)
	pos.y = zone.ground_y(pos)
	zone.world.add_child(shard)
	shard.global_position = pos
	shard._bob = fmod(pos.x * 0.37 + pos.z * 0.11, TAU)
	if PoiBuilder.has_art(zone):
		shard._visual = SetPieces.prop(shard, "rune_shard", pos, randf() * TAU, 1.4)
		# a faint teal gleam gives it away to whoever looks (no shadows, short)
		shard._light = OmniLight3D.new()
		shard._light.light_color = ArtKit.color("color_roles.player_accent.body", Color("#3CBEB4"))
		shard._light.light_energy = 0.9
		shard._light.omni_range = 3.2
		shard._light.shadow_enabled = false
		shard._light.position = Vector3(0, 0.45, 0)
		shard.add_child(shard._light)
	return shard


func prompt_text(hero: Player) -> String:
	return "" if hero.collected.has(id) else Texts.t("ui.prompt.take_shard")


func can_interact(hero: Player) -> bool:
	return not hero.collected.has(id)


func interact(hero: Player) -> void:
	var zone := ZoneBase.zone_of(self)
	if zone == null or not hero.collect(id):
		return
	Sfx.play_ui("ability_learned", -10.0)
	var found := 0
	for c in hero.collected:
		if String(c).begins_with("shard_"):
			found += 1
	zone.receive_reward(hero, TAKE_XP, TAKE_GOLD, 1, [], global_position,
		Texts.t("ui.shard.found", [found, TOTAL]), true)
	if zone.hud != null:
		zone.hud.toast(Texts.t("shard.%d" % index), UiTheme.MUTED)
	if found >= TOTAL and hero.grant_blessing(&"shards"):  # M12 phase 6: all twelve
		zone.blessing_toast(hero, &"shards")
	VFX.flash(zone, global_position + Vector3(0, 0.6, 0), ArtKit.color("color_roles.player_accent.hot"), 1.2, 0.25)


func _process(delta: float) -> void:
	super._process(delta)
	if _visual == null:
		return
	var zone := ZoneBase.zone_of(self)
	var taken := zone != null and zone.player != null and zone.player.collected.has(id)
	_visual.visible = not taken
	if _light != null:
		_light.visible = not taken
	if not taken:
		_bob += delta * 1.6
		_visual.position.y = 0.08 + sin(_bob) * 0.06
		_visual.rotation.y += delta * 0.6
