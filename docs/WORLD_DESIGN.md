# RUNEBOUND — World Design (M08)

Open, but dense (§50–52, changed 2026-09-23): several large, freely
explorable zones (~300–500 m) linked through Runehold, not one seamless
streamed world. Size is allowed, emptiness is not: a point of interest every
50–80 m, several routes instead of a corridor, landmarks visible from far
away. All zones extend `ZoneBase`; travel via `[E]` at portals and waypoint
shrines with fade + save. Player gear, attuned shrines and map discovery
persist per character through `SaveGame`; cleared camps persist in the world
(see TECHNICAL_ARCHITECTURE).

## RUNEHOLD (hub — scenes/hub.tscn)
34x34 safe settlement, warm dawn palette. Campfire heart (flicker light,
ember loop, crackle ambience), three stone shelters with rune lintels.
Portals: ASHEN HIGHLANDS (north; arrives at the Highlands' south gate),
TRAINING GROUNDS / Combat Lab (east), THE SHATTERED SPIRE (west, once the
Colossus has fallen). New game and every return lands here. No enemies, ever.
- **Sigrun Runewright** (M07b, `TrainerNpc`) stands north of the west hut by
  the weapon rack and training post, facing the hearth, on her own paved
  path. `[E] Talk` opens the trainer panel (abilities for gold + level). She
  borrows the Runebreaker rig in bronze until M14 gives her a model and a
  story; the three flavour lines are placeholders.
- **Runehold shrine** (M08, `Waypoint`, by the Highlands gate): always
  attuned; `[E] Travel` lists every shrine the character has attuned.

## ASHEN HIGHLANDS (open region — scenes/ashen_highlands.tscn, M08)
384 x 384 m heightmap zone (`assets/world/highlands`, baked by
`tools/worldgen/bake.py` from `highlands_layout.py`). Ember-haze sky, ash
ground with trodden trails (path mask), rolling relief that climbs from the
south slopes (about y 5–10) to the north plateau (about y 30); the outer 24 m
rise into rim mountains with charred trees. Ambient wind loop; camera far
plane 560 m, haze hides the far edge.

**Routes** (graded to <= 24 deg, carved into the terrain, drawn as trails):
- *main* S→N: south gate → Ashford Slopes → the Crossroads pass (ambush) →
  camp 4 in the middle → the north pass (ambush) → Colossus Gate.
- *east loop*: Cinder Flats (camps 2, 5), Eastwatch shrine, the elite pocket
  (camp 6) back to the main route.
- *west detour*: the Crossroads cairn, camp 3, Westreach ruin, Northreach
  shrine.
- *far east*: over Emberfall Ridge (level 3) past the Hollow Cistern gate,
  the bone field and camp 7 to the gate. *far west*: past the Ember Warrens
  gate, the far ruin and camp 8 to the gate. Short spurs reach hidden
  chests and the south ruins.

**Points of interest** (32, one every 50–80 m along every route; every
combat POI stands on a baked flat pad):

| Type | Count | Notes |
|---|---|---|
| Raider camps | 8 | escalating compositions (2 rushers → brute + assassin + caster + rusher), bonfire, log seats, bone piles, banners on colliders; **respawn ~10 min after a clear** while no hero is within 45 m |
| Ambushes | 2 | at the two passes: the pack spawns on a 6–9 m ring around the hero (horn) |
| Elite patrol | 1 | roams the far-east route between the Cistern gate and camp 7 (wakes at 55 m) |
| Ruins | 3 | broken masonry with a chest inside; two hold an ambush |
| Chests | 4 free (+3 in ruins) | detours and dead ends; rare bias in the north |
| Waypoint shrines | 5 | Ashford, Crossroads Cairn, Eastwatch, Northreach, Colossus Gate |
| Landmarks | 5 | two rune monoliths, two charred groves, a bone field |
| Sealed gates | 2 | Hollow Cistern (east), Ember Warrens (west): placeholders for the M13 dungeons |
| Arena | 1 | the Colossus plateau in the north with its rock ring and the gates to Runehold and the Spire |
| Gates | 3 | south gate (Runehold), arena gates (Runehold, Spire) |

**Level bands** (8x8 grid, 48 m cells): south third 1, middle 2, north third
and the Emberfall Ridge 3; the Colossus is 3. Chests take their item level
from the band.

**Named areas** (a card on entering): Ashford Slopes, The Crossroads, Cinder
Flats, Westreach, Emberfall Ridge, Northreach, Colossus Gate.

**Map + compass:** M opens the baked map with everything this character has
seen (POIs within pad + 15 m, shrines once attuned); the compass strip shows
attuned shrines, gates, the arena, sealed gates and armed camps within
120 m. Ambushes and the patrol never show.

**Death:** back at the nearest attuned shrine (else the spawn), healed.

## ASHVEIN COLOSSUS (mini-boss)
600 HP, stagger-resistant (HEAVY only), boss bar on HUD. Kit:
- **Slam**: 0.9s telegraphed disc (r3.2, 28 dmg heavy).
- **Charge**: 0.8s red lane telegraph → 14 m/s rush, 30 dmg contact,
  extra stun when it slams a wall (punish window; the arena's rock ring).
- **Enrage <50%**: faster (3.4 m/s), 0.65s slams, drops fire patches, red aura.
Death: guaranteed legendary + unseals the north gates (Runehold, Spire).

## THE SHATTERED SPIRE (dungeon — scenes/shattered_spire.tscn)
Interior, near-black with violet fog; teal crystal torches + glowing floor
runes carry all light — telegraphs must read in the dark. Deep drone ambience.
Gated behind `colossus_defeated` (portal in the Highlands boss arena; shortcut
portal appears in Runehold). 50x72, four sections with door-gap dividers:
1. **Entry hall**: rusher/caster/warden camp.
2. **Broken gallery**: raised side platforms with casters (ramp up to the east
   platform from its west edge, x 2.8 to 8; west platform is ranged-only),
   assassins below; west alcove: warden-guarded chest (rare bias).
3. **Rune vault**: elite camp + second chest.
4. **Boss chamber**: torch ring, sealed exit portal.

## VESSEL OF THE SHATTERED RUNE (major boss)
1400 HP, stagger-resistant, floating crystal construct (violet/teal identity
vs. the Colossus' orange). Two phases:
- **P1 Construct**: telegraphed slams, 3 shadow runes around the player
  (1.2s arm → r2.5 blast), summons 2 rusher adds (~20s, max 3).
- **P2 Shatter (<50%)**: 1s invulnerable transition burst, then blinks
  between 5 arena anchors (centre + 7 x 3.5 m ellipse inside the chamber), 3-bolt rune fans, 4 shadow runes, expanding hazard
  ring from the arena center (~10s) — pure timing dodge.
Death: legendary + 2 rares, `spire_cleansed` flag, exit unsealed. Once
cleansed the Vessel stays dead (world flag).

## HOLLOW WARDEN (dungeon enemy)
90 HP construct, halves frontal damage (spark/clink feedback), exposed rune
core on its back, slow turner — flanking and Storm Step counter it.
Telegraphed full-circle spin (r2.4).

## Rules going forward
Every zone must answer: where does the player go next (readable path), what
rewards curiosity (detours), what escalates (camp order).

**Open zones (M08+)** are data: a declarative layout (`tools/worldgen`) with
routes, ridges, plateaus, level bands, named areas and a POI list is baked
into a heightmap, a trail mask, a map image and `layout.json`; the zone
script builds every POI through `PoiBuilder`. Rules the bake asserts: every
combat POI on a flat pad (< 3 deg), route grades <= `grade_max`, camps
>= 45 m apart and >= 40 m from the spawn, every POI with a neighbour within
80 m. Activation, spawners and triggers work with *all* heroes in range
(`players_within`); enemies only through the zone factory. M15's two new
zones copy this pattern (with the M12 additions below).

## The Highlands' sub-biomes (M12, built so far)
Three looks on top of the ash (the south, the middle and Cinder Flats stay
ash and raiders):
- **Ashwick, the abandoned village** (Westreach, level 2): grey-olive earth,
  dead grass, cobbled street and lane; seven ruined houses around a square
  with the well, fences, a cart, a barricade at the east entrance; the
  graveyard south-west (its curse comes later), the trial shrine east of it,
  the chapel spot with the braziers in the west.
- **The Charwood, the burnt forest** (north-west, level 3): charcoal ground
  with soot drifts and embers, dense charred trunks and snags, fallen logs,
  smouldering stumps; camp 8, ruin 3 and the Ember Warrens gate in
  clearings; the trial shrine, the wisp nest, a last stand of spears, and a
  secret climb (no trail) up to the tome shelf.
- **The Ribs of Emberfall, the bone field** (east, level 3): dark bone dust
  with pale chips, bones everywhere, a giant skeleton (skull, spine, a cage
  of ribs to walk in) and rib sets; camp 7, the elite patrol, the Hollow
  Cistern gate, the trial shrine, the jackal den and the dodge run.
- Ash places that tell a story: fallen soldiers at the south funnel, an
  abandoned raider camp, an overturned cart.

## Planned: the Highlands with substance (M12)
User decisions of 2026-09-29 (ROADMAP "Spieler-Leitlinien"). The user's
verdict on today's Highlands: visually uniform (ash and brown everywhere, the
same rocks and trees), too little to do (between POIs only walking, POIs are
nearly always a camp or a chest), no life, nothing to discover off the
trails. The Highlands get this first and become the template for every later
zone.

Wanted:
- **Sub-biomes:** every corner with its own look, for example a burnt forest,
  lava fissures, an abandoned village, a frozen lake, the bone field grown
  into an area. Palette, props, scatter and ground layers per sub-biome.
- **More POI types** next to camps and chests: small puzzles outdoors, trial
  shrines, nests, cursed places, small caves.
- **Harmless animals and creatures** for life, not for combat: carrion
  crows, ash hares, neutral things that flee or watch.
- **New enemy families per sub-biome** instead of the same raiders
  everywhere.
- **Secrets and lore:** hidden caves, climbing paths, graves, notes, ghosts,
  collectibles with a small reward, ability tomes (CLASS_DESIGN "Loadout").
  Lore objects may carry the rare meta breaks of STORY_DESIGN.
- **Places that tell a story without text:** fallen warriors, barricades,
  traces of a fight, abandoned camps.

Not chosen for now (don't propose them again without a reason): weather and
time of day, world events, NPCs in the open world, more music tracks, a
richer soundscape, light and sky changes. The music is liked as it is.

## Planned: dungeons (M13)
User decisions of 2026-09-29. Dungeons should be more varied.
- **Puzzle types:** ability puzzles (light braziers with fire, freeze water
  with frost, lead lightning to a gate), mechanical puzzles (pressure plates,
  levers, pushable blocks, light beams and mirrors), traps and skill (blade
  corridors, collapsing floors, timing runs with Dodge). Not chosen: memory
  and logic puzzles (rune sequences, symbol riddles).
- **Size, mixed:** mostly short (under 2 min) as a break from combat; per
  dungeon one bigger puzzle that opens a secret.
- **Secret rooms and branches:** hidden walls, optional paths, bonus chests,
  shortcuts back to the entrance.
- **Mid-bosses**, each with its own idea (for example using the room against
  it).
- Not chosen: in-dungeon events (waves, escapes, escorts), room modifiers.
- **Normal dungeons** (first: the Hollow Cistern and the Ember Warrens behind
  the Highlands' sealed gates) are solvable alone and with every class, so
  an ability puzzle needs a way for each class (derived from the co-op
  answer, not asked directly).

**Co-op dungeons** (the user: "there should be extra dungeons for co-op"):
- for **3–5 players**, locked for fewer; extra content with their own loot,
  the story is complete without them;
- built for the roles (CLASS_DESIGN "Three roles"): without a tank or a
  healer they get clearly harder; real co-op puzzles are allowed here;
- proposal, not decided: scaling from 3 to 5 like today's enemy health
  (+70 % per extra hero), plus mechanics that use the group.
