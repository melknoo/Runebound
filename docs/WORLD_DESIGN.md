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
| Dungeon gates | 2 | Hollow Cistern (east), Ember Warrens (west): M13 dungeons; the seal breaks when a hero comes close (the Warrens stay sealed until built) |
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

## The Highlands' sub-biomes (M12)
Three looks on top of the ash (the south, the middle and Cinder Flats stay
ash and raiders):
- **Ashwick, the abandoned village** (Westreach, level 2): grey-olive earth,
  dead grass, cobbled street and lane; seven ruined houses around a square
  with the well, fences, a cart, a barricade at the east entrance; the
  cursed graveyard south-west, the trial shrine east of it,
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

## The Highlands with substance (M12, built 2026-10-01/02)
User decisions of 2026-09-29 (ROADMAP "Spieler-Leitlinien"). The user's
verdict on today's Highlands: visually uniform (ash and brown everywhere, the
same rocks and trees), too little to do (between POIs only walking, POIs are
nearly always a camp or a chest), no life, nothing to discover off the
trails. The Highlands get this first and become the template for every later
zone.

Built (the user chose in two rounds on 2026-10-01; details in
PROJECT_STATE "M12"):
- **Sub-biomes:** the village, the burnt forest and the bone field above
  (not the lava fissures); their own ground, rocks, props and scatter, a
  mask the bake writes, one terrain material.
- **Enemy families**, two each: the Restless in Ashwick (Grave Shambler
  rising from the ground, Mourner screaming a slow), the Charwood (the
  Cinderbark standing as a tree, the blinking Smoulder Wisp), the carrion
  brood on the bones (Ash Jackals in packs of three, the diving Carrion
  Vulture). The raiders keep the ash.
- **New POI types:** four outdoor puzzles (braziers, monoliths, a boulder,
  a dodge run), two grottos, three trial shrines with rune blessings, two
  nests, the cursed graveyard; a secret climb to the tome.
- **Animals** (hares, crows): scenery that flees, never a target, local to
  every machine.
- **Secrets and lore:** graves, notes and inscriptions, two ghosts and the
  priest, twelve shards of the Shattered Rune (a blessing for all), the
  tome teaching each class its art; food to gather (the Ember Tuber).
- **Places that tell a story without text:** fallen soldiers, an abandoned
  camp, a cart, barricades, a last stand, a skeleton in the bones.
- Every new text is in the DE/EN text table (STORY_DESIGN).

