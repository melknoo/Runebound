# RUNEBOUND — Project State

Updated: 2026-09-25 · Milestone: **M09 Co-op** — in progress (plan approved by
the user 2026-09-25, see ROADMAP.md M09 for architecture, rules and phases).
M08 was played by the user; small notes follow after M09. M07 and M07b were
accepted on 2026-09-24. The co-op server laptop is set up:
[SERVER_SETUP.md](SERVER_SETUP.md) (Tailscale, port 7777/udp, systemd unit
disabled until M09 ships).

## M09 Co-op (2026-09-25, in progress)
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
    (M10/M11 placeholders) and the Colossus arena on the plateau. Level
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
