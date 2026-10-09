# RUNEBOUND — agent guide

Original third-person co-op ARPG (2-5 players), Godot 4.6.3, typed GDScript. Public repo `melknoo/Runebound`; a dedicated server (the owner's home laptop) follows the `release` branch. **This repo is the single source of truth** for status and know-how: Claude's local memory is not synced between machines. Put durable lessons into `docs/dev-notes/` (public, no secrets), not only into memory.

## The user (every machine)
- Reply in **German**, **extremely concise** (grammar may go). If a request is ambiguous, ask **one** clarifying question before doing anything.
- Commit and **push `main` after every finished piece of work** (standing rule since 2026-09-24).
- Never push or ship `release` unasked: the laptop server deploys it automatically (`tools\run_godot.cmd release` = main -> release fast-forward + deploy now). After a `Net.PROTOCOL` bump remind the user that a release must follow before co-op.
- The user **playtests every milestone** (the gate): the in-game list is on key J (J and F1 need developer tools: `run_godot play` / `coop` pass `--dev`, otherwise Settings -> Gameplay -> Developer tools); results land in `%APPDATA%\Godot\app_userdata\RUNEBOUND\playtest.json` on the PC where they play (not in git). When KNOWN_ISSUES gains or resolves a playtest point, update `resources/playtest/checklist.json` too (stable ids).
- The user models nothing by hand: the `tools/modelgen` scripts are the only source of 3D assets (live Blender = trying things + screenshots, port every result back into the script).
- Per milestone: plan first, with questions to the user; build in phases, each ending with smoke green + docs + commit/push. Numbers are data, tuned after playtest feedback.
- Docs are English (PROJECT_STATE, TECHNICAL_ARCHITECTURE, ...); the user-facing ROADMAP, SERVER_SETUP and HANDOFF are German.

## Session start
1. `git pull --rebase` (two machines work on this repo).
2. Read `docs/HANDOFF.md` section "Status", the top of `docs/PROJECT_STATE.md`, `docs/ROADMAP.md` (everything up to M12 is built, even where it still sits under "Aktuell" / "Geplant"; M13 is in progress, M14-M17 unbuilt) and `docs/KNOWN_ISSUES.md`. Some older section headings still say "in progress": the HANDOFF status and the file headers win.
3. Before touching code or the server, read the matching note (table at the end).

## Commands
Godot must be exactly **4.6.3-stable** (a 4.6.1 client crashed on an RTX 2070: a GPU TDR while the game ran embedded in the editor, see KNOWN_ISSUES; play and test standalone). Set `GODOT` to the **`_console`** exe (the plain exe prints no stdout); `tools/run_godot.ps1` falls back to a path on the owner's main PC.
- `tools\run_godot.cmd <mode>` (the `.cmd` bypasses the PowerShell execution policy). Modes: `import`, `smoke`, `play`, `capture`, `worldcapture`, `shots <list>`, `perf <scenario> [label]`, `stress`, `net [scenario]`, `server [port]`, `coop [bots]`, `serverperf [heroes]`, `solocheck [class] [level]`, `reset` (deletes the real save), `wsspike`, `release`, `deploy`; the header of `tools/run_godot.ps1` explains each. From the Bash tool: `cmd //c "tools\run_godot.cmd smoke"`.
- Linux (server laptop): `tools/server/run_godot.sh import|ensure-import|smoke|serve|serverperf|net` (`GODOT` default `~/godot/godot`).
- Tests are **scenes** (`tests/*.tscn`), never `--script` MainLoops (autoloads do not load there). `smoke` is headless and takes minutes (the test's own watchdog exits 2 after 420 s, the wrapper's hard limit is 8 minutes, exit 3). From the Bash tool pass `timeout: 600000` or run it in the background: the default 2-minute tool timeout is shorter. Last result: 773 checks green (2026-10-09, M13 phase 3, on the RTX 2070 PC). `run_godot` imports by itself when project files are newer than the import stamp (fresh clone, after a pull).

## Hard rules
- **Secrets:** `.env` (git-ignored, `PIXELLAB_API_KEY`) is never printed or committed. MCP servers are registered `-s local` (key-free) or `-s user` (key-bearing), **never** project scope or a `.mcp.json`. The repo is public: no IPs, address prefixes or keys in docs.
- **No passive regeneration out of combat** (user, 2026-09-30): healing between fights only from items (draughts, food), the Runehold hearth or the druid, each with a limit.
- Manual headless boots: pass `-- --save=user://scratch.json` (never touch the real save). Never run windowed tests while the user is playing; never edit scripts while a net suite runs.
- New player-facing texts are bilingual DE+EN through `Texts` (`resources/i18n/*.json`, `Texts.t`); older menus/HUD stay English until M14. Tests force English.
- A new net message or a changed shared layout bumps `Net.PROTOCOL`.
- Write code with the Write/Edit tools, not Bash heredocs (they mangle backslashes and backticks). Commit messages are English: a short subject in the style of the log (`M12 phase 7: the tome and its three abilities`) and a body that lists what changed; pass them via a file (`git commit -F`) with `git -c core.safecrlf=false`.

## Code rules (details: TECHNICAL_ARCHITECTURE)
- Enemies only via `_spawn_enemy` / `make_enemy`; rewards only via `ZoneBase.give_reward`; hits via `roll_ability_hit`; activation via `players_within` / `nearest_player`.
- Ground heights through the ground seam (`ZoneBase.ground_y` / `ground_point`, `VFX.ground_hit`), never y = 0. New zones are layout data + `PoiBuilder`.
- Anything that simulates in the world checks `Net.is_authority()`; roles via `Net.is_authority()/is_client()/is_dedicated()/has_view()`, never `DisplayServer`. The server owns enemies, camps, bosses, flags, chests, rewards and travel; each client owns its hero.
- Enemy looks go into `_present_state` / `play_fx`; hero ability looks through `Player.hero_fx(kind, args)` + a `HeroFx` entry; player feedback via `feel_shake / feel_impulse / ui_denied`.
- Save additions go under `world` or `characters[i]` (SaveGame is versioned; read new keys with defaults).

## Decided — do not re-propose
- Not chosen: weather/day-night, world events, outdoor NPCs, more music, memory/logic puzzles, dungeon events/modifiers.
- Ability icons stay with the generator `tools/texgen/ui.py` (PixelLab comparison, 2026-09-29).
- The laptop stays the server (no paid relay such as Hetzner, no third-party tunnel service such as playit.gg); friends join through Tailscale Funnel + invite codes.
- Potions and food are used from the inventory only (no hotkey). Animals are scenery (never targetable, no net traffic).

## What to read when
| Task | Read |
| --- | --- |
| Where are we, what is next | `docs/HANDOFF.md`, top of `docs/PROJECT_STATE.md`, `docs/ROADMAP.md` |
| Set up a machine | `docs/HANDOFF.md` |
| Toolchain, tests, perf A/B, shell/git quirks | `docs/dev-notes/workflow.md` |
| Writing GDScript, scenes, tests | `docs/dev-notes/gotchas.md`, TECHNICAL_ARCHITECTURE |
| Net, server, deploy | `docs/dev-notes/server-ops.md`, `docs/SERVER_SETUP.md`, TECHNICAL_ARCHITECTURE "Co-op (M09)" |
| Classes, abilities, loadout | CLASS_DESIGN, TECHNICAL_ARCHITECTURE "Classes and the loadout (M10)" and "Healing and allies (M11)" |
| World, biomes, POIs | WORLD_DESIGN, TECHNICAL_ARCHITECTURE "Open world (M08)" and "Sub-biomes (M12)" |
| Art, models, icons, sounds | ART_BIBLE, ASSET_MANIFEST |
| Items, progression, story, combat | ITEMIZATION, PROGRESSION_DESIGN, STORY_DESIGN, COMBAT_DESIGN |
| Menus, settings | TECHNICAL_ARCHITECTURE "Menus and settings (M17a)" |
| Known problems, playtest points | `docs/KNOWN_ISSUES.md` |

`laptop_prompt` in the repo root is a historical one-shot prompt (2026-09-24, server laptop setup): ignore it.