Not chosen for now (don't propose them again without a reason): weather and
time of day, world events, NPCs in the open world, more music tracks, a
richer soundscape, light and sky changes. The music is liked as it is.

## Dungeons (M13)
User decisions of 2026-09-29 and, for M13, of 2026-10-09 (three rounds;
ROADMAP M13). Dungeons should be more varied.
- **Puzzle types:** ability puzzles (light braziers with fire, freeze water
  with frost, lead lightning to a gate), mechanical puzzles (pressure plates,
  levers, pushable blocks, light beams and mirrors), traps and skill (blade
  corridors, collapsing floors, timing runs with Dodge). Not chosen: memory
  and logic puzzles (rune sequences, symbol riddles).
- **Every puzzle is solvable alone by every class** with the basic attack,
  Dodge, [E] and walking: an ability puzzle takes its element from a source
  in the room (an ember bowl, a frost crystal, a storm coil charge the hero
  for a few seconds); the Elementalist's own fire, frost and lightning are a
  shortcut.
- **Size:** about 15 minutes for a first run - 6-8 rooms, 4-5 short puzzles
  (under 2 min), one bigger puzzle per dungeon that opens a secret (its
  tome), 1-2 branches, a secret room behind a hidden wall, a mid-boss with
  its own idea (the room used against it), an end boss and a shortcut back
  to the entrance.
- **Afterwards:** normal enemies come back like camps (~10 min, never while
  a hero is near); puzzles, shortcuts and secrets stay solved; bosses stay
  dead (world flags). Dungeon chests open once.
- **Death:** back at the entrance or the last rune touched in the dungeon;
  the dungeon keeps its progress; a boss resets (full health) once nobody
  alive is left in its arena.
- **Gates** open at once (the seal breaks when a hero comes close) and name
  a recommended level; free order. Music: the Spire's tracks (no new ones),
  an ambience loop each.
- **Enemies:** per dungeon a family of two new types, a mid-boss and an end
  boss. **Reward of the big secret:** a tome per dungeon, every class learns
  one new ability from each (role gaps, the dungeon's flavour).
- Not chosen: in-dungeon events (waves, escapes, escorts), room modifiers.
- **Interiors** are open-topped like the Spire (walls 6-9 m, the camera may
  look over them); secret rooms are roofed (they read as rock from outside).
  Corridors are at least 5 m wide, doors 4 m, combat rooms 16 x 16 m.

### The Hollow Cistern (east gate, the Ribs of Emberfall; built from M13 phase 0)
An old, half-flooded cistern, cold blue-green stone; enemies level 3, the
bosses 4 (recommended level 4). A ring: the inlet -> the sluice hall (water
level) with the pump chamber as a branch (plates and a block, a bonus
chest) -> the frost channel (an ice bridge) -> a slope up to the mirror
gallery (a light beam) -> the antechamber (a rune) -> the settling basin
(the mid-boss, the Bloated Keeper: drain the basin with its sluice levers)
-> the undertow run (sluice blades; a cracked wall hides the vault with the
big puzzle and the tome room) -> the Maw's threshold (its lever opens the
shortcut to the inlet) -> the heart of the cistern (the end boss, the
Deepmaw). Family: the Drowned (a bloated thrall that bursts into a slowing
puddle; a channel lurker that strikes from the water). Phases 0-4 built
the rooms, every puzzle (the sluice valves, the pump chamber's block and
plates, the frost channel's ice, the gallery's light, the run's blades, the
cracked wall, the vault's ice + light + plates), the runes, both arenas, the
shortcut, the look (wet blue-green stone, algae, dark water, phosphor
lanterns) and five lore texts; phase 5 the Drowned and both bosses:
- **Drowned Thrall:** slow and heavy, both arms down on a disc ahead;
  dead, it bursts into a puddle that chills (slows) and nips for 5 s.
- **Channel Lurker:** waits under the floor (untouchable), rises, spits a
  bolt of cistern water, stays up spent for 1.6 s (the moment to punish),
  sinks and rises a few metres away (a hero fighting within 24 m wakes
  it too). A lone lurker guards the frost channel's south bank.
- **The Bloated Keeper** (mid-boss, the settling basin): tough while the
  basin stands full (x0.4 damage, a splash shows it); both sluice levers
  pulled within 8 s drain the basin for 15 s: laid bare it takes x1.25 and
  drags itself slower. A slam ahead, a stamped ring wave every 9 s (dodge
  through it), two drowned at two thirds and one third.
- **The Deepmaw** (end boss, the heart): never walks; rises at one of four
  drains, lunges down a lane or spits three bolts, sinks after 7 s and
  rises at another drain; calls drowned through the other drains. Below
  half its health the outer ring floods (nips, slows); a strike on one of
  the two frost pylons in the ring freezes the flood for 6 s (firm ice, no
  harm). The middle stays dry.

### The Ember Warrens (west gate, the Charwood; built from M13 phase 6)
Old ember mines and their smelting halls, soot-black hewn rock, old timber,
copper ore in the walls, lava in the runnels; enemies level 4, the bosses 5
(recommended level 5). A ring: the adit -> a gallery into the rail hall (an
ore cart pushed along its rail onto a plate holds the kiln gate open; the
ore store is a branch: cart b off the crossing first, then cart a through,
both on their plates open an alcove with a bonus chest) -> the kiln hall
(an ember bowl and four kilns lit within 20 s, a lava runnel along its back
wall) -> a ramp up to the spark shaft (a storm coil, four copper posts struck
in order lift the gate) -> a ramp down into the collapse gallery (rows of
stone over a lava pit fall away in turn) -> the landing (a rune) -> the
smelting hall (the mid-boss, the Slag Reeve: cooled at a quench trough) ->
the jet run west (fire jets in rhythm; a cracked wall hides the mould room)
-> the brood's threshold (a rune; its lever opens the shortcut to the adit)
-> the brood hall (the end boss, the Ember Broodmother). The big puzzle in
the mould room: heat three crucibles (the ember bowl or a fire spell), pull
the tipping lever, turn two chutes until the melt runs into the mould - the
tome room opens. Six lore texts. Phase 7 brought the Ember Brood and both
bosses:
- **Cinder Beetle:** waits dug in; woken (a hero within 9 m, or a fight
  within 20 m) it tunnels under its prey and breaks out beneath it (a ring
  fills - step out), then bites. Its slag head plate turns most of a blow
  from the front: strike it from the side or behind. After a while up, or
  when its prey runs off, it digs in again.
- **Kiln Imp:** small and quick, keeps 5-9 m away and lobs slag where its
  prey stands (a disc; the ground burns after); dead, its belly bursts
  once its ring fills.
- **The Slag Reeve** (mid-boss, the smelting hall): hot, his crust turns
  most of every blow (x0.4). Two quench troughs: pull a chain while he
  stands within 6 m of that trough and his crust cracks for 14 s (x1.3,
  slower) - lure him there. A hammer slam ahead, a fan of slag every 12 s, two imps
  at half health.
- **The Ember Broodmother** (end boss, the brood hall): bites, charges
  down a lane, digs in and breaks out under her prey (a wide ring), lays
  a cinder beetle every 28 s (two at most). Below half her health the two lava runnels across the
  hall fill and burn; a valve by the wall crusts its runnel over for 8 s.

**Co-op dungeons** (M13b, the user: "there should be extra dungeons for co-op"):
- for **3–5 players**, locked for fewer; extra content with their own loot,
  the story is complete without them;
- built for the roles (CLASS_DESIGN "Three roles"): without a tank or a
  healer they get clearly harder; real co-op puzzles are allowed here;
- proposal, not decided: scaling from 3 to 5 like today's enemy health
  (+70 % per extra hero), plus mechanics that use the group.
