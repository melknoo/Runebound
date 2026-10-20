class_name StoryEffects
extends Object
## M14a: what quests, dialogue options and camera pans change. An effect is a
## one-key dict; a list runs in order:
##   {"start": quest id}              {"beat": id}           {"act": n}
##   {"event": [kind, id]}            {"seen": cutscene id}  {"choice": [key, value]}
##   {"give": {xp, gold, draughts, items: [{rarity, slot?}]}}  (ZoneBase.give_reward)
##   {"toast": text key}              {"cutscene": id}       {"open": "trainer" | "shop" | "storm"}
##   {"complete_step": quest id}      {"track": quest id}
## Story state changes happen here on the quest log; the zone-side ones (rewards,
## toasts, windows, camera pans) go through the hero's zone and its
## QuestDirector, and are skipped when the hero isn't in one (unit tests).

const KINDS: Array[String] = ["start", "beat", "act", "event", "seen", "choice", "give", "toast", "cutscene", "open",
	"complete_step", "track"]


## `ctx` may carry {"npc": Npc} (dialogue) for "open".
static func apply(effects: Variant, hero: Player, qlog: QuestLog, ctx: Dictionary = {}) -> void:
	if effects is not Array or qlog == null:
		return
	for eff: Variant in effects:
		if eff is Dictionary and not (eff as Dictionary).is_empty():
			_one(eff as Dictionary, hero, qlog, ctx)


static func _one(e: Dictionary, hero: Player, qlog: QuestLog, ctx: Dictionary) -> void:
	var kind := str(e.keys()[0])
	var v: Variant = e[kind]
	var zone := ZoneBase.zone_of(hero) if hero != null and is_instance_valid(hero) and hero.is_inside_tree() else null
	match kind:
		"start":
			qlog.start(str(v))
		"beat":
			qlog.add_beat(str(v))
		"act":
			qlog.set_act(int(v))
		"event":
			var pair: Array = v if v is Array else [v, ""]
			qlog.event(str(pair[0]), str(pair[1]) if pair.size() > 1 else "")
		"seen":
			qlog.mark_seen(str(v))
		"choice":
			var kv: Array = v if v is Array else []
			if kv.size() == 2:
				qlog.set_choice(str(kv[0]), str(kv[1]))
		"complete_step":
			qlog.complete_step(str(v))
		"track":
			qlog.track(str(v))
		"give":
			if zone != null and v is Dictionary:
				give(zone, hero, v as Dictionary)
		"toast":
			if zone != null and zone.hud != null and hero.is_local:
				zone.hud.toast(Texts.t(str(v)), ArtKit.color("color_roles.player_accent.hot", Color("#9FF2E6")))
		"cutscene":
			if zone != null and zone.get(&"quest_director") != null:
				zone.quest_director.play_cutscene(str(v))
		"open":
			if zone != null:
				_open(zone, hero, str(v), ctx)
		_:
			push_warning("StoryEffects: unknown effect " + kind)


## A quest reward: XP, gold, draughts and items (rarity 0-3, an optional
## slot) at the hero's feet, through the one reward path.
static func give(zone: ZoneBase, hero: Player, r: Dictionary) -> void:
	var items: Array[ItemData] = []
	for spec: Variant in r.get("items", []):
		if spec is not Dictionary:
			continue
		var s: Dictionary = spec
		var item := ItemGenerator.generate(int(s.get("rarity", 1)), hero.class_data.id)
		if item != null:
			ItemGenerator.apply_item_level(item, maxi(hero.progression.level, 1))
			items.append(item)
	zone.give_reward(hero, int(r.get("xp", 0)), int(r.get("gold", 0)), 1, items, hero.global_position, "", true,
		int(r.get("draughts", 0)))


static func _open(zone: ZoneBase, hero: Player, what: String, ctx: Dictionary) -> void:
	var npc: Variant = ctx.get("npc")
	if npc == null or not is_instance_valid(npc) or zone.trainer_ui == null:
		return
	match what:
		"trainer", "shop", "storm":
			# the NPC's own [E] path (its panel view), minus the dialogue
			if (npc as Object).has_method(&"open_panel"):
				npc.call(&"open_panel", hero)
