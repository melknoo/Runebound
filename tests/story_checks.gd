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
	await _dialogue()
	await _cutscenes()
	_story_bosses()
	StoryDB.reload()
	await _act1()
	await _prologue()  # drops the test quests
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


## Phase 2: talks. A story NPC with a test dialogue (conditions, effects, the
## key that closes it must not reopen it), a trainer that talks while it has a
## topic and opens its panel otherwise, a marker that counts an interact goal,
## a stage entry shown by its condition, badges.
func _dialogue() -> void:
	var hero: Player = lab.player
	var ql := QuestLog.of(hero)
	ql.from_dict({"v": 1, "act": 1})
	ql.bind(hero)
	StoryDB.add_test_npc("t_friend", {"name": "npc.edda.name", "rig": "druid"})
	StoryDB.add_test_dialogue("t_friend", {"npc": "t_friend", "entries": [{"start": "greet"}], "nodes": {
		"greet": {"say": "dlg.sigrun.intro.0", "options": [
			{"text": "dlg.sigrun.opt.place", "next": "more", "effects": [{"event": ["talk", "t_friend"]}]},
			{"text": "dlg.common.train", "if": {"class": "no_such_class"}, "end": true},
			{"text": "dlg.common.bye", "end": true}]},
		"more": {"say": "dlg.sigrun.place.0", "effects": [{"choice": ["t.asked", "yes"]}], "next": "last"},
		"last": {"say": "dlg.sigrun.place.1", "end": true}}})
	StoryDB.add_test_quest({"id": "t_talk", "kind": "side", "act": 1, "title": "ui.journal.title", "steps": [
		{"id": "talk", "text": "ui.journal.side", "goal": {"type": "talk", "npc": "t_friend"}}]})
	var friend := StoryNpc.create("t_friend")
	friend.position = lab.ground_point(hero.global_position + Vector3(2, 0, 0))
	lab.world.add_child(friend)
	ql.start("t_talk")
	lab.quest_director.refresh_badges()
	var badge := friend.get_node_or_null(^"StoryBadge") as Label3D
	_check(badge != null and badge.visible and badge.text == "?", "a quest that wants a talk puts a ? over the NPC")
	var dui := lab.dialogue_ui
	friend.interacted.emit(hero)
	_check(dui.visible and dui.npc_id == "t_friend" and hero.input_locked and dui.current_text() == Texts.t("dlg.sigrun.intro.0")
		and dui.option_texts().size() == 2 and DialogueUI.speaker_name("t_friend") == "Edda",
		"talking opens the dialogue: name, line, the answers whose conditions hold (2 of 3)")
	dui.choose(0)
	_check(dui.node_id == "more" and ql.is_done("t_talk") and ql.choice("t.asked") == "yes",
		"an answer runs its effects (the talk goal) and the next line its own (a choice)")
	dui.advance()
	_check(dui.node_id == "last", "a line without answers goes on with the key")
	dui.advance()
	_check(not dui.visible and hero.input_locked, "the last line closes the talk; the hero stays locked this frame")
	await t.get_tree().process_frame
	await t.get_tree().process_frame
	_check(not hero.input_locked, "and is free again a frame later (the same key can't reopen it)")
	# a trainer: its story topic first, the panel when it has none
	var trainer := TrainerNpc.new()
	trainer.teaches_class = &"runebreaker"
	trainer.position = lab.ground_point(hero.global_position + Vector3(-2, 0, 0))
	lab.world.add_child(trainer)
	lab.quest_director.refresh_badges()
	var tb := trainer.get_node_or_null(^"StoryBadge") as Label3D
	_check(trainer.story_id() == "sigrun" and tb != null and tb.text == "!", "Sigrun has a story to tell: a ! over her")
	trainer.interacted.emit(hero)
	var teaches := trainer.teaches(hero)
	_check(dui.visible and dui.npc_id == "sigrun" and not lab.trainer_ui.visible and ql.has_beat("dlg:sigrun_intro")
		and dui.option_texts().has(Texts.t("dlg.common.train")) == false,
		"her first talk opens before the panel (the first line has no answers yet)")
	dui.advance()
	_check(dui.option_texts().has(Texts.t("dlg.common.train")) == teaches,
		"\"Teach me\" is offered only to her own class")
	if teaches:
		dui.choose(dui.option_texts().find(Texts.t("dlg.common.train")))
		_check(not dui.visible and lab.trainer_ui.visible and hero.input_locked, "\"Teach me\" opens the trainer panel")
		lab.trainer_ui.close()
	else:
		dui.close()
	await t.get_tree().process_frame
	await t.get_tree().process_frame
	trainer.interacted.emit(hero)
	_check(not dui.visible and lab.trainer_ui.visible, "without a topic [E] opens her panel straight away")
	_check(trainer.flavour_line() == Texts.t("dlg.sigrun.flavour.%d" % (int(trainer.get(&"_visit")) % 3))
		and Texts.in_language("dlg.sigrun.flavour.0", "de").begins_with("Runen"), "her panel lines come from the text table (DE + EN)")
	lab.trainer_ui.close()
	lab.quest_director.refresh_badges()
	_check(tb.text == "" and not tb.visible, "the ! goes once her story is told")
	# a marker counts an interact goal; a stage entry follows its condition
	StoryDB.add_test_quest({"id": "t_look", "kind": "side", "act": 1, "title": "ui.journal.title", "steps": [
		{"id": "look", "text": "ui.journal.side", "goal": {"type": "interact", "marker": "t_mark"}}]})
	var mark := lab.quest_director.place({"marker": "t_mark", "zone": "combat_lab",
		"at": [hero.global_position.x, hero.global_position.z + 3.0], "show_if": {"quest_active": "t_look"}}) as StoryMarker
	lab.quest_director.refresh_stage()
	_check(mark != null and not mark.visible, "a stage marker stays hidden while its condition fails")
	ql.start("t_look")
	lab.quest_director.refresh_stage()
	mark.use_by(hero)
	_check(mark.visible and ql.is_done("t_look"), "shown once its quest runs; looking at it completes the interact goal")
	ql.from_dict({})
	await t.get_tree().process_frame
	await t.get_tree().process_frame
	for n in [friend, trainer, mark]:
		if is_instance_valid(n):
			n.queue_free()


