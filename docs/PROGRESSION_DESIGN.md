# RUNEBOUND — Progression Design (M07, classes M10)

Status: **implementer proposal**, built while the user was away (they asked
to continue past M06). Every number and every talent is data. XP values sit
in the enemy scripts and in `Progression`, and talents are `.tres` files in
`resources/talents/`. Retuning or replacing a node is a data edit.

## Goals (ROADMAP M07)
- Leveling: XP from kills, camps, chests and discoveries; a level cap; enemy
  and item levels, so loot scales with the player.
- A talent tree: one point per level, three branches (**Storm / Ember /
  Runic Warden**). Nodes change behavior, not only percentages. Respec at
  any time.
- Abilities 7–8 (**Runic Guard**, **Resonance Burst**) are talent unlocks.

## Leveling
- **Level cap 25.** XP to the next level: `round(80 * L^1.6)`, so
  80 → 243 → 464 → … → ~12,900 at 24.
- One clear of today's slice (Highlands + Spire, bosses included) gives
  about 3,500 XP, which is level 6–7. Camps re-arm on every visit, so
  farming works until M08/M09 add the open zones and their level ranges.
- **Per level:** +1 talent point, +6 max health, +2 % ability damage.
- **XP sources:**

  | Source | XP |
  |---|---|
  | Marauder | 20 |
  | Duskweaver | 22 |
  | Veilstalker | 24 |
  | Warden | 40 |
  | Stonehulk | 45 |
  | Colossus | 600 |
  | Vessel | 1,200 |

  - Elites give x4.
  - Enemy level scales XP: x(1 + 0.15 (L−1)).
  - Camp cleared: 15 per enemy in the composition.
  - Chest: 60.
  - First visit of a zone (discovery): 150.
- **Enemy level:** zones set it per area.
  - Highlands south 1, north 2, the Colossus 3.
  - Spire 3, the Vessel 4.
  - Hub and lab: 1.

  Per level above 1, health +8 %; damage is not scaled yet (see the open
  questions). Level 1 is today's balance, unchanged. A player arriving at
  the expected level gains about as much damage from levels (+2 % each) as
  the enemies gain health, so the tested difficulty stays close.
- **Item level:** set by the source (enemy level, or the zone level for
  chests). Numeric affix values x(1 + 0.06 (ilvl−1)); behavioral affixes
  and legendary powers don't scale. The item detail shows "Item Level N",
  and the compare view lists affix deltas.

## Talent trees (M10: one per class, 3 branches x 8 nodes)
- **Tiers** open by points spent in the same branch: tier 1 at 0, tier 2 at
  3, tier 3 at 6, the capstone at 10 (the generator asserts every tier is
  reachable).
- One point per level: by the cap (24 points) a build finishes one branch
  and dips into a second.
- **Respec:** free, in the talent panel (key N).
- Behavior nodes are marked ⚙.
- M10 moved the Storm and Ember branches with their spells to the
  Elementalist; Molten Core (an Earthbreaker talent) stayed with the tank.
  A migrated Runebreaker's spell talents drop out of its tree (the points are
  free again).

### Runebreaker (tank)
**Bulwark** (block, threat, damage taken)
| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Runic Plate | 3 | +15 max health per rank |
| 1 | Stalwart | 3 | take 3 % less damage per rank |
| 2 | Shield Wall | 2 | Rune Wall blocks 5 % more per rank |
| 2 | Provoker | 2 | taunts hold 1 s longer per rank |
| 2 | ⚙ Unbroken | 1 | dodging through an attack grants a 15-health barrier (8 s cooldown) |
| 3 | ⚙ Riposte | 1 | a parry's counter hits every enemy within 2.5 m, +15 Resonance |
| 3 | Bastion | 2 | Warding Rune reduces damage 5 % more per rank |
| Cap | ⚙ Unyielding | 1 | below 30 % health you take 30 % less damage |

