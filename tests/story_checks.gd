extends RefCounted
## M14a: the story's checks, run at the end of the smoke test
## (tests/smoke_test.gd loads this file at runtime, so a parse error here
## fails one check instead of the whole smoke run) and on their own by
## tests/story_test.tscn (`tools\run_godot.cmd story`). `t` is the runner: it
## has `lab` (the Combat Lab), `_check(cond, label)` and `_wait_frames(n)`.

var t: Node
## The runner's Combat Lab, or one of our own when the runner has none left
## (the smoke test ends on the title screen).
var lab: ZoneBase


func run(runner: Node) -> void:
	t = runner
	var cand: Variant = t.get(&"lab")
	lab = cand as ZoneBase if cand != null and is_instance_valid(cand) and (cand as Node).is_inside_tree() else null
	var own: ZoneBase = null
	var prev := t.get_tree().current_scene
	if lab == null:
		own = (load("res://scenes/combat_lab.tscn") as PackedScene).instantiate() as ZoneBase
		t.get_tree().root.add_child(own)
		t.get_tree().current_scene = own
		lab = own
		await t.call(&"_wait_frames", 5)
	await _texts_and_data()
	await _quest_log()
	await _save_v7()
	await _director_in_the_lab()
	StoryDB.reload()  # drops the test quests
	if own != null:
		own.queue_free()
		if prev != null and is_instance_valid(prev):
			t.get_tree().current_scene = prev


func _check(cond: bool, label: String) -> void:
	t.call(&"_check", cond, label)


func _texts_and_data() -> void:
	_check(Texts.has("ui.journal.title") and Texts.in_language("ui.journal.title", "de") == "Tagebuch",
		"M14a: the story's text tables load from resources/i18n/story/ (Journal / Tagebuch)")
	var problems := StoryDB.problems()
	_check(problems.is_empty(), "M14a: the story data is consistent (%s)" % ", ".join(problems.slice(0, 5)))
	_check(InputMap.has_action(&"journal_toggle") and InputSetup.key_label(&"journal_toggle") != "?"
		and KeyBindings.actions().has(&"journal_toggle"), "M14a: the journal has its own rebindable key")
	_check(ResourceLoader.exists("res://assets/ui/map/quest.png") and ResourceLoader.exists("res://assets/ui/map/quest_turnin.png"),
		"M14a: quest marker icons for the map and the compass")


