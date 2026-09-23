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

## Physics layers
1 world · 2 player · 3 enemy · 4 player_hurtbox · 5 enemy_hurtbox · 6 projectile
Melee hits = shape queries against hurtbox layers; projectiles = Area3D.

## Data
`AbilityData` Resource (.tres in resources/abilities/) carries all ability
tuning: timing (startup/active/recovery), damage, type, weight, knockback,
resonance cost/gain, crit. Behavior lives in Player; numbers live in data.

## Testing
- `tools\run_godot.ps1 import|smoke|play|capture`
- `tests/smoke_test.tscn` — headless functional pass (must stay green)
- `tests/playtest_capture.gd` — windowed automated playtest, screenshots to
  `captures/` (run with `capture` mode) for visual review
