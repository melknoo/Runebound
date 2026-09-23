# RUNEBOUND — Itemization (M03)

Philosophy: every interesting drop should ask "what happens if I use this?"
Numeric affixes stay chunky; the exciting drops change ability behavior.

## Structure
- **Slots**: Weapon · Armor · Relic (3 equip slots, list inventory cap 24).
- **Rarities**: Common (0 affixes) · Magic (1) · Rare (2–3) ·
  Legendary (2 + power). Epic/Unique reserved for later.
- **Drop rates**: trash 20% · brute 60% · elite 100% (rare or better,
  25% legendary). Debug: key 7 random, key 8 legendary.
- **Presentation** scales with rarity: label → glow → gold beam → tall orange
  beam + fanfare. Auto-pickup at 1.4m, HUD toast on pickup.

## Affix pool (scripts/items/affix_pool.gd)
Numeric: +12–20% damage (W/R) · +20–35 HP (A/R) · 10–20% CDR (A/R) ·
+20–35% Resonance (W/R) · +8–12% move speed (A) · +4–7% crit (W).
Behavioral: Ember Lance +1 pierce · Chain Spark +1 jump · Cleave +35% area ·
Dodge CD −30% · Earthbreaker −15 cost · Fracture Rune arms 0.4s faster.

## Legendary powers
| Item | Slot | Power |
|---|---|---|
| Cindermaw | Weapon | Burning enemies struck by Ember Lance erupt (r2.5 fire, spreads Burn) |
| Conductor's Oath | Relic | Chain Spark marks Conductors (6s); lightning damage on one arcs 8 dmg to all others (≤14m, no re-chaining) |
| Glacier Heart | Armor | Earthbreaker leaves a frost field (r4, 4s) that Chills |

## Implementation notes
- Items are runtime `ItemData` resources from `ItemGenerator`; base ability
  .tres files are never mutated — equipment modifies at the hook points in
  `player.gd` (`roll_ability_hit`, `_set_cooldown`, `earthbreaker_cost`,
  radius/jump/pierce/arm-time reads) and `Equipment.stat()/has_power()`.
- Conductor splash hits carry `HitInfo.is_conductor_arc` to prevent chains.
- Aim rule added for pierce builds: direct enemy ray hits aim center mass,
  not the surface point (feet hits buried pierced lances into the floor).
