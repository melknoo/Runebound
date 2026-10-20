class_name StoryCond
extends Object
## M14a: one condition evaluator for quests (`requires`), dialogue (`if`) and
## the stage (`show_if` / `hide_if`). A condition is a dict; every key must
## hold (AND). Keys:
##   done / not_done: [quest ids]     quest_active / not_active: quest id
##   quest_step: [quest id, step id]  beat / not_beat: beat id (or [ids])
##   act: n (exactly) / act_min: n    class: class id (or [ids])
##   level: n (at least)              seen / not_seen: cutscene id
##   choice: [key, value]             npc_teaches_hero: true (the talking NPC trains this class)
##   legacy: true/false (an existing character from before M14)
## An empty dict holds. Unknown keys fail (and StoryDB reports them).

const KEYS: Array[String] = ["done", "not_done", "quest_active", "not_active", "quest_step", "beat", "not_beat",
	"act", "act_min", "class", "level", "seen", "not_seen", "choice", "npc_teaches_hero", "legacy"]


## `ctx` may carry {"npc": Npc} for npc_teaches_hero.
static func check(cond: Variant, qlog: QuestLog, hero: Player, ctx: Dictionary = {}) -> bool:
	if cond is not Dictionary or (cond as Dictionary).is_empty():
		return true
	if qlog == null:
		return false
	var c: Dictionary = cond
	for key: String in c:
		var v: Variant = c[key]
		if not _one(key, v, qlog, hero, ctx):
			return false
	return true


static func _one(key: String, v: Variant, qlog: QuestLog, hero: Player, ctx: Dictionary) -> bool:
	match key:
		"done":
			for id: Variant in _list(v):
				if not qlog.is_done(str(id)):
					return false
			return true
		"not_done":
			for id: Variant in _list(v):
				if qlog.is_done(str(id)):
					return false
			return true
		"quest_active":
			return qlog.is_running(str(v))
		"not_active":
			return not qlog.is_running(str(v))
		"quest_step":
			var pair := _list(v)
			return pair.size() == 2 and qlog.is_running(str(pair[0])) and qlog.step_id(str(pair[0])) == str(pair[1])
		"beat":
			for id: Variant in _list(v):
				if not qlog.has_beat(str(id)):
					return false
			return true
		"not_beat":
			for id: Variant in _list(v):
				if qlog.has_beat(str(id)):
					return false
			return true
		"act":
			return qlog.act == int(v)
		"act_min":
			return qlog.act >= int(v)
		"class":
			return hero != null and hero.class_data != null and _list(v).has(String(hero.class_data.id))
		"level":
			return hero != null and hero.progression.level >= int(v)
		"seen":
			return qlog.seen.has(str(v))
		"not_seen":
			return not qlog.seen.has(str(v))
		"choice":
			var kv := _list(v)
			return kv.size() == 2 and qlog.choice(str(kv[0])) == str(kv[1])
		"npc_teaches_hero":
			var npc: Variant = ctx.get("npc")
			var teaches: bool = npc != null and is_instance_valid(npc) and npc.has_method(&"teaches") \
				and bool(npc.call(&"teaches", hero))
			return teaches == bool(v)
		"legacy":
			return qlog.has_beat("legacy") == bool(v)
	push_warning("StoryCond: unknown key " + key)
	return false


static func _list(v: Variant) -> Array:
	return v as Array if v is Array else [v]