## A log on the lab's hero, without a director: starting, counting, retroactive
## goals, effects, pending quests, the save round trip.
func _quest_log() -> void:
	var hero: Player = lab.player
	StoryDB.add_test_quest({"id": "t_counted", "kind": "main", "act": 1, "title": "t.counted", "steps": [
		{"id": "slay", "text": "t.slay", "goal": {"type": "kill", "enemies": ["rusher"], "count": 2}},
		{"id": "report", "text": "t.report", "goal": {"type": "talk", "npc": "t_npc"}}],
		"rewards": {"xp": 40, "gold": 5}, "on_done": [{"beat": "t_counted_done"}]})
	StoryDB.add_test_quest({"id": "t_retro", "kind": "side", "act": 1, "title": "t.retro", "steps": [
		{"id": "gather", "text": "t.gather", "goal": {"type": "collect", "prefix": "t_shard_", "count": 2}},
		{"id": "read", "text": "t.read", "goal": {"type": "read", "ids": ["lore.t.a"]}}],
		"on_done": [{"start": "t_next"}]})
	StoryDB.add_test_quest({"id": "t_next", "kind": "side", "act": 1, "title": "t.next",
		"requires": {"done": ["t_retro"]}, "steps": [{"id": "b", "text": "t.b", "goal": {"type": "beat", "id": "t_beat"}}]})
	var ql := QuestLog.new()
	ql.from_dict(QuestLog.new_story())
	ql.bind(hero)
	_check(ql.active and ql.act == 0 and ql.pending.has("p_ash_road"), "a new story: act 0, the prologue waiting")
	_check(ql.start("t_counted") and ql.is_running("t_counted") and ql.shown_quest() == "t_counted"
		and ql.step_id("t_counted") == "slay", "a quest starts at its first step and is tracked")
	ql.event("kill", "caster")
	ql.event("kill", "rusher")
	_check(ql.progress("t_counted") == Vector2i(1, 2), "a kill of the wrong kind does not count, the right one does (1/2)")
	var before := Vector2i(hero.progression.level, hero.progression.xp)
	ql.event("kill", "rusher")
	_check(ql.step_id("t_counted") == "report", "the second kill completes the step, the next one starts")
	ql.event("talk", "someone_else")
	_check(ql.is_running("t_counted"), "talking to another NPC does nothing")
	ql.event("talk", "t_npc")
	_check(ql.is_done("t_counted") and not ql.is_running("t_counted") and ql.has_beat("t_counted_done"),
		"talking to the right one finishes the quest and runs its effects (a beat)")
	_check(Vector2i(hero.progression.level, hero.progression.xp) != before, "the quest's reward goes through the reward path (XP)")
	# retroactive: the hero already holds what the steps want
	hero.collect("t_shard_1")
	hero.collect("t_shard_2")
	_check(ql.start("t_retro") and ql.step_id("t_retro") == "read", "a collect step the hero already did completes at once")
	hero.read_lore("lore.t.a")
	ql.event("read", "")
	_check(ql.is_done("t_retro") and ql.is_running("t_next"), "reading finishes it, and its effect starts the next quest")
	_check(not ql.start("t_next") and ql.add_beat("t_beat") and ql.is_done("t_next"),
		"a running quest doesn't start twice; a beat goal completes on the beat")
	# pending: a quest whose requirements don't hold yet waits
	var ql2 := QuestLog.new()
	ql2.from_dict({"v": 1, "act": 1})
	ql2.bind(hero)
	_check(not ql2.start("t_next") and ql2.pending.has("t_next"), "a blocked quest waits in pending")
	ql2.done.append("t_retro")
	ql2.flush_pending()
	_check(ql2.is_running("t_next") and not ql2.pending.has("t_next"), "it starts once its requirement holds")
	# the save round trip
	ql.set_choice("t.choice", "b")
	var d := ql.to_dict()
	var ql3 := QuestLog.new()
	ql3.from_dict(JSON.parse_string(JSON.stringify(d)))
	_check(ql3.active and ql3.done == ql.done and ql3.beats == ql.beats and ql3.choice("t.choice") == "b"
		and ql3.quests == ql.quests, "the log survives a JSON round trip")
	var off := QuestLog.new()
	off.from_dict({})
	_check(not off.active and off.to_dict().is_empty() and not off.start("t_counted"), "an empty story is inactive and starts nothing")
	_check(StoryCond.check({"class": "druid"}, ql, hero) == (hero.class_data.id == &"druid")
		and StoryCond.check({"done": ["t_counted"], "beat": "t_counted_done", "choice": ["t.choice", "b"]}, ql, hero)
		and not StoryCond.check({"not_done": ["t_counted"]}, ql, hero), "conditions: class, done, beat, choice")
	# tidy up the lab hero
	for id in ["t_shard_1", "t_shard_2"]:
		hero.collected.remove_at(hero.collected.find(id))
	hero.lore_read.remove_at(hero.lore_read.find("lore.t.a"))


func _save_v7() -> void:
	var hero: Player = lab.player
	_check(SaveGame.VERSION == 7 and SaveGame.new_character(&"druid", "X").get("story", {}).get("act", -1) == 0,
		"save v7: a new character carries a story at act 0")
	QuestLog.of(hero).from_dict({})
	_check(not SaveGame.character_dict(hero).has("story"), "a hero without a story saves none (test heroes, bots)")
	QuestLog.of(hero).from_dict({"v": 1, "act": 1, "beats": ["legacy"]})
	var ch := SaveGame.character_dict(hero)
	_check(ch.has("story") and (ch["story"] as Dictionary).get("beats", []) == ["legacy"],
		"a hero with a story saves it in its character")
	QuestLog.of(hero).from_dict({})
	var v6 := {"version": 6, "active": 0, "characters": [
		{"name": "Old", "class_id": "runebreaker", "world": {"zone": "res://scenes/hub.tscn",
			"flags": {"colossus_defeated": true}, "camps": {}}},
		{"name": "New", "class_id": "druid", "world": {"zone": "res://scenes/hub.tscn", "flags": {}, "camps": {}}}]}
	var v7 := SaveGame.migrate(v6.duplicate(true))
	var c0: Dictionary = (v7.get("characters", []) as Array)[0]
	var c1: Dictionary = (v7.get("characters", []) as Array)[1]
	var s0: Dictionary = c0.get("story", {})
	_check(int(v7.get("version", 0)) == 7 and int(s0.get("act", 0)) == 1 and (s0.get("beats", []) as Array).has("legacy")
		and (s0.get("beats", []) as Array).has("boss:colossus") and (s0.get("pending", []) as Array).has("a1_call")
		and (c0.get("notes", []) as Array).has("m14_call")
		and not ((c1.get("story", {}) as Dictionary).get("beats", []) as Array).has("boss:colossus"),
		"save v6 -> v7: every character joins Act 1 as legacy, its own bosses count, Sigrun calls")
	# the old file is kept before the first v7 write
	var keep := SaveGame.save_path
	var path := "user://story_backup_test.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(v6))
	f.close()
	var bak := path + ".v6.bak"
	if FileAccess.file_exists(bak):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(bak))
	SaveGame.save_path = path
	SaveGame.reload_from_disk()
	_check(FileAccess.file_exists(bak) and SaveGame.characters().size() == 2, "loading a v6 save keeps a .v6.bak copy")
	for p in [path, bak]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	SaveGame.save_path = keep
	SaveGame.reload_from_disk()