## Phase 3: camera pans. Headless runs finish them at once (their end effects
## still run); the full flow is checked with `play(id)` forced on: the hero
## is held, the HUD and the tracker go, its own camera is current, a skip
## puts everything back and shows the act card.
func _cutscenes() -> void:
	var hero: Player = lab.player
	var ql := QuestLog.of(hero)
	ql.from_dict({"v": 1, "act": 0})
	ql.bind(hero)
	var director := lab.quest_director
	_check(director.cutscene != null and director.cutscene.get_parent() == director, "every director has a camera-pan layer")
	StoryDB.add_test_cutscene("t_pan", {"safe": false, "shots": [
		{"from": {"at": "hero", "offset": [0, 4, 8]}, "to": {"at": "hero", "offset": [0, 2, 4]}, "t": 30.0,
			"say": "dlg.sigrun.intro.0", "speaker": "sigrun"},
		{"from": [0, 10, 0], "look": [0, 0, 0], "t": 30.0}],
		"fx": [{"t": 0.0, "kind": "shake", "amount": 0.1}],
		"card": {"title": "act.1.title", "sub": "act.1.sub"}, "on_end": [{"act": 1}, {"beat": "t_pan_done"}]})
	director.play_cutscene("t_pan")
	_check(not director.cutscene.playing and ql.act == 1 and ql.has_beat("t_pan_done") and ql.seen.has("t_pan"),
		"headless: a pan finishes at once, counts as seen and runs its end effects")
	ql.from_dict({"v": 1, "act": 0})
	var rig_cam := lab.camera_rig.camera
	var forced := director.cutscene.play_forced("t_pan")
	await t.call(&"_wait_frames", 2)
	var cam := lab.get_viewport().get_camera_3d()
	_check(forced and director.cutscene.playing and director.cutscene.visible and hero.input_locked
		and not lab.hud.visible and cam != rig_cam and cam != null and cam.name == "CutsceneCamera",
		"playing: letterbox up, HUD away, the hero held, the pan's own camera current")
	var skip := InputEventAction.new()
	skip.action = &"interact"
	skip.pressed = true
	director.cutscene._input(skip)
	await t.call(&"_wait_frames", 2)
	_check(not director.cutscene.playing and not director.cutscene.visible and lab.hud.visible and not hero.input_locked
		and lab.get_viewport().get_camera_3d() == rig_cam and ql.act == 1,
		"the interact key skips it: camera, HUD and hero back, its end effects ran")
	ql.from_dict({})


