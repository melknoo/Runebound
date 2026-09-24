# RUNEBOUND — Technical Architecture

Godot 4.6.3 stable, typed GDScript, Forward+. Physics 60 Hz.

## Decisions
- **Code-built scenes for M01.** Player, enemies, VFX and UI construct their
  node trees in `_ready()`. Rationale: the combat lab iterates on behavior and
  tuning, not art layout; hand-written .tscn files were the main friction in
  autonomous iteration. Revisit when real 3D assets replace primitive meshes.
- **No NavigationAgent yet.** Arena is open; enemies steer directly at the
  player via `move_and_slide`. Add navmesh when levels gain real layouts.
- **Hitstop is duck-typed** (`apply_hitstop(duration)` on Player/EnemyBase):
  entities freeze their own `_physics_process` without leaving the physics
  space. `process_mode = DISABLED` broke SpringArm raycasts (body removed
  from space) — do not go back to it.
- **Projectiles position BEFORE `add_child`.** Spawning at origin for one
  frame overlaps the arena floor and self-detonates.
- **Autoloads:** `GameFeel` (hitstop, camera feedback, damage numbers),
  `Sfx` (pooled positional audio, auto-scanned variant library).
  `VFX` is a static class, not an autoload.
- Tests are **scenes**, not `--script` MainLoops — autoloads only exist in
  scene runs.

## World & persistence (M04)
- **ZoneBase** (`scripts/world/zone_base.gd`) owns all bootstrap; zones
  (CombatLab, HubZone, AshenHighlands) override `_build_zone()`,
  `_environment_colors()`, `_player_spawn_point()`. World objects (Portal,
  EncounterSpawner, TreasureChest) find their zone via
  `get_tree().current_scene as ZoneBase`.
- **SaveGame** autoload: versioned JSON, `save_path` var (tests point it at a
  scratch file — never let tests touch the real save), debounced writes,
  `restore_player()` called by ZoneBase after spawn. Gear survives zone travel
  because `travel_to()` saves synchronously before `change_scene_to_file`.
- Ambient loops: WAVs are made loopable (tail-into-head crossfade in sfxgen)
  and get `AudioStreamWAV.loop_mode = LOOP_FORWARD` set at runtime on a
  duplicate of the imported stream.

## Look pipeline (M06)
- `assets/art_spec.json` is the single source of look parameters (sRGB
  palettes, color roles, texel densities, outline, emissive caps, marker
  heights, shadows); Python generators and ArtKit read it.
- Blender helpers in `tools/modelgen/lib/rig.py`: rigid-skinned parts, box UVs
  at a fixed texel density, 60 fps actions (slotted-action safe), GLB export
  without images. sRGB→linear happens before values reach Blender.
- `LookDev` (static registry) exposes switchable look variants to shot lists,
  perf A/B and the debug overlay (O = outline). Start values from the
  command line: `-- --look=<key>:<value>`.
- `ArtKit` hands out materials by role: terrain (world-mapped pixel shader),
  character bodies (baked 64 px/m atlas, toon, rim, stencil outline), props
  (32 px/m atlas, no outline), glow parts (unshaded, fog-exempt).
- `CharacterAnimator` plays rig clips from the owner's existing state
  (`Player.action_started`, `EnemyBase.state_entered`): manual advance,
  hitstop freeze, speed-matched locomotion, animation LOD. Enemies drive
  their AnimationPlayer directly. The player's "layered" profile builds an
  AnimationTree:
  - `base` is a Transition over idle / run (time-scaled) / full-body
    one-shots;
  - `upper` is a OneShot filtered to the upper-body bones (Chain Spark,
    Fracture Rune play over running legs);
  - `flinch` is a OneShot in ADD mode.
  A finished-looking one-shot is handed to locomotion once the owner is free
  (`free` callable) and moving, after a 0.1 s commit.
- Environment kit:
  - `SetPieces` builds POIs (bonfire, raider camp, collider wrapping). It
    matches prop surfaces by material name: `_glow` gets the emissive
    material, `_cloth` gets `ArtKit.sway_material`.
  - `Scatter.populate(zone, rules)` places items in bands around the
    obstacle footprints from `ZoneBase.scatter_obstacles()`.
    - Output is one MultiMeshInstance3D per item and 16 m chunk under
      `world/Dressing`.
    - Each chunk also stores its world positions as meta, because the
      headless renderer keeps no MultiMesh buffers.
