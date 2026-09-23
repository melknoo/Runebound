# RUNEBOUND — Asset Manifest

All current assets are generated procedurally (no asset-generation MCP servers
exist in this environment; Python numpy/Pillow + synth WAV pipeline instead).
Blender 5.2 is installed (`C:\Program Files\Blender Foundation\Blender 5.2`)
and available for headless scripted 3D asset generation in later passes.

## Textures — tools/texgen/generate.py (seeded, deterministic)
| file | size | purpose |
|---|---|---|
| assets/vfx/spark.png | 16 | melee/lightning impact particles |
| assets/vfx/ember.png | 16 | fire particles, Ember Lance trail |
| assets/vfx/dust.png | 16 | dodge dust, slam dust |
| assets/vfx/shard.png | 16 | debris, death bursts |
| assets/vfx/smoke.png | 24 | fire impact smoke |
| assets/vfx/flash.png | 32 | impact flash star |
| assets/vfx/glyph.png | 32 | rune cast flash |
| assets/vfx/ring.png | 64 | shockwave rings |
| assets/vfx/slash.png | 64 | melee arc |
| assets/vfx/scorch.png | 64 | fire ground decal |
| assets/vfx/cracks.png | 64 | Earthbreaker decal |
| assets/vfx/telegraph.png | 64 | enemy/ground telegraph disc |
| assets/textures/floor.png | 64 | arena floor tiles (plum stone) |
| assets/textures/stone.png | 64 | walls/blocks |
| assets/textures/rune_stone.png | 64 | accent blocks w/ teal runes |

All imported nearest-filtered (project default), used with alpha-scissor
billboard materials for particles. Regenerate: `python tools/texgen/generate.py`.

## Audio — tools/sfxgen/generate.py (32 kHz mono WAV, seeded)
35 files in assets/sfx/, grouped by prefix with _NN variants; Sfx autoload
auto-discovers. Keys: footstep, swing, impact_flesh, enemy_hurt, enemy_death,
dodge, ember_cast, ember_fire, ember_impact, earthbreaker_windup,
earthbreaker_impact, telegraph, caster_charge, bolt_fire, bolt_impact,
player_hurt, ui_denied, storm_step, chain_spark, rune_place, rune_detonate,
pickup, equip, legendary_drop, wind_loop, campfire_loop, portal_hum,
portal_travel, chest_open, boss_roar, charge_horn, spire_drone_loop,
boss_blink, vessel_roar, shatter_burst.
Regenerate: `python tools/sfxgen/generate.py`.
Textures also include: ash_ground, ash_rock, spire_floor, spire_wall.

## 3D models — tools/modelgen/generate_characters.py (Blender 5.2 headless)
| file | purpose |
|---|---|
| assets/models/player_runebreaker.glb | armored knight body: beveled iron, teal pauldrons, emissive visor/sigil, crest |
| assets/models/enemy_rusher.glb | horned brute: rust slabs, bone jaw/horns, emissive gold eyes |
| assets/models/enemy_caster.glb | hooded robe cone, void face, emissive magenta eyes |
| assets/models/enemy_assassin.glb | slim crouched skirmisher, scarf, cyan eye slit |
| assets/models/enemy_brute.glb | massive stone slabs, moss patches, ember eyes |
| assets/models/enemy_warden.glb | shield-slab construct, teal core exposed on the back |
| assets/models/boss_vessel.glb | floating crystal shard construct, glowing violet heart |

Weapons (sword/axe/staff+orb) are code-built so ability tweens can animate
their pivots. Regenerate models:
`& "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" --background --python tools/modelgen/generate_characters.py`
then reimport (`tools\run_godot.ps1 import`). Fallback primitive bodies remain
in code if a GLB is missing.
