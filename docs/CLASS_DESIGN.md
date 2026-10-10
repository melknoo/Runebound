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
- **Tome (M12): Lodestone Rune** - a gold rune at the aim (12 m) arms for
  0.5 s, then drags every enemy within 6 m 3 m toward its middle (the heavy
  ones keep their footing), strikes them (12) and taunts them for 2 s; 30
  Resonance, 15 s. Gathers a scattered pack for the party's area spells.
- **Tome (M13, the Hollow Cistern): Breakwater** - a shield charge along the
  aim, 8 m in 0.45 s, taking half damage on the way; every enemy in the
  lane is struck (14), taunted for 3 s and shoved 2.6 m to the side it
  stood on; 20 Resonance, 12 s. The tank's way into a pack that went for
  the healer, without a jump over it.
- **Tome (M13, the Ember Warrens): Forge Brand** - a brand of embers on one
  enemy (the target or the best one in view, 12 m, 8 Fire): for 8 s it
  takes 20 % more damage from every hero and deals 25 % less to everyone;
  15 Resonance, 14 s. Turns the tank's attention into the party's damage.

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

- **Tome (M12): Hoarfrost Fan** - a 60-degree fan of rime 7 m ahead, 20
  Frost and Chill; enemies already Chilled take half again as much and freeze
  in place for 1 s; 20 Aether, 8 s. The third frost spell, the answer to the
  bone field's jackals at close range.
- **Tome (M13, the Hollow Cistern): Rime Ward** - a barrier of 40 + 3 per
  level for 6 s; while it holds, an enemy that strikes the Elementalist in
  melee (within 4 m) is Chilled (6 Frost); 25 Aether, 18 s. The caster's
  answer when the line breaks.
- **Tome (M13, the Ember Warrens): Ember Seed** - a seed planted in one
  enemy (14 m) bursts after 3 s, or at once when its host dies: 30 Fire and
  Burn to every enemy within 3.5 m; 25 Aether, 10 s. Damage over a pack,
  delayed, aimed at one.

### Root druid, the healer (M11)
Plants breaking out of burnt earth, totems, thorns. User decisions of
2026-09-30: 8 pool abilities + LMB now (the rest from M12-M14 sources); the
resource **Sap** is a pool - it starts full, heals spend it, and it refills
(5 a second) **only in a fight** (the hero hits or is hit, or an enemy within
30 m hunts someone), so the druid never out-heals the no-regeneration rule;
**heals threaten a little** (half of what was healed, split over the enemies
already fighting; overheal counts nothing; zones make none). 95 health at
level 1.
- **Heals targeted:** the ally under the crosshair (a green chevron marks
  whom the heal would reach); aiming at no one heals the ally with the least
  health share within 30 m; alone, the druid heals itself.
- **LMB (fixed):** Thorn Volley - three thorns in a small fan (about 20 m),
  held down it keeps throwing.
- **Pool (8):**

  | Ability | Role | Source | Built |
  |---|---|---|---|
  | Mending Bloom | targeted heal 30, 14 Sap, 1 s | start kit | yes |
  | Barkskin | targeted barrier 35 + 2 per level for 6 s, 20 Sap, 8 s | trainer L2, 50 g | yes |
  | Regrowth | targeted heal over time, 40 over 8 s (refreshes), 18 Sap, 4 s | trainer L3, 150 g | yes |
  | Root Grasp | roots at the aim (16 m): 16 damage + Root 2 s in 3 m, 12 Sap, 10 s | trainer L4, 275 g | yes |
  | Renewal Grove | zone at the aim (14 m): 4 health a second in 5 m for 8 s, 35 Sap, 20 s | trainer L5, 400 g | yes |
  | Thornfield | thorns at the aim: 6 damage every 0.5 s + Chill in 4 m for 6 s, 20 Sap, 12 s | trainer L6, 525 g | yes |
  | Totem of Growth | totem at the feet for 12 s: allies in 8 m +15 % damage, heal 3 every 2 s, 30 Sap, 24 s | trainer L7, 650 g | yes |
  | Wild Bloom | every ally in 10 m heals 30 % of their health; enemies in 5 m thrown back and rooted 1 s, 50 Sap, 40 s | trainer L8, 800 g | yes |

- **Talents** (`Growth`, `Thorns`, `Grove`, 24 nodes, PROGRESSION_DESIGN).
- **Legendaries:** Heartwood Idol (the grove roots enemies stepping in),
  Ashbloom Seed (Mending Bloom doubles below 35 %), Thornmother's Crown
  (two more thorns).
- **Tome (M12): Rootwalk** - down into the roots and up to 12 m on in 0.4 s
  (untouchable like a dodge, never through a wall or over a drop); both ends
  bloom: allies within 3 m heal 15 and lose their slows (the first debuffs on
  heroes came with M12); 18 Sap, 12 s. The druid's only movement ability.
- **Tome (M13, the Hollow Cistern): Wellspring** - on the heal target: 25
  at once, its slows washed off, 30 more over 5 s (its own heal over time,
  it stacks with Regrowth); 24 Sap, 9 s. The cleanse the dungeons' chilling
  hazards asked for.
- **Tome (M13, the Ember Warrens): Cinder Ward** - on the heal target for
  10 s: the next blow that would kill it leaves it standing (1 health) and
  the embers heal 40 (scaled like the druid's heals); spent once; 30 Sap,
  45 s. Planned as "Aschenblüte", renamed: Ashbloom Seed is already the
  druid's legendary.
- **Travel no longer heals** (user 2026-09-30, for every class): health (and
  Sap) are kept across zones and in the save; the Runehold hearth heals out
  of combat.

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