## The lab's director with a story on its hero: kill credit by distance, the
## tracker, the journal on its key, markers on the compass, reaching a place.
func _director_in_the_lab() -> void:
	var hero: Player = lab.player
	_check(QuestDirector.credits(Vector3.ZERO, Vector3(0, 0, 59.0)) and not QuestDirector.credits(Vector3.ZERO, Vector3(0, 0, 70.0)),
		"kill credit: within 60 m like XP, not from 70 m")
	_check(lab.quest_director != null and lab.journal_ui != null and lab.quest_tracker != null
		and lab.quest_tracker.get_parent() == lab.hud.get_child(0), "every zone has a director, a journal and a tracker in the HUD")
	var ql := QuestLog.of(hero)
	ql.from_dict({"v": 1, "act": 1})
	lab.quest_director.begin()
	_check(lab.quest_director.running, "the director runs for a hero with a story")
	var spot := hero.global_position + Vector3(10, 0, 0)
	StoryDB.add_test_quest({"id": "t_lab", "kind": "main", "act": 1, "level": 99, "title": "ui.journal.title", "steps": [
		{"id": "slay", "text": "ui.journal.main", "goal": {"type": "kill", "enemies": ["rusher"], "count": 1}},
		{"id": "go", "text": "ui.journal.side", "goal": {"type": "reach", "at": [spot.x, spot.z], "radius": 3}}]})
	ql.start("t_lab")
	await t.call(&"_wait_frames", 2)
	var lines := lab.quest_tracker.lines()
	_check(lab.quest_tracker.visible and lines.size() == 2 and lines[0] == Texts.t("ui.journal.title")
		and lines[1].contains(Texts.t("ui.journal.main")), "the tracker shows the quest and its step (%s)" % ", ".join(lines))
	var far := ZoneBase.make_enemy("rusher")
	lab._spawn_enemy(far, hero.global_position + Vector3(0, 0, 75))
	var near := ZoneBase.make_enemy("rusher")
	lab._spawn_enemy(near, hero.global_position + Vector3(0, 0, 6))
	await t.call(&"_wait_frames", 2)
	far.take_hit(HitInfo.create(99999.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, far.global_position))
	await t.call(&"_wait_frames", 2)
	_check(ql.step_id("t_lab") == "slay", "a kill 75 m away gives the hero no credit")
	near.take_hit(HitInfo.create(99999.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.LIGHT, near.global_position))
	await t.call(&"_wait_frames", 2)
	_check(ql.step_id("t_lab") == "go", "a kill near the hero counts")
	var marks := lab.story_markers()
	var compass: Variant = lab.hud.get(&"compass")
	_check(marks.size() == 1 and String(marks[0]["icon"]) == "quest" and (marks[0]["pos"] as Vector3).distance_to(spot) < 1.0,
		"the tracked step puts a quest marker on the map and the compass")
	if compass != null:
		_check((compass.call(&"markers") as Array).any(func(m: Dictionary) -> bool: return String(m.get("kind", "")) == "quest"),
			"the compass lists it")
	var jev := InputEventAction.new()
	jev.action = &"journal_toggle"
	jev.pressed = true
	lab.journal_ui._unhandled_input(jev)
	await t.call(&"_wait_frames", 1)
	_check(lab.journal_ui.visible and lab.journal_ui.shown == "t_lab" and hero.input_locked
		and lab.journal_ui.listed().has("t_lab"), "U opens the journal on the tracked quest")
	lab.journal_ui._unhandled_input(jev)
	_check(not lab.journal_ui.visible and not hero.input_locked, "U again closes it")
	hero.global_position = lab.ground_point(spot, 0.2)
	for i in 120:
		if ql.is_done("t_lab"):
			break
		await t.get_tree().process_frame
	_check(ql.is_done("t_lab") and not lab.quest_tracker.visible, "reaching the place finishes the quest; the tracker hides")
	ql.from_dict({})
	for e in [far, near]:
		if is_instance_valid(e):
			e.queue_free()
