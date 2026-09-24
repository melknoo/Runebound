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

## M06 look kit (all generated from assets/art_spec.json — sRGB palettes)
| asset | generator | size / density | notes |
|---|---|---|---|
| assets/textures/biome/hl_ash_a, hl_ash_b, hl_ash_top, hl_strata, hl_basalt | tools/texgen/biome.py | 64 px tiles = 2 m (32 px/m) | tileable, per-texture seeds, palette-quantized, lossless + mipmaps |
| assets/textures/biome/macro_noise, sky_clouds | tools/texgen/biome.py | 64 / 128x64 | blend mask (linear), 3-level cloud mask |
| assets/models/chars/runebreaker.glb + textures/char/runebreaker_atlas.png | tools/modelgen/generate_characters_v2.py | atlas 512 (64 px/m, Gate 0) | 17-bone rigid rig @60 fps: idle, run, cleave_l/r, dodge, ember, earthbreaker_rise/impact, storm_step, chain_spark + fracture_rune (upper body), flinch (additive); 2 surfaces (body, glow) |
| assets/models/chars/cinder_marauder.glb + textures/char/cinder_marauder_atlas.png | same | 512 (64 px/m) | hunched raider rig: idle, run, attack (contact = WINDUP_TIME, blade on the disc centre), stagger; 3 surfaces (body, eyes, telegraph axe) |
| assets/models/chars/duskweaver.glb + textures/char/duskweaver_atlas.png | same | 512 (64 px/m) | legless caster rig (robe hem bone, staff on root): idle, glide, charge (= WINDUP_TIME), cast, stagger; 2 surfaces (body, eyes); orb stays code-built |
| assets/models/env/highlands/{bonfire, rune_monolith, banner_pole, charred_tree, bone_pile, log_seat}.glb + textures/env/*_atlas.png | tools/modelgen/generate_props.py | 32 px/m | static kit props; monolith wraps its collider; walk-through props <= 0.4 m; banner cloth on a `_cloth` material (wind sway) |
| assets/models/env/highlands/{ash_tuft, stone_cluster}.glb + atlases | same | 32 px/m | scatter items (scripts/world/scatter.gd, MultiMesh); tuft = solid tapered blades on a `_cloth` material |
| assets/music/highlands_{explore, combat}.wav | tools/musicgen/compose.py | 53.3 s stereo loops, 32 kHz, 16-bit (QOA on import) | same key/tempo/length, played in sync by MusicDirector; loop_mode Forward in .import |
| assets/fonts/PixelifySans.ttf (+ OFL_PixelifySans.txt) | google/fonts ofl/pixelifysans (SIL OFL 1.1) | crisp 20/40/60 px | UI body + numbers; pixel rendering set at runtime (UiTheme) |
| assets/fonts/RuneboundPixel.ttf (+ OFL_RuneboundPixel.txt) | Pixelify Sans, modified by `tools/fontgen/numerals.py` (SIL OFL 1.1) | crisp 20/40/60 px | **the UI font**: Pixelify letters, digits 0-9 redrawn on the pixel grid (5x7, tabular) |
| assets/fonts/Jacquard24-Regular.ttf (+ OFL_Jacquard24.txt) | google/fonts ofl/jacquard24 (SIL OFL 1.1) | crisp 43/86 px | titles, boss + place names |
| assets/ui/{frame, slot, bar, button, button_hover, button_pressed, cooldown}.png | tools/texgen/ui.py | art 1x, saved 2x | 9-slice pixel frames (teal player accent), radial cooldown fill |
| assets/ui/icons/{melee, ember, earthbreaker, storm_step, chain_spark, fracture_rune, dodge}.png | tools/texgen/ui.py | 20x20 art, saved 40x40 | ability icons in their element colour roles, 1-px ink outline |
| assets/models/spike/spike_biped.glb | tools/modelgen/spike_rig.py | — | A4 pipeline spike only |
| assets/models/chars/{stonehulk, veilstalker, hollow_warden, ashvein_colossus, vessel}.glb + textures/char/*_atlas.png | tools/modelgen/generate_characters_v2.py | 256–512 atlases (64 px/m) | Phase C cast; clips listed in ART_BIBLE §7 "Cast"; Colossus slot 2 = veins (code-owned), Vessel = floating-construct rig (body segments, orbit bone) |
| runebreaker.glb (update) | same | same atlas (byte-identical) | the blade moved to its own surface (slot 2) so legendary weapons can restyle it |
| assets/textures/biome/rh_{flagstone (128), earth, granite_top, masonry, moss, turf} | tools/texgen/biome.py | 64 px = 2 m (flagstone 128 = 4 m) | Runehold ground, walls, sod roofs, meadow |
| assets/textures/biome/sp_{floor (128), wall, wall_top, crystal} | same | same | Spire slab floor, coursed walls, crystal |
| assets/models/env/runehold/{rh_hut_trim, rh_wall_banner, rh_pine, rh_oak, rh_hearth_fire, rh_hearth_stone, rh_grass_tuft, rh_stone_cluster, rh_weapon_rack, rh_training_post}.glb + textures/env/*_atlas.png | tools/modelgen/generate_props.py | 32 px/m | settlement trim, trees, hearth (animated `flames` node), scatter items, wall-hugging training gear |
| assets/models/env/spire/{sp_crystal_pillar, sp_wall_arch, sp_beacon, sp_shard, sp_crystal_cluster, sp_rubble}.glb + atlases | same | 32 px/m | pillar wraps its collider, relief arch <= 0.3 m deep, torch v2 (`orbit` node), floating debris, scatter |
| assets/models/env/common/{portal_arch, portal_plate, treasure_chest, loot_blade, loot_armor, loot_relic, loot_helm, loot_gloves, loot_boots, loot_ring, legendary_cindermaw, legendary_conductors_oath, legendary_glacier_heart}.glb + atlases | same | 32 px/m | portal v2 frame + plate, chest with hinged `lid` node (own atlas), loot and legendary drop shapes |
| shaders/portal_gate.gdshader | — | 16 px/m snap | upright swirling gate oval, sealed state |
| assets/ui/items/{weapon, armor (chest), relic (amulet), helm, gloves, boots, ring, cindermaw, conductors_oath, glacier_heart}.png | tools/texgen/ui.py | 16x16 art, saved 32x32 | inventory icons |
| assets/music/runehold_{explore, combat}.wav, spire_{explore, combat}.wav | tools/musicgen/compose.py | 58.2 s / 64.0 s stereo loops | loop_mode Forward in .import |
| assets/music/stinger_victory.wav | same | 4.6 s one-shot | boss-kill stinger (not looped) |
| resources/talents/*.tres (24) | tools/talents/generate_talents.py | — | M07 talent nodes (TalentData), generated from one table |
| resources/abilities/{runic_guard, resonance_burst}.tres | hand-authored data | — | M07 talent abilities (G, H) |
| assets/ui/icons/{runic_guard, resonance_burst}.png | tools/texgen/ui.py | 20x20 art, saved 40x40 | HUD slots for the talent abilities |
| assets/sfx/{level_up, runic_guard, resonance_burst}_01.wav | tools/sfxgen/generate.py (appended last: earlier sounds stay byte-identical) | 32 kHz mono | M07 level-up chime, ward snap, burst bloom |
| runebreaker.glb clips runic_guard, resonance_burst | tools/modelgen/generate_characters_v2.py | — | M07 talent ability clips (upper-body ward, full-body burst) |
Blender helpers: tools/modelgen/lib/rig.py (armature, rigid parts, lofts, actions, export),
tools/modelgen/lib/atlas.py (UV to exact density, pixel-atlas bake). GLB imports:
60 fps, no LODs, name suffixes off (no accidental -col bodies). Regenerate:
`blender --background --python tools/modelgen/generate_characters_v2.py` (and
generate_props.py), `python tools/texgen/biome.py`, then `tools\run_godot.ps1 import`.
