# RUNEBOUND — Art Bible (v2)

v2 (2026-09-23) was written after Gate 0, from in-game evidence in the gold
target (Ashen Highlands South), and replaces the pre-Gate-0 direction sheet.
Numbers live in `assets/art_spec.json` and in each zone's `ZoneLook`. This
document holds the rules and the reasons behind them.

## 1. Direction
**STYLIZED 3D PIXEL FANTASY.** Fully 3D, colorful twilight fantasy: chunky
readable forms, exaggerated silhouettes, pixel-inspired textures and VFX,
dramatic emissive accents. Never "normal 3D with a cheap pixel filter".

Pillars, in priority order:
1. **Gameplay reads first.** Readability order: enemy telegraphs > player
   position > dangerous enemies > targeting info > player attacks > loot >
   decoration. Enemy danger must read through player VFX.
2. **One visual language.** Every asset is generated from the same spec
   (palette ramps, texel density, facet/bevel rules, lighting model). To
   change a look, change the spec and regenerate. Never hand-tune one asset.
3. **Chunky and exaggerated.** Big readable masses, forms exaggerated about
   1.2x, detail in the texture rather than the geometry.
4. **Pixel identity in textures, VFX and UI**, not in a low-res framebuffer.
5. **Fits the iGPU.** 60 FPS at 1600x900 on an Intel UHD 770 is part of the
   look; every feature has a measured cost (section 14).

