# RUNEBOUND — Class Design: RUNEBREAKER

Armored magical warrior: melee builds **Resonance**, heavy rune abilities
spend it. Rhythm: BUILD → SPEND. Max Resonance 100.

## Current kit (6 base abilities; M07b: learned, not given)
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

## Elemental statuses (StatusEffectComponent)
- **Burn** (Fire): 4 dps · 3s. Source: Ember Lance.
- **Chill** (Frost): −45% move/AI speed · 3s. Source: Fracture Rune.
- **Shock** (Lightning): +20% damage taken · 4s ("Conductive"). Sources:
  Storm Step, Chain Spark. Interaction: Chain Spark gains a 4th jump when it
  touches a Shocked enemy.

## Intended play patterns
- Melee loop: Cleave to build → Earthbreaker crowds.
- Lightning loop: Storm Step through a pack → Chain Spark the Shocked group.
- Control loop: Fracture Rune ahead of a chase → kite Chilled enemies into it.

## M07: specializations and abilities 7-8 (talent unlocks)
The talent tree has three branches, Storm, Ember and Runic Warden
(PROGRESSION_DESIGN.md). The Runic Warden branch unlocks two abilities:

| Key | Ability | Element | Role | Resonance |
|---|---|---|---|---|
| 5 | Runic Guard | — | barrier: absorbs 40 + level for 4 s, 12 s cooldown (Glacial Bulwark chills attackers) | −30 |
| 6 | Resonance Burst | Physical | finisher nova, 4 m, 0.7 damage per point spent, heavy stagger | all (≥ 50) |
