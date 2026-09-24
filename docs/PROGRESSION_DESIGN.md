# RUNEBOUND — Progression Design (M07)

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

## Talent tree (3 branches x 8 nodes)
- **Tiers** open by points spent in the same branch: tier 1 at 0, tier 2 at
  3, tier 3 at 6, the capstone at 10.
- One point per level: by the cap (24 points) a build finishes one branch
  and dips into a second.
- **Respec:** free, in the talent panel (key N).
- Behavior nodes are marked ⚙.

### Storm (lightning, tempo)
| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Static Charge | 3 | +3 % crit chance per rank |
| 1 | Quickstep | 2 | Storm Step cooldown −12 % per rank |
| 2 | Arc Conduit | 2 | Chain Spark +1 jump per rank |
| 2 | Galvanize | 3 | +8 % damage to Shocked enemies per rank |
| 2 | ⚙ Overload | 1 | Storm Step's end point Shocks every enemy within 2.5 m |
| 3 | ⚙ Thunderclap | 1 | Chain Spark's last target bursts: 60 % damage within 2 m |
| 3 | Storm Surge | 2 | +15 % Resonance from lightning hits per rank |
| Cap | ⚙ Eye of the Storm | 1 | Storm Step refunds 20 % of its cooldown per enemy it passes through |

### Ember (fire, damage over time)
| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Kindling | 3 | Burn damage +20 % per rank |
| 1 | Searing Lance | 3 | Ember Lance damage +8 % per rank |
| 2 | ⚙ Split Lance | 1 | Ember Lance splits into two half-damage lances on its first hit |
| 2 | Piercing Heat | 1 | Ember Lance pierces +1 enemy |
| 2 | ⚙ Molten Core | 1 | Earthbreaker ignites (Burns) every enemy it hits |
| 3 | ⚙ Wildfire | 1 | A Burning enemy that dies spreads Burn to enemies within 3 m |
| 3 | Fuel the Fire | 2 | +10 % damage to Burning enemies per rank |
| Cap | ⚙ Phoenix Burst | 1 | Ember Lance bursts where it ends: 50 % damage within 2 m, and Burn |

### Runic Warden (defense, Resonance, frost)
| Tier | Node | Ranks | Effect |
|---|---|---|---|
| 1 | Runic Plate | 3 | +15 max health per rank |
| 1 | Resonant Strikes | 3 | +10 % Resonance gained per rank |
| 2 | ⚙ Runic Guard | 1 | **Ability 7 (key 5):** a Resonance barrier (30 Resonance, absorbs 40 + 1 per level, 4 s, 12 s cooldown) |
| 2 | Earthshaker | 2 | Earthbreaker costs 8 less Resonance per rank |
| 2 | Frost Ward | 2 | Fracture Rune arms 0.2 s faster per rank |
| 3 | ⚙ Glacial Bulwark | 1 | Enemies that hit your Runic Guard are Chilled |
| 3 | ⚙ Resonance Burst | 1 | **Ability 8 (key 6):** spend all Resonance (at least 50) in a 4 m nova: 0.7 damage per point, heavy stagger |
| Cap | ⚙ Unbroken | 1 | Dodging through an attack grants a 15-health barrier (8 s cooldown) |

## Save format
SaveGame v2 adds `progression: {level, xp, talents: {id: rank}}`. v1 saves
migrate to level 1 with no talents; gear and flags are kept.

## Open for the user (decisions to confirm)
1. The cap (25), the curve steepness, and XP per source.
2. The talent list and names, especially the capstones.
3. Key bindings (user, 2026-09-24): every ability on the number row:
   1 Earthbreaker (also Q), 2 Storm Step, 3 Chain Spark (also R),
   4 Fracture Rune, 5 Runic Guard, 6 Resonance Burst. E is interact
   (portals and chests; loot still picks up by walking over it). All are added at runtime,
   so `project.godot` stays unchanged.
4. Whether enemy levels should also raise enemy damage. Today they raise
   health only.
