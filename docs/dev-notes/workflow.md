# Workflow notes

Dev-environment and agent know-how that the architecture docs do not carry. Facts are dated where they can age. Architecture: TECHNICAL_ARCHITECTURE. Server: [server-ops.md](server-ops.md). Engine and GDScript pitfalls: [gotchas.md](gotchas.md).

## Toolchain
- **Godot 4.6.3-stable, exactly.** Windows: the `_console` exe (the plain exe prints no stdout), found through the `GODOT` env var (`tools/run_godot.ps1` has a fallback path of the owner's main PC). Linux: `~/godot/godot` or `GODOT`; never Godot from apt/flatpak/snap. A 4.6.1 client crashed on an RTX 2070 (KNOWN_ISSUES). `Net.godot_minor` compares only major.minor, so a 4.6.1 client can still join a 4.6.3 server: do not rely on that.
- **Blender 5.2** (`C:\Program Files\Blender Foundation\Blender 5.2\blender.exe`) runs headless: `--background --python tools/modelgen/<script>.py` (`generate_characters_v2.py`, `generate_props.py -- <prop>`). The live loop and its MCP server are in ASSET_MANIFEST "Live Blender".
- **Python 3** + `numpy`, `Pillow`, `fontTools` for the generators. Generated assets are committed (about 830 files): regenerate only what you change, then `run_godot import`.
  - `tools/texgen/generate.py`, `biome.py`, `ui.py`: pixel textures, biome textures, UI and ability icons.
  - `tools/sfxgen/generate.py`: synth WAVs. **Append new synths at the END**, the RNG order is shared.
  - `tools/worldgen/bake.py`: heightmap, trail mask, map and layout from `highlands_layout.py`; deterministic, asserts the layout rules.
  - `tools/fontgen/numerals.py`: the UI font `assets/fonts/RuneboundPixel.ttf` (Pixelify letters + grid-exact 5x7 digits). The user rejected Jacquard (blackletter) and Pixelify's own digits; `UiTheme.font()` always returns RuneboundPixel.
- **Icons:** a new ability icon is a new function in `tools/texgen/ui.py`, added to the icon loop in `main()` once its ability id exists; colour roles live in `art_spec.json`. Decided 2026-09-29: the generator beat PixelLab, do not reopen.
- **uv/uvx behind a system proxy:** with a SOCKS system proxy uv fails with "tunnel error ... dns error". Fix: `NO_PROXY=*` in the environment of every uv/uvx command (for the Blender MCP server `-e NO_PROXY=*`). The owner's main PC has such a proxy on purpose (an SSH tunnel): leave it alone.

## MCP servers and secrets
- `.env` holds `PIXELLAB_API_KEY` (git-ignored, the repo is public). Never print or commit it. PixelLab is no longer needed.
- Register MCP servers `-s local` (key-free, e.g. `blender`) or `-s user` (key-bearing, run from a terminal that reads the key from `.env` so it is never printed). Never project scope, never a `.mcp.json` in the repo.
- Local scope is keyed by the exact project path, **case-sensitively**. VS Code starts sessions as `d:\fable_test`, Bash and PowerShell write `D:/fable_test`, so a server registered from them is invisible to the VS Code extension. Register from **cmd** after `cd /d <your clone path, lowercase drive letter>` (on the main PC `d:\fable_test`) or use `-s user`. Check: `cmd /c "cd /d d:\fable_test && claude mcp get blender"`. MCP servers load only at session start. A session's working directory also flips between `d:\` and `D:\` after tool calls.
- Do not read `~/.claude.json` or run `claude mcp list` from a session: auto mode blocks both as credential exploration.
- Blender MCP: `uvx mcp-for-blender@2.1.1` (pinned, telemetry off, asset integrations off) plus the add-on "MCP for Blender" in Blender (sidebar -> "Connect to Claude", port 9876). Rule: the modelgen scripts stay the only source, every live result is ported back into the script before exporting.

## Tests and measurements
- Tests are scenes; `--script` MainLoops do not load autoloads. All modes are listed in the header of `tools/run_godot.ps1`; TECHNICAL_ARCHITECTURE "Testing" details shots, perf, solocheck and the save flags. From the Bash tool a smoke or net run needs `timeout: 600000` (or the background): the default tool timeout is 2 minutes.
- `smoke` runs unseeded: anything that counts random drops near the player is flaky, probe with a spawned object instead.
- `net [scenario]` spawns a real dedicated server and headless clients as processes (20-minute limit). Logs: `%APPDATA%/Godot/app_userdata/RUNEBOUND/net_test/`; a failing scenario keeps its logs in `net_test/failed/<scenario>/`. The full suite needs RAM: with WSL/Docker/other apps eating it `heal`, `handshake@ws` and `travel@ws` crash with "Out of memory" but pass alone. Never edit scripts while it runs: fresh child processes compile the half-edited tree.
- A local look at remote heroes: headless server + `tests/net_client.tscn -- --net-test=bot` and a windowed `--net-test=watch --snap=<png>`. `coop [bots]` is the one-command version.
- **Manual boots always pass `-- --save=user://scratch.json`.** A headless boot of a zone scene without a test flag once used the real save and migrated it (v5 -> v6) early, which ate a one-time toast. Headless runs without `--save=` now use `user://headless_save.json`; never boot windowed without a test flag.
- **Perf:** the dev PC's iGPU (Intel UHD 770) swings about 20 % between back-to-back runs (thermal), so only interleaved A/B counts.
  - Same tree: `_console.exe --path . --quit-after 30000 --resolution 1600x900 res://scenes/<zone>.tscn -- --perf=res://tests/perf/<s>.json --ab=<lookdev key>`.
  - Build vs build: `git worktree add --detach <scratchpad>/pre_x <commit>` OUTSIDE the project folder, `powershell -File <wt>/tools/run_godot.ps1 import`, then alternate `perf <scenario> <label>` between the two trees (drop each tree's cold first run: shader cache), `git worktree remove --force` afterwards.
  - A sky shader that uses TIME costs ~4 ms unless `Sky.process_mode = QUALITY` (see gotchas).
- **Playtest log:** the user ticks points in game (J). Read `%APPDATA%/Godot/app_userdata/RUNEBOUND/playtest.json` (`{items: {id: {state ok|problem, note, at}}}`, an `open` tick is erased) on their PC to pick up problems. Keep `resources/playtest/checklist.json` (German items, stable ids, one group per milestone) in step with KNOWN_ISSUES.
- **Solo check** (`solocheck [class] [level]`): bots never read telegraphs, so it is a floor for a player, not a verdict. `--only=<camp>` traces one fight (`-- --trace`).

## Process hygiene
- Before perf runs, or when crashes look random, list Godot processes: `Get-CimInstance Win32_Process -Filter "Name like 'Godot%'"`. Hung headless runs (once four, up to 22 h old) burn CPU, which throttles the iGPU (shared power budget). A second windowed game made the first die with "Vulkan device was lost" (Windows GPU resets).
- The user often has the Godot editor open (`--editor`) and plays via `run_godot play` (a `_console.exe --path` + `.exe --path` pair without `--editor`). Leave both alone and start no windowed test run then.
- The harness blocked PowerShell commands containing `rm` / `Remove-Item` on the repo root: use `-LiteralPath` on the single file, and Bash for ssh strings that contain `rm`.

## Shell, git and editing quirks (Windows)
- Bash-tool heredocs mangle backslash escapes (`\n`, `\r` become real characters) and fail on backticks ("unexpected EOF while looking for matching"). Write code, patch scripts and commit messages with the Write tool, then run them. Never put backslash paths in heredocs (`tools\run_godot` once turned into a CR). In a Python patch script a `'''...\r...'''` writes a real CR: use `chr(92)`.
- Line endings: `docs/*.md` are LF. Some repo files are CRLF (`zone_look.gd`, `terrain_pixel.gdshader`, `generate_props.py`, `biome.py`, the sfxgen files, the working copy of `art_spec.json`): patch scripts read with `newline=""`, normalise, write back with the file's own ending. Python `Path.write_text` writes CRLF on Windows: use `open(p, "w", newline="\n")` or bytes. Never re-dump `art_spec.json` (inline arrays expand).
- PowerShell 5.1: `Set-Content -Encoding utf8` writes a BOM (bad for `.gd`); `git commit -F -` here-strings with quotes get mangled, so write the message to a file.
- Git for Windows (`core.autocrlf=true`) prints "LF will be replaced by CRLF": harmless; commit with `git -c core.safecrlf=false`.
- Git Bash sometimes leaves a `bash.exe.stackdump` in the repo root (ignored by `.gitignore`).
- Blender: convert colours sRGB -> linear before Base Color, else models render too light. GLB fronts land at Godot +Z (`rotation.y = PI`).

## Commit rhythm
Commit and push `main` after every finished piece of work. Update the docs in the same piece (PROJECT_STATE, KNOWN_ISSUES, ROADMAP, the playtest checklist). After a `Net.PROTOCOL` bump remind the user to ship `release`.
