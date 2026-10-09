# Engine and GDScript gotchas

Hard-won, one line each. Dates are when it bit. Architecture rules are in CLAUDE.md and TECHNICAL_ARCHITECTURE; shell and git quirks are in [workflow.md](workflow.md).

## Project, import, parsing
- A new `class_name` script is unknown to headless runs until `run_godot import` rescans; every dependent then fails with "Identifier not declared" (2026-09-23).
- Font import options antialiasing=0 / hinting=0 / subpixel=0 crash the 4.6.3 headless reimport (heap corruption): set `FontFile` pixel properties at runtime instead (2026-09-23).
- Godot auto-imports CSVs, so text tables are JSON (`Texts`, `resources/i18n/*.json`).
- Warnings are errors in this project, so Variant inference fails: `var x := weakref(...)` needs `: WeakRef`; `var b := dict["k"] == &"x"` needs `: bool`; loop variables over literal arrays need a type (`for corner: Vector2 in [...]`), else `var c := corner.rotated()` is a "cannot infer type" error.
- `x == [..] as Array[T]` parses as `(x == [..]) as Array[T]`: parenthesise or compare size and elements.
- An `@export var resource_name` on a Resource script fails to parse (clashes with `Resource.resource_name`). A `static func` sharing its name with an `@export var` (it was `ZoneLook.spire`) makes the whole class unparseable and every dependent fails.
- A const dict holding class references is not a constant expression: use a `match` function (`ZoneBase._enemy_script`).
- `TypedArray.find()` / `has()` errors on a freed object argument: scan manually or validate first (`targeting_system.cycle_target`).
- `--check-only` on a script with class dependencies only says "Failed to compile depended scripts": run the smoke test for the real parse error. Quick parse check: `_console.exe --headless --path . --check-only --script res://...` (autoload names show as "Identifier not found" there, ignore).
- Lambdas capture `Packed*Array`s by value, so appends vanish: use `Array`.
- `Texts.t` formats with `%` (`%s`, `%d`), never `{0}`; the smoke test checks it. Tests force English.

## Nodes, scenes, input, UI
- `add_child(node)` names duplicates `@Name@12`: use `add_child(node, true)` when a test counts by name prefix.
- Zones set node positions AFTER `add_child`, so `global_position` read in `_ready` (a spawner's `home`) is the world origin: resolve lazily.
- Projectiles set their position BEFORE `add_child`.
- Statics that hold materials or lambdas crash the process on quit unless an autoload clears them in `_exit_tree`.
- `_unhandled_input` reaches later-added siblings first: UI layers added after World consume Esc before Player.
- A Control added to a CanvasLayer after the viewport is sized must use `offset_*` after `set_anchors_preset`, not `position` (absolute puts it off-screen). Code-built Controls need `set_anchors_and_offsets_preset`; plain `set_anchors_preset` keeps the 0-size rect.
- `draw_string` with a small `width` and CENTER alignment clips glyphs: use width -1.
- Freeing an outlined rig together with its materials logs "material is null" in the renderer: drop the surface overrides first.
- `InputSetup.ensure()` runs once per process, else a zone load would wipe the player's rebinds.
- A plain `InputSource.new()` still has a script: check `is LocalInputSource`, not `get_script() == null`.
- Two coroutines awaiting the same `physics_frame` resume in connection order: record intermediate state (for example `EncounterSpawner.spawn_frames`) instead of trying to observe it.
- Smoke checks that observe `_process` effects (pickups, camera yaw -> compass heading) must `await get_tree().process_frame`; several physics steps can pass without an idle frame.
- The smoke test's `_run` is one function: new local names must be unique.

## Gameplay seams
- SpringArm camera children must not have their position overwritten: shake goes on a child node.
- Hitstop goes through the duck-typed `apply_hitstop`, never `process_mode = DISABLED`.
- Enemy-enemy physics collision is off (separation steering instead).
- Imported GLB materials are shared: duplicate per instance for the hit flash.
- Slows need min-wins (`add_buff` keeps the larger value, `maxf`).
- Burrowed and airborne enemies share one central hit guard.
- Untargetable enemies are skipped by bots, so dormant ones need a non-bot wake rule (ambush spawners call `wake()`).
- The `InteractPrompt` focus picks the nearest prompt; chests, shrines, portals and NPCs all go through it.
- Biomes need their own shapes (area circles overlap `dungeon_w` / `camp_6`); the biome mask is a texture, not vertex COLOR (rock hulls use COLOR for AO).
- Nests and curse lanterns are immobile `EnemyBase` types. Puzzle state goes through `PoiPuzzle` (`POI_ACT` / `POI_STATE`), never locally.

## Rendering and assets
- Godot's PNG loader cuts 16-bit channels to 8: the heightmap is a raw `height.r16` (uint16 LE) read with `FileAccess` + `decode_u16`.
- `HeightMapShape3D` is centred on its body (body at `origin + (res-1)/2`, 1 m cells, no scale); the smoke test checks collision against `height_at` at 50 random points.
- A sky shader that uses TIME makes Godot re-filter the radiance map every frame (+~4 ms) unless `Sky.process_mode = QUALITY`; in QUALITY mode the half-res sky pass does not update (white sky).
- The dummy (headless) renderer keeps no MultiMesh buffers: `get_instance_transform` returns identity there.
- First use of a shader pipeline costs 50-140 ms (Intel compiles Forward+ variants synchronously): see KNOWN_ISSUES.
- The dev PC is an iGPU: two windowed game instances at once can lose the Vulkan device (workflow.md "Process hygiene").

## Networking
- ENet's packet throttle drops unreliable packets on links quantised to 60 fps: `ENetPacketPeer.throttle_configure(5000, 32, 0)`. Right after a zone build about one second may still drop.
- `ENetMultiplayerPeer` silently resets connections whose connect data (the peer id) is < 2: raw `ENetConnection` test clients must pass a random id >= 2.
- The server probe writes its result file aside and renames it (a read once caught it empty).
- Bots have no camera: zone abilities need an aim point (`_bot_aim_point` of the druid), else they land at full reach.

## Tests
- A test standing in the bone field wakes the elite patrol (55 m) and breaks later camp counts: test the brood enemies in trial_f's clearing.
- Smoke runs unseeded (random drops are flaky); automated windowed runs use the scratch save and a fixed seed.
- Headless and test runs use default settings and never touch `settings.cfg`; `--snap` is a test-run flag (capture save).
