# RUNEBOUND — Project State

Updated: 2026-09-23 · Milestone: **M05 The Shattered Spire** · Status:
implementation complete, ~120 smoke checks green, awaiting user playtest.
**The vertical slice is content-complete**: Hub → Region → Mini-Boss →
Dungeon → Major Boss, with persistence.

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
