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
| assets/textures/biome/{vl,bf,bn}_{ground_a, ground_b, top, trail, rock, masonry} | tools/texgen/biome.py (`generate_subbiomes`) | 64 px tiles = 2 m (32 px/m) | M12 sub-biome looks (village, burnt forest, bone field) from `palettes.village / burnt_forest / bone_field`; read into texture arrays at runtime (all 64 px) |
| assets/world/highlands/biome_mask.png | tools/worldgen/bake.py | 384 x 384, 1 px/m | M12 sub-biome weights (R village, G burnt forest, B bone field); own RNG |
| assets/models/chars/runebreaker.glb + textures/char/runebreaker_atlas.png | tools/modelgen/generate_characters_v2.py | atlas 512 (64 px/m, Gate 0) | 17-bone rigid rig @60 fps: idle, run, cleave_l/r, dodge, ember, earthbreaker_rise/impact, storm_step, chain_spark + fracture_rune (upper body), flinch (additive); 2 surfaces (body, glow) |
| assets/models/chars/cinder_marauder.glb + textures/char/cinder_marauder_atlas.png | same | 512 (64 px/m) | hunched raider rig: idle, run, attack (contact = WINDUP_TIME, blade on the disc centre), stagger; 3 surfaces (body, eyes, telegraph axe) |
| assets/models/chars/duskweaver.glb + textures/char/duskweaver_atlas.png | same | 512 (64 px/m) | legless caster rig (robe hem bone, staff on root): idle, glide, charge (= WINDUP_TIME), cast, stagger; 2 surfaces (body, eyes); orb stays code-built |
| assets/models/env/highlands/{bonfire, rune_monolith, banner_pole, charred_tree, bone_pile, log_seat}.glb + textures/env/*_atlas.png | tools/modelgen/generate_props.py | 32 px/m | static kit props; monolith wraps its collider; walk-through props <= 0.4 m; banner cloth on a `_cloth` material (wind sway) |
| assets/models/env/highlands/{trial_altar, curse_lantern, wisp_nest, jackal_den}.glb + textures/env/*_atlas.png | tools/modelgen/generate_props.py (`trial_altar`, `curse_lantern`, `wisp_nest`, `jackal_den`) | 32 px/m | M12 phase 6: the trial shrines' altar (rune in the player accent), the graveyard's curse lanterns (the Restless' sickly gold, #C8D86A) and the two nests; the lantern and nests are bodies of enemies (outline added in code) |
| assets/models/env/highlands/tome_lectern.glb + textures/env/tome_lectern_atlas.png | tools/modelgen/generate_props.py (`tome_lectern`) | 32 px/m | M12 phase 7: the stone lectern with the open tome (runes in the player accent) |
| assets/ui/icons/{lodestone_rune, hoarfrost_fan, rootwalk}.png | tools/texgen/ui.py (`icon_lodestone_rune`, `icon_hoarfrost_fan`, `icon_rootwalk`) | 20 px | M12 phase 7: the three tome abilities |
| assets/ui/map/{trial, nest, cursed}.png | tools/texgen/ui.py (`mk_trial`, `mk_nest`, `mk_cursed`) | 12 px | M12 phase 6 map marks |
| assets/models/chars/{ash_jackal, carrion_vulture}.glb + textures/char/*_atlas.png | tools/modelgen/generate_characters_v2.py (`jackal`, `vulture`) | 64 px/m | M12 phase 5, the carrion brood: jackal on the four-legged template (idle, run, trot, pounce, stagger), vulture on the winged one (idle, soar, charge, swoop, takeoff, stagger); 2 surfaces (body, eyes) |
| assets/models/chars/{ash_hare, carrion_crow}.glb + textures/char/*_atlas.png | tools/modelgen/generate_characters_v2.py (`hare`, `crow`) | 64 px/m | M12 phase 5 animals (scenery, no outline, no glow): hare (idle, hop, alert), crow (idle, fly, takeoff); 1 surface |
| assets/sfx/{jackal_snarl_01-02, vulture_screech_01, wing_beat_01-02}.wav | tools/sfxgen/generate.py (appended) | 32 kHz mono | M12 phase 5: the jackal's snarl and bite, the vulture's screech from above, wing beats (vulture and crow) |
| assets/models/chars/{grave_shambler, mourner, cinderbark, smoulder_wisp}.glb + textures/char/*_atlas.png | tools/modelgen/generate_characters_v2.py (`shambler`, `mourner`, `cinderbark`, `wisp`) | 64 px/m | M12 families: shambler (idle, run, attack, stagger, emerge), mourner (idle, glide, charge, cast, stagger), cinderbark (idle, run, slam, stagger, dormant, wake), wisp (idle, glide, charge, cast, stagger); 2 surfaces (body, eyes) |
| assets/models/env/highlands/{ash_tuft, stone_cluster}.glb + atlases | same | 32 px/m | scatter items (scripts/world/scatter.gd, MultiMesh); tuft = solid tapered blades on a `_cloth` material |
| assets/models/env/highlands/{vl_rafters, vl_fence, vl_well, vl_grave, vl_grave_cross, vl_barricade, vl_cart, bf_snag, bf_log, bf_stump, bn_rib, bn_skull, bn_vertebra, vg_fallen, vg_tent, vg_spears}.glb + atlases | same | 32 px/m | M12 sub-biome and storytelling kit (BiomeDressing); solid ones over 0.4 m stand on blockers; snag / stump with a dim ember `_glow`; trunks via Grove (MultiMesh), stumps via Scatter |
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
| assets/world/{hollow_cistern, puzzle_lab}/{layout.json, map.png} | tools/worldgen/dungeon_bake.py (from cistern_layout.py, lab_layout.py; deterministic, asserts the room rules) | map 3 px/m | M13 dungeons: rooms, doors, merged walls, channels, POIs with floor heights |
| assets/textures/biome/ci_{floor (128), wall, wall_top} | tools/texgen/biome.py (`generate_cistern`, `python tools/texgen/biome.py cistern`) | 64 px = 2 m (floor 128 = 4 m) | M13 Cistern slabs and walls with algae in the joints (`palettes.cistern`) |
| assets/models/env/cistern/{ci_lamp, ci_wall_arch, ci_pipe, ci_grate, ci_sluice_gate, ci_moss_tuft, ci_rubble}.glb + textures/env/*_atlas.png | tools/modelgen/generate_props.py (`CISTERN_PROPS`) | 32 px/m | M13 cistern kit: lantern on an arm (phosphor `_glow`), relief arch with a drain mouth, pipe run, floor grate, sluice frame, scatter; placed by DungeonDressing, no collision |
| shaders/water_pixel.gdshader | — | 16 px/m snap | M13 opaque dungeon water: pixel ripples and glints, no SCREEN / DEPTH reads |
| assets/sfx/cistern_drip_loop_01.wav | tools/sfxgen/generate.py (appended last) | 32 kHz mono, 9.4 s loop | M13 Cistern ambience: standing-water hum, uneven drips; loop_mode Forward in .import |
| assets/world/ember_warrens/{layout.json, map.png} | tools/worldgen/dungeon_bake.py (from warrens_layout.py) | map 3 px/m | M13 phase 6: the Warrens' rooms, doors, lava channels (drawn in `palettes.warrens.lava`), POIs |
| assets/textures/biome/wa_{floor, wall, wall_top} | tools/texgen/biome.py (`generate_warrens`, `python tools/texgen/biome.py warrens`) | 64 px = 2 m | M13 Warrens hewn rock with copper specks (floor) and streaks (wall strata) (`palettes.warrens`) |
| assets/models/env/warrens/{wa_lamp, wa_timber, wa_ore_vein, wa_ember_grate, wa_lava_spout, wa_slag, wa_ore_chunk}.glb + textures/env/*_atlas.png | tools/modelgen/generate_props.py (`WARRENS_PROPS`) | 32 px/m | M13 warrens kit: cage lamp on an arm (ember `_glow`), mine timbering, a copper vein with warm spots, an ember grate, a lava spout frame, slag and ore scatter; placed by DungeonDressing, no collision |
| shaders/lava_pixel.gdshader | — | 12 px/m snap | M13 opaque dungeon lava: dark crust plates, glowing cracks that pulse, no SCREEN / DEPTH reads |
| assets/sfx/warrens_rumble_loop_01.wav | tools/sfxgen/generate.py (appended after the phase 5 sounds) | 32 kHz mono, 9.4 s loop | M13 Warrens ambience: furnace rumble, ember crackle, a far hammer; loop_mode Forward in .import |
| assets/models/chars/{drowned_thrall, channel_lurker, bloated_keeper, deepmaw}.glb + textures/char/*_atlas.png | tools/modelgen/generate_characters_v2.py (`thrall`, `lurker`, `keeper`, `deepmaw`) | 64 px/m | M13 phase 5, the Drowned and the Cistern's bosses: thrall on the humanoid template (idle, run, attack, stagger), keeper a swollen giant (idle, run, slam, stomp, stagger), lurker and Deepmaw on the new serpent template (`build_serpent`: base, seg1, seg2, neck, head, jaw, two fins; idle, emerge, submerge, charge/lunge, spit, stagger; the Deepmaw at 1.3 x with 1.9 x girth); timings read from the enemy scripts; 2 surfaces (body, eyes); contact sheets in captures_contact/ |
| assets/sfx/{water_splash_01-02, deep_roar_01, wave_surge_01}.wav | tools/sfxgen/generate.py (appended after the drip loop) | 32 kHz mono | M13 phase 5: a thrall bursting / a lurker or the Deepmaw breaking the surface, the keeper's and the Deepmaw's roar through water, the keeper's ring wave / the heart flooding / the basin running dry |
| assets/world/highlands/{height.r16, path_mask.png, map.png, layout.json} | tools/worldgen/bake.py (from highlands_layout.py; deterministic, asserts the layout rules) | 385x385 samples at 1 m (uint16 LE); mask + map 2 px/m (768x768) | M08 heightmap, trail mask, zone map, POI layout with baked heights |
| assets/textures/biome/hl_{trail, masonry} | tools/texgen/biome.py | 64 px = 2 m | M08 trodden trails (path mask paving), basalt masonry for ruins |
| assets/models/env/common/waypoint_shrine.glb + textures/env/waypoint_shrine_atlas.png | tools/modelgen/generate_props.py | 32 px/m | M08 waypoint shrine (plinth, rune pillar, crystal brazier `_glow`); wraps a 1.2 x 2.2 x 1.2 collider |
| assets/ui/map/{player, waypoint, portal, camp, camp_cleared, chest, ruin, landmark, boss, dungeon}.png | tools/texgen/ui.py | 12x12 art, saved 24x24 | M08 map and compass icons |
| assets/sfx/waypoint_attune_01.wav | tools/sfxgen/generate.py (appended last) | 32 kHz mono | M08 shrine attunement shimmer |
Blender helpers: tools/modelgen/lib/rig.py (armature, rigid parts, lofts, actions, export),
tools/modelgen/lib/atlas.py (UV to exact density, pixel-atlas bake). GLB imports:
60 fps, no LODs, name suffixes off (no accidental -col bodies). Regenerate:
`blender --background --python tools/modelgen/generate_characters_v2.py` (and
generate_props.py), `python tools/texgen/biome.py`, then `tools\run_godot.ps1 import`.

**Live Blender (2026-09-29):** the Blender MCP (`mcp-for-blender` 2.1.1 by
ahujasid, pinned, telemetry off, registered in Claude Code's local scope)
drives an open Blender window through the add-on "MCP for Blender" (port
9876 on localhost; the sidebar tab "MCP for Blender" -> "Connect to
Claude"). It is used to try out forms and poses and to take viewport
screenshots. The source stays the `tools/modelgen` scripts (ART_BIBLE
"Construction"). Its asset integrations (Poly Haven, Sketchfab, Poly Pizza,
Hyper3D, Hunyuan3D, Tripo) stay off: the style is built from the scripts, and
every source needs a clear licence.

Live loop: `tools/modelgen/live.py` rebuilds one builder inside the open
Blender, exports nothing and leaves `assets/` untouched. Through the MCP's
`execute_blender_code`:

```python
import sys; sys.dont_write_bytecode = True
p = r"D:\fable_test\tools\modelgen"; p in sys.path or sys.path.insert(0, p)
import importlib, live; importlib.reload(live)
live.build("runebreaker"); live.pose("cleave_r", 7); live.view("front34")
live.snap("rb_cleave")  # or the MCP's get_viewport_screenshot
```

`build(name, bake=True)` takes a character key (`runebreaker`, `marauder`, ...)
or a prop function (`waypoint_shrine`, `treasure_chest`, ...). Each call
reloads lib and both generators, so a script edit shows on the next build.
For that build only it swaps module functions and restores them in
`finally`. rig.py, atlas.py and the generators stay unchanged, and the
headless path never imports live.py:
- `rig.reset_scene` empties the open scene in place.
- `rig.export_glb` is skipped.
- `atlas.bake` writes to `%TEMP%\runebound_live` and puts the atlas on the
  body slots.
- `bake=False` also skips `atlas.unwrap`, which gives a white body with glow
  colours.

A size/mtime fingerprint of `assets/` is taken before and after each build,
and a change raises `RuntimeError`. The other helpers:
- `pose(clip, frame)`
- `view(front34|side|front|back|top)`: orthographic, framed on the bounding box
- `snap(label)`: saves `%TEMP%\runebound_live\shots\<label>.png`, outside the
  repo

Build times in the GUI (2026-09-29):
- Runebreaker: 2.5-3.7 s baked, 0.1 s without the bake.
- Waypoint shrine 16 s and chest 22 s baked, almost all of it UV packing;
  0.0 s without the bake.
- 22 s calls did not time out.

Pitfalls:
- `read_factory_settings`, the original reset, unloads the MCP add-on.
- Export and bake write to `assets/` unless they are swapped.
- Without the reload, Python keeps the old modules and the old shapes.
- `lib/__pycache__/*.pyc` used to be tracked, so Blender imports set
  `sys.dont_write_bytecode`.
- Never delete the Scene: the add-on keeps its server state on it.
- Actions carry a fake user and have to be removed, or the next `idle`
  becomes `idle.001`.
- A Blender window behind the editor never redraws. `region_3d.view_matrix`,
  which the screenshot reads, then stays stale until a region draw
  (`wm.redraw_timer` type `DRAW`; `DRAW_WIN_SWAP` is skipped). `view()` and
  `snap()` force that draw.

Registration: the local scope is keyed by the exact project path. VS Code
opens `d:\fable_test`, while shells write `D:/fable_test`. Register from cmd
after `cd /d d:\fable_test`:
`claude mcp add blender -s local -e DISABLE_TELEMETRY=true -e NO_PROXY=* -- uvx mcp-for-blender@2.1.1`
(`-e` takes values up to the `--`). `NO_PROXY=*` is needed because uv
otherwise follows the Windows system proxy.