## Phase 4: whether a beaten story boss stands again for the heroes near it.
func _story_bosses() -> void:
	var hero: Player = lab.player
	var ql := QuestLog.of(hero)
	ql.from_dict({})
	var at := hero.global_position
	_check(not StoryBosses.needed_near(lab, "colossus", at), "a hero without a story never wakes a story boss (test heroes, bots)")
	ql.from_dict({"v": 1, "act": 1})
	_check(StoryBosses.needed_near(lab, "colossus", at) and not StoryBosses.needed_near(lab, "colossus", at + Vector3(0, 0, 90)),
		"a hero whose story lacks the Colossus wakes it when near the arena, not from 90 m")
	ql.from_dict({"v": 1, "act": 1, "beats": ["boss:colossus"]})
	_check(not StoryBosses.needed_near(lab, "colossus", at) and StoryBosses.needed_near(lab, "vessel", at),
		"a veteran doesn't need it again; the Vessel it still needs")
	ql.from_dict({"v": 1, "act": 1})
	var credited := StoryBosses.credit(lab, "colossus", at)
	_check(credited.size() == 1 and credited[0] == hero, "the heroes that needed it are the ones its replay pays")
	ql.from_dict({})
	_check(Net.PROTOCOL >= 17, "the story in CHARACTER bumped the protocol (17)")