- Settlement and interior builders (Phase C), all static in `SetPieces`, all
  wrapping existing colliders without adding any:
  - `masonry_wall(body, role, pier_every, end_piers)` swaps the box to a
    terrain role and adds one merged mesh (cap course plus piers). It
    returns the pier offsets, so banners and arches go between them.
  - `hut(body, roof, wall_role, roof_role, door_back)` builds a sod gable
    around the roof slab (`gable_mesh`) and adds the trim prop.
  - `hearth(zone, pos, stones, logs)` and `wall_banner(zone, face, inward)`.
  - Kit props live in `assets/models/env/<kit>/` (highlands, runehold,
    spire, common). `prop_path()` searches the kits. A prop part with its
    own baked atlas (e.g. `treasure_chest_lid`) gets that atlas;
    `glow_object()` in the generator exports animated emissive nodes
    (`flames`, `orbit`).
- `terrain_pixel` extras are shader-side and cost nothing when unused:
  - Paving: `paved_circles` / `paved_paths`, set via `ArtKit.paved`.
  - Rune inlays: `rune_lines`, set via `ArtKit.inlaid`.
  - Each top layer samples at its own tile size (`textureSize`).
- ZoneLook presets: `ZoneLook.runehold()` (hub and lab) and
  `ZoneLook.spire_interior()`. `interior = true` builds a colour background
  and one cold top light with shadows; the rim is skipped at energy 0.
  - GDScript gotcha: a static func must not share a name with an exported
    property (`spire` vs `spire_interior`); the class then fails to parse
    everywhere.
- Enemy rigs (all types) go through `EnemyBase._setup_rigged_visual`.
  - Pivot tweens the clips replace run on invisible stand-ins
    (`ArmsPivotStandIn`, `BladePivotStandIn`).
  - Code-owned surfaces (the Colossus' veins on slot 2) keep emission on and
    ramp energy only.
  - `ZoneBase.make_enemy(id)` is the one factory (spawn, warm-up, shot
    runner).
  - Zones list the types they warm up in `_warm_up_ids()`.
- CharacterAnimator state entries:
  - `"~clip"` loops a clip for as long as the state lasts (strafe, dash,
    retreat, charge, stun, p2_idle). A running one-shot plays out first.
  - A Callable picks the clip (the Colossus' WINDUP is either a slam or a
    charge).
  - `rate` is a Callable that scales a one-shot's playback (the enraged
    slam).
  - Zones and enemies may call `play_one_shot` for presentation beats
    (roar, shatter, fan).
- `MusicDirector.stinger(key)` plays `assets/music/stinger_<key>.wav` once
  over the ducked zone music (boss deaths).
- Clip authoring (`tools/modelgen/`): poses are FK Euler dicts plus intents
  (`_reach.R`, `_blade.R`, see `lib/pose.py`). Every key is a full pose over
  the stance. `--sheets` renders contact sheets for review.
- VFX (`scripts/systems/vfx.gd`, static):
  - `telegraph_disc` / `telegraph_lane` draw enemy danger with
    `threat_marker.gdshader` and tween its `progress`.
  - `player_ring` / `ground_ring` draw dashed player marks and shockwaves
    with `player_ring.gdshader`.
  - `burst()` uses CPUParticles3D; GPU bursts stay behind LookDev
    `vfx_cpu` for A/B.
  - Quads, arc meshes and materials are cached, and cleared in
    `GameFeel._exit_tree`.
  - `VFX.warm_up(root, spot)` draws every effect once. `spot` must be inside
    the view frustum: culled draws compile nothing.
- Audio:
  - The `Sfx` autoload creates the buses at runtime (no
    `default_bus_layout`, no `project.godot` change) and routes by key
    (`Sfx.bus_for`).
  - It also hosts `MusicDirector` (`MusicDirector.instance`).
  - Zones return a music key from `_zone_music()`; ZoneBase starts it on
    ready and fades it on travel.
  - Looping WAVs are looped by their `.import` (`edit/loop_mode=2`), never
    at runtime.
- UI: `UiTheme` (static) builds the Theme.
  - Fonts get pixel rendering set on the FontFile at runtime; the same
    options in the `.import` file crash Godot 4.6.3's headless font
    reimport.
  - `UiTheme.apply(root)` is used on the HUD, tooltip and inventory roots.
  - `UiTheme.label3d()` sets up world labels (fixed_size, `pixel_size` from
    the camera FOV and viewport height).
  - The UI kit comes from `tools/texgen/ui.py`.