**Earthshaker** (Rune Cleave, Earthbreaker, Warden's Leap)
| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Heavy Hands | 3 | Rune Cleave +8 % damage per rank |
| 1 | Earthshaker | 2 | Earthbreaker costs 8 less Resonance per rank |
| 2 | ⚙ Molten Core | 1 | Earthbreaker sets every enemy it hits ablaze |
| 2 | Aftershock | 2 | Earthbreaker's area +0.5 m per rank |
| 2 | Wide Arc | 2 | Rune Cleave reaches 15 % further per rank |
| 3 | ⚙ Quake Leap | 1 | Warden's Leap lands like Earthbreaker (heavy stagger) |
| 3 | Hold the Line | 2 | +8 % damage per rank to enemies that are attacking you |
| Cap | ⚙ Tectonic | 1 | Earthbreaker taunts every enemy it hits for 3 s |

**Runic Warden** (Resonance, barrier, the burst)
| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Resonant Strikes | 3 | +10 % Resonance gained per rank |
| 1 | Steadfast | 2 | +3 Resonance per hit Rune Wall blocks, per rank |
| 2 | ⚙ Runic Guard | 1 | **unlocks Runic Guard** (30 Resonance: a barrier of 40 + 1 per level for 4 s) |
| 2 | Warding Runes | 2 | Runic Guard absorbs 15 more per rank |
| 2 | ⚙ Glacial Bulwark | 1 | enemies that strike your Runic Guard are Chilled |
| 3 | ⚙ Resonance Burst | 1 | **unlocks Resonance Burst** (all Resonance, 50+, in a 4 m nova) |
| 3 | Binding Chains | 2 | Rune Chain cooldown -15 % per rank |
| Cap | ⚙ Aegis of Runes | 1 | Runic Guard also shields allies within 6 m for half its amount |

### Elementalist (damage)
**Storm** (lightning, tempo) - the M07 branch unchanged: Static Charge (+3 %
crit), Quickstep (Storm Step cooldown -12 %), Arc Conduit (+1 Chain Spark
jump), Galvanize (+8 % vs Shocked), ⚙ Overload, ⚙ Thunderclap, Storm Surge
(+15 % Aether from lightning), ⚙ Eye of the Storm (capstone).

**Ember** (fire, damage over time) - the M07 branch with one change: Kindling,
Searing Lance, ⚙ Split Lance, Piercing Heat, **⚙ Cinderfall** (Ember Fall
leaves burning ground for 3 s; replaces Molten Core), ⚙ Wildfire, Fuel the
Fire, ⚙ Phoenix Burst (capstone).

**Frost** (control)
| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Frost Ward | 2 | Fracture Rune arms 0.2 s faster per rank |
| 1 | Aether Flow | 3 | +10 % Aether gained per rank |
| 2 | Shatter | 3 | +8 % damage per rank to Chilled enemies |
| 2 | ⚙ Deep Freeze | 1 | Frost Nova roots the enemies it Chills for 1 s |
| 2 | Rune Mastery | 2 | Fracture Rune's area +0.5 m per rank |
| 3 | ⚙ Echo Rune | 1 | Fracture Rune detonates a second time, at half damage |
| 3 | Cold Snap | 2 | Chill lasts 0.5 s longer per rank |
| Cap | ⚙ Absolute Zero | 1 | an enemy Chilled three times within 6 s freezes for 2 s |

### Druid (healer, M11)
**Growth** (the heals): Verdant Touch (+6 % healing and shields), Deep Roots
(+12 health), Lingering Growth (Regrowth +15 % longer), Thick Bark (Barkskin
+10), Frugal Bloom (Mending Bloom -2 Sap), ⚙ Overgrowth (Mending Bloom below
35 % also starts Regrowth), Nurture (+10 % healing on allies below half),
⚙ Lifebloom (capstone: Wild Bloom also shields for a fifth of the heal).

**Thorns** (its own damage): Sharp Thorns (Thorn Volley +8 %), Wild Heart
(+3 % damage), Strangle (roots +0.5 s), Bramble (Thornfield +0.5 m),
⚙ Splinter (a fourth thorn), Grasping Briars (+10 % vs rooted), Keen Thorns
(+3 % crit), ⚙ Briar Burst (capstone: Root Grasp bursts again at half
damage).

**Grove** (zones, totem, Sap): Sap Well (Sap +15 % faster in a fight), Grove
Keeper (grove +15 % healing), Wide Grove (+0.75 m), Totem Ward (totem +5 %
damage), ⚙ Green Tide (standing in the grove refills 2 Sap a second),
⚙ Rooted Totem (the totem roots enemies within 3 m for 1.5 s), Thrift
(cooldowns -4 %), ⚙ Heart of the Grove (capstone: grove and totem last
50 % longer).

## Gold and the trainers (M07b, M10: one per class)
- **Start kit:** the class's basic attack and Dodge. The rest is bought from
  the class's trainer in Runehold (`[E]`; a hero of another class is sent to
  its own):
  - **Sigrun Runewright** (Runebreaker, by the training gear, north-west):
    Earthbreaker L2 / 50, Rune Wall L3 / 150, Rune Challenge L4 / 275,
    Warden's Leap L5 / 400, Rune Chain L6 / 500, Warding Rune L7 / 650
    (cumulative 50 / 200 / 475 / 875 / 1,375 / 2,025).
  - **Maren Emberwright** (Elementalist, by the east wall near the spawn):
    Ember Lance L2 / 50, Storm Step L3 / 150, Chain Spark L4 / 275, Fracture
    Rune L5 / 400, Frost Nova L6 / 525, Flame Wall L7 / 650, Ball Lightning
    L8 / 800, Ember Fall L9 / 1,000 (cumulative 50 / 200 / 475 / 875 / 1,400
    / 2,050 / 2,850 / 3,850).
  - **Hild Ashroot** (druid, M11, by the south wall west of the spawn):
    Barkskin L2 / 50, Regrowth L3 / 150, Root Grasp L4 / 275, Renewal Grove
    L5 / 400, Thornfield L6 / 525, Totem of Growth L7 / 650, Wild Bloom
    L8 / 800 (cumulative 50 / 200 / 475 / 875 / 1,400 / 2,050 / 2,850). The
    druid starts with Thorn Volley and Mending Bloom (it heals itself from
    the first minute).

  Runic Guard and Resonance Burst stay talent unlocks. All of it is data on
  the `AbilityData` (`unlock`, `learn_level`, `learn_price`). The M07b list
  (one Runebreaker with all eight, Fracture Rune at L7 / 600) is history; the
  v2 -> v3 migration still refunds those frozen prices.