## 2. Decisions
| Date | Decision | Evidence |
|---|---|---|
| 2026-09-23 (M01) | Render style **C HYBRID**: full-resolution geometry, pixel textures/VFX, posterize 14 + light Bayer dither. Rejected: A (low-res SubViewport, motion/precision risk) and B (heavy posterize, weaker readability). The switcher on debug key V stays a comparison tool only; don't build features on it. | live playtest |
| 2026-09-23 | Gold target: **Ashen Highlands South** | user |
| 2026-09-23 Gate 0 | **Character outline on** (stencil, characters only) | live play (O switch) |
| 2026-09-23 Gate 0 | **Smooth animation**, 60 fps playback; stepped 12 fps rejected | live play (L switch) |
| 2026-09-23 Gate 0 | **Characters 64 px/m over environment 32 px/m** (2:1); uniform 32 px/m rejected | live play (P switch) |
| 2026-09-23 | Music is procedurally composed (`tools/musicgen`) | user |
| 2026-09-23 | UI fonts: Pixelify Sans (body, numbers) + Jacquard 24 (titles, boss names), both SIL OFL | user |
| 2026-09-23 | Ability names only as hover tooltips while the inventory is open | user |
| 2026-09-24 | Jacquard retired (unreadable as place names, then as headings); one UI font, **Runebound Pixel** = Pixelify letters + grid-exact digits (Pixelify's digits read 2 as 3, 5 as S) | user, playtest screenshots |

Gate-0 comparison stills: `captures_shots/gate0/`. The rejected variants
(32 px/m atlases, stepped playback) were removed from code and assets.
Outline stays switchable (debug key O, `--look=outline:false`) for
comparison and perf A/B.

## 3. Single source and pipeline
- `assets/art_spec.json` holds:
  - palettes as sRGB hex ramps
  - color roles
  - texel densities
  - shapes and gameplay envelope
  - outline and animation settings
  - emissive caps, the fog-exempt list and marker heights
  - shadow settings and forbidden render features
- Who reads the spec:
  - `tools/texgen` for biome textures.
  - `tools/modelgen` for characters and props. It converts sRGB to linear
    before a value reaches Blender's Base Color; without that, models
    rendered lighter than the spec.
  - `ArtKit` for materials at runtime.
- Each zone has a `ZoneLook` resource (sky, sun/rim/ambient, fog, glow,
  tonemap, grading). Zones without one keep their legacy environment until
  Phase C.
- Generated GLBs ship without embedded images. ArtKit binds the atlases in
  code with nearest filtering and mipmaps. Pixel art is imported lossless.

## 4. Render and post (C HYBRID)
- Forward+, MSAA off, depth prepass on (off is slower on this iGPU).
- Post pass: posterize to 14 luma levels in YCoCg (chroma 32 levels) plus a
  light Bayer dither (0.02). Per-channel RGB posterize is not used in ZoneLook
  zones: at 14 levels it flipped dark browns between olive and red.
- Linear tonemap plus explicit grading per zone: lift/gain, split tone,
  saturation and a light vignette. The palette must survive the grade.
- Glow: level 3 only, HDR threshold 1.1, so only emissives and VFX bloom.
- Forbidden on the target iGPU: SSAO, SSR, SSIL, SDFGI, volumetric fog.

## 5. Color
### Roles (no two roles share hue *and* shape)
| Role | Hue | Shape / motion |
|---|---|---|
| Enemy threat | crimson #E8283C + near-white rim | filled disc/lane, visible fill progress, top render priority, fog-exempt |
| Resonance (player resource) | rune gold #FFC34D | armor rune glow, HUD bar |
| Player identity / targeting | teal #3CBEB4 | trims, Tab ring, UI frames |
| Fire | orange #FF6A2A → core #FFD27A | turbulent, rising embers, short |
| Frost | ice cyan #7FE0FF | angular crystals, mist |
| Lightning | pale yellow-white, violet-blue fringe | instant branching arcs |
| Physical | off-white/steel | directional sparks, dust |
| Void (Spire/Duskweaver magic) | violet #A060E8 | enemy projectiles, orbs |
| Environment emissive | dim deep orange #A8441C | tiny ground specks, slow flicker, below glow threshold |
| Settlement light (hearth) | warm #FFB866 | small lit window/lantern rectangles, environment cap, never on the ground |
| Ancient runes (monoliths, lintels, Spire inlays, portals) | teal/cyan | straight channels, glyphs, upright gate ovals — never ground rings |
| Loot rarity | white / blue / gold / orange | vertical beam + label; the shape carries it |

Red is reserved for danger. M05 used one orange for rune glow, Resonance,
fire and Legendary. Now Resonance is rune gold, fire stays orange-red, and
Legendary stays orange but is identified by its beam.

### Palettes
Every material color comes from a 5-step ramp in the spec (ash ground,
basalt, Runebreaker iron, Marauder hide, ...). Bakes pick the ramp step by
up-facing and AO; generators never pick free colors.

### Value structure (luminance 0–100)
| Layer | Luminance |
|---|---|
| Background | 15–40 |
| Ground | 25–40 |
| Walls, rocks | 20–45 |
| Character key planes | 40–70 |
| Telegraphs, VFX | 80–100 |

An enemy must be at least 15 points brighter than its ground. The M05
Marauder on ash failed this, so its hide and plate ramps were lifted in v2.

Measure the delta in gameplay captures, not in the texture. The luma
posterize moves values in bands of about 7 L*, and fog lifts distant ground.

| Character | Delta over ground (B2, Highlands South) |
|---|---|
| Runebreaker | +24 L* |
| Cinder Marauder | +27 L* |
| Duskweaver (fights at 7–12 m, robe at ramp step 4) | +21 L* |

## 6. Lighting, atmosphere, shadows
- **Key light:** one directional per zone at 35–50° elevation, side-back to
  the main path.
- **Rim light:** a cool directional from the opposite side, sky-only, no
  shadow.
- **Ambient and reflections:** ambient comes from a ZoneLook color, not the
  sky; sky reflections are off.
- **Point lights:** only for gameplay and landmarks (bonfire, torches, VFX
  pops), never with shadows. At most 6 transient VFX lights at once.
- **Sky:** a pixel sky shader with explicit bands, a horizon cloud band and
  a hard sun disc. Distant silhouettes (ridges, volcano, the Shattered
  Spire) are baked into an azimuth LUT: distant landmarks live in the sky,
  not as meshes. Sky process mode is QUALITY, because an animated sky in
  AUTOMATIC mode re-filters radiance every frame (+4 ms).
- **Fog:** depth plus height fog, tinted toward the horizon, with aerial
  perspective 0. Fog-exempt: telegraphs, enemy eyes and orbs, the player
  X-ray and loot beams.
- **Shadows:** one directional, orthogonal single split, 2048 atlas, hard
  filter, 60 m.
  - Casters: characters, rock hulls, props taller than 0.6 m.
  - Scatter, decals, ground VFX and small props cast none.
- **Highlands South reference** (`AshenHighlands._zone_look`):
  - warm sun at 40° elevation, energy 1.3
  - violet rim light at 0.5
  - ambient energy 1.35
  - split tone: cool shadows, warm highlights, amount 0.35
  - vignette 0.18

## 7. Characters
### Proportions and shape language
- **Runebreaker (player):** heroic-chunky, about 4.5 heads, at most 2.0 m
  including the crest.
  - Oversized parts: pauldrons about 1.5x shoulder width, gauntlets 1.4x,
    boots 1.3x.
  - Broad V-torso, short legs, big rune sword (blade about 1.1 m).
  - Shapes: **squares and rune circles**, plated and grounded, reads as
    "the solid one".
- **Ash raiders (Cinder Marauder, Ashvein Colossus):** jagged wedges, horns,
  forward lean, heavy forearms. The silhouette says "charges at you".
- **Duskweavers (casters):** tall cones and drapes, hoods, vertical lines,
  no visible legs. The silhouette says "stands back and casts".
- **Veilstalker:** slim crescents and hooks, a trailing scarf.
- **Stone & Spire constructs (Stonehulk, Warden, Vessel):** blocks, shards,
  hex facets, floating pieces.

### Construction (`tools/modelgen`)
- Forms are lofted cross-section rings per bone, not box primitives.
  Facets are flat-shaded, forms exaggerated about 1.2x.
- Build mirrored, then add deliberate asymmetry (the Marauder's single
  shoulder plate).
- No geometry smaller than 10 cm. Rivets, runes and seams live in the
  texture.
- Parts are rigid-skinned on a humanoid template. No root motion: hips stay
  within 0.15 m of the origin. The gameplay `Visual` node owns yaw and scale.
- At most 3 surfaces per character:
  - body (atlas)
  - glow (eyes, runes), never hit-flashed
  - telegraph weapon, which keeps its ramp and is never in the hit-flash
    list

### Texturing
- One baked pixel atlas per character at **64 px/m**, measured exactly
  after unwrap.
- The ramp step comes from up-facing (a baked key light from above).
  Also baked: raycast AO with 4 probes, a 1-px highlight on sharp convex
  up-facing edges, and cloth/hide/plate patterns from the spec.
- No dither on the baked light: on facets it read as checkerboard noise.
- Material: nearest + mipmaps + anisotropic filtering, toon diffuse,
  specular off, rim 0.35.

### Outline
Every character body gets a stencil outline (0.012 thickness, #0B0810).
Props and environment never get one: the outline marks "this can act".

### Gameplay envelope and validation
- Silhouettes stay within ±15 % of the hurtbox (r 0.55, h 1.7) and below
  the nameplate height (2.05 m).
- Models are authored at today's base size; bosses keep their Visual scale
  factor.
- Per asset: turntables and per-clip contact sheets in zone light, and the
  enemy-vs-ground value check.

## 8. Animation language
- **Smooth 60 fps playback** (Gate 0). Clips are authored at gameplay timing
  and imported at 60 fps.
  - Player clip length = startup + active + recovery.
  - Enemy clip length = windup + strike + recover.
  - The contact frame is the frame on which the timer-driven hit fires.
  - A smoke check pins clip lengths to the current tuning.
- **Timing and easing:**
  - Anticipation lives in the ready stance and in windups.
  - Strikes are fast, with an EXPO ease-in into contact.
  - Contact overshoots with a BACK ease-out; recovery settles with a QUART
    ease-out.
  - Attacks blend in within 2 frames. Dodge cancels anything.
- **Telegraph windups:** reach their pose by about 60 % of the windup, then
  hold with a small tremble. That hold is the readable tell.
- **Impact freeze:** a rig stops while its owner is in hitstop.
- **Locomotion** is speed-matched: playback rate = speed ÷ authored stride
  speed, clamped to 0.5–1.8, so Chill-slowed enemies don't ice-skate. There
  are no strafe or back clips; the player turns into its movement.
- **Overlap and follow-through** come from key offsets of 1–3 frames, not
  physics bones.
- **Authoring by intent:** weapon poses are given as a wrist target, an
  elbow direction and a blade direction (`tools/modelgen/lib/pose.py`), not
  as guessed Euler angles. That keeps each contact pose on its hit volume.
  Review every clip on its contact sheet (`--sheets`): 3/4 view, side view
  for foot contact, top view for sweep direction.
- **Weapon swings match their VFX:** `cleave_l` (combo opener) sweeps left
  to right, `cleave_r` right to left, the same way the slash sprite spins.
- **Animation LOD:**
  - Enemies beyond 12 m advance at 30 Hz, beyond 24 m at 15 Hz.
  - One-shots (attacks, windups) always run at full rate.
  - The player always runs at full rate.
- **Deaths** stay the 0.22 s gameplay removal (restyled as a burst in B4).
  There is no player death clip, because respawn is instant.

## 9. Environment kit (reusable, because M08 rebuilds the Highlands)
- **Kit and systems, not layout decoration.** Today's layouts only get
  automatic dressing: collider wrapping, scatter and set pieces at the
  existing camps and landmarks. No hand-composed sightlines.
- **Ground:** the `terrain_pixel` shader.
  - World-XZ mapping at 32 px/m, slope blend between top and side.
  - Two layers mixed per texel by macro noise.
  - Sparse, dim ember specks (environment emissive, below the glow
    threshold).
  - Reused unchanged on the M08 heightmap.
- **Rock formations:** `RockHull` wraps any box collider.
  - An outward-only faceted hull with terraced strata and alternating
    far/near ledge bands, vertex AO, and a slope-blended material (ash
    tops, strata sides).
  - It contains its collider, rises at most 0.3 m above the collider top,
    and overhangs walkable sides by at most 0.3 m.
- **Props:** a Blender library at 32 px/m, toon shading, no outline, no
  shadows below 0.6 m. Solid-looking props over 0.4 m only inside collider
  footprints or outside the perimeter.
- **Set pieces:** parametrized builders (`raider_camp`, `bonfire`,
  `wrap_collider`), the building blocks for M08 POIs.
- **Scatter:** chunked MultiMesh, placed by rules only.
  - Taller items (dead-grass tufts, stone clusters) grow in clumps in a
    band 0.3–1.4 m outside obstacle footprints, where debris collects.
  - Open combat space keeps only ground texture (the 0.02 m rule), so
    telegraphs stay unobstructed.
  - Keep-clear circles around camps, spawn, portals, chests and arenas.
  - Solid geometry, no alpha cards, no shadows.
  - Ground height comes from a callable: flat now, heightmap in M08.
- **Wind:** hide banners and grass sway (`wind_sway` shader, anchored at the
  crossbar or the ground). Instances are phase-shifted by world position,
  never in lockstep.
- **Atmosphere:** camera-attached ash fall per zone (`ZoneLook.ash_fall`),
  tiny flakes only.
- **No new collision in M06.** The walkable floor stays flat at y = 0.
- **Big surfaces are shader-mapped, props are trim.** Walls, hut bodies, sod
  roofs, floors and cover blocks use world-mapped `terrain_pixel` roles, so
  every surface of a zone shares one texel grid. Blender props add only the
  trim (doors, frames, banners, crystals).
- **Paving and inlays are shader-side** (`ArtKit.paved` / `ArtKit.inlaid`):
  - Plazas are circles and roads are segments in world XZ, with a ragged,
    dithered edge. The paving texture has its own tile size (4 m), so
    large paved areas hide the repeat.
  - Rune inlays are dim emissive channels along straight segments, with a
    cross-bar glyph every 1.6 m.
  - Inlays are never rings: rings are the player's ground-VFX shape.
  - The same calls pave and inlay the M08 heightmap.
- **Settlement kit (Runehold, hub + training grounds):**
  - Palette: packed earth, flagstone, granite, moss, turf, warm wood, teal
    Runebreaker cloth.
  - `SetPieces.masonry_wall`: coursed granite with a cap course and piers,
    at most 0.3 m over the top and 0.25 m proud. Corner piers belong to one
    wall per corner, so coplanar caps never z-fight.
  - `SetPieces.hut`: a masonry body, a sod gable that contains the roof slab
    (eaves 0.15 m out, ridge 0.3 m over the top), and a trim prop with
    corner posts, a plank door, a rune lintel and lit shuttered windows.
    Doors face the hearth.
  - `SetPieces.hearth`: granite ring stones wrap the ring colliders and the
    log colliders hide under the fire prop. Flame tongues breathe (a
    `flames` node is tweened), plus warm light and embers.
  - Wall banners are held 0.1 m off the wall, so their sway never clips.
  - Weapon racks and pells hug the walls (at most 0.28 m deep: the 0.42 m
    player capsule can't reach them).
  - Beyond the walls: a visual-only meadow skirt and a deterministic ring
    of pines and oaks.
  - Scatter: living grass tufts and mossy granite.
- **Interior kit (Shattered Spire):**
  - Coursed violet stone walls with piers; relief arches (0.28 m deep) in
    every other bay of the perimeter walls.
  - Floors are 1 m dressed slabs.
  - Crystal pillars wrap the accent colliders (hex, apothem >= 0.85 m, so
    the box is contained at any yaw).
  - Torch v2 is a floating crystal beacon: its bottom is at least 2.08 m up,
    so it is never in the walk space, with orbiting shards and the same
    cold light as before. The boss chamber ring was re-placed inside the
    chamber.
  - Floating debris drifts 5–8.5 m overhead and casts no shadow on fight
    floors.
  - A processional rune channel runs from the entry through every door gap
    to a rune octagon around the Vessel's floor.
  - Scatter: rubble and crystal clusters, with every camp's fight space
    kept clear.
- **Common kit (every zone):**
  - Portal v2 is a flush octagonal rune plate, an upright swirling gate
    oval (`portal_gate.gdshader`) and floating arch stones (all >= 2.2 m).
    It turns to face the zone centre. Sealed portals are grey and still.
  - The treasure chest wraps its collider; its lid is hinged at the back
    edge.
  - Loot shapes: blade, cuirass and relic. Their glow part carries the
    rarity colour; commons stay unlit.

### Cast (M06 complete)
Every enemy type now has a rigged, atlas-baked model at 64 px/m with clips
at gameplay timing. The old pivot tweens run on invisible stand-ins, so
gameplay timing is untouched.

| Character | Shape / palette | Clips |
|---|---|---|
| Stonehulk (Brute) | stone slabs, boulder shoulders, knuckles near the ground, moss on up-facing planes, ember slit | idle, run (stomp), slam (= WINDUP + RECOVER), stagger |
| Veilstalker (Assassin) | low and lean, slate cloak (not the player teal), bone mask for the value read, trailing scarf, twin daggers, acid eye slit | idle, run, strafe, dash, stab (contact = WINDUP), retreat, stagger |
| Hollow Warden | square violet-grey slabs, tower shield fused to the chest front ("not here"), teal rune core on the back ("hit here"), bladed forearms | idle, walk, windup (coils against the Visual's pre-turn), spin, stagger |
| Ashvein Colossus (x1.7) | ash-grey basalt hulk, curled horns, ember veins and back crystals on a code-owned surface that ramps up on enrage | idle, walk, slam (rate follows the enraged 0.65 s windup), charge_windup, charge, stun, roar, stagger |
| Vessel (x1.4) | floating lavender crystal, violet heart, crystal-blade arms, four orbiting shards | idle, glide, slam, shatter (segments burst apart), p2_idle, fan, stagger |

- Elites keep their model and get an aura only: eyes burn in the affix's
  element colour, and element motes rise off the body. There is no ground
  shape, because discs and rings are taken.
- Cindermaw (the legendary weapon) shows on the hero: the blade surface
  turns basalt with a molten, breathing edge. Conductor's Oath and Glacier
  Heart get unique drop models and inventory icons. General visible
  equipment is M07+.

## 10. VFX language (pixel)
- **Style:** chunky pixel sprites (16–64 px, alpha scissor, nearest) at
  about 32 px/m, stepped gradients, short readable bursts. No soft realistic
  smoke, no large transparent clouds.
- **Elements:**
  - Fire: turbulent orange embers and scorch.
  - Frost: angular crystals and mist.
  - Lightning: instant branching arcs, pale yellow-white with a violet-blue
    fringe.
  - Physical: directional sparks, dust, debris.
  - Void: violet orbs and bolts.
- **Telegraphs** (`threat_marker.gdshader`, the only red filled shape): a
  crimson disc or lane.
  - Faint base (alpha 0.2) and a 0.12 m near-white rim.
  - An inner fill that grows from the centre (lanes: from the attacker) to
    the rim over the windup. The strike lands when it is full.
  - Top render priority, fog-exempt, drawn at +0.05 m, snapped to 32 px/m.
  - Every enemy uses it unchanged; the attack's source reads from the
    enemy, not from a tinted disc.
- **Player ground effects** (`player_ring.gdshader`):
  - Broken rings of 8 dashes, 0.12 m wide, additive, opacity at most 0.7,
    short-lived.
  - Never a filled disc.
  - Arming effects light their dashes one by one.
  - Impact shockwaves use the same dashed ring in the element's colour.
- **Boss shockwaves** use the same threat language as a band (shape 2): a
  crimson ring of +-0.8 m with bright rims on both edges. The drawn band is
  exactly the band that hits (the Vessel's hazard ring used a violet ring
  before).
- **Portals** are upright ovals of swirling rune light, never ground rings.
- **Settlement light** (colour role `hearth`, #FFB866) is for windows and
  lanterns only: small lit rectangles at the environment cap.
- **Emissive caps** (from the spec): environment 0.8, eyes 3.0, telegraph
  2.5, VFX 4.0.

## 11. UI
- **Fonts:** Runebound Pixel for everything: body text, numbers, place names,
  panel headings and the boss name. It is Pixelify Sans with the digits 0-9
  redrawn on the exact pixel grid (5x7 cells of 2 px at 20 px, all the same
  width), `tools/fontgen/numerals.py`. Pixelify's own digits are off-grid and
  rasterized 2 as 3 and 5 as S (user feedback 2026-09-24). Jacquard 24 is retired (user feedback
  2026-09-24, twice: the blackletter was unreadable as place names and then
  as panel headings); the file stays in `assets/fonts/` but nothing uses it.
  SIL OFL, license in `assets/fonts/`.
  - Only the measured crisp sizes are allowed:
    - Pixelify 20 / 40 / 60 px (1/20 em grid; body 20, headings and crits 40,
      arrival cards 60)
  - Antialiasing, hinting and subpixel positioning are off.
- **Pixel scale:** text is drawn at 1x; frames and icons at 2x (the UI kit is
  saved pre-scaled and drawn 1:1).
- **World labels** (plates, loot, portals, damage numbers) keep their world
  anchor but a fixed screen size, one font pixel per screen pixel. A pixel
  font shrunk by distance drops glyph pixels and becomes unreadable.
- **Elements:**
  - 9-slice frames from texgen with the teal player accent
  - integer-scaled ability icons
  - framed health and Resonance bars (Resonance in rune gold)
  - cooldown sweep and key labels
- **Ability names** never appear during play. With the inventory open,
  hovering a slot shows a tooltip: name, key, element, cost, cooldown and a
  one-line description.
- **Label3Ds** (damage numbers, nameplates, loot and portal labels) set the
  same fonts explicitly.
- Nothing sits over the combat center.

## 12. Audio direction and mix
- **Buses:** Master → Music, SFX, Telegraph, Ambience, UI. Telegraph sounds
  duck the music (sidechain) and are never masked.
- **Mix priority:** telegraphs > player impacts > enemy attacks > ability
  casts > loot and UI > ambience > music.
- **Music** is procedurally composed (`tools/musicgen`; compositions are
  data).
  - Each region has an exploration layer and a combat layer in the same key,
    tempo and length, played in sync.
  - The combat layer swells in within 1.2 s while an enemy within 22 m is
    engaged, and ebbs out over 4 s. Travel fades everything out.
  - Highlands: D minor, 72 BPM, 16 bars.
    - Exploration: low drone, pad, plucked harp arpeggios, FM bells, long
      reverb.
    - Combat: frame drums, shaker, bass pulse, low swells.
    - No bright leads.
  - Runehold (hub and training grounds): F major, 66 BPM. Harp in gentle
    eighths, drone F/C, no minor turn-around. Its combat layer is a calmer
    training-yard drum pulse, which only swells in the lab.
  - Shattered Spire: D Phrygian, 60 BPM, cathedral reverb (4.2 s), sparse
    bells, heavy frame drums in the combat layer.
  - Boss fights ride the zone's combat layer at full. When a boss falls, a
    victory stinger (D major harp run into a bell chord) plays over the
    ducked zone music.
  - Start bus levels: Music −7 dB, Ambience −3, UI −2, Telegraph +1 dB.
- **Ambience:** layered, seamless loops per zone (wind, and campfire near
  camps), plus footsteps per ground type (ash).
- **SFX** are retimed to the clips' contact frames.
- The Style Gate rates audio separately from the look.

## 13. Camera and composition
- Third-person shoulder camera; the readability order from section 1 applies
  to every frame.
- The key light sits side-back to the main path, so characters get a lit
  side and a rim.
- Landmarks in the sky (Spire silhouette, volcano) point toward goals.
- Camps read as warm light pools (bonfire) against the cool twilight.

## 14. Performance budget (Intel UHD 770 iGPU)
- **Target:** at least 60 FPS average at 1600x900, both in the Highlands
  South scripted fight (`perf highlands_south`) and in the lab stress test.
- **Measured costs** (interleaved A/B, 2026-09-23):

  | Feature | Cost |
  |---|---|
  | Rock hulls | 0.5 ms |
  | Outline | about 0 |
  | 29 animated outlined rigs | +0.2 ms |
  | Enemy shadows | about 0 |
  | Animation LOD | saves 0.3 ms |
  | Depth prepass off | slower (keep it on) |
  | Animated sky in AUTOMATIC mode | +4 ms |

- **Per zone after Phase C** (median of 3, 2026-09-23 evening):

  | Scenario | FPS | GPU |
  |---|---|---|
  | `perf hub_idle` (whole settlement in view) | 80.0 | 12.0 ms |
  | `perf highlands_south` (8-enemy fight, all 5 camps dressed) | 72.4 | 13.2 ms |
  | `perf spire_hall` (interior, mixed pack of the new rigs) | 64.8 | 14.9 ms |
  | `perf lab_crowd` (29 rigs, Runehold look) | 64.0 | 14.6 ms |
  | `stress` full combat (lab) | 71.1 | — |

- **How to measure:** compare look features only with interleaved A/B
  (`--ab=<key>`), because this GPU swings up to 25 % between runs.
- **Before measuring:** close other game instances. They distort the numbers
  and can crash the driver (see KNOWN_ISSUES).

## 15. Asset compliance (every generated asset)
- **Source:** generated from the spec by a script in `tools/`, never a
  hand-edited export. Listed in ASSET_MANIFEST with generator, size and
  import settings.
- **Texel density:** characters 64 px/m; environment, props and VFX 32 px/m;
  tolerance ±15 %.
- **Color:** ramps from the spec only, converted sRGB → linear before
  Blender.
- **Characters:**
  - at most 3 surfaces
  - within the envelope, and passing the value check against the ground
  - clips at gameplay timing, no root motion
  - telegraph surfaces outside the hit-flash list
- **Environment:** contains its collider, respects the marker heights, and
  no node name ends in `-col` or `-colonly`.
- **Import:** lossless with mipmaps (filtering is set by ArtKit). GLBs
  without images, at 60 fps, without LOD generation.

## 16. Style Gate checklist (draft, to be agreed with the user)
The user plays Highlands South after B5 (character clips, environment kit,
VFX v2, HUD v2, music). Look and audio are rated separately. The verdict is
recorded here: pass, pass with notes, or reject (then iterate on Phase B).
Nothing propagates to other zones (Phase C) before a pass.

**Look**
1. Telegraphs read instantly: on ember ground, in fog, and under heavy
   player VFX.
2. The player is always findable (outline, teal accents, value), also among
   8+ enemies.
3. Runebreaker, Marauder and Duskweaver can be told apart by silhouette
   alone at 15 m.
4. Enemies stand out from the ground by value, in motion as well as in
   stills.
5. Characters, rocks, props, sky and UI read as one game. Nothing looks like
   unrelated generated output or greybox.
6. No shimmer or crawling texels at distance, no posterize hue flips, and
   no banding that looks like a bug.
7. Attacks read as windup → contact → recovery. Impacts visibly freeze.
   No foot sliding.
8. Every VFX element can be identified by hue and shape; nothing can be
   mistaken for a telegraph.
9. The HUD is crisp (fonts, icons, frames), tooltips are themed, and
   nothing covers the combat center.
10. Highlands South reads as a place: path, camps as light pools, landmark
    and horizon.
11. At least 60 FPS average in `perf highlands_south` and in `stress` on the
    dev iGPU.

**Audio**
12. The music fits the twilight mood and doesn't wear on loop. The combat
    layer rises on aggro and falls afterwards.
13. Telegraph sounds cut through everything, hits feel heavy, and loops have
    no clicks or gaps.
14. Balance: nothing fatiguing, UI subtle, ambience present but quiet.

Verdict (user, 2026-09-24): **pass with one note**. Art style is approved
throughout, and the music is approved ("mega gut"). The note: portal labels
in Jacquard were unreadable, so place names now use Pixelify.

**Propagation (Phase C, for the same review)**
15. Runehold reads as a safe, lived-in settlement: warmer and greener than
    the Highlands, but still the same twilight family.
16. The training grounds read as part of Runehold.
17. The Spire reads as a dark interior that is still readable: floor value
    band, beacons, rune channels, crystals.
18. Every enemy is identifiable by silhouette and value in its zone. The
    Veilstalker never reads as the player's teal.
19. Portals, chests and loot look like the same game as the characters.

## 17. Visual Quality Gate (§71) — implementer self-review
Captures: `captures_shots/{vignette, c3_runehold, c3_lab, c4_spire,
c12_rigs, c5_props}`, with before/after pairs in `*_legacy` for the hub,
lab and Spire, and per-clip contact sheets in `captures_contact/`.

- **One character language:** passed. All eight characters come from one
  recipe (lofted facets, rigid rigs, baked 64 px/m atlases, the same toon,
  rim and outline). Faction shapes hold: squares for Runebreaker and
  Warden, wedges and horns for raiders, cones for Duskweavers, shards for
  the Spire.
- **One environment language:** passed. Every zone uses the
  `terrain_pixel` family at 32 px/m plus Blender trim props. No greybox box
  is left visible in the art pass; the Combat Lab's cover blocks read as
  masonry.
- **Intentional texel density:** passed, with one note. Characters are
  64 px/m and everything else 32 px/m; the paving and slab floors use
  4 m tiles at the same density. The 2:1 ratio is the Gate 0 decision.
- **Coherent palette:** passed. All three zones share the twilight family;
  Runehold is warmer and greener, the Spire colder and darker. The color
  roles are untangled: red is threat only, teal is the player and ancient
  runes, gold is Resonance, and the rarity colours sit on beams and labels.
- **VFX, lighting and UI fit:** passed. The threat language is consistent,
  including the boss band. Portals and elite auras avoid the ground shapes
  that are taken.
- **Nothing that looks like unrelated generated output:** mostly passed.
  Open notes for the user's eye:
  - The Spire is dark by design; judge it in motion.
  - The sky clouds in Runehold may still be busy.
- **Performance:** passed. Every zone is at least 60 FPS on the dev iGPU
  (table in section 14).

Verdict: the implementer considers the §71 gate met. The user's verdict is
pending, in the final playtest.
