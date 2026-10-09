class_name ElementCharge
extends Object
## M13: an element a hero carries for a few seconds after striking an
## element source in a dungeon (an ember bowl, a frost crystal, a storm
## coil). While it lasts, the hero's strikes on element targets count as
## that element - so every class can light a kiln, freeze a channel or feed
## a copper post with its basic attack. The Elementalist's own fire, frost
## and lightning count without one. Kept on the hero (meta), on its own
## machine only; the others see an aura through HeroFx ("element_charge").

const SECONDS := 8.0
const META := &"element_charge"
const NONE := -1


static func element_id(name: String) -> int:
	match name:
		"fire": return HitInfo.DamageType.FIRE
		"frost": return HitInfo.DamageType.FROST
		"storm", "lightning": return HitInfo.DamageType.LIGHTNING
	return NONE


static func element_name(element: int) -> String:
	match element:
		HitInfo.DamageType.FIRE: return "fire"
		HitInfo.DamageType.FROST: return "frost"
		HitInfo.DamageType.LIGHTNING: return "storm"
	return ""


static func color(element: int) -> Color:
	match element:
		HitInfo.DamageType.FIRE: return ArtKit.color("color_roles.fire.body", Color(1.0, 0.55, 0.2))
		HitInfo.DamageType.FROST: return ArtKit.color("color_roles.frost.body", Color(0.55, 0.85, 1.0))
		HitInfo.DamageType.LIGHTNING: return ArtKit.color("color_roles.lightning.body", Color(0.85, 0.9, 1.0))
	return Color.WHITE


## The element a hit carries by itself (its damage type or its status), else NONE.
static func of_hit(hit: HitInfo) -> int:
	if hit == null:
		return NONE
	if hit.type in [HitInfo.DamageType.FIRE, HitInfo.DamageType.FROST, HitInfo.DamageType.LIGHTNING]:
		return hit.type
	if hit.applies_burn:
		return HitInfo.DamageType.FIRE
	if hit.applies_chill:
		return HitInfo.DamageType.FROST
	if hit.applies_shock:
		return HitInfo.DamageType.LIGHTNING
	return NONE


## The element `hero` carries right now (NONE when none or run out).
static func carried(hero: Player) -> int:
	if hero == null or not hero.has_meta(META):
		return NONE
	var c: Dictionary = hero.get_meta(META)
	if Time.get_ticks_msec() >= int(c.get("until", 0)):
		return NONE
	return int(c.get("element", NONE))


## The element a strike by `hero` brings to a target: the hit's own, else
## the carried one.
static func of_strike(hit: HitInfo, hero: Player) -> int:
	var own := of_hit(hit)
	return own if own != NONE else carried(hero)


## `hero` (this machine's) takes up an element: the charge, and its aura on
## every machine.
static func give(hero: Player, element: int, seconds: float = SECONDS) -> void:
	if hero == null or element == NONE:
		return
	var renewed := carried(hero) == element
	hero.set_meta(META, {"element": element, "until": Time.get_ticks_msec() + int(seconds * 1000.0)})
	hero.hero_fx(&"element_charge", [element, seconds])
	var zone := ZoneBase.zone_of(hero)
	if not renewed and hero.is_local and zone != null and zone.hud != null:
		zone.hud.toast(Texts.t("ui.element." + element_name(element)), color(element))


## The look (HeroFx, any machine): a glow on the hero that fades with the charge.
static func aura(hero: Player, element: int, seconds: float) -> void:
	var old := hero.get_node_or_null("ElementAura")
	if old != null:
		old.free()
	var holder := Node3D.new()
	holder.name = "ElementAura"
	hero.add_child(holder)
	holder.position = Vector3(0, 1.1, 0)
	var light := OmniLight3D.new()
	light.light_color = color(element)
	light.light_energy = 1.4
	light.omni_range = 3.0
	light.shadow_enabled = false
	holder.add_child(light)
	VFX.flash(hero.get_tree().current_scene, hero.global_position + Vector3(0, 1.1, 0), color(element), 1.2, 0.2)
	var tw := light.create_tween()
	tw.tween_interval(maxf(seconds - 1.0, 0.1))
	tw.tween_property(light, "light_energy", 0.0, 1.0)
	tw.tween_callback(holder.queue_free)