- Materials that effects light up (hit flash, axe telegraph) keep emission
  enabled at energy 0 (`ArtKit.KEEP_EMISSION`). Toggling `emission_enabled`
  compiles a new shader variant on first use.

## Progression (M07)
- `Progression` (child of Player) holds level, XP and talent ranks and
  caches the stat and power totals.
  - `Player.stat(key)` = `Equipment.stat` + `Progression.stat`.
  - `Player.has_power(id)` checks both, so a legendary can grant a
    talent's behavior.
  - Every ability hook (and `EmberLanceProjectile`) reads through these.
- Talents are `TalentData` resources (`resources/talents/`, generated from
  one table by `tools/talents/generate_talents.py`).
  - A talent is either a numeric stat (`stat` + `per_rank`) or a behavior
    (`power`, checked in the ability code).
  - `Progression.tree()` loads them once.
- Player hits carry `HitInfo.from_player`, `ability` and `burn_mult`. The
  conditional talent damage is applied in `EnemyBase.take_hit` via
  `Player.talent_damage_mult` (Shocked, Burning, Ember Lance).
- The barrier (`Player.grant_barrier`) absorbs damage before health in
  `Player.take_hit`. Unbroken triggers there while the dodge's i-frames
  are on.
- XP awards live in `ZoneBase._on_enemy_died`, `EncounterSpawner` (camp
  clear), `TreasureChest.open` and `ZoneBase._discover` (first visit,
  flag `discovered_<scene>`).
- Levels: zones map areas in `_enemy_level(enemy, pos)` (applied in
  `_spawn_enemy` before `_ready`, which scales health), and
  `ItemGenerator.apply_item_level` scales drops.
- `InputSetup.ensure()` adds the M07 input actions at runtime (N, G, H),
  so `project.godot` stays untouched.
- SaveGame v2: `SaveGame.migrate()` upgrades v1 saves.

## Physics layers
1 world · 2 player · 3 enemy · 4 player_hurtbox · 5 enemy_hurtbox · 6 projectile
Melee hits = shape queries against hurtbox layers; projectiles = Area3D.

## Data
`AbilityData` Resource (.tres in resources/abilities/) carries all ability
tuning: timing (startup/active/recovery), damage, type, weight, knockback,
resonance cost/gain, crit. Behavior lives in Player; numbers live in data.

## Testing
- `smoke` runs under an 8-minute hard limit (exit code 3): a compile error
  before the test's own watchdog starts would otherwise idle forever.
- Shot lists can spawn bosses (`colossus`, `vessel`) and start an attack on
  a frozen enemy (`"call": "_start_windup"`), so windups are caught at any
  fraction. `{"do": "legendary"}` drops a legendary.
- `tools\run_godot.ps1 import|smoke|play|capture|worldcapture|stress`
  (`tools\run_godot.cmd <mode>` does the same where the PowerShell execution
  policy blocks .ps1 files). Windowed modes warn when another game instance
  is running (GPU contention on the iGPU). Smoke quits with code 2 after a
  300 s watchdog.
- Debug a copied save without touching the real one:
  `-- --save=user://<file>.json` (no wipe, no fixed seed).
- `tools\run_godot.ps1 shots <list>` — data-driven screenshots from
  `tests/shots/<list>.json` (zone, camera, spawns, actions, LookDev variants).
- `tools\run_godot.ps1 perf <scenario> [label]`: scripted fight from
  `tests/perf/<scenario>.json`.
  - Reports the median of repeats with GPU/CPU render time, keeps history in
    `captures_perf/`, and exits 1 below `budget_fps`.
  - Frames over 50 ms are listed with the fight step that preceded them,
    their GPU / render-CPU / script time and new pipeline compiles.
  - `-- --prefire=a,b` runs abilities or effects once before recording, to
    bisect first-use hitches.
- Windowed test modes run with `--quit-after 30000`, so a run whose runner
  never attaches (for example after a script compile error) can't hang.
- Automated runs (`--capture/--worldcapture/--shots/--perf/--stress`) use the
  scratch save and a fixed RNG seed from the first frame (SaveGame autoload).
- `tests/rig_spike.tscn` — rig/animation pipeline checks (headless) and
  `-- --spike-visual` captures + crowd perf (windowed).
- `tests/smoke_test.tscn` — headless functional pass (must stay green)
- `tests/playtest_capture.gd` — windowed automated playtest, screenshots to
  `captures/` (run with `capture` mode) for visual review
