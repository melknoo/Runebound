# RUNEBOUND — Class Design

## Three roles (planned, M10–M11)
User decisions of 2026-09-29 (ROADMAP "Spieler-Leitlinien"). Each milestone
gets its own plan with the numbers; this section records the direction.

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
  or thrown for 3 s).
- **Sources for the pool:** the class trainer (gold + level, as today),
  quests and bosses, secrets and dungeons (tomes), the talent tree (like
  Runic Guard and Resonance Burst today). M10 starts with the trainer and the
  talent tree; the other sources arrive with M12–M14.
- **Need:** about 12 pool abilities plus a basic attack per class, about 30
  new abilities in total (tank ~9, elementalist ~8 on top of the four spells
  it inherits, druid ~12), each with an icon (ROADMAP "Icon-Quelle").

### Runebreaker, the tank
- **Keeps the melee core:** Rune Cleave (LMB, builds Resonance), Earthbreaker,
  Runic Guard, Resonance Burst. The BUILD → SPEND rhythm stays.
- **New:** a taunt, a block, damage reduction; abilities that make threat.
- **Gives away** the elemental spells (Ember Lance, Chain Spark, Fracture
  Rune, Storm Step) to the elementalist.

### Elementalist, the damage dealer
- Ranged fire, lightning and frost; the statuses Burn, Shock and Chill and
  their interactions move with the spells.
- **Inherits** Ember Lance, Chain Spark, Fracture Rune and Storm Step, plus
  new spells and its own basic attack.

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

## Runebreaker today (until M10)
Armored magical warrior: melee builds **Resonance**, heavy rune abilities
spend it. Rhythm: BUILD → SPEND. Max Resonance 100.

### Current kit (6 base abilities; M07b: learned, not given)
A fresh Runebreaker knows **Rune Cleave and Dodge only**. The other five are
bought from the trainer **Sigrun Runewright** in Runehold for gold, each with
a level requirement (PROGRESSION_DESIGN.md "Gold and the trainer"). Keys are
fixed per ability (number row, applied at runtime by `InputSetup`).

| Key | Ability | Element | Role | Resonance | Learned |
|---|---|---|---|---|---|
| LMB | Rune Cleave | Physical | melee builder, alternating sweeps | +12/hit | start |
| 1 | Earthbreaker | Physical | heavy AoE slam, big stagger | −40 | trainer, L2, 50 g |
| RMB | Ember Lance | Fire | fast projectile + Burn | +4/hit | trainer, L3, 150 g |
| 2 | Storm Step | Lightning | offensive dash through enemies, Shocks path | +5/hit | trainer, L4, 275 g |
| 3 | Chain Spark | Lightning | instant jump-bolt (Tab target), 3 jumps, 4 vs Shocked | +4/hit | trainer, L5, 400 g |
| 4 | Fracture Rune | Frost | ground rune, 1.2s arm, AoE + Chill | +6/hit | trainer, L7, 600 g |
| SPC | Dodge | — | i-frame reposition, cancels recovery | — | always |

Earthbreaker comes first so the class rhythm (BUILD → SPEND) is complete from
level 2. The class itself is data: `resources/classes/runebreaker.tres`
(`ClassData`: abilities in HUD order, starting kit, branch names, rig).

### Elemental statuses (StatusEffectComponent)
- **Burn** (Fire): 4 dps · 3s. Source: Ember Lance.
- **Chill** (Frost): −45% move/AI speed · 3s. Source: Fracture Rune.
- **Shock** (Lightning): +20% damage taken · 4s ("Conductive"). Sources:
  Storm Step, Chain Spark. Interaction: Chain Spark gains a 4th jump when it
  touches a Shocked enemy.

### Intended play patterns
- Melee loop: Cleave to build → Earthbreaker crowds.
- Lightning loop: Storm Step through a pack → Chain Spark the Shocked group.
- Control loop: Fracture Rune ahead of a chase → kite Chilled enemies into it.

### M07: specializations and abilities 7-8 (talent unlocks)
The talent tree has three branches, Storm, Ember and Runic Warden
(PROGRESSION_DESIGN.md). The Runic Warden branch unlocks two abilities:

| Key | Ability | Element | Role | Resonance |
|---|---|---|---|---|
| 5 | Runic Guard | — | barrier: absorbs 40 + level for 4 s, 12 s cooldown (Glacial Bulwark chills attackers) | −30 |
| 6 | Resonance Burst | Physical | finisher nova, 4 m, 0.7 damage per point spent, heavy stagger | all (≥ 50) |
