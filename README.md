# Runebound

Original third-person co-op action RPG (2-5 players) in a stylised pixel-fantasy world. Godot 4.6.3, typed GDScript; models, textures, sounds and the world heightmap are generated from scripts (Blender, Python). Singleplayer is complete, co-op runs on a dedicated server.

- **Status and next steps:** [docs/HANDOFF.md](docs/HANDOFF.md) (German), [docs/PROJECT_STATE.md](docs/PROJECT_STATE.md), [docs/ROADMAP.md](docs/ROADMAP.md)
- **Known problems:** [docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md)

## Run it
Godot **4.6.3-stable** exactly. On Windows point the environment variable `GODOT` at the `Godot_v4.6.3-stable_win64_console.exe`, then:

```
tools\run_godot.cmd import
tools\run_godot.cmd smoke    # headless tests, must end green
tools\run_godot.cmd play     # the game
```

Linux: `tools/server/run_godot.sh import|smoke|serve`. All modes: header of [tools/run_godot.ps1](tools/run_godot.ps1). Setting up a second machine: [docs/HANDOFF.md](docs/HANDOFF.md).

## Docs
| | |
| --- | --- |
| [GAME_VISION](docs/GAME_VISION.md), [ROADMAP](docs/ROADMAP.md) | what the game is, milestone order |
| [PROJECT_STATE](docs/PROJECT_STATE.md), [KNOWN_ISSUES](docs/KNOWN_ISSUES.md) | what is built, what is open |
| [TECHNICAL_ARCHITECTURE](docs/TECHNICAL_ARCHITECTURE.md) | how it is built |
| [CLASS_DESIGN](docs/CLASS_DESIGN.md), [COMBAT_DESIGN](docs/COMBAT_DESIGN.md), [ITEMIZATION](docs/ITEMIZATION.md), [PROGRESSION_DESIGN](docs/PROGRESSION_DESIGN.md) | gameplay design |
| [WORLD_DESIGN](docs/WORLD_DESIGN.md), [STORY_DESIGN](docs/STORY_DESIGN.md) | world and story |
| [ART_BIBLE](docs/ART_BIBLE.md), [ASSET_MANIFEST](docs/ASSET_MANIFEST.md) | look and asset pipelines |
| [SERVER_SETUP](docs/SERVER_SETUP.md) | the dedicated server |
| [dev-notes](docs/dev-notes/README.md) | workflow, engine pitfalls, server operations |

## Working with Claude Code
[CLAUDE.md](CLAUDE.md) is loaded automatically and tells the agent the rules, the commands and where to read what.
