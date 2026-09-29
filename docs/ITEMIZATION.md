# RUNEBOUND — Itemization (M03)

Philosophy: every interesting drop should ask "what happens if I use this?"
Numeric affixes stay chunky; the exciting drops change ability behavior.

## Structure
- **Slots** (7, user decision 2026-09-24): Weapon · Helm · Chest · Gloves ·
  Boots · Amulet · Ring. Old Armor/Relic items are Chest/Amulet (same enum
  values, no save conversion). Inventory cap 24.
- **Affix spread**:
  - Movement, dodge and Storm Step cooldown roll on boots only.
  - Crit and area on gloves, rings and weapons.
  - Health on chest, helm and amulet.
  - Cooldown reduction on amulet, helm and chest.
  - Every slot has at least 3 affixes.
- **Rarities**: Common (0 affixes) · Magic (1) · Rare (2–3) ·
  Legendary (2 + power). Epic/Unique reserved for later.
- **Drop rates** (M08 notes, user 2026-09-28: "fewer drops, rare items much
  rarer"; all in `ItemGenerator`'s loot tuning): a kill drops an item with
  trash 8% · brute 30% · elite 60%. Rarity by bias: trash / plain chests
  legendary 0.3%, rare 6%, magic 30%; brutes / better chests legendary 1%,
  rare 17%, magic 45%; elites rare or better, 5% legendary. Chests give 1-2
  items per hero (was 2-3). Boss legendaries stay guaranteed. (Before:
  20 / 60 / 100%, legendaries 2 / 6 / 25%.) Debug: key 7 random, key 8
  legendary.
- **Presentation** scales with rarity: label → glow → gold beam → tall orange
  beam + fanfare. Auto-pickup at 1.4m, HUD toast on pickup.

## Affix pool (scripts/items/affix_pool.gd)
Numeric: +12–20% damage (W/R) · +20–35 HP (A/R) · 10–20% CDR (A/R) ·
+20–35% Resonance (W/R) · +8–12% move speed (A) · +4–7% crit (W).
Behavioral: Ember Lance +1 pierce · Chain Spark +1 jump · Cleave +35% area ·
Dodge CD −30% · Earthbreaker −15 cost · Fracture Rune arms 0.4s faster.

## M07 additions
- **Item level** = level of the drop source. `damage_pct`, `max_hp` and
  `resonance_pct` scale +6 % per level above 1; cooldown, speed, crit and
  behavioral affixes stay fixed.
- **Compare:** the detail pane lists every stat that changes against the
  equipped item (green gain, red loss), plus legendary power gain or loss.
- **New affixes** on the talent stats, so they stack with talents:
  +10–16 % damage to Shocked, Burn +20–35 %, Storm Step cooldown −10–18 %.
- **New legendaries** grant a talent's behavior. A matching talent doesn't
  stack with them.

  | Item | Slot | Power |
  |---|---|---|
  | Forked Ember | Weapon | Split Lance |
  | Stormcaller's Band | Relic | Overload |
  | Emberheart Plate | Armor | Molten Core |

## M07b additions
- **Gold** is a `GoldDrop` (coin stack, magnet glide from 3 m, always picked
  up, `+N gold` float text, `coin_pickup` SFX). `ItemDrop` and `GoldDrop`
  share `WorldPickup` (proximity test, bob). Amounts: PROGRESSION_DESIGN.md.
- **Class tags:** the six ability-specific affixes (`ember_pierce`,
  `chain_jumps`, `cleave_radius_pct`, `eb_cost_reduce`, `rune_arm_reduce`,
  `storm_cd_pct`) and every legendary carry `"class": &"runebreaker"`.
  `ItemGenerator.generate(bias, class_id)` rolls only what fits the killer's
  class (an elite drop with no legendary for the class becomes rare); an
  empty class id (debug drops, tests) allows everything.
- Drops, XP and gold go to the **attacker** who landed the last hit
  (`HitInfo.attacker_id`), not to "the" player.

## M10: two classes
- **The class tags follow the abilities.** Elementalist: `ember_pierce`,
  `chain_jumps`, `rune_arm_reduce`, `storm_cd_pct`, `shocked_dmg_pct` and a
  new `aether_pct` ("+N % Aether gained", the same `resonance_pct` stat under
  the Elementalist's resource name). Runebreaker: `cleave_radius_pct`,
  `eb_cost_reduce`, `resonance_pct`. Shared: damage, health, cooldown,
  movement, crit, dodge cooldown, Burn damage (the tank's Molten Core burns
  too).
- **Legendaries by class:** the Elementalist rolls Cindermaw, Conductor's
  Oath, Forked Ember and Stormcaller's Band; the Runebreaker Glacier Heart,
  Emberheart Plate and (M10 phase 2) Warden's Oath. Boss legendaries roll for
  each hero's own class (they used to ignore it).
- **Names:** an Elementalist's gear uses its own nouns (`ItemGenerator.CLASS_NOUNS`:
  staves, wands, rods, scepters; robes and mantles; hoods and circlets;
  wraps; slippers). A Runebreaker keeps blades and plate.
- Items already in a bag keep their affixes; an affix of the other class
  simply does nothing (every ability hook reads its stat by key).

## Legendary powers
| Item | Class | Slot | Power |
|---|---|---|---|
| Cindermaw | Elementalist | Weapon | Burning enemies struck by Ember Lance erupt (r2.5 fire, spreads Burn) |
| Conductor's Oath | Elementalist | Amulet | Chain Spark marks Conductors (6s); lightning damage on one arcs 8 dmg to all others (≤14m, no re-chaining) |
| Forked Ember | Elementalist | Weapon | Split Lance |
| Stormcaller's Band | Elementalist | Ring | Overload |
| Glacier Heart | Runebreaker | Chest | Earthbreaker leaves a frost field (r4, 4s) that Chills |
| Emberheart Plate | Runebreaker | Chest | Molten Core |
| Warden's Oath | Runebreaker | Helm | a parry with Rune Wall grants a 20-health barrier for 3 s |

## Implementation notes
- Items are runtime `ItemData` resources from `ItemGenerator`; base ability
  .tres files are never mutated — equipment modifies at the hook points in
  hero scripts (`Player.roll_ability_hit`, `_set_cooldown`,
  `resource_cost`, radius/jump/pierce/arm-time reads in
  `scripts/player/classes/`) and `Equipment.stat()/has_power()`.
- Conductor splash hits carry `HitInfo.is_conductor_arc` to prevent chains.
- Aim rule added for pierce builds: direct enemy ray hits aim center mass,
  not the surface point (feet hits buried pierced lances into the floor).