- **Ylva Ashbrew** (M10b, south-west of the hearth): Healing Draughts at
  30 gold (ITEMIZATION "consumables") - gold's second use after the
  trainers.
- **Gold drops:** every kill pays `round(xp_reward * 0.5 * rand(0.8..1.25))`,
  so elites (x4) and enemy levels (+15 %) carry over. Bosses scatter theirs
  into 3 (Colossus) / 4 (Vessel) piles; chests add 40–60 x item-level scale.
  Coins glide to the player from 3 m and never need an inventory slot.
- **Pacing check:** a slice clear (~3,500 XP, level 6–7) yields ~1,500 gold,
  so the fifth ability lands around level 6–8; the second one after camps
  1–2. A toast says when Sigrun can teach something new (level and gold met).
- **HUD / sheet:** gold counter right of the bars; the character tab (C)
  lists effective damage, average with crit, cooldown, cost and Resonance
  gain per known ability (`StatSheet`, same formulas as the hits).

## The loadout (M10, built)
A hero takes **4 of its class's pool** into the field (RMB, 1, 2, 3; the
basic attack on LMB and Dodge stay fixed) and swaps them anywhere out of
combat (the Abilities tab, K; the sprint's 3 s rule). A newly learned ability
takes the first free slot; a forgotten one (a respec) leaves its slot. M10
builds 8 pool abilities per class; abilities join the pool through the class
trainer, the talent tree and, from M12-M14, quests, bosses and tomes. See
CLASS_DESIGN "Three roles".

## Save format
SaveGame **v6** (M10): `{version, characters: [{name, class_id,
known_abilities, loadout, gold, inventory, equipped, progression, waypoints,
map_discovered, discovered, world: {zone, flags, camps: {id: {cleared_at}}},
notes}], active}`. **Every character has its own world** (user, 2026-09-29):
a new character meets the Colossus itself. The title screen lists, creates
(class + name) and deletes characters. A save without characters (the
dedicated server's) keeps one top-level `world`. Migrations: v5 -> v6 copies
the world into every character and gives a Runebreaker the M07b price of the
spells that moved to the Elementalist as gold (a toast says so once); v4 ->
v5 moves zone discovery into the character; v3 -> v4 adds camps, waypoints
and the map; v2 -> v3 wraps the single character as a Runebreaker with **the
start kit only and the prices of the abilities its level had reached
refunded as gold** (user, 2026-09-24: every character walks the trainer
path); v1 -> v2 adds progression. Debug `[9]` gives the active character a
true fresh start (the others stay); `tools\run_godot.cmd reset` (game closed)
deletes the whole save.

## Open for the user (decisions to confirm)
0. M07b: Earthbreaker before Ember Lance (L2 / L3); prices; Fracture Rune
   now gets gear and talent bonuses like every ability.
1. The cap (25), the curve steepness, and XP per source.
2. The talent list and names, especially the capstones.
3. Key bindings (user, 2026-09-24): every ability on the number row:
   1 Earthbreaker (also Q), 2 Storm Step, 3 Chain Spark (also R),
   4 Fracture Rune, 5 Runic Guard, 6 Resonance Burst. E is interact
   (portals and chests; loot still picks up by walking over it). All are added at runtime,
   so `project.godot` stays unchanged.
4. Whether enemy levels should also raise enemy damage. Today they raise
   health only.
