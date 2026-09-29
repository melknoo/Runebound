# RUNEBOUND — Class Design

## Three roles (M10–M11)
User decisions of 2026-09-29 (ROADMAP "Spieler-Leitlinien"). Each milestone
gets its own plan with the numbers; this section records the direction.
**M10 phase 1 is built** (2026-09-29): both classes as their own hero
scripts, the loadout, several characters per save; phases 2 (tank) and 3
(Elementalist) add the new abilities.

### Roles
| Class | Role | Range | Built in |
|---|---|---|---|
| Runebreaker | tank | melee | M10 (rework of today's class) |
| Elementalist (working name) | damage dealer | ranged | M10, together with the tank |
| Root druid (working name) | healer | mid range | M11 |

- **Soft when alone:** every class finishes the story and the open world
  solo. A role is a strength, not a ticket.
- **Demanding in co-op dungeons** (3–5 players, locked solo, WORLD_DESIGN
  "Planned: dungeons"): without a tank or a healer they get clearly harder.
- **Threat + taunt:** enemies remember who threatens them most (damage dealt,
  plus extra threat from tank abilities); a taunt pulls at once for a few
  seconds. Today's rule (recent attacker, else nearest) becomes the fallback.

### Loadout: 4 of about 12
- **Fixed:** the class's basic attack on LMB and Dodge on Space.
- **Free:** 4 slots, **RMB, 1, 2, 3**, filled from a pool of about 12
  abilities per class.
- **Changing** works anywhere out of combat (the sprint's rule: no hit taken
  or thrown for 3 s): the hero window's Abilities tab (K). A newly learned
  ability takes the first free slot.
- **Sources for the pool:** the class trainer (gold + level, as today),
  quests and bosses, secrets and dungeons (tomes), the talent tree (like
  Runic Guard and Resonance Burst today). M10 starts with the trainer and the
  talent tree; the other sources arrive with M12–M14.
- **Need:** about 12 pool abilities plus a basic attack per class, about 30
  new abilities in total (tank ~9, elementalist ~8 on top of the four spells
  it inherits, druid ~12), each with an icon drawn in `tools/texgen/ui.py`
  (ROADMAP "Icon-Quelle").

### M10 decisions (user, 2026-09-29)
- **8 pool abilities per class in M10**; the remaining ~4 per class arrive in
  M12-M14 as rewards from bosses, quests and tomes (those sources then have
  something to give).
- **Block:** held (frontal hits -75 %, a blocked hit gives Resonance) plus a
  **parry** in the first 0.3 s (no damage and a rune counter, a HEAVY hit on
  the attacker).
- **The Elementalist's resource:** build -> spend like the Runebreaker's,
  under its own name and colour: **Aether** (magenta, `color_roles.aether`).
- **One world per character** (flags, camps, zone); co-op keeps the
  server's world.

### Runebreaker, the tank (M10)
Armored rune warrior. Rune Cleave builds Resonance, heavy rune abilities spend
it; rhythm BUILD -> SPEND, max 100. 100 health at level 1.
- **LMB (fixed):** Rune Cleave.
- **Pool (8):**

  | Ability | Role | Source | Built |
  |---|---|---|---|
  | Earthbreaker | leaping AoE slam, big stagger, -40 Resonance | trainer L2, 50 g | yes |
  | Runic Guard | barrier (40 + level), -30 Resonance | talent (Runic Warden) | yes |
  | Resonance Burst | finisher nova, spends all Resonance (50+) | talent (Runic Warden) | yes |
  | Rune Challenge | taunt shout, 8 m, 4 s | trainer | phase 2 |
  | Rune Wall | hold to block (-75 % from the front), parry in the first 0.3 s | trainer | phase 2 |
  | Rune Chain | pulls one enemy to you and taunts it | trainer | phase 2 |
  | Warden's Leap | leap to the aim point, the landing taunts briefly | trainer | phase 2 |
  | Warding Rune | ground zone, allies inside take -25 % damage | trainer | phase 2 |

- **Talents** (`Bulwark`, `Earthshaker`, `Runic Warden`, 24 nodes, PROGRESSION_DESIGN).
- **Gave away** the elemental spells (Ember Lance, Chain Spark, Fracture Rune,
  Storm Step) to the Elementalist.

### Elementalist, the damage dealer (M10)
Ranged caster of fire, lightning and frost; Rune Bolts and spell hits build
**Aether**, the big spells spend it. 85 health at level 1 (frailer than the
tank). Burn, Shock and Chill and their interactions moved with the spells.
- **LMB (fixed):** Rune Bolt - a quick arcane dart in the player teal
  (damage type ARCANE); held down it keeps casting and never roots.
- **Pool (8):**

  | Ability | Role | Source | Built |
  |---|---|---|---|
  | Ember Lance | fast fire lance + Burn | trainer L2, 50 g | yes |
  | Storm Step | lightning dash through enemies, Shocks the path | trainer L3, 150 g | yes |
  | Chain Spark | jump-bolt, 3 jumps (+1 through Shocked) | trainer L4, 275 g | yes |
  | Fracture Rune | ground rune, arms 1.2 s, AoE + Chill | trainer L5, 400 g | yes |
  | Frost Nova | ring around you, Chill; spends Aether | trainer | phase 3 |
  | Flame Wall | a burning line on the ground | trainer | phase 3 |
  | Ball Lightning | a slow orb that zaps and Shocks along its way | trainer | phase 3 |
  | Ember Fall | meteor with a telegraph, big Burn; spends Aether | trainer | phase 3 |

- **Talents** (`Storm`, `Ember`, `Frost`, 24 nodes). Until its own rig
  exists (phase 3) it borrows the Runebreaker's rig in a blue tint.

### Root druid, the healer
- Plants breaking out of burnt earth, totems, thorns.
- **Heals targeted:** the ally under the crosshair; aiming at no one heals
  the ally with the least health in range; alone, the druid heals itself.
- **Healing zones** on the ground, **shields and buffs** for the group.
- Enough damage of its own (thorns, roots) to finish the story solo.

### Consequences for the M10 plan
- The talent branches Storm and Ember go with the spells to the
  elementalist; the tank gets new branches around Runic Warden.
- Legendaries and affixes tied to an element or a moving spell (for
  example Forked Ember, Stormcaller's Band, the Shocked / Burn / Storm Step
  affixes) get new class tags.
- Save migration: spells a Runebreaker has learned that move to the
  elementalist are refunded as gold (as in the M07b migration).
- Character select, several characters per save (one class each), a trainer
  per class.

## The kit before M10 (history)
Until M10 the Runebreaker carried all eight abilities: Rune Cleave, Earthbreaker,
Ember Lance, Storm Step, Chain Spark, Fracture Rune (trainer, keys LMB / 1 /
RMB / 2 / 3 / 4) and Runic Guard / Resonance Burst (talents, keys 5 / 6). The
M10 split moved the four elemental spells to the Elementalist; a v5 save's
Runebreaker got their price back as gold.

### Elemental statuses (StatusEffectComponent, the Elementalist's)
- **Burn** (Fire): 4 dps · 3s. Sources: Ember Lance; the tank's Molten Core
  talent sets Earthbreaker's victims ablaze too.
- **Chill** (Frost): −45% move/AI speed · 3s. Sources: Fracture Rune; the
  tank's Glacial Bulwark / Glacier Heart.
- **Shock** (Lightning): +20% damage taken · 4s ("Conductive"). Sources:
  Storm Step, Chain Spark. Interaction: Chain Spark gains a 4th jump when it
  touches a Shocked enemy.

### Intended play patterns
- **Runebreaker:** Cleave to build → Earthbreaker the crowd → Runic Guard when
  the pack turns on you; Resonance Burst to finish (phase 2 adds taunt, block
  and pull so the tank holds the enemies' attention).
- **Elementalist:** Rune Bolts from range to build Aether; Storm Step through a
  pack → Chain Spark the Shocked group; Fracture Rune ahead of a chase → kite
  Chilled enemies into it.

### Talent unlocks (Runebreaker's Runic Warden branch)
| Ability | Element | Role | Resonance |
|---|---|---|---|
| Runic Guard | — | barrier: absorbs 40 + level for 4 s, 12 s cooldown (Glacial Bulwark chills attackers) | −30 |
| Resonance Burst | Physical | finisher nova, 4 m, 0.7 damage per point spent, heavy stagger | all (≥ 50) |

Learned, they join the loadout pool like any trainer ability.
