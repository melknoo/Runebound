# RUNEBOUND — Art Bible

## Direction: STYLIZED 3D PIXEL FANTASY
Fully 3D, colorful twilight fantasy. Chunky readable forms, exaggerated
silhouettes, pixel-inspired textures and VFX, dramatic emissive lighting.
Never "normal 3D with a cheap pixel filter".

## Render style — DECIDED (2026-09-23): **C HYBRID**
Full-resolution geometry, pixel textures/VFX, gentle posterize (14 levels)
+ light Bayer dither. Chosen after live playtest by the user over A (low-res
SubViewport — cohesive stills but motion/precision risk) and B (heavy
posterize — strong identity, weaker readability, sky banding).
All future assets and post work target C. The A/B switcher stays available
under debug key V as a comparison tool only — do not build features on it.

## Palette
- World base: dusk purples/plum stone (#342C3E–#66565E range), teal rune
  accents (#3CBEB4)
- Sky: deep violet top, ember-rose horizon; fog plum
- Player: dark iron armor + teal pauldrons + orange rune glow (#FF8C33)
- Rusher enemy: rust red-orange, gold eyes
- Caster enemy: violet robes, magenta orb
- Rarity/danger reserved colors: red = enemy threat, orange/gold = fire &
  Resonance, cyan = frost (later), yellow-white = lightning (later)

## VFX language (pixel)
Chunky pixel sprites (16–64px, alpha-scissor, nearest filter), stepped
gradients via color ramps, short readable bursts, brief point lights on hot
impacts. Fire = turbulent orange/gold embers + scorch decals. Physical =
sparks + dust + debris shards. Telegraphs = white-rimmed discs, red tint.
No soft realistic smoke, no giant transparent clouds.

## Texture rules
Environment 64x64 tiles, nearest filtered, intentional texel density.
Characters currently primitive-mesh flat colors (M01); keep saturation
grouping per faction.

## Readability priority
enemy telegraphs > player position > dangerous enemies > targeting info >
player attacks > loot > decoration. Enemy danger must read through player VFX.
