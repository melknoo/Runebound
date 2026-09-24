# RUNEBOUND — Project State

Updated: 2026-09-23 (night) · Milestone: **M06 Art Direction Pass** — Phase C
propagation and Phase D gate work done; user gates pending (Style Gate
review on the captures, final playtest, listening checkpoint) ·
Plan: gold standard in Ashen Highlands South → Gate 0 (direction, user) →
production → Style Gate (user) → propagation → §71 Visual Quality Gate.
Environment work is reusable kit/systems only (Highlands become an open
zone in M08 — see ROADMAP).

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
`tools\run_godot.ps1 play` (or open in Godot 4.6.3 and F5) launches the Combat
Lab: third-person controller, free mouse camera (wheel zoom, SpringArm
collision), center-screen aim with capsule-sweep soft assist, directional
dodge with i-frames, Rune Cleave melee (alternating swings, Resonance
builder), Ember Lance (fire projectile + Burn DoT), Earthbreaker (Resonance
spender, AoE slam), melee Rusher + ranged Caster enemies with telegraphs and
3-tier hit reactions, full VFX/SFX feedback stack, HUD, damage numbers,
debug overlay (F3: spawn/heal/god/reset/stress/style keys), instant respawn.

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
- Directional shadow: single split (SHADOW_ORTHOGONAL), 50m max — 4-split PSSM
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