## Phase 5: the prologue, played through in its own zone: Edda, the road, the
## shard, the cart, the bridge breaking behind, the Reeve, the gate, then
## Runehold (Act 1, Sigrun's quest); checkpoints; skipping it.
func _prologue() -> void:
	var tree := t.get_tree()
	var prev := tree.current_scene
	var keep_save := SaveGame.save_path
	SaveGame.save_path = "user://story_prologue_test.json"
	SaveGame.wipe()
	var title_like := Node.new()  # character creation happens with no hero in the scene (the title)
	tree.root.add_child(title_like)
	tree.current_scene = title_like
	SaveGame.create_character(&"runebreaker", "Prologue")
	title_like.queue_free()
	_check(SaveGame.current_zone == SaveGame.PROLOGUE_SCENE and int((SaveGame.active_character().get("story", {}) as Dictionary).get("act", -1)) == 0,
		"a new character starts on the Ash Road with the prologue waiting ")
	var zone := (load(SaveGame.PROLOGUE_SCENE) as PackedScene).instantiate() as AshRoadZone
	tree.root.add_child(zone)
	tree.current_scene = zone
	await t.call(&"_wait_frames", 6)
	var hero := zone.player
	var ql := QuestLog.of(hero)
	_check(zone.terrain != null and zone.layout != null and zone.layout.pois.size() >= 10 and zone.bridge_deck != null
		and zone.boss_portal != null and zone.boss_portal.locked, "the Ash Road: terrain, POIs, the bridge, the gate sealed")
	_check(ql.is_running("p_ash_road") and ql.step_id("p_ash_road") == "wake" and ql.seen.has("p_intro")
		and zone.quest_tracker.hint_text() != "", "the prologue starts by itself: its camera pan, the first step, a walking hint")
	var edda := _stage_node(zone, "edda_camp")
	_check(edda != null and edda.visible, "Edda waits at the camp")
	zone.dialogue_ui.try_open("edda", edda, hero)
	zone.dialogue_ui.advance()
	zone.dialogue_ui.choose(0)
	_check(ql.step_id("p_ash_road") == "road" and zone.quest_tracker.hint_text().contains(InputSetup.key_label(&"dodge")),
		"talking to her sends the hero down the road (attack and dodge hint)")
	await _frames(3)
	_check(not edda.visible, "she stays behind with the carts")
	hero.global_position = zone.ground_point(zone.poi_position("clearing"), 0.2)
	await _until(func() -> bool: return ql.step_id("p_ash_road") == "shard_talk", 120)
	var edda2 := _stage_node(zone, "edda_clearing")
	await _frames(3)
	_check(ql.step_id("p_ash_road") == "shard_talk" and ql.has_beat("runebound") and edda2 != null and edda2.visible,
		"the clearing: the shard strikes (runebound), Edda catches up")
	zone.dialogue_ui.try_open("edda", edda2, hero)
	zone.dialogue_ui.advance()
	zone.dialogue_ui.choose(1)
	_check(ql.step_id("p_ash_road") == "cart", "Edda sends the hero to the supply cart")
	var cart := _stage_node(zone, "p_cart") as StoryMarker
	var draughts := hero.consumable_count(Consumables.HEALING_DRAUGHT) if hero.has_method(&"consumable_count") else int(hero.consumables.get(Consumables.HEALING_DRAUGHT, 0))
	cart.use_by(hero)
	await t.call(&"_wait_frames", 3)
	var after := hero.consumable_count(Consumables.HEALING_DRAUGHT) if hero.has_method(&"consumable_count") else int(hero.consumables.get(Consumables.HEALING_DRAUGHT, 0))
	_check(ql.step_id("p_ash_road") == "bridge" and zone.dialogue_ui.visible, "searching the cart: its line, and on to the bridge")
	zone.dialogue_ui.close()
	_check(after > draughts or _draught_drops(zone) >= 2, "the cart's draughts (%d -> %d, %d on the ground)" % [draughts, after, _draught_drops(zone)])
	hero.global_position = zone.ground_point(zone.poi_position("bridge_n"), 0.2)
	await _until(func() -> bool: return ql.step_id("p_ash_road") == "toll", 120)
	_check(ql.step_id("p_ash_road") == "toll" and zone.bridge_down and ql.has_beat("p_bridge_down"),
		"over the gorge: the bridge breaks behind the hero")
	_check(zone._respawn_point(hero).distance_to(zone.poi_position("bridge_n")) < 3.0, "a fall now brings the hero back at the north end")
	hero.global_position = zone.ground_point(zone.poi_position("toll") + Vector3(0, 0, 4), 0.2)
	await _until(func() -> bool: return zone.reeve != null, 60)
	_check(zone.reeve != null and zone.reeve.type_id == "risen_reeve" and zone.reeve.level == 1, "the Risen Reeve rises at his toll gate")
	if zone.reeve != null:
		zone.reeve.take_hit(HitInfo.create(99999.0, HitInfo.DamageType.PHYSICAL, HitInfo.Weight.HEAVY, zone.reeve.global_position))
	await _until(func() -> bool: return ql.step_id("p_ash_road") == "gate", 60)
	_check(ql.step_id("p_ash_road") == "gate" and ql.has_beat("boss:risen_reeve") and not zone.boss_portal.locked,
		"the Reeve falls: the gate to Runehold opens")
	var edda3 := _stage_node(zone, "edda_gate")
	await _frames(3)
	zone.dialogue_ui.try_open("edda", edda3, hero)
	zone.dialogue_ui.advance()
	zone.dialogue_ui.choose(0)
	_check(ql.step_id("p_ash_road") == "runehold", "Edda at the gate: go first")
	ql.event("enter", "hub")
	_check(ql.is_done("p_ash_road") and ql.act == 1 and ql.has_beat("prologue_done") and ql.is_running("a1_call")
		and ql.seen.has("p_arrival"), "Runehold: the prologue is done, Act 1 begins with Sigrun's quest")
	var level := hero.progression.level
	_check(level == 2, "the prologue ends at level 2 (level %d)" % level)
	zone.queue_free()
	await t.call(&"_wait_frames", 2)
	# skipping it: at creation (a second character), or online first
	var skipped := SaveGame.new_character(&"druid", "Skip", true)
	var sst: Dictionary = skipped.get("story", {})
	_check(int(sst.get("act", 0)) == 1 and (sst.get("done", []) as Array).has("p_ash_road")
		and str((skipped["world"] as Dictionary)["zone"]) == SaveGame.HUB_SCENE
		and int((skipped["progression"] as Dictionary)["level"]) == QuestLog.PROLOGUE_LEVEL and SaveGame.can_skip_prologue() == false,
		"skipping at creation: Act 1 in Runehold at the prologue's level (offered only once one finished it)")
	var online_first := QuestLog.new()
	online_first.from_dict(QuestLog.new_story())
	online_first.skip_prologue()
	_check(online_first.act == 1 and online_first.is_done("p_ash_road") and online_first.pending.has("a1_call")
		and not online_first.pending.has("p_ash_road"), "online first: the prologue is skipped, Sigrun waits")
	SaveGame.wipe()
	SaveGame.save_path = keep_save
	SaveGame.reload_from_disk()
	if prev != null and is_instance_valid(prev):
		tree.current_scene = prev


