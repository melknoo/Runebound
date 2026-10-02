# RUNEBOUND — Project State

Updated: 2026-10-01 · Milestone: **M12 Highlands with substance** (in
progress, below). **M17a Menus & settings** (pulled forward
from M17, all five phases built, below; the user's playtest is the gate). **M11 Three roles II (the root druid,
healer)** - all four phases built; the user's playtest is the gate. **M10 Three roles I (tank +
Elementalist + loadout)** — all four phases built, plus **M10b Healing
Draughts**; the user's playtest is the gate for both (still open, M11 started
alongside at the user's wish). M09 Co-op was played by the user and a
friend; M09b (friends without Tailscale) is deployed. M08 was played by the
user; the notes from that playtest were built on 2026-09-28. M07 and M07b were
accepted on 2026-09-24. Server laptop: [SERVER_SETUP.md](SERVER_SETUP.md).

## M12 Highlands with substance (in progress, 2026-10-01)
Plan with the user's answers: ROADMAP M12 (three sub-biomes - the abandoned
village in Westreach, the burnt forest in the north-west, the bone field on
Emberfall Ridge; two new enemy types per family; animals as scenery; food
gathered, a rest heal out of combat; one tome teaching each class a new
ability; all four outdoor puzzle kinds; trial shrines with rune blessings;
only the new texts bilingual, the first start follows the system language).
- **Phase 0 (built): the text table, the language, the lore window.**
  - `Texts` (`scripts/systems/texts.gd`): JSON tables
    `resources/i18n/m12_ui.json` / `m12_lore.json` (`{key: {en, de}}`)
    become one Translation per language in the TranslationServer, so a
    Label showing a key translates itself; `Texts.t(key, args)` for code. A
    missing German line falls back to the English one. Keys are dotted ids
    and never collide with the older English UI text.
  - Setting `general/language` (auto / en / de; own section, so the
    Gameplay tab's Reset leaves it alone) in Settings -> Gameplay with a
    hint that the menus follow later. Test runs read English.
  - `LoreUI` (`ZoneBase.lore_ui`): title + body of a lore id, follows a
    language switch while open, Esc / the interact key / X close it, one
    window at a time (in `close_windows`, closed by the other windows).
  - Smoke 614 green (every key in both languages, test runs in English, the
    switch translates a Label, the setting round trip and Reset, the lore
    window open / switch / close paths).
- **Phase 1 (built): the sub-biomes, their looks, the places that tell a
  story** (WORLD_DESIGN "The Highlands' sub-biomes", TECHNICAL_ARCHITECTURE
  "Sub-biomes (M12)").
  - Layout once for all of M12: three biome shapes, the pads and spurs of
    every new POI (village, braziers, graveyard, three trial shrines, two
    nests, two caves, the monolith puzzle, the dodge run; built in their
    phases), a secret climb (no trail) to the tome shelf, the forest's south
    edge at level 3, three new named areas (Ashwick, the Charwood, the Ribs
    of Emberfall) with DE/EN names. The old POI ids all stay (saves keep
    their map, camps and shrines). **Protocol 13** (both sides must stand on
    the same ground: ship a release before co-op).
  - Bake: `biome_mask.png`, the map tinted per biome, biome stamps, new
    layout rules. Terrain shader `use_biomes` with texture arrays; 18 new
    textures and three palettes; rocks, ruins and walls follow the mask.
  - Dressing: the forest (trunks with shadows on the new foliage physics
    layer, snags, logs, stumps), dead grass in the village, bones in the
    bone field; 16 new props; Ashwick's houses, well, fences and cart; the
    graveyard's graves; fallen soldiers, an abandoned camp, a cart, a
    barricade, a last stand, the giant skeleton and three rib sets.
  - Place names: overlapping areas show one name (the smaller place), a new
    name replaces the one on show and waits for the title card.
  - Shots `m12_highlands` (18). Perf (median of 3; the iGPU swings ~20 %
    between runs): interleaved `highlands_open` before M12 50.5 / 42.7 FPS
    vs M12 49.0 / 47.1 (no measurable cost); M12 scenarios `highlands_forest`
    45.5-54.6, `highlands_village` 48.9, `highlands_bones` 51.9 FPS; the
    trunks' shadows cost 0.2 ms GPU (`--ab=grove_shadows`).
  - Smoke 629 green (mask weights per camp, biome stamps, four looks per
    role, the forest off routes and clear of camps, the camera ignores
    trunks, bones only in the bone field, one area name, the set pieces).
- **Phase 2 (built): lore, ghosts, the chronicle, shards, gathering, food.**
  - `Interactable` (scripts/world/interactable.gd): the base of everything
    used with [E] (prompt text, can_interact, interact; ticks only within
    20 m of the local hero). **[E] focus:** of the prompts in reach only the
    nearest shows and fires (InteractPrompt; chests, shrines, portals and
    NPCs too).
  - **Lore:** 12 lore objects (graves, notes, a letter, two carved stones)
    and 2 ghosts (a pale, see-through figure without outline that fades in
    as you come near and turns to you; [E] Listen), all texts DE/EN; one
    rare meta break (the grave whose name the AI never wrote). The first
    read pays 15 XP (a ghost 20) and goes into the **chronicle** (key L, the
    lore window with a list: everything read, newest first, and the shards).
    Lore and ghosts show on the map once seen within 6 m, never on the
    compass.
  - **Rune shards:** 12 hidden off the paths (one on the secret climb), each
    with a faint teal gleam; taking one pays 25 XP + 15 gold and a line
    (`shard.<n>`); per character. The set's reward comes with the blessings
    (phase 6).
  - **Food:** the Ember Tuber (DE Glutknolle): 50 % health over 8 s, only out
    of a fight, a hit (dealt or taken) ends the meal, 10 in the bag. From 40
    rule-placed tuber patches (village gardens, forest edge, the ash; none in
    the bone field), a cooking pot in every raider camp (2 a time) and Ylva
    (12 gold). Patches and pots grow back / refill 15 min after use, per
    character, on every machine (no net traffic; personal food).
  - Save: `lore_read`, `collected`, `gathered` per character (read with
    defaults, no version bump).
  - New props lore_note, lore_tablet, rune_shard, ember_tuber_plant,
    cook_pot; icons ember_tuber, map lore / ghost; shots 19-23 in
    `m12_highlands`.
  - Smoke 649 green (texts complete, the nearest prompt wins, reading +
    XP once, the chronicle on L, a shard once, gathering + regrowth + a full
    bag, patches off trails and pads, the save keys, a ghost, the map; food:
    Ylva sells it, no eating in a fight, slow heal, a hit ends it, 50 % in
    8 s).
- **Phase 3 (built): shared puzzle state, the four puzzles, the grottos,
  the secret climb.**
  - `PoiPuzzle` (scripts/world/puzzles/): a hero `request`s, the authority
    (offline this machine, online the server) `act`s, keeps the state in the
    world (`SaveGame.pois`, beside the camps) and tells everyone; every
    machine `apply_state`s. Net: `POI_ACT` (client -> server, checked
    against the proxy's reach) and `POI_STATE` (server -> clients, replayed
    to late joiners); still protocol 13 (no release since).
  - **Braziers** (Ashwick's chapel): three; any hit lights one (a hurtbox on
    the enemy-hurtbox layer, `take_hit` gives no Resonance), each burns 10 s;
    all three at once open the crypt chest. Heroes can share the work.
  - **Monoliths** (the Crossroads): a crystal's beam runs stone to stone;
    [E] turns a stone an eighth; when all three face on, the seal lights and
    a chest appears.
  - **Boulder** (the tome shelf): push it by walking into it (or [E]) step by
    step along a fixed track onto the plate; the grotto's door sinks.
  - **Dodge run** (the bone field): six bone-spike strips burst in a rolling
    wave (red strip telegraph first) on the server's clock; a hit costs 14,
    never the last point; a chest at the end.
  - **Grottos:** two rock-hull caves with a roof (the hull gets its
    underside), 4.6 m inside for the camera, a light; one with a chest, the
    tome grotto sealed by the boulder puzzle (the tome comes in phase 7).
  - **Secret climb:** low stones along its downhill edge. Map icons puzzle /
    cave (secret ones only once found within 6 m), never on the compass.
  - Puzzle rewards: 60-80 XP to every hero within 25 m, the chest; reward
    notes travel as text keys (`@key`) and are shown in the receiver's
    language.
  - Smoke 657 green (a brazier lights from a hit and burns out, all three
    solve and persist, the beam stone by stone, the boulder and the door,
    the grottos, the dodge strip and the last point, the climb's stones).
    Net scenario `puzzles` green (two clients share the braziers, a late
    joiner sees them solved, the server keeps the state).
- **Phase 4 (built): the enemy seams and the village and forest families.**
  - Seams: one registry (`ZoneBase.ENEMY_IDS` / `make_enemy`, an unknown id is
    a rusher with a warning), `EnemyBase.loot_kind` (the drop tables read the
    tier, not the class), `targetable` + `set_targetable` (a buried, dormant
    or airborne enemy has no body on the enemy layer, no hurtbox and
    `take_hit` refuses; targeting, bots, the combat music and the druid's
    fight check skip it), five AIStates appended (BURIED, EMERGE, DORMANT,
    WAKE, BLINK). Heroes can be slowed now (`Player.apply_slow`, the
    stronger slow wins; an enemy hit with a Chill slows 40 % for 3 s).
  - **The Restless (Ashwick):** the **Grave Shambler** waits buried and claws
    out when a hero comes within 7 m (a ring telegraph, a burst), then rakes
    with both claws; the **Mourner**, a pale shrouded spirit, keeps its
    distance and screams down a strip (damage + the slow).
  - **The Charwood:** the **Cinderbark** stands among the trunks as one of
    them (solid, no target, a dim ember tell) until a hero comes within 6 m
    or a fight starts within 16 m, then slams (24, heavy) and leaves burning
    bark; the **Smoulder Wisp** spits embers and blinks away when cornered
    (never through a wall or a trunk).
  - Camp 3 holds the Restless, camp 8 and ruin 3 the Charwood; two
    cinderbark lurkers stand in the forest. Map labels per family (DE/EN),
    enemy names DE/EN.
  - Four rigs from `generate_characters_v2.py` (shambler, mourner,
    cinderbark, wisp; 5-6 clips each, timings from the scripts) and their
    palettes.
  - Solo check L6: Elementalist 13/13 (0 deaths), Druid 13/13 (also at L4);
    the Runebreaker bot clears the new camps but dies at ruin 3 after the
    whole run without healing between fights (KNOWN_ISSUES).
  - Smoke 667 green (rigs and timings, the registry, buried / dormant /
    awake, the scream's slow, the blink); net `enemy_types` green with all
    13 types as puppets.
- **Phase 5 (built): the bone field's family and the animals.**
  - **The carrion brood (Ribs of Emberfall):** the **Ash Jackal** hunts in a
    pack of three: it trots in a ring around a hero, crouches with its jaws
    open while a disc fills a leap ahead (where the hero stands), springs
    and bites. The pack takes turns (no two leaps at one hero within
    0.9 s), so it reads as a rhythm to dodge. The **Carrion Vulture**
    circles 6.5 m up, out of reach (no target, no hit, a shadow on the
    ground), throws its wings up while a lane fills toward a hero, swoops
    down it (the hero still in it is struck) and lands at its end: on the
    ground for 2.2 s, the moment to punish it, then it beats back up. Only
    heavy hits stagger it. In the air its body only stops colliding (it
    glides over rocks and trunks along the ground); its visual flies.
  - Camp 7 holds the brood (three jackals and a vulture; label "Carrion
    den"), a lone vulture lurks over the bones (lurker_b1). The elite
    raider patrol keeps its route through the field.
  - **Animals:** hares in the ash and the village, crows on the village's
    graves and the bone field, none in the burnt forest (`CritterField`:
    up to 8 around the local hero, 22-42 m out, rather where the camera is
    not looking; never in a combat pad's clearing). They graze or peck,
    then flee from any hero (puppets too): a hare sits up at 11 m and bolts
    in zigzag hops at 7 m, a crow takes off at 8 m and flies off. No body,
    no collider, no outline, never an enemy or a target, nothing on the
    net, none on the server. LookDev `critters` (perf A/B in the village:
    no measurable cost).
  - Two new rig templates (four-legged, winged; ART_BIBLE §7) and four rigs
    from them; sounds for the snarl, the screech and wing beats.
  - Fix from the solo check: an ambush wakes its cinderbarks at once (one
    spawned 6-9 m off the hero stayed a tree once the fight around it
    ended).
  - Solo check L6: camp 7 and the vulture lurker clear for all three
    classes (14 damage for the Elementalist and the Runebreaker, 28 for
    the Druid). Ruin 3 as in phase 4 (the Runebreaker bot dies there; the
    others clear it, the Elementalist 14/14 after the ambush fix).
  - Smoke 676 green (rigs and timings, the brood's camp, the vulture aloft
    and landed, the pack's turns and the leap, the animals' biomes, a hare
    bolting, a crow flying off); net `enemy_types` green with all 15 types
    as puppets.
- **Phase 6 (built): rune blessings, trial shrines, nests, the cursed graveyard.**
  - **Rune blessings** (`Blessings`, per character, saved as `blessings`):
    Ashwick +3 % maximum health, the Charwood +2 % damage, Emberfall +2 %
    movement speed (one per trial shrine), and +3 % maximum health for all
    twelve shards of the Shattered Rune. `Player.stat()` adds them like gear
    (`max_hp_pct` is new); the chronicle lists them.
  - **Trial shrines** (`TrialShrine`, trial_v / trial_f / trial_b): [E] at
    the altar wakes two waves of the sub-biome's family around it; clear
    them in 70-75 s, struck at most 4 times, and the shrine's blessing is
    yours. The server runs the waves and the clock (POI state, replayed to
    late joiners); every owner counts its own hero's hits and grants itself
    the blessing, so in co-op the one who took the hits misses out. Every
    hero near gets the clear's XP. Out of time (or nobody near for 6 s) the
    wave is dismissed; an ended trial rests 20 s, then anyone may take it
    again. The HUD shows the time left and the hits under the compass.
  - **Nests** (nest_f: the Charwood's smouldering stump, nest_b: the jackal
    den): immobile objects that breed - while a hero is near and fewer than
    three of their brood live they swell (smoke and glow, 1.2 s) and let
    one out, eight in all. A nest is a camp of its own (it comes back after
    the camp respawn time) and drops like a brute.
  - **The cursed graveyard** (`CursedGround`, graveyard_v): while its three
    curse lanterns burn (a camp of three that never comes back), every heal
    a hero receives on its ground heals 30 % less, a sickly mist hangs over
    it and the dead rise from the graves near the heroes (up to three
    buried shamblers). Break the lanterns: the curse lifts for good, the
    risen fall, the priest's ghost appears and tells why he cut the bell
    rope (DE/EN).
  - Seams: `HealthComponent.heal_mult`, `EnemyBase.immobile` (no knockback,
    no shove) and `_setup_prop_visual` (an object that fights wears a kit
    prop with the character outline), `EnemyBase.dismiss()` (gone without a
    death on every machine), `EncounterSpawner.spots` (fixed places),
    `loot_kind` `none`, hidden interactables show no prompt.
  - Four props (trial altar, curse lantern, wisp nest, jackal den), three
    map icons (trial, nest, cursed) and their legend rows.
  - Smoke 684 green (blessings and the save, the heal cut, the graveyard
    from curse to priest, a nest breeding, a trial passed, struck and out
    of time, the shard set, every text formats alike in DE and EN); net
    scenario `trial` green (c1 passes, c2 is
    struck past the limit and gets nothing, the server keeps the shrine).

## M17a Menus & settings (pulled forward from M17, built 2026-10-01, the user's playtest is the gate)
The user found that picking a character on the title went straight into a
solo game, and that the game had no Esc menu and no settings. Plan with the
user's answers: ROADMAP M17a (character first, then Play solo / Play
online; Esc pauses solo only; audio, video, mouse and camera, comfort and
key rebinding; a campfire scene behind the title with the character's own
rig; English; the character's name online; developer tools off by default).
- **Phase 1 (built): settings core + window.**
  - Autoload `GameSettings` (`user://settings.cfg`, sections audio / video /
    controls / gameplay next to `ClientSettings`' coop; load -> set -> save
    per change). Volumes ride on `Sfx.BUSES`' mix levels (Effects = SFX +
    Telegraph); window mode / size, VSync, FPS limit, an FPS counter; mouse
    sensitivity, invert Y, zoom speed (`CameraRig.look`); screen shake
    (scales trauma and impulses), the red hit flash, damage numbers; the
    developer tools gate F1 and J and the title's playtest line (`-- --dev`
    or a test run turns them on; `run_godot play` / `coop` pass `--dev`).
    Headless and test runs use the defaults and never touch the file.
  - `SettingsUI` (tabs Audio / Video / Controls / Gameplay, live, "Reset
    tab"), opened from the title's new "Settings" button. New UI kit pieces
    in `tools/texgen/ui.py` (slider knob, checkbox) and UiTheme styles for
    sliders, checkboxes and scroll bars.
  - Title look review: `-- --snap=<png> --snap-page=<page>` (a test-run flag).
  - Smoke 576 green (bus math, file round trip with the coop section kept,
    sensitivity / invert / zoom / shake / flash / damage numbers, the dev
    tools gate, the settings window on the title).
- **Phase 2 (built): the Esc menu.**
  - `PauseMenu` (CanvasLayer 12, runs while paused): Resume, Settings, Save
    and return to title, Save and quit. Solo it pauses the tree; online
    ("MENU", "Online on Acer - the world keeps moving") it only locks the
    hero, "Leave the server" / "Leave and quit" (`Net.leave(quit)`, a
    voluntary leave shows no warning on the title). Solo it also opens when
    the window loses focus (setting; never on test runs).
  - Esc: an open window closes first (the menu sits before the windows in
    the tree), else the menu opens; windows close on Esc even under the F1
    panel; the hero's cursor toggle is gone; window hotkeys, Tab and the
    zoom stay quiet under the menu (`PauseMenu.showing`).
  - Pause hygiene: music and UI sounds play on (`PROCESS_MODE_ALWAYS`),
    gameplay timers wait out a pause. Closing the window saves whenever a
    hero is in the scene.
  - `ZoneBase.close_windows / return_to_title / quit_game`; shot list
    `m17a_menus` (the menu, its settings), shot actions `pause_menu`,
    `pause_settings`.
  - Smoke 585 green (Esc routing, pause, no hotkeys under the menu, settings
    from the menu, the way back saves the hero's health); net `handshake`
    (c2 opens the menu online - nothing pauses - and leaves through it) and
    `server_gone` green.
- **Phase 3 (built): the main menu.**
  - Flow (`title_screen.gd`): main = Continue (the last character the way
    it was last played: "Solo - Runehold" or "Online - Acer", from
    `ClientSettings` `last_mode`), Characters, Settings, Quit. Characters =
    the list (click selects), Play solo / Play online / Delete (two clicks) /
    New character; Create returns to the list with the new one selected.
    Online = the server dropdown and code as before; the party sees the
    **character's name** (the "Your name" field is gone; an unnamed
    character is asked once, `SaveGame.rename_character`). A refused
    Continue lands on the online page with the reason.
  - Backdrop `TitleBackdrop` (a ZoneBase with `_is_backdrop`: look, props,
    StyleManager grading and music only): a camp at the Highlands' edge at
    night (`ZoneLook.title_night`, bonfire as the key light, log seats,
    charred trees, a rune monolith, ash fall, the Spire on the horizon),
    slow camera drift, Runehold's music. `HeroPreview` shows the selected
    character's own rig by the fire; a new pick plays its signature move
    (war cry, frost nova, bloom). `ArtKit.dress_rig` is shared with the NPCs.
    The menu sits left on CanvasLayer 5, above the post layer.
  - Found: freeing an outlined rig together with its materials made the
    renderer log "material is null" (the preview drops its materials first;
    KNOWN_ISSUES asks whether enemy deaths do the same).
  - Title snaps in `captures_shots/m17a_menus/` (main, characters, create,
    online). The title's `--connect=` auto-join (run_godot coop) still joins.
  - Smoke 595 green (the backdrop and its rig follow selection and class,
    Create selects, the name rule online, Continue's mode line, Delete, Esc
    back).
- **Phase 4 (built): key bindings.**
  - `KeyBindings`: 22 actions in three groups (movement, combat - basic
    attack and the four loadout slots -, interface; the playtest key only
    with the developer tools), two bindings each, keys or mouse buttons.
    The defaults are the InputMap after `InputSetup.ensure()` (now applied
    once per run, so a zone load keeps the player's keys); changed ones go
    to `[keys]` in settings.cfg. A key given to one action leaves the action
    that had it ("Not bound" in red). Esc and F1 stay reserved.
  - Controls tab: click a binding, press the new key or mouse button; Esc
    cancels, Delete clears; "Reset tab" puts every key back.
  - Labels follow: HUD slots, the hero window's tabs, the [E] prompts, the
    talent toast, the party banner's cancel key, the trainer's loadout hint;
    keys show in the keyboard layout's own letters.
  - Smoke 605 green (defaults, a move, a conflict, Esc refused, relabelled
    HUD and tabs, save and reload, reset; the Controls tab by key events).
- **Phase 5 (built): wrap-up.** TECHNICAL_ARCHITECTURE "Menus and
  settings (M17a)" (and the autoload list), KNOWN_ISSUES "M17a open items",
  the J list got a group "M17a: Menüs & Einstellungen" (14 points; the
  server-dropdown point now starts from "Play online"). Smoke 605 green,
  the whole net suite green (24 scenarios incl. the WebSocket ones).
- **No protocol change:** the server needs no new release for M17a (the
  user may still ship it so friends get the menus: `tools
un_godot.cmd
  release`).
- **Gate walk (user):**
  1. `tools
un_godot.cmd play`: the campfire scene. Continue (the line
     under it says how), or Characters -> pick one (the figure by the fire
     changes) -> Play solo.
  2. In Runehold press Esc: the world stops, the music plays on. Settings:
     a volume, the mouse sensitivity, Controls -> rebind a key (e.g.
     Interact) and look at the [E] prompt; Gameplay -> screen shake.
     "Save and return to title".
  3. Characters -> Play online -> Acer (or `tools
un_godot.cmd coop`):
     Esc online - the world keeps moving -> "Leave the server".
  4. Settings from the title: window mode / FPS limit, then restart: is
     everything kept?
  5. The J list, group "M17a: Menüs & Einstellungen" (developer tools: on
     with `run_godot play`, else Gameplay -> Developer tools).

## Co-op: server dropdown and the version refusal (2026-10-01)
- **Why the join failed on 2026-09-30:** the laptop server runs the
  `release` branch, which was still at the M09b state (protocol 8) while
  `main` was at 12 (M10, M10b, M11). The refusal told the (newer) game to
  `git pull`. Now `Net.version_reason` names the side that is behind, and
  `release` was shipped (`tools
un_godot.cmd release`).
- **Server dropdown** (user: pick the Acer by an alias, room for more
  servers): `resources/net/servers.json` + `ServerList`, the Join page shows
  names only, "Other address ..." for LAN / local servers
  (TECHNICAL_ARCHITECTURE "Server list"). Playtest point `c_server_pick`.

## M11 Three roles II: the root druid (built 2026-09-30, the user's playtest is open)
Plan with the user's answers (8 pool abilities + LMB now, the rest from
M12-M14; **Sap** is a pool that refills **only in a fight**; LMB **Thorn
Volley**; **health and Sap travel with the hero** - only death, draughts,
heals and the Runehold hearth refill them; **heals threaten a little**):
ROADMAP M11, CLASS_DESIGN "Root druid".
- **Phase 1 (built): the healing groundwork and the class skeleton.**
  - Heals on allies: `Player.receive_heal`, heals over time (`add_hot`),
    timed buffs (`add_buff`, added to `stat()`), `heal_pct`. They travel as
    HERO_FX `ally_heal / ally_hot / ally_shield / ally_buff` with a hero ref
    (`ZoneBase.hero_ref / hero_by_ref`: the peer id in co-op, the index
    offline); only the target's owner applies them (the M10 rule).
  - The heal target (`Player.pick_heal_target`): the ally under the
    crosshair (`TargetingSystem.ally_under_aim`, geometry - remote heroes have
    no collision), else the lowest health share within 30 m, else the healer.
    A green chevron marks it; the party frames colour its name.
  - Heal threat (`ZoneBase.heal_threat`, authority): half of what was healed,
    split over the enemies within 30 m that already fight the party; overheal
    counts nothing. Offline the HeroFx entry books it, in co-op the server
    when it relays the heal.
  - `ClassData.resource_mode` BUILD | POOL + `resource_regen`: a pool starts
    full and refills only while the hero is in combat or an enemy within 30 m
    hunts someone (a healer who only heals is neither hitting nor hit).
  - Vitals: the character dict keeps `vitals {hp, resource}`; the zone
    restores them after the spawn (travel no longer heals). Runehold's hearth
    heals 10 %/s (and refills Sap) out of combat within 6 m.
  - Co-op: the barrier rides in HERO_STATE and the snapshot hero rows (party
    frames show it as a light segment); remote heroes' nameplates got a slim
    health bar. **Protocol 12.**
  - The class: `resources/classes/druid.tres` (95 health, Sap 100, 5/s in a
    fight), `DruidHero` with Thorn Volley (3 thorns, held auto-fire) and
    Mending Bloom (30, 14 Sap) as the start kit, on the Elementalist's rig
    tinted moss green until its own rig exists. Hild Ashroot, the druid
    trainer, stands by the south wall west of the spawn. Colour role
    `nature` moved into art_spec.json; all nine druid icons (ui.py) and
    sounds (sfxgen, appended) exist already. Bots heal the most wounded first.
  - Tests: smoke 542 green (Sap, the three target rules, heals / HoT / shield
    / buff on an offline ally, heal threat and overheal, thorns, vitals in
    the save and across travel, the hearth, Hild); net scenario `heal` (a
    druid client heals and shields a tank client across the server, the
    server sees the heal's threat).
- **Phase 2 (built): the kit, talents, legendaries.**
  - The seven trainer abilities (CLASS_DESIGN "Root druid"): Barkskin,
    Regrowth, Root Grasp, Renewal Grove, Thornfield, Totem of Growth, Wild
    Bloom. `RenewalGrove` and `GrowthTotem` exist on every machine and heal /
    buff the heroes it simulates (like the Warding Rune); `ThornField` has a
    visual-only copy for puppets (like the Flame Wall). Zone heals make no
    threat; the targeted ones do.
  - Talents Growth / Thorns / Grove (24 nodes, 72 in all); legendaries
    Heartwood Idol, Ashbloom Seed, Thornmother's Crown; affixes `heal_pct`,
    `sap_regen_pct`, `hot_dur_pct`; druid item names (Rootstaff, Barkmail,
    Antler Crown ...); the character sheet reads heals as heals.
  - Bots: the healer heals first, then Thorn Volley, Root Grasp, Thornfield,
    the totem and (close up) Wild Bloom. Without a camera a zone lands on the
    enemy nearest the aim line (it always landed at full reach before, and a
    druid bot stood stuck at a ruin wall for 90 s).
  - Solo check: druid L4 11/11 fights, 0 deaths (144 damage taken, healed
    itself). Smoke 554 green; `net heal` green. The server probe now writes
    its result aside and renames it (one run read the file while a rewrite
    had emptied it).
- **Phase 3 (built): the rig.** The user approved the look (2026-09-30,
  live preview `captures_shots/m11_druid/_look_preview.png`). `druid.glb` +
  its atlas from `build_druid` / `druid_clips` (13 clips: thorn, mend, bark,
  regrowth upper-body; root_grasp, grove, totem, bloom full-body; idle, run,
  dodge, flinch); the class and Hild wear it. Shot list `m11_druid` (11).
- **Phase 4 (built): wrap-up.**
  - Solo check L6: druid 11/11 (0 deaths, 156 damage, healed itself),
    Elementalist 11/11, Runebreaker 10/11 or 11/11 (the Colossus kills the
    bot tank about one run in three - the same on the build before M11,
    KNOWN_ISSUES "M11 open items").
  - Docs: CLASS_DESIGN "Root druid", PROGRESSION_DESIGN (talents, Hild),
    ITEMIZATION, TECHNICAL_ARCHITECTURE "Healing and allies (M11)",
    ART_BIBLE (roles, druid shape language), KNOWN_ISSUES; the J list got a
    group "M11: Druide & Heilen".
  - **Gate walk (user):**
    1. Title -> "New character" -> Druid. In Runehold find Hild Ashroot
       (south wall, west of the spawn), learn Barkskin, set the loadout (K).
    2. Highlands camps alone: Thorn Volley on LMB, heal yourself, watch the
       Sap refill only while fighting.
    3. Travel hurt to Runehold: the health stays; rest by the hearth.
    4. Co-op (a friend or `tools\run_godot.cmd coop`: the second bot is a
       druid): aim at a hurt ally and heal - the green chevron shows whom;
       the party frames show the shield.
    5. The J list, group "M11: Druide & Heilen".

## M10b Healing Draughts (built 2026-09-30, the user's playtest is open)
The M10 solo check found no healing between fights; the user decided (2026-09-30):
**no regeneration out of combat**, healing from consumables instead - now,
as a small M10b; drunk **only from the inventory**; healing **over a few
seconds**; from **drops, chests and a merchant**.
- **Healing Draught:** 35 % of the maximum health over 4 s, one at a time,
  5 in the bag (no inventory slot). Right-click in the inventory (I) drinks;
  the HUD counts them next to the gold.
- **Sources:** kills (5 % trash, 15 % brute, 30 % elite, a boss always 2),
  chests (60 %), and **Ylva Ashbrew**, south-west of the hearth in Runehold,
  for 30 gold. On the ground: a red flask that glides into the bag like gold
  while there is room. Co-op: personal loot in GRANT (protocol 11); other
  players see the drinking (HeroFx "drink").
- New colour role `health` (#D8404A, the HUD bar's red) for the flask, the
  icon and the motes; sounds `potion_drink`, `potion_pickup` (sfxgen).
- Tests: smoke 517 green (shop, cap, drinking over time, drops and a full
  bag, the save, the inventory row, the HUD); shots `m10b_draughts`.
- User note (2026-09-30): the screen flashed red while drinking - the HUD's
  hurt flash fired on every health change below full; now only on a loss.
- **Gate walk (user):** Runehold: Ylva ([E] Trade) south-west of the fire,
  buy two draughts. The Highlands: take a few hits in a camp, then I ->
  right-click the draught. Watch for dropped flasks after kills and in
  chests. The J list, group "M10: Klassen & Heiltränke" (the draught points).

## M10 Three roles I (in progress, 2026-09-29)
Plan with the user's answers (8 abilities per class now, the rest from M12-M14
sources; block = hold + parry; the Elementalist builds and spends **Aether**;
**one world per character**): CLASS_DESIGN "Three roles", ROADMAP M10.
- **Phase 1 (built): chassis, loadout, characters.**
  - Classes are their own hero scripts: `Player` is the shared chassis,
    `RunebreakerHero` (Rune Cleave, Earthbreaker, Runic Guard, Resonance
    Burst) and `ElementalistHero` (new **Rune Bolt** on LMB, held for
    auto-fire, plus Ember Lance, Storm Step, Chain Spark, Fracture Rune).
    `Player.create(class_data)` makes every hero (TECHNICAL_ARCHITECTURE
    "Classes and the loadout").
  - **Loadout:** LMB = basic attack, Space = dodge, four free slots RMB / 1 /
    2 / 3 (keys 4-6 are free again). New abilities take the first free slot;
    swapping in the hero window's **Abilities tab (K)**, only out of combat.
    The HUD always shows six slots.
  - **Characters:** title screen "Characters" (list, play, delete with a
    second click) and "New character" (class + name). SaveGame **v6**: every
    character has its own world (flags, camps, zone). The migration refunds a
    Runebreaker's four elemental spells as gold (toast on the next zone).
  - **Two trainers** in Runehold: Sigrun (Runebreaker, north-west) and Maren
    Emberwright (Elementalist, east wall by the spawn; Ember Lance L2 50 g,
    Storm Step L3 150, Chain Spark L4 275, Fracture Rune L5 400).
  - **Talent trees per class** (48 nodes): tank Bulwark / Earthshaker / Runic
    Warden, Elementalist Storm / Ember / Frost (every node works since
    phase 3).
  - Items follow their ability's class (four spell legendaries to the
    Elementalist, the tank keeps Glacier Heart and Emberheart Plate; boss
    legendaries roll per hero class; staves and robes for the Elementalist).
  - The Elementalist has 85 health, the tank 100 (120 since phase 2). New
    colour role `aether` (#F06AC8).
  - Bots play their class (the caster keeps its distance); `run_godot coop`
    brings a tank and an Elementalist companion. Net protocol 9.
  - Tests: smoke 461 checks green (loadout rules, both trainers, v5 -> v6
    migration, characters on the title screen, the class swap); the
    harnesses (shots, perf, stress, captures) switch the hero to the class of
    the ability they ask for (`ZoneBase.debug_hero_for`).
  - Found on the way: a headless boot without a test flag used the player's
    real save (it migrated the user's save to v6 early; backup
    `runebound_save.backup_2026-09-29_m10.json`). Headless runs without
    `--save=` now use `user://headless_save.json`.
- **Phase 2 (built): the tank.**
  - **Threat:** enemies hunt whoever threatens them most (the tank's damage
    counts double, a new favourite needs 10 % more); taunts pull at once and
    hold; in a party a red "!" marks the enemies after you (co-op: the server
    tells the clients, `ENEMY_TARGET`).
  - **Rune Wall:** hold to block (frontal hits -75 %), the first 0.3 s parry
    (no damage, a staggering counter on the striker, even on a caster whose
    bolt it was). New `block` clip on the rig (the brace, held) and a
    translucent ward in front.
  - **Rune Challenge** (war cry, new `challenge` clip), **Warden's Leap**,
    **Rune Chain** (pulls, heavy foes hold their ground), **Warding Rune**
    (allies inside take 25 % less); Sigrun sells all five (L3-L7). The tank
    has 120 health now.
  - Every Bulwark / Earthshaker / Runic Warden talent works (Shield Wall,
    Provoker, Riposte, Bastion, Unyielding, Quake Leap, Tectonic, Steadfast,
    Binding Chains, Aegis of Runes); new tank legendary Warden's Oath.
  - Tank bots block wind-ups aimed at them, shout at groups, leap and chain
    at range. Protocol 10.
  - Fixed: the Hollow Warden halved frontal hits twice in co-op; the base
    health of a class was lost on the first gear change.
  - Tests: smoke 485 green; net scenario `threat` (the caster pulls a dummy,
    the tank's war cry takes it away, both clients see the change).
- **Phase 3 (built): the Elementalist.**
  - **Own rig** (`elementalist.glb`, modelgen): steel-blue coat, teal mantle,
    gold circlet, rune rod with an Aether crystal; 13 clips (idle, run, dodge,
    one per spell, flinch). The blue-tinted Runebreaker stand-in is gone.
    Maren in Runehold wears it too. Look preview for the user:
    `captures_shots/m10_classes/_look_preview.png`.
  - **Four new spells** (Maren sells them, L6-L9): **Frost Nova** (25 Aether,
    a 5 m Chill ring), **Flame Wall** (a 6 m line of fire at the aim),
    **Ball Lightning** (a slow orb that zaps and Shocks), **Ember Fall**
    (40 Aether, a telegraphed meteor on the aim, HEAVY stagger + Burn). Icons
    (ui.py), SFX (sfxgen), HeroFx copies on the other screens in co-op.
  - **Frost branch works:** Deep Freeze and Absolute Zero root (new status
    `root`, on the wire as `ST_ROOT`), Cold Snap stretches the Chill (the hit
    carries `chill_bonus`), Echo Rune bursts the Fracture Rune twice; Ember's
    Cinderfall leaves burning ground.
  - Elementalist bots use all eight spells (Frost Nova when a pack is close,
    the rest from range).
  - Tests: smoke 500 green (every new spell and Frost talent); the whole net
    suite green.
- **Phase 4 (built): wrap-up.**
  - **Shots** `tests/shots/m10_classes.json` (17: the Elementalist from three
    sides and each spell, the tank's wall, war cry, leap, chain and ward, the
    loadout tab). They showed Flame Wall too faint and Ember Fall's rock too
    white; both were fixed in phase 3's commit. Shot lists can now switch
    the class per shot, cast any ability and fill a slot.
  - **Solo check** (`tools\run_godot.cmd solocheck <class> [level]`, a bot
    hero alone through the 10 stationary Highlands camps, then the Colossus;
    trainer kit of its level, rolled gear, no talents):

    | | level 6 | level 4 |
    |---|---|---|
    | Elementalist | 11/11 won, 0 deaths, 89 s, 88 damage taken (0.7 bars) | 11/11, 0 deaths, 106 s, 76 (0.7) |
    | Runebreaker | 11/11 won, 0 deaths, 78 s, 372 damage taken (2.4 bars) | 11/11, 0 deaths, 83 s, 356 (2.4) |

    The Colossus falls in 13-19 s either way. Two points it raised: there
    is no healing between fights (the user, 2026-09-30: no regeneration,
    consumables instead - planned), and the Colossus may be too easy
    (KNOWN_ISSUES "M10 open items"). The check found a bot stall
    (a caster and an enemy caster on either side of a ruin wall); casters
    now walk in when a wall blocks their line.
  - **Perf** (interleaved A/B against the state before M10, `highlands_open`,
    median of 3 each): before M10 55.7 FPS / GPU 16.5 ms (runs 55.7, 57.8;
    a cold first run of 48.1 left out), M10 with the Elementalist's full
    rotation incl. the four new spells 56.4 FPS / GPU 16.2 ms (55.9, 56.4,
    60.1): no measurable cost. Both builds ran below the M08 value (66.3 FPS)
    on this day and rose from round to round - the machine, not the build;
    the interleaving takes that out.
  - Playtest log (J): new group "M10: Klassen & Heiltränke" (17 points in
    M10, 4 more with M10b).
  - **Gate walk (user):**
    1. Title -> "Neuer Charakter": an Elementalist. Runehold: Maren at the
       east wall by the spawn; Rune Bolt held down, buy Ember Lance (L2).
       The four new spells need levels 6-9: F1 -> [L] learns the whole kit
       (or play there). K: swap the slots around. The Highlands: a camp from
       range, Frost Nova when they reach you, Ember Fall on a group.
    2. Title -> "Charaktere": your old Runebreaker (it has the gold for its
       four spells already - 2,442 gold; the refund toast was used up by the
       test boot that migrated the save early) or a new tank; its own world.
       Sigrun: Rune Wall (L3). Hold RMB against a brute's wind-up, tap it
       just before the hit for a parry.
    3. `tools\run_godot.cmd coop` (a tank and an Elementalist companion):
       a camp as the tank - do the enemies stay on you (the red "!")?
    4. The Colossus as the Elementalist, alone.
    5. The J list, group "M10: Klassen & Heiltränke"; the look of the Elementalist
       (the preview sheet above).
- **Tooling:** the live Blender loop (`tools/modelgen/live.py` through the
  Blender MCP: build, pose, screenshot) is there for poses and silhouettes;
  whatever it finds goes back into the generator script, the only model
  source. M10's rig and clips were checked on the generator's contact
  sheets (`captures_contact/`) and the in-game shots.

## Direction after M09b (user decisions 2026-09-29)
The user likes the setting, the music and the atmosphere; what is missing
is substance. Eight rounds of questions settled four points, recorded in
ROADMAP "Spieler-Leitlinien" and the design docs:
- **Three classes + loadout first** (new M10: Runebreaker becomes the tank
  with threat + taunt, an elementalist takes over the elemental spells; M11:
  a root druid heals). 4 free slots (RMB, 1, 2, 3) out of about 12 per
  class. [CLASS_DESIGN](CLASS_DESIGN.md) "Three roles".
- **The Highlands with substance** (M12: sub-biomes, POI types, animals,
  enemy families, secrets + lore, places that tell a story) and **dungeons
  with puzzles** (M13, plus co-op dungeons for 3–5 players, locked solo).
  [WORLD_DESIGN](WORLD_DESIGN.md) "Planned".
- **Story with meta seasoning** (M14): dark story, rare explicit and loving
  "written by an AI" breaks, answer options, German + English.
  [STORY_DESIGN](STORY_DESIGN.md).
- **Icons stay with the generator** (decided 2026-09-29): the same three
  motifs were made both in `tools/texgen/ui.py` and with PixelLab, and the
  user liked the generator's best. New ability icons are drawn in `ui.py`
  as their abilities arrive (M10 tank + elementalist, M11 druid with a
  `nature` colour role). Results and costs: ROADMAP "Icon-Quelle".
Old numbers: M10 Open World II is now M15, M11 Story is M14, the second
class (M12) became M10/M11, Endgame M16, Release polish M17.

## Auto-deploy and the playtest log (built 2026-09-28)
- **Auto-deploy** (user: "no more SSH restarts"; with players online a
  5-minute countdown): `runebound-deploy.timer` every 5 min, rollback and
  hold on a failed start, `tools\run_godot.cmd deploy` / `sudo systemctl
  start runebound-deploy` without a password (SERVER_SETUP "Updates:
  automatisch"). Needs one more `sudo tools/server/setup-service.sh` on the
  laptop (done 2026-09-28: timer active, the password-free manual run works).
  Net scenario `deploy_notice` green.
- **Release branch** (user: "only a new commit on e.g. release restarts
  the server"): the server follows `release` (`RUNEBOUND_BRANCH`), main
  keeps moving; ship with `tools\run_godot.cmd release`. Friends clone
  `-b release`. The laptop switched over on 2026-09-28.
- **Playtest log** (key J, user: "a quest log for the open KNOWN_ISSUES
  points, to tick off"): 50 points in 7 groups (German), states offen /
  passt / Problem + note, saved per machine in `user://playtest.json` (Claude
  reads it on the dev PC: `%APPDATA%/Godot/app_userdata/RUNEBOUND/playtest.json`).
  The title screen shows how many are open. Smoke 427 green.

## M08 notes (the user's playtest notes, built 2026-09-28)
The six notes from the user's M08 playtest, with his choices (sprint free
but out of combat only; drops "deutlich" fewer):
- **Dodge ("still hit after dodging out of the field"):** the real hit zones
  were bigger than the red markers (a sphere against the 0.5 m hurtbox; the
  colossus charge 2.0 m wide and past its lane; the nova where the elite had
  walked; the assassin sliding 1.6 m) and enemies kept turning after the
  marker. Now an attack hits exactly its marker (TECHNICAL_ARCHITECTURE,
  enemy rule): `EnemyBase.lock_strike` / `strike_circle`, the charge lane
  stays drawn during the run, co-op `HURT_MARGIN` 1.2 -> 0.3. Input: a dodge
  pressed during the cooldown or a hit freeze is buffered and fires from
  MOVE; Space without a direction dodges away from the nearest enemy.
- **Sprint:** Shift, x1.45, only when no hit was taken or thrown for 3 s
  (`Player.in_combat`); a toast says why when held in a fight.
- **Unequip:** "Unequip" in the item panel, right-click on worn gear (and
  right-click equips from the bag); a full bag refuses with "Inventory full"
  (also when walking over loot); equip / unequip / discard save at once.
- **Waypoint map:** the travel panel shows the zone map (`ZoneMapView`, also
  used by the M map) with the known shrines; hovering a name lights its
  shrine, clicking an icon travels. Runehold has no map (list only).
- **Drops:** kill drop 8 / 30 / 60 % (trash / brute / elite), legendaries
  0.3 / 1 / 5 %, chests 1-2 items; all in `ItemGenerator`'s loot tuning
  (docs/ITEMIZATION.md). Boss legendaries stay guaranteed.
- **Portal titles:** body size, shown within 22 m (the three arena gates
  14 m).
- Smoke 424 green.

## M09b Friends without Tailscale (in progress, 2026-09-25)
The user wants friends to join without installing Tailscale, the laptop to
stay the server, no paid relay (Hetzner) and no tunnel service (playit.gg).
Starlink lets nothing in (CGNAT for IPv4, the router blocks inbound IPv6), so
the plan (approved 2026-09-25) is **Tailscale Funnel**: a public HTTPS name
for the laptop, relayed over the laptop's own outbound Tailscale link, no
port opened, TLS ends on the laptop. Funnel carries TCP only, so the game
gets a WebSocket path next to ENet. Access control moves into the game:
personal **invite codes**. The service moves to its own sandboxed user.
- **Phase 1 (built):** invite codes in the handshake (TECHNICAL_ARCHITECTURE
  "Access (M09b)"): `NetAuth` (HMAC challenge-response, nothing decoded
  before the MAC checks out), protocol 8, KICK, a waiting room of 8
  unverified connections, `server_relay` off, the title's "Invite code"
  field (remembered per server), `tools/server/invites.sh`,
  `RUNEBOUND_INVITES=/etc/runebound/invites` in server.env. Without an invite
  list a server is open and binds 127.0.0.1. Smoke 412, net 17 scenarios
  green (new: `invite`, `invite_live`, `auth_garbage`).
- **Phase 2 (built):** WebSocket transport next to ENet
  (TECHNICAL_ARCHITECTURE "Transports (M09b)"): a bare server name means
  wss://<name>/ (the Funnel address), `host:port` / IPs stay ENet; the WS
  server binds 127.0.0.1 and needs an invite list; NetWorld draws 150 ms
  behind over WS; WS clients ping with ECHO. Net scenarios: 21 green (17 over
  ENet, `handshake`, `invite`, `travel`, `server_gone` also `@ws`), smoke
  green.
- **Deployed 2026-09-28:** the user ran `setup-service.sh`, created codes
  and joined over Funnel **with Tailscale switched off** on his PC. Public
  probes from outside the tailnet: no code -> "needs an invite code", an
  unknown code -> "not accepted". Checked over SSH: runebound-egress and
  runebound-server active, 0 restarts, the game runs as `runebound` from
  /opt/godot (170 MB RSS), `systemd-analyze security` 1.4 "OK" (server) /
  1.5 "OK" (update), Funnel https:443 -> 127.0.0.1:7780, journal shows the
  join, both refusals and idle ticks p95 0.1 ms. Egress rules checked by the user
  (`sudo runebound-egress status`): DNS accepts above the IPv4/IPv6 REJECT for uid 997 (runebound). Gate left: a friend joins.
- **Phase 3 (built, deployed 2026-09-28):**
  `sudo tools/server/setup-service.sh` moves the server to the system user
  `runebound` (own HTTPS clone, Godot in /opt/godot, `/etc/runebound/invites`
  owned by the user), units `runebound-update` (pull + import) and
  `runebound-server` (sandbox, `IPAddressAllow=127.0.0.1 ::1`,
  `systemd-analyze security` offline 1.3 "OK" instead of 9.2 "UNSAFE"),
  `runebound-egress` (iptables: the server user opens no new localhost
  connections, only DNS for git), Funnel `--bg 7780`, drops the old
  7777/udp rule. server.env: `RUNEBOUND_TRANSPORT=ws`, port 7780. Godot
  runs under the seccomp filter and W^X (tested on the laptop).
  SERVER_SETUP rewritten; home network details are out of the public docs.
- **Phase 0 (measured 2026-09-28, passed):** `tests/ws_spike.gd`,
  `run_godot wsspike <host> [secs]` (echo 30 x 900 B/s for 5 min, then a
  200 KB/s download). Work PC (company network) -> Funnel relay
  (185.40.234.x) -> Starlink -> laptop: RTT **p50 62 / p95 90 / p99 173 /
  max 451 ms**, 19 of 9000 answers over 250 ms, 1 stall (339 ms), download
  the full 200 KB/s (min 180). Threshold was p95 <= 150 ms. For comparison
  the same PC over the tailnet (DERP relay "fra"): p50 55 but p95 669 ms and
  stalls up to 14.6 s. Localhost baseline: RTT 7 ms. Findings: a freshly
  enabled Funnel needs ~10 min to show up in public DNS; on a tailnet PC
  Windows answers *.ts.net from Tailscale even with `Resolve-DnsName
  -Server` (NRPT), so `wsspike` resolves over DNS-over-HTTPS.
- **Deploy note:** the laptop keeps running the M09 build until its next
  restart; after one it serves WebSocket on 127.0.0.1 and waits for its
  invite list. Games from protocol 8 on cannot join an M09 server (and vice
  versa).

## M09 Co-op (2026-09-25)
Architecture, rules and phases: ROADMAP.md M09; tech: TECHNICAL_ARCHITECTURE
"Co-op (M09)".
- **Phase 0:** `.godot/` is no longer tracked (`.gitignore`; run
  `tools\run_godot.cmd import` after a fresh clone, the server script imports
  after every pull). `.gitattributes` keeps the server files LF.
  **Spike A** (`run_godot serverperf [heroes]`: headless Highlands, bot
  heroes at different camps, `--fixed-fps 60` so wall time per frame = tick
  cost): the laptop (Pentium 3556U) needed p50 16.3 / p95 20.9 ms per tick
  with 5 heroes (budget 16.7) and 12.7 ms with one. Ablation on the dev PC:
  the base load was the ~36 idle camp enemies (animation 0.6 ms, UI 0.6 ms,
  idle enemies 3.4 of 4.7 ms).
- **Phase 1 (network foundation):**
  - **AI sleep** (`EnemyBase.sleeping`): an idle, standing enemy with no hero
    within 60 m skips its tick; a hit wakes it (singleplayer benefits too).
  - **`Net` autoload** (`scripts/net/net.gd`): modes OFFLINE / SERVER /
    CLIENT, ENet on `*` (IPv4 + IPv6), async host name lookup, `host:port` /
    `[v6]:port` (`NetAddress`), SceneMultiplayer auth handshake (protocol +
    Godot version, player limit, readable refusals), roster, zone epochs +
    ZONE_READY, three channels (events / hero / snapshots), netsim
    (`-- --netsim=rtt,jitter,loss`), server tick + traffic log every 60 s,
    ENet throttling off (it dropped 23 % of unreliable packets on localhost).
  - **Dedicated server** `scenes/dedicated_server.tscn` (`server.env` now
    points at it): its own world save `user://runebound_server.json`, zones
    boot without local hero, camera, UI, music, rigs, particles, sounds or
    floating text. Clients run no camps, boss triggers or lab spawns.
  - **SaveGame online session:** the server's flags in memory, the client's
    own world (zone, flags, camps) untouched on disk.
  - **Title screen** (new main scene): Continue / Join co-op (name + server
    address, last one remembered in `user://settings.cfg`) / Quit; shows why
    a session ended. Zone travel is blocked for co-op clients until phase 5.
  - **Tests:** smoke 384 checks (+ sleep, address parsing, offline role,
    online save session, local dispatch). `run_godot net [scenario]`
    (`tests/net_test.tscn`, also `run_godot.sh net` on the laptop) starts a
    real dedicated server and headless clients per scenario: handshake +
    leave, version refused, server full, client in the Highlands (no local
    camps), echo (20 Hz x 900 B: loss after the first second 0 %), unknown
    host. `run_godot server [port]` runs a local server to join from the
    title screen.
  - **Server cost after phase 1** (`serverperf --dedicated`): dev PC 1 hero
    p50 0.8 / p95 1.5 ms, 5 bot heroes with ~13 enemies fighting p50 2.4 /
    p95 4.0 ms; the laptop 1 hero p50 2.0 / p95 3.3 ms (was 12.7 / 16.0),
    5 bots p50 7.6 / p95 17.9 ms (the bots run their whole kit on the
    server; real clients run theirs at home). Net tests green on the laptop.
- **Phase 2 (heroes in one world):**
  - `Player.net_role`: OWNER (this machine plays it), PUPPET (another
    player's hero on a client: pose, state, HP and actions from the network,
    no input, physics, hurtbox or local death), PROXY (a client's hero on the
    server: position and HP from its owner, a hurtbox, the client's
    character for stat math, no rig). Remote heroes never block anyone.
  - `NetWorld` (per zone while online): clients send their hero at 30 Hz,
    their actions (`action_started`, so puppets play the clip) and their
    character (on join and after changes); the server keeps the proxies,
    relays actions and sends a 20 Hz hero snapshot; puppets are posed 100 ms
    in the past (interpolated, 150 ms extrapolation, snap on teleport).
  - Remote heroes show a nameplate (name + level, `Sigmund  Lv2`); a party
    panel on the HUD's left lists them with health and the ping.
  - Tests: smoke 391 (+ interpolation, puppet role, character re-apply);
    net scenario `heroes` (two clients, one with netsim 100 ms / 2 %: each
    walks to a spot and dodges, the other sees the puppet there and replays
    the dodge; the level-up reaches the roster and the proxy).
  - **WAN (Spike B):** the dev PC joined the laptop's real dedicated server
    over Tailscale (DERP relay Frankfurt): echo 20 Hz x 900 B, 0 % loss,
    RTT p50 67 / p95 84 / max 166 ms; the `heroes` scenario passed with two
    clients over the internet.
- **Phase 3a (enemy replication core: rusher, caster, bolts):**
  - Server: every enemy gets a net id (`NetWorld.register_enemy`, deferred
    from `_spawn_enemy`); spawn, state entries (with the pose at that
    moment), hits (true damage), burn ticks, deaths and despawns go out as
    events; 20 Hz snapshots carry awake enemies within 150 m of each client
    (27-byte rows, `NetCodec`, 32 per packet) plus a round-robin of sleeping
    ones. Enemy bolts are announced and popped by event.
  - Client: enemy puppets (`EnemyBase.net_puppet`): no AI or physics,
    posed 100 ms behind the server, statuses from snapshot bits (burn shows,
    never ticks), hits and statuses they take go to the server (flash and
    squash at once, the damage number when the server answers), death by
    event. Bolts are visual copies.
  - Presentation seam: `_present_state(state)` with `present_origin()` /
    `present_forward()`; the rusher and caster moved their telegraphs, glows
    and sounds there (singleplayer unchanged).
  - Enemy hits on heroes: the proxy forwards them (`HURT`) with the struck
    area (`HitInfo.area_center/area_radius`); the owner takes the hit
    unless its own hero dodged (i-frames) or stands > 1.2 m outside the
    area. Rusher sweeps hit every hero inside, not only the first.
  - Tests: smoke 397 (+ hit / snapshot codec, puppet enemy behaviour);
    net scenario `enemies` (combat lab on the server, two bot clients, one
    with netsim: puppets appear, all three enemies die with kill credit to a
    player, enemy hits reach the owners). Windowed look: telegraph discs,
    hit flashes, the caster's charge and bolt all show on a client.
- **Phase 3b (every enemy, hazards, bosses, scaling):**
  - `EnemyBase.play_fx(name)`: a named action's look (stab, slam, spin,
    block, nova, charge, enrage, shatter, blink, fan, ring) plays locally
    and goes to the puppets as ENEMY_FX. Brute, assassin, hollow warden
    (block sparks; a puppet's spin turns its rig, not its facing), the elite
    nova, the Ashvein Colossus and the Vessel moved their looks into
    `_present_state` / `_present_fx`. The Vessel's blink snaps puppets.
  - Every enemy attack now hits every hero inside and carries its area.
  - Fire patches and shadow runes are server hazards; clients get visual
    copies (HAZARD).
  - Enemy health scales with the party: +70 % per hero beyond the first,
    kept as a fraction when heroes join or leave (ENEMY_SCALE).
  - Boss puppets bring their boss bar on the client
    (`ZoneBase.setup_enemy_puppet`; the Spire hands the Vessel its arena).
  - Fixed on the way: a heavy stagger in the Vessel's phase 2 lasted forever.
  - Tests: net scenario `enemy_types` (every type incl. both elites and both
    bosses as puppets, all killed with credit, fx sent, boss bar, x1.7
    health for two heroes). Windowed look: the colossus fight (bar, slam
    telegraph and impact, a hero dying and snapping back) reads on a client.
- **Phase 4 (rewards and world):**
  - One reward path, `ZoneBase.give_reward(hero, xp, gold, piles, items,
    pos, note)`: the local hero gets it at once, a co-op proxy's owner gets
    a GRANT and spawns the drops as its own personal loot. Kills pay every
    hero within 60 m full XP plus its own gold and item rolls (class and
    level of that hero); singleplayer keeps "the killer".
  - Chests open once (server), every hero within 12 m gets its own purse;
    clients ask with CHEST_OPEN, all lids swing (CHEST_OPENED, replayed to
    late joiners). Camp bonuses and boss loot (a legendary per hero, plus
    two rares in the Spire) go to the whole party.
  - World flags: `SaveGame.flag_set` -> FLAG to clients; zones react in
    `apply_world_flag` (boss bar away, victory stinger, gates unseal) on
    the server and every client.
  - **SaveGame v5:** zone discovery XP is remembered per character
    (`discovered`), migrated from the old world flags.
  - Tests: smoke 401 (+ v4 -> v5 migration, local reward path, discovery
    per character); net scenario `rewards` (Highlands: c1 clears camp_1
    and opens chest_south, c2 108 m away gets only the party's camp bonus,
    no loot and no drops, and sees the chest open; the server spawns no
    drops of its own).
- **Phase 5 (party flow):**
  - A portal or a shrine into another zone starts a 5 s party countdown
    (banner: "Party travel to ... in 5  [X] Cancel  (who)"); anyone can
    cancel with X. At zero the server starts a new zone epoch, tells every
    client (TRAVEL_GO), saves its world and changes scene; clients fade and
    follow and arrive at the same gate. The new zone adopts clients that
    loaded before the server did.
  - Shrine hops inside a zone are personal (only this machine's hero moves).
  - Death: the owner respawns its own hero (nearest attuned shrine).
  - Late joiners appear next to a party member (welcome `spawn_at`).
  - A server that shuts down disconnects everyone at once; clients go back
    to the title with the reason and their own world restored.
  - Tests: net scenarios `travel` (countdown, cancel, travel hub ->
    Highlands, arrival at the south gate, a late joiner next to the party,
    epoch 2) and `server_gone`; 12 scenarios green, smoke 401.
- **Phase 6 (tools, effects, gates):**
  - `tools\run_godot.cmd coop [bots]`: a local server, companion bots
    (Sigmund, Brynja, ...; they follow the first real hero, fight near it,
    follow party travel) and the game window, joined automatically.
  - Remote heroes' ability effects: `HeroFx` (slash arcs, Ember Lance as a
    visual copy, Earthbreaker slam, Storm Step flash and trail, chain / arc
    lightning, rings, Fracture Rune as a visual copy, barrier, Resonance
    Burst, key sounds) plays for the acting hero and goes to the others
    (HERO_FX). Windowed look: the buddy's slashes, slam and lance read.
  - **Soak** (10 min, 4 bots + a window, local server): 5 players the whole
    time, nodes flat (2216-2232), 0 orphans, tick p95 ~1 ms, ~48 KB/s out.
  - **Server laptop under load** (5 min, 4 bots over Tailscale DERP relay
    fighting at 4 camps that re-arm after 5 s, enemies x10 health, 13-15
    awake): tick p50 5.8-6.6 ms, p95 7.9-10.7 ms (budget 16.7), single
    spikes up to 63 ms, 57-76 KB/s out; 500-800 hits per client applied.
  - WAN: echo over the relay 0 % loss, RTT p50 67 ms; `heroes` passed over
    the internet.
- **Gate walk (user):**
  1. `tools\run_godot.cmd coop` - you join a local server with two
     buddies. Runehold -> portal to the Highlands: the 5 s party countdown
     (X cancels) -> fight camp 1 with the buddies (only your loot drops for
     you; everyone near gets full XP) -> a chest (one opening, a purse each)
     -> the Colossus (boss bar, a legendary for each hero).
  2. On the laptop once (M09b): SERVER_SETUP "Einrichtung" (Funnel in the
     Tailscale console, `sudo tools/server/setup-service.sh`, codes with
     `tools/server/invites.sh add NAME`). Title -> Join co-op -> the
     laptop's name (no port) + your code.
  3. With a friend: send them SERVER_SETUP "Für Freunde", the address and
     their code; no Tailscale needed.

## M08 Open World I (2026-09-24)
The Ashen Highlands are an open 384 x 384 m heightmap zone built from data.
- **Visible:**
  - **Terrain:** rolling ash relief from the south slopes up to the north
    plateau, rim mountains with charred trees, ridges with rock hulls,
    graded trails carved into the ground and drawn through a baked trail
    mask; every combat spot is a flat pad. Camera far plane 560 m, haze on
    the far edge.
  - **32 points of interest** along five routes (WORLD_DESIGN.md): 8 raider
    camps (respawn ~10 min after a clear, never while a hero stands near),
    2 pass ambushes that spawn around the hero, a roaming elite patrol,
    3 masonry ruins with chests, 4 free chests, 5 waypoint shrines, rune
    monoliths / charred groves / a bone field, 2 sealed dungeon gates
    (placeholders for the M13 dungeons) and the Colossus arena on the plateau. Level
    bands south 1 / middle 2 / north + Emberfall Ridge 3.
  - **Camp members have a leash:** dragged beyond it (or stuck, or with
    their target out of reach) they walk home, heal and rest.
  - **Waypoints:** walking up to a shrine attunes it (+40 XP, lit crystals);
    `[E] Travel` lists Runehold and every attuned shrine; travelling fades
    and hops within the zone or changes zones. Gates place you in front of
    the gate you came through. Death returns you to the nearest attuned
    shrine. Runehold has its own always-attuned shrine by the Highlands gate.
  - **Compass strip** (top of the HUD): headings, attuned shrines, gates,
    the arena, sealed gates, armed camps within 120 m. **Map on M:** the
    baked map with everything this character has seen, the hero's arrow, a
    legend and the list of known places. Named areas announce themselves.
- **Tech (TECHNICAL_ARCHITECTURE "Open world"):** `tools/worldgen` bake
  (deterministic, asserts the layout rules), `Terrain` (chunked 3-LOD mesh,
  `HeightMapShape3D`, `height_at` / `normal_at`), `ZoneLayout`, `PoiBuilder`,
  the ground seam (`ground_y` / `ground_point` / `VFX.ground_hit`: nothing
  hard-codes y 0 any more), `EncounterSpawner` v2 (states, persistence,
  staggered spawns, ambush, patrol), `EnemyBase.RETURN`, SaveGame **v4**
  (`world.camps`, `characters[i].waypoints` / `map_discovered`),
  `WaypointRegistry`, `ZoneBase.travel_to(scene, arrival)` / `fast_travel`,
  `MapUI`, `Compass`. Runners address positions by POI id
  (`{"poi": id, "offset": [...]}`).
- **Tests:** smoke 373 checks (terrain spike: decode, build time, bake
  orientation, collision vs `height_at`, flat pads, slope walk, ground
  seam on flat and sloped ground; zone: POI heights, camp spacing, bands,
  gates, hull grounding, ruins, scatter fields, colliders under tall
  props; camps: clear → save → round-trip → stays cleared with a hero
  near → re-arms after 11 min → staggered spawns, leash return + heal,
  ambush ring, patrol wake + roaming, v3 → v4 migration; waypoints: attune,
  save, travel list, fast travel, shrine respawn, arrival at the gate used;
  compass heading, map open/close, discovery, area card). Shot list
  `tests/shots/m08_open_world.json`; perf scenarios `highlands_open`,
  `highlands_vista`; the older Highlands shot lists and `highlands_south`
  moved to POI positions.
- **Perf (median of 3, 2026-09-24):** `perf highlands_open` 66.3 FPS / GPU
  13.9 ms / 340 draw calls; `perf highlands_vista` 71.8 FPS / 13.2 ms / 391
  draw calls; A/B: terrain LOD saves 0.7 ms GPU, terrain shadows cost
  0.4 ms (kept). Zone build about 150 ms (terrain) + POIs and scatter.
- **Open for the user:** KNOWN_ISSUES "M08 open items". **Gate walk:**
  `tools\run_godot.cmd reset` → `play` → the Highlands gate → attune the
  Ashford shrine → clear camp 1 → M (map) → the Crossroads → `[E] Travel`
  back to Runehold and out again (you arrive at the south gate) → let a camp
  come back (10 min) → the plateau and the Colossus.

## M07b Character Foundations (2026-09-24)
Decided after the user's post-M06 wishes (co-op for 2–5 on a home server,
several classes, a real RPG, one ability at the start, gold, a stats
window): a foundation milestone before the open world, so M08+ don't build
on "one player, one class". No netcode yet, only the seams.
- **Visible:**
  - A fresh Runebreaker knows Rune Cleave and Dodge. Earthbreaker (L2, 50 g),
    Ember Lance (L3, 150), Storm Step (L4, 275), Chain Spark (L5, 400) and
    Fracture Rune (L7, 600) are bought from **Sigrun Runewright** in Runehold
    (`[E] Talk`, TrainerUI: level / gold reasons, Learn, toast + slot pop +
    `ability_learned` SFX). Runic Guard / Resonance Burst stay talent unlocks.
  - **Gold:** every kill pays ~half its XP (elite x4, +15 %/level), bosses in
    3–4 piles, chests a purse; coins glide to the player, never need a slot;
    HUD counter with a coin icon; debug `[0]` +500 gold, `[L]` learn all.
  - **Hero window** (HeroUI): I / C / N open Inventory / Character / Talents
    as tabs, same key or Esc closes. The Character tab shows level/XP,
    health, barrier, Resonance, damage/crit/cooldown/move %, gold, per
    ability: damage, average with crit, crit %, cooldown, cost, gain and
    behaviour notes, plus defence and equipped gear (`StatSheet`, the same
    formulas as the hits; the HUD tooltip leads with the damage too).
- **Seams (TECHNICAL_ARCHITECTURE "Multi-class / multi-player seams"):**
  `ClassData` resource + one ability id space (`melee` → `rune_cleave`,
  `ember` → `ember_lance`, icons renamed) + `knows()` gate + action table;
  `PlayerIntent` / `InputSource` (Player never reads `Input` for gameplay);
  `HitInfo.attacker_id` (talent mults, XP, gold, loot follow the attacker;
  Wildfire follows the burn's owner; Fracture Rune rolls through the player);
  `ZoneBase.players` / `local_player` / `nearest_player` / `players_within`,
  enemies retarget (recent attacker, else nearest) when spawned by the zone;
  boss triggers, camps, novas, charge and Vessel ring use the registry;
  `Player.is_local` gates camera shake / impulses / denied clicks / pickup
  toasts; SaveGame **v3** (world / characters / active, v1+v2 migrate);
  talents carry `class_id`, ability-specific affixes and legendaries a
  `"class"` tag; `ItemGenerator.generate(bias, class_id)`.
- Tests: smoke 304 checks (start kit, gate, trainer, gold, hero window,
  StatSheet vs formula, save v3 round-trip + migrations, input seam with a
  scripted source, attacker identity, registry + retarget + local camera,
  class filters). Shot list `tests/shots/m07b_character.json` (8 shots),
  `b5_hud` and `m07_progression` re-captured. Harness runs (shots, perf,
  stress, captures) call `debug_learn_all()` unless a shot list sets
  `"fresh_abilities": true`.
- Open for the user: KNOWN_ISSUES "M07b open items" (learn order/prices,
  Fracture Rune buff, Esc ordering, Sigrun placeholder).
- **First playtest feedback (2026-09-24), fixed:** Jacquard retired
  everywhere (titles are Pixelify 40 px, `UiTheme.font(true)` resolves to
  it); X close buttons on the hero window and the trainer panel; debug `[9]`
  resets abilities and gold too; `reset` refuses while the game runs; the
  v2 → v3 migration refunds reached abilities as gold instead of granting
  them (the user's level-7 save had arrived with five abilities).

## M06 progress
- **Step 0 (user request):** ability names only as hover tooltips while the
  inventory is open (HUD hit-tests its slot rects; tooltip on CanvasLayer 9).
  `AbilityData.description` added.
- **Step 0b (user-approved gameplay fixes):** dodge-cancelled Storm Step now
  resolves (mask + path zap); enemy registry survives the style-A reparent;
  Spire ramp rebuilt, Vessel blink anchors inside the chamber.
- **A1 harness:** SaveGame switches to the scratch save + `seed(1207)` for any
  `--capture/--worldcapture/--shots/--perf/--stress` run; `run_godot.ps1`
  modes `shots <list>`, `perf <scenario> [label]`, `stress`; smoke fails on
  `SCRIPT ERROR`; stress exits 1 below 60 FPS; capture folders `.gdignore`d.
  Pre-M06 captures kept in `captures_baseline_m05/`.
- **A2 perf bank** (Highlands South scripted fight, 8 immortal enemies,
  median of 3, `captures_perf/highlands_south.json`):
  baseline 62.1 FPS / GPU 14.92 ms → 2048 hard directional shadows +
  roughness limiter off + linear glow upscale + max 6 transient VFX lights
  → 65.5 / 13.75 → glow level 3 only → **68.7 FPS / GPU 13.12 ms**.
  Depth prepass OFF is worse on this iGPU (58.8) — keep it on.
  Lab stress full combat 58.2 → **68.5 FPS**, worst frame 140 → 54 ms.
- **A3:** `assets/art_spec.json` (single look source) + ART_BIBLE direction
  sheet (proportions, shape language, color roles, value bands, Gate-0 axes).
- **A4 rig spike PASSED** (`tests/rig_spike.tscn`, `tools/modelgen/lib/rig.py`):
  Blender 5.2 rigid-skinned biped → GLB (ACTIONS, 60 fps, no images) →
  Godot: exact clip lengths, sRGB→linear color fidelity exact (#3A404D),
  manual mixer advance frame-exact, upper-body OneShot bone filter, weapon on
  BoneAttachment3D, per-instance hit flash, stencil outline; **29 animated
  outlined rigs cost +0.20 ms GPU** in the lab.
- Dev machine: Intel UHD 770 iGPU — GPU-bound (render CPU ~1 ms).
- **B1 vignette (Highlands South):**
  ZoneLook (pixel sky with explicit bands + baked azimuth silhouettes incl.
  the Spire landmark, ambient color, depth/height fog, luma-banded posterize
  so dark browns never flip olive/red, split-tone + vignette), ArtKit
  materials at 32 px/m (terrain_pixel shader: slope blend, per-texel layer
  mix, dim ember specks), RockHull dressing on every ridge/cliff/rock
  (terraced ledges, contains its collider — smoke-checked), kit props
  (bonfire, rune monolith, banner pole, charred tree, bone pile) via
  SetPieces builders, Runebreaker + Cinder Marauder rigs (baked pixel
  atlases, idle/run/attack at gameplay timing, hitstop freeze, anim LOD).
- **Gate 0 PASSED (2026-09-23, user in live play):** character outline ON,
  smooth animation (stepped 12 fps rejected), characters 64 px/m over
  environment 32 px/m (uniform 32 rejected). Rejected variants removed from
  code/assets; outline stays on debug key O for comparison and perf A/B.
  ART_BIBLE rewritten as **v2** (rules + reasons, perf budget, asset
  compliance, draft Style Gate checklist for the user to agree on).
- Crash during Gate 0 ("Vulkan device was lost", 4 runs in 15:09–15:13):
  Windows logged GPU resets (LiveKernelEvent) exactly then, while several
  game instances shared the iGPU, plus 4 hung headless smoke runs (up to
  22 h old) burning CPU. Hung runs killed; the same save has been stable in
  every solo run since. `run_godot.ps1` now warns about other running game
  instances; smoke has a 300 s watchdog.
- **B2 characters DONE:**
  - Authoring:
    - `tools/modelgen/lib/pose.py` resolves pose intents: two-bone reach and
      blade aim, evaluated with Blender's own bone formula.
    - `--sheets` renders per-clip contact sheets (3/4, side, top) to
      `captures_contact/`.
  - Runebreaker has every clip at gameplay timing:
    - `cleave_l` backhand and `cleave_r` forehand; both now match the slash
      VFX direction.
    - dodge dash and Ember thrust.
    - Earthbreaker rise plus impact (new presentation-only
      `action_started("earthbreaker_impact")`).
    - Storm Step lunge.
    - Chain Spark and Fracture Rune on an upper-body layer (legs keep
      running).
    - additive hit flinch.
  - Cinder Marauder: stagger clip; the axe chop now lands on the telegraph
    disc centre.
  - Duskweaver v2:
    - legless cone robe and a hovering staff
    - the orb stays the code-built telegraph and bolt origin
    - clips: glide, charge (60 % pose then trembling hold), cast, stagger
  - Animator: the player runs an AnimationTree (Transition, filtered upper
    OneShot, ADD flinch); enemies keep the cheap AnimationPlayer path.
  - Value rule measured in captures (luma posterize bands are ~7 L*):
    Runebreaker +24, Marauder +27, Duskweaver +21 L* over the ground. The
    Duskweaver robe was lifted to reach this.
  - Hit flash and axe telegraph change emission energy only, so no shader
    variant compiles on the first hit. Lab-crowd first-run worst frame:
    94 → 61 ms.
  - Rig scenes are kept loaded (`ArtKit.rig_scene`).
  - Perf after B2: Highlands South 65.6 FPS median (GPU 14.0 ms); lab crowd
    (29 enemies) 67.5 FPS.
- **B3 environment kit DONE** (reusable, rule-placed; no hand composition):
  - `Scatter` (`scripts/world/scatter.gd`) places items along obstacle
    footprints.
    - Chunked MultiMesh, 16 m chunks, no shadows, 42 m visibility range.
    - Keep-clear circles around camps, spawn, portals, chests and the
      boss arena.
    - Ground height comes from a Callable, so the M08 heightmap can plug
      in.
  - Highlands: about 2,000 scatter instances (dead-grass tufts in clumps
    plus stone clusters) at every wall, ridge and rock base. Open combat
    space stays clear.
  - New props: `ash_tuft`, `stone_cluster`, `log_seat` (two per raider
    camp, 0.32 m, walk-through).
  - Kit materials are matched by Blender material name
    (`_body` / `_cloth` / `_glow`).
  - `wind_sway.gdshader` moves hide banners (hung from the crossbar) and
    tufts (from the ground).
  - `ZoneLook.ash_fall` adds camera-attached falling ash.
  - Cost: in the noise (Highlands South 67.2 FPS median, +30 draw calls).
- **B4 VFX v2 DONE:**
  - One threat language (`threat_marker.gdshader`): crimson area, near-white
    rim, fill progress over the windup, fog-exempt, sorted on top, snapped
    to 32 px/m.
    - Used for every enemy telegraph disc plus the Colossus charge lane.
    - The Vessel, shadow runes and elite nova no longer tint their danger.
  - Player-side ground marks are broken rings (`player_ring.gdshader`,
    procedural, crisp at any radius, opacity capped at 0.7).
    - The Fracture Rune lights its dashes while arming. It used the
      enemies' filled disc before.
    - Shockwaves (Earthbreaker, Ember, Frost, Warden) are drawn the same
      way, in their element colours. The Warden ring lost the player teal.
  - Lightning: white-hot core + violet-blue fringe, forks; fades by thinning
    out; meshes and materials shared per colour.
  - Duskweaver bolt: void core + halo + wake.
  - Deaths: body shards + rising pixel ash + embers.
  - Fog exemptions: orb, bolt, loot beams, lightning, telegraphs.
  - Bursts run on CPUParticles3D (A/B: +0.07 ms GPU, i.e. free). VFX meshes
    cast no shadows.
  - `VFX.warm_up` + `ZoneBase._warm_up_characters` precompile materials
    inside the view frustum at zone start. See KNOWN_ISSUES for the
    remaining first-fight hitches.
- **B5 HUD v2 DONE:**
  - `UiTheme` puts the SIL-OFL pixel fonts (Pixelify Sans, Jacquard 24) at
    measured crisp sizes on the HUD, inventory and tooltip, with 9-slice
    pixel frames in the player teal.
  - Framed bars; Resonance in rune gold with an Earthbreaker cost tick.
  - Pixel ability icons (`tools/texgen/ui.py`), radial cooldown sweep, key
    labels.
  - Boss and place names in Jacquard.
  - World labels (plates, loot, portals, damage numbers) are drawn at a
    fixed screen size, one font pixel per screen pixel. Distance-scaled
    pixel text was unreadable.
- **Audio track DONE** (listening checkpoint pending; not heard by the
  implementer, only analysed: levels, seams, spectrum):
  - `Sfx` builds the mix buses at startup: Music, SFX, Telegraph, Ambience,
    UI.
  - A sidechain compressor on Music, keyed by the Telegraph bus, ducks the
    music for enemy tells.
  - Sounds are routed by key.
  - `tools/musicgen/compose.py` synthesises the Highlands music from data:
    D minor, 72 BPM, 16 bars.
    - Exploration layer: drone, pad, harp arpeggios, FM bells.
    - Combat layer: frame drums, shaker, bass pulse, swells.
    - Seamless stereo loops: note and reverb tails are wrapped onto the
      start.
  - `MusicDirector` (under Sfx) plays both layers in sync
    (AudioStreamSynchronized). The combat layer swells in while an enemy
    within 22 m is engaged, ebbs out over 4 s, and fades on travel.
  - Loop bug fixed: ambience and portal hum now loop via their `.import`
    (`edit/loop_mode = Forward`). The runtime
    `loop_end = data.size() / 2` was wrong for QOA-compressed streams.
- **Phase C propagation DONE** (the user asked to continue past the Style
  Gate; its review happens on the captures):
  - **C3 Runehold + training grounds:**
    - Runehold ZoneLook: warm ESE dawn sun, lighter haze, more ambient.
    - Paved flagstone plaza and paths (shader-side).
    - Coursed granite walls with piers and teal Runebreaker banners.
    - Sod-roofed huts with timber trim, plank doors, rune lintels and lit
      windows.
    - A hearth with breathing flame tongues.
    - A meadow skirt with 26 pines and oaks beyond the walls; grass and
      stone scatter.
    - The Combat Lab uses the same kit as the training grounds (sparring
      ring, racks and pells hugging the walls).
    - Runehold music: F major, 66 BPM; the combat layer is a training drum
      pulse.
    - Collider counts are unchanged (hub 19, lab 14; smoke-checked).
  - **C4 Shattered Spire:**
    - Interior ZoneLook (colour background, cold top light), 1 m slab
      floors, coursed walls with piers and relief arches.
    - Crystal pillars wrap the accent colliders.
    - Torch v2 as floating crystal beacons (bottom >= 2.08 m); the boss
      chamber ring was re-placed inside the chamber.
    - Floating debris overhead, a processional rune channel plus an arena
      octagon (lines, never rings), rubble and crystal scatter.
    - Spire music: D Phrygian, 60 BPM, cathedral reverb.
  - **C1/C2 cast:** rigs for Stonehulk, Veilstalker, Hollow Warden, Ashvein
    Colossus (x1.7, ember veins ramp on enrage, charge/stun loops, enraged
    slam rate) and the Vessel (floating construct, shatter, p2_idle, fan).
    - The Vessel's hazard ring now uses the threat band (exactly the band
      that hits).
    - Highlands camps 3–5, the elite pocket and the boss arena half-walls
      got the automatic kit, and the east monolith is wrapped.
    - Per-zone warm-up lists.
  - **C5:**
    - Portal v2 in every zone: plate, upright swirling gate, floating arch
      stones; faces the zone centre; sealed portals grey.
    - A kit treasure chest with a hinged lid.
    - Loot shapes with rarity glow, plus unique drop models for the three
      legendaries.
    - Elite aura: element-coloured eyes and rising motes.
    - Inventory item icons.
    - A victory stinger on boss kills.
  - **C6:** Cindermaw shows on the hero (the blade surface turns molten).
- **Phase D:**
  - Review captures are in `captures_shots/` (list in ART_BIBLE §17), with
    before/after pairs in `*_legacy`.
  - Implementer self-review of the §71 gate: met (ART_BIBLE §17, with open
    notes for the user).
  - Perf on the dev iGPU (median of 3):
    - hub 80.0 FPS
    - Highlands South fight 72.4
    - Spire hall fight 64.8
    - lab crowd (29 rigs) 64.0
    - lab stress full combat 71.1
  - Smoke green: 206 checks.
- **Style Gate verdict (user, 2026-09-24): pass.** The art style is
  approved, and the music is approved. The only note: Jacquard place names
  were unreadable, so portal labels and arrival title cards now use
  Pixelify.
- **User feedback 2026-09-24:**
  - Level cap and talent list accepted for now.
  - Keyboard layout: every ability on the number row, applied at runtime
    by `InputSetup`:
    - 1 Earthbreaker (Q also works)
    - 2 Storm Step
    - 3 Chain Spark (R also works)
    - 4 Fracture Rune
    - 5 Runic Guard
    - 6 Resonance Burst
  - E is the interact key: portals and chests no longer trigger by walking
    in and show an "[E] Travel / Open" prompt. Loot is still auto-pickup.
    F is free.
  - Real fresh start: debug [9] (F3 overlay) wipes the save and the live
    character, then reloads Runehold. `tools\run_godot.cmd reset` deletes
    the save from outside the game.
  - 7 gear slots (Weapon, Helm, Chest, Gloves, Boots, Amulet, Ring) with
    icons, drop shapes and a new affix spread. Stormcaller's Band is now a
    ring.
  - Ember Lance aim: when the camera ray hits the floor (the normal
    downward view), the lance aims at muzzle height above that spot, so it
    flies level instead of diving into the ground. Enemy aim and aim assist
    are unchanged; looking up still shoots upward.

## M07 Progression — started (implementer proposal, see PROGRESSION_DESIGN.md)
The user asked to continue past M06. M07 is built as a data-driven proposal
for review; every number and talent is data.
- **Leveling:**
  - `Progression` sits on the player: cap 25, XP to the next level
    `80 * L^1.6`, +1 talent point, +6 health and +2 % damage per level.
  - XP from kills (per-type value, x4 elites, +15 % per enemy level), camp
    clears (15 per enemy), chests (60) and first zone visits (150,
    discovery flag).
  - Zones set enemy levels (Highlands south 1, north 2, Colossus 3; Spire
    3, Vessel 4); +8 % health per level. Level 1 is the tested balance.
- **Item level:** the drop source's level. Only damage, health and
  Resonance affixes scale (+6 % per level). The inventory shows the item
  level and per-stat deltas against the equipped item.
- **Talent tree:**
  - 24 nodes in 3 branches (Storm, Ember, Runic Warden), one table in
    `tools/talents/generate_talents.py` → `resources/talents/*.tres`.
  - Tiers open at 3/6/10 points spent below them. Removing a rank is
    blocked while it holds a higher tier open. Respec is free.
  - Panel on N (`TalentUI`): left click learns, right click removes.
- **Behavior talents:** Overload, Thunderclap, Eye of the Storm, Split
  Lance, Molten Core, Wildfire, Phoenix Burst, Glacial Bulwark and
  Unbroken. Stat talents plug into `Player.stat()`, which sums equipment
  and progression.
- **Abilities 7–8 as talent unlocks** (their HUD slots appear once
  learned):
  - Runic Guard (5): 30 Resonance, a barrier of 40 + level for 4 s,
    12 s cooldown.
  - Resonance Burst (6): spends all Resonance (at least 50), 0.7 damage
    per point in 4 m, heavy stagger.
  - Keys are added at runtime (`InputSetup`), so `project.godot` is
    unchanged.
- **Items:**
  - Three new affixes on the talent stats: damage to Shocked, Burn damage,
    Storm Step cooldown.
  - Three new legendaries grant a talent behavior: Forked Ember,
    Stormcaller's Band, Emberheart Plate.
- **HUD:** a thin experience bar (new colour role `experience`), a level
  badge, level-up toast with a gold ring, and place-name title cards on
  arrival.
- **SaveGame v2:** progression in the save; v1 saves migrate (level 1,
  gear and flags kept).
- Presentation:
  - Dedicated hero clips: `runic_guard` (upper body: blade upright, rune
    fist out) and `resonance_burst` (full body: arms flung wide).
  - Synthesized SFX: `level_up`, `runic_guard`, `resonance_burst`.
  - "+N XP" float text on kills.
- Smoke: 241 checks, all green. They cover every behavior talent, both new
  abilities, the tier rules, respec, the save round-trip and the migration.
  Highlands South perf after M07: 68.5 FPS median (within thermal noise).
- **Open for the user:** the numbers and the talent list
  (PROGRESSION_DESIGN "Open"), the G/H bindings, and whether enemy levels
  should also scale damage.
- Perf (normal thermal state): Highlands South 62–69 FPS median (62.1 /
  GPU 13.9 ms after the Gate-0 cleanup), lab stress
  full combat 72.5 FPS. Interleaved A/B costs: rock hulls 0.5 ms, outline
  ~0, anim LOD saves ~0.3 ms. Trap found: a TIME-animated sky in AUTOMATIC
  process mode re-filters radiance every frame (+~4 ms) -> Sky QUALITY.
  This iGPU swings up to 25 % between runs (thermal): compare with
  `perf_probe.gd -- --ab=<key>` only.

## M05 additions
- World flags in SaveGame (`colossus_defeated`, `spire_cleansed`): bosses stay
  dead, gates stay open, hub gains a Spire shortcut portal.
- **Shattered Spire** dungeon (interior lighting model: no sun, crystal
  torches, glowing floor runes) with 4 sections, warden-guarded treasure,
  elite vault — see WORLD_DESIGN.md.
- **Hollow Warden**: frontal 50% damage block, teaches flanking.
- **Vessel of the Shattered Rune**: 2-phase major boss (melee construct →
  blinking ranged shatter form with rune fans + arena hazard rings).
- Capture hygiene: capture runs use a scratch save file, never the real one.
- Perf: lab stress 69 FPS avg after all M05 content.

## M04 additions
- **SaveGame autoload**: versioned JSON (user://runebound_save.json), debounced
  saves on loot actions, immediate on travel/quit; corrupt saves → fresh start;
  `save_path` swappable so tests stay hermetic. Debug key 9 wipes.
- **ZoneBase refactor**: all bootstrap (player/camera/HUD/targeting/inventory/
  debug/style) + greybox helpers + enemy/loot plumbing extracted from
  CombatLab; zones override `_build_zone`/`_environment_colors`/spawn point.
  `travel_to()` fades, saves, switches scenes; gear restored on arrival.
- **RUNEHOLD hub** (new main scene) + **ASHEN HIGHLANDS** region with 5 camps,
  2 chests, landmarks, ambient loops — see WORLD_DESIGN.md.
- **ASHVEIN COLOSSUS** mini-boss: slam + lane-telegraphed charge + enrage,
  boss HP bar, guaranteed legendary, unseals the exit portal.
- New assets: ash_ground/ash_rock textures; wind/campfire/portal loops,
  portal travel, chest, boss roar, charge horn SFX.
- Perf after refactor: 67 FPS avg lab stress, worst frame down to 52ms.

## M03 additions
- Item system (see ITEMIZATION.md): 3 slots, 4 rarities, numeric + behavioral
  affixes, 3 legendary powers (Cindermaw / Conductor's Oath / Glacier Heart),
  procedural names. Drops with rarity-scaled beams, auto-pickup, HUD toasts.
- Equipment node on Player aggregates stats; all ability hooks routed through
  `roll_ability_hit` / `_set_cooldown` / getters. Inventory UI on `I`
  (equipped | list | details+compare, Equip/Discard), locks combat input.
- Aim fix from pierce testing: direct enemy ray hits now aim center mass.
- Perf with drops active: 61 FPS avg full rotation vs 29 mixed enemies.
- M02 recap: 6-ability kit, statuses, Assassin/Brute, elites — user-approved.
(M01 passed its human playtest; art style locked to C HYBRID; Tab-targeting
per user preference: Tab selects/cycles, target persists until death/>18m,
teal ring + world HP bar + status pips, gold bar for elites. Melee snaps to
the held target within 4m, else camera-aim facing.)

## M02 additions
- **6-ability kit** (see CLASS_DESIGN.md): + Storm Step (E, offensive
  Lightning dash, phases through enemies), Chain Spark (R, target-jumping
  bolt, 3 jumps / 4 vs Shocked), Fracture Rune (F, ground-placed 1.2s-armed
  Frost AoE).
- **StatusEffectComponent** on every enemy: Burn / Chill (−45% speed) /
  Shock (+20% dmg taken). HealthComponent is now status-free.
- **Enemies**: Assassin (circle→dash→stab→retreat), Brute (stagger-resistant,
  big telegraphed slam). Blender models for both.
- **Elite prototype**: EliteModifier child node (×3 HP, aura, label);
  Emberbound (fire patches) & Stormtouched (telegraphed shock nova).
  Debug keys: 4 assassin, 5 brute, 6 elite.
- Perf: full rotation vs 29 mixed enemies incl. elite = 54 FPS avg on dev
  machine (worst-frame spikes remain mass-spawn only).

## What is playable
`tools\run_godot.cmd play` (or open in Godot 4.6.3 and F5) launches Runehold
(the hub; the Combat Lab is behind the training-grounds portal). M01 core:
third-person controller, free mouse camera (wheel zoom, SpringArm
collision), center-screen aim with capsule-sweep soft assist, directional
dodge with i-frames, Rune Cleave melee (alternating swings, Resonance
builder), Ember Lance (fire projectile + Burn DoT), Earthbreaker (Resonance
spender, AoE slam), melee Rusher + ranged Caster enemies with telegraphs and
3-tier hit reactions, full VFX/SFX feedback stack, HUD, damage numbers,
debug overlay (F1: spawn/heal/god/reset/stress/style keys), instant respawn.

## Verification status
- `tools\run_godot.ps1 smoke` — 35 headless functional checks, all green.
- `tools\run_godot.ps1 capture` — automated playtest writes 18 screenshots to
  captures/ (movement, dodge, each ability, telegraphs, stress, 3 art styles).
- Stress (`res://tests/stress_test.tscn`, windowed): 29 enemies + constant
  casting = **60 FPS avg** on the dev machine (baseline empty-scene cost is
  ~13ms here — weak GPU). Worst-frame spike ~100ms on mass spawn (26 enemies
  in one frame; not a gameplay scenario, pooling later if real spawns hitch).

## Important decisions
- Godot 4.6.3, binary at `C:\Users\mknop\Downloads\Godot_v4.6.3-stable_win64.exe\`
  (use `_console.exe`; `tools\run_godot.ps1` wraps it, `GODOT` env overrides).
- Code-built scenes; data-driven ability tuning via AbilityData .tres
  (see TECHNICAL_ARCHITECTURE.md for the full decision list).
- Aim assist: capsule sweep r=0.8 along the camera ray, extended 8m past
  terrain hits; direct enemy ray hits stay exact. Without it a shoulder camera
  fires projectiles into the ground short of distant targets.
- Enemy-enemy physics collision OFF (mask world+player) + O(n) separation
  steering — clustered capsule solver pairs were eating the frame budget.
- Duck-typed hitstop (`apply_hitstop`), never `process_mode=DISABLED`
  (breaks SpringArm/area queries).
- Hitstop 45ms melee / 70ms Earthbreaker; camera trauma shake + impulses.
- Directional shadow: single split (SHADOW_ORTHOGONAL), 60m max — 4-split PSSM
  cost ~2ms on the dev GPU. MSAA off (pixel aesthetic).
- Characters: Blender-5.2-headless generated GLBs
  (`tools/modelgen/generate_characters.py`) with primitive-mesh fallback in
  code. Weapons stay code-built (ability tweens animate the pivots).
  Imported GLB surface materials are duplicated per instance (shared
  materials made hit-flash light up every enemy of that type).
- Blender→Godot orientation: model front lands at Godot +Z; visuals apply
  `rotation.y = PI` on the instanced model.

## Art style status (M01 Step 15)
Three switchable render styles (debug key V), captured for comparison:
- A low-res (1/4 SubViewport, nearest): most cohesive stills, motion shimmer
  and aim precision risk — judge in live play.
- B native-pixel (posterize 7 + strong dither): strongest identity, slight
  readability cost, sky banding.
- C hybrid (posterize 14 + light dither) — **current default**: cleanest
  combat readability, pixel identity carried by textures/VFX.
Final lock needs the human motion test; record verdict in ART_BIBLE.md.

## Known weaknesses / next priorities
See KNOWN_ISSUES.md. Biggest feel unknowns that need a human hand on the
mouse: camera sensitivity defaults, dodge distance/cooldown trust, melee
range vs. enemy approach speed, whether Ember Lance cast lock (0.14s
stationary) feels bad while kiting.

## M02 recommendation (after M01 gate passes)
Combat depth: ability framework generalization (4 more abilities incl. a
mobility skill), elemental status interactions (Chill/Shock), 1–2 more enemy
archetypes (assassin/support), elite modifier prototype, first pass on
ability-modifier itemization hooks. No world/loot UI yet.
