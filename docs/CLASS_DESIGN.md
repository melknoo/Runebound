# RUNEBOUND — Class Design

## Three roles (M10–M11)
User decisions of 2026-09-29 (ROADMAP "Spieler-Leitlinien"). Each milestone
gets its own plan with the numbers; this section records the direction.
**M10 phases 1 to 3 are built** (2026-09-29): both classes as their own
hero scripts, the loadout, several characters per save, the tank with
threat, taunts, Rune Wall and its five new abilities, and the Elementalist
with its own rig, four new spells and the Frost branch.

### Roles
| Class | Role | Range | Built in |
|---|---|---|---|
| Runebreaker | tank | melee | M10 (rework of today's class) |
| Elementalist (working name) | damage dealer | ranged | M10, together with the tank |
| Root druid (working name) | healer | mid range | M11 |

- **Soft when alone:** every class finishes the story and the open world
  solo. A role is a strength, not a ticket. (M10 solo check: a bot of
  either class beats every Highlands camp and the Colossus alone at level
  4-6; the tank takes about four times the damage, and nothing heals it
  between fights yet - PROJECT_STATE M10 phase 4.)
- **No regeneration out of combat** (user, 2026-09-30): otherwise waiting
  would answer every fight. Between fights a hero heals with consumables
  (potions, food: part of the health, ROADMAP); in a fight the druid (M11)
  heals the party.
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
it; rhythm BUILD -> SPEND, max 100. 120 health at level 1; its damage
threatens double (ClassData `threat_mult` 2).
- **LMB (fixed):** Rune Cleave.
- **Pool (8):**

  | Ability | Role | Source | Built |
  |---|---|---|---|
  | Earthbreaker | leaping AoE slam, big stagger, -40 Resonance, threat x1.5 | trainer L2, 50 g | yes |
  | Rune Wall | hold: frontal hits -75 %, walk at 40 %; the first 0.3 s parry (no damage, a 30-damage HEAVY counter on the striker, +10 Resonance); +5 Resonance per blocked hit; 1 s cooldown after lowering | trainer L3, 150 g | yes |
  | Rune Challenge | war cry: every enemy within 8 m targets you for 4 s, +5 Resonance each; 12 s | trainer L4, 275 g | yes |
  | Warden's Leap | leap up to 10 m to the aim (over enemies); the 3 m landing deals 22 and taunts 2 s; 9 s | trainer L5, 400 g | yes |
  | Rune Chain | chain to the target (16 m): 14 damage, pulls it 2 m in front of you, taunts 3 s; heavy foes hold their ground; 10 s | trainer L6, 500 g | yes |
  | Warding Rune | 30 Resonance: a 4 m ward, allies inside take 25 % less damage for 8 s; 18 s | trainer L7, 650 g | yes |
  | Runic Guard | barrier (40 + level), -30 Resonance | talent (Runic Warden) | yes |
  | Resonance Burst | finisher nova, spends all Resonance (50+) | talent (Runic Warden) | yes |

- **Threat** (all numbers data): an enemy remembers every hero's threat
  (damage x the ability's `threat_mult` x the class's; fades 6 % a second)
  and hunts the highest; a new favourite needs 10 % more than the current
  one. A **taunt** pulls at once and holds for its seconds, then leaves the
  tank on top of the list. Without any threat the old rule stays (the recent
  attacker, else the nearest). In a party an enemy that hunts you wears a red
  **"!"**.

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
  | Frost Nova | 25 Aether: a 5 m ring around you, 22 Frost damage + Chill, knocks back; 10 s | trainer L6, 525 g | yes |
  | Flame Wall | a 6 m line of fire across the aim (up to 12 m away) for 4 s; every 0.5 s 8 Fire + Burn to what stands in it; 12 s | trainer L7, 650 g | yes |
  | Ball Lightning | a slow orb (6 m/s, 3 s) along the aim, passes through enemies, stops at walls; every 0.5 s 9 Lightning + Shock to all within 3 m; 9 s | trainer L8, 800 g | yes |
  | Ember Fall | 40 Aether: a meteor on the aim (up to 16 m); a fire ring fills 0.9 s, then 60 Fire, HEAVY stagger and Burn in 3.5 m; 14 s | trainer L9, 1,000 g | yes |

- **Talents** (`Storm`, `Ember`, `Frost`, 24 nodes, PROGRESSION_DESIGN).
- **Look:** its own rig (`elementalist.glb`, modelgen): a steel-blue coat
  with a teal mantle and trim, tall leather boots, a gold circlet, swept-back
  hair, and a rune rod with a gold ring and a glowing Aether crystal in the
  right hand (material slot 2, so a legendary weapon like Cindermaw swaps its
  look). A clip for every spell; Rune Bolt and the aimed spells play on the
  upper body, so casting never roots the legs.

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
- **Chill** (Frost): −45% move/AI speed · 3s. Sources: Fracture Rune, Frost
  Nova; the tank's Glacial Bulwark / Glacier Heart. Frost talents stretch it
  (Cold Snap), root in place (Deep Freeze) or freeze solid (Absolute Zero).
- **Root** (M10): the enemy stands still (no movement, still turns and
  strikes) for its seconds. Sources: Deep Freeze, Absolute Zero.
- **Shock** (Lightning): +20% damage taken · 4s ("Conductive"). Sources:
  Storm Step, Chain Spark. Interaction: Chain Spark gains a 4th jump when it
  touches a Shocked enemy.

### Intended play patterns
- **Runebreaker:** Cleave to build → Earthbreaker the crowd → Runic Guard when
  the pack turns on you; Resonance Burst to finish (phase 2 adds taunt, block
  and pull so the tank holds the enemies' attention).
- **Elementalist:** Rune Bolts from range to build Aether; Storm Step through a
  pack → Chain Spark the Shocked group; Fracture Rune ahead of a chase → kite
  Chilled enemies into it. Frost Nova when a pack reaches you (then Storm Step
  out), Flame Wall across a choke, Ball Lightning down a corridor, Ember Fall
  on a staggered or rooted group.

### Talent unlocks (Runebreaker's Runic Warden branch)
| Ability | Element | Role | Resonance |
|---|---|---|---|
| Runic Guard | — | barrier: absorbs 40 + level for 4 s, 12 s cooldown (Glacial Bulwark chills attackers) | −30 |
| Resonance Burst | Physical | finisher nova, 4 m, 0.7 damage per point spent, heavy stagger | all (≥ 50) |

Learned, they join the loadout pool like any trainer ability.