func _stage_node(zone: ZoneBase, stage_id: String) -> Node3D:
	for n in zone.quest_director.stage_nodes:
		if is_instance_valid(n) and str((n.get(&"stage") as Dictionary).get("id", "")) == stage_id:
			return n
	return null


func _draught_drops(zone: ZoneBase) -> int:
	var n := 0
	for c in zone.world.get_children():
		if c is ConsumableDrop:
			n += 1
	return n


func _until(cond: Callable, frames: int) -> void:
	for i in frames:
		if cond.call():
			return
		await t.get_tree().process_frame


## Process frames (the director refreshes its stage there; after a heavy load
## Godot catches up on physics frames without any).
func _frames(n: int) -> void:
	for i in n:
		await t.get_tree().process_frame


## Phase 6: Act 1. The main chain step by step (Sigrun's talk at each turn),
## the gates the story seals, the side quests' choices and rewards.
func _act1() -> void:
	var hero: Player = lab.player
	var ql := QuestLog.of(hero)
	ql.from_dict({"v": 1, "act": 1, "beats": ["prologue_done", "runebound"], "done": ["p_ash_road"]})
	ql.bind(hero)
	var dui := lab.dialogue_ui
	_check(ql.start("a1_call") and dui.entry_for("sigrun", null, true) == "call", "Act 1 opens with Sigrun naming the shard")
	ql.event("talk", "sigrun")
	_check(ql.is_done("a1_call") and ql.is_running("a1_shards"), "Runebound -> What the Shards Sing")
	for id in ["shard_1", "shard_2", "shard_3"]:
		if not hero.collected.has(id):
			hero.collect(id)
	ql.event("collect", "")
	_check(ql.step_id("a1_shards") == "return" and dui.entry_for("sigrun", null, true) == "shards",
		"three shards found: Sigrun listens to them")
	ql.event("talk", "sigrun")
	_check(ql.is_running("a1_ashwick"), "-> The Bell of Ashwick")
	ql.event("reach", "ashwick", {"zone": "ashen_highlands"})
	hero.read_lore("lore.ghost.priest")
	ql.event("read", "")
	_check(ql.step_id("a1_ashwick") == "cord", "Ashwick reached, the priest heard: search the graves")
	ql.event("interact", "a1_cord")
	_check(ql.step_id("a1_ashwick") == "return" and dui.entry_for("sigrun", null, true) == "knot",
		"the keepers' cord: Sigrun knows the knot")
	ql.event("talk", "sigrun")
	_check(ql.is_running("a1_colossus"), "-> The Warden in the North")
	ql.add_beat("boss:colossus")
	_check(ql.is_running("a1_spire") and ql.step_id("a1_spire") == "enter", "the Colossus down -> The Empty Socket")
	ql.event("enter", "shattered_spire")
	ql.add_beat("boss:vessel")
	_check(ql.step_id("a1_spire") == "socket", "the Spire, the Vessel down: look at the socket")
	ql.event("interact", "a1_socket")
	_check(ql.step_id("a1_spire") == "return" and ql.seen.has("a1_socket") and dui.entry_for("sigrun", null, true) == "reveal",
		"the socket's camera pan; Sigrun hears it was opened")
	ql.event("talk", "sigrun")
	_check(ql.has_beat("act1_done") and ql.is_running("a2_soon") and dui.entry_for("sigrun", null, true) == "mentor",
		"End of Act I: Act II waits in the journal, Sigrun checks the script")
	# the gates the story seals
	var gate := DungeonGatePortal.new()
	gate.dungeon_id = "cistern"
	var probe := QuestLog.new()
	hero.set_meta(QuestLog.META, probe)
	probe.from_dict({"v": 1, "act": 1})
	var sealed := not gate.story_open(hero)
	probe.from_dict({"v": 1, "act": 2, "beats": ["act1_done"]})
	var opened := gate.story_open(hero)
	probe.from_dict({"v": 1, "act": 1, "beats": ["legacy"]})
	var legacy := gate.story_open(hero)
	probe.from_dict({})
	var none := gate.story_open(hero)
	gate.dungeon_id = "stormwatch"
	probe.from_dict({"v": 1, "act": 1})
	var storm := gate.story_open(hero)
	gate.free()
	hero.set_meta(QuestLog.META, ql)
	_check(sealed and opened and legacy and none and storm and Texts.t("lore.seal.story.body").contains("language model"),
		"the Cistern and the Warrens stay sealed until Act 1 ends (legacy and story-less heroes pass, the Stormwatch stays open)")
	# side quests
	ql.from_dict({"v": 1, "act": 1})
	ql.bind(hero)
	_check(dui.entry_for("edda", null) == "letter_offer", "Edda asks about her husband")
	ql.start("s_letter")
	hero.read_lore("lore.ash.letter_1")
	ql.event("read", "")
	_check(ql.step_id("s_letter") == "return" and dui.entry_for("edda", null) == "letter_back", "the letter found: back to Edda")
	var rings_before := _rings(hero)
	dui.try_open("edda", null, hero)
	dui.choose(0)
	await t.call(&"_wait_frames", 2)
	var ring := _rings(hero) > rings_before
	for c in lab.world.get_children():
		if c is ItemDrop and (c as ItemDrop).item != null and (c as ItemDrop).item.slot == ItemData.Slot.RING:
			ring = true
	dui.close()
	_check(ql.is_done("s_letter") and ql.choice("s_letter") == "truth" and ring, "telling her the truth ends it; his father's ring")
	dui.try_open("s_nameless_stone", null, hero)
	var names := dui.option_texts().size()
	dui.choose(1)
	_check(names == 4 and ql.is_done("s_nameless") and ql.choice("s_nameless") == "rune" and dui.current_text() == Texts.t("dlg.nameless.named.rune"),
		"the nameless grave gets a name (Rune - of course)")
	dui.close()
	_check(dui.entry_for("s_nameless_stone", null) == "is_rune", "and keeps it")
	ql.start("s_ten")
	for i in 9:
		ql.event("kill", "rusher", {"zone": "ashen_highlands"})
	var nine := ql.step_id("s_ten") == "kill" and ql.progress("s_ten") == Vector2i(9, 10)
	ql.event("kill", "grave_shambler", {"zone": "ashen_highlands"})
	ql.event("kill", "brute", {"zone": "ashen_highlands"})
	_check(nine and ql.step_id("s_ten") == "return" and Texts.t("quest.s_ten.summary").contains("ten"),
		"Ten Is a Good Number: ten raiders (not the dead) - nobody knows why ten")
	await t.call(&"_wait_frames", 2)
	for c in lab.world.get_children():
		if c is ItemDrop or c is GoldDrop or c is ConsumableDrop:
			c.queue_free()
	for id in ["shard_1", "shard_2", "shard_3"]:
		var at := hero.collected.find(id)
		if at >= 0:
			hero.collected.remove_at(at)
	for id in ["lore.ghost.priest", "lore.ash.letter_1"]:
		var at := hero.lore_read.find(id)
		if at >= 0:
			hero.lore_read.remove_at(at)
	ql.from_dict({})


func _rings(hero: Player) -> int:
	var n := 0
	for item in hero.equipment.inventory:
		if item.slot == ItemData.Slot.RING:
			n += 1
	return n
