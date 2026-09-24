# RUNEBOUND — Class Design: RUNEBREAKER

Armored magical warrior: melee builds **Resonance**, heavy rune abilities
spend it. Rhythm: BUILD → SPEND. Max Resonance 100.

## Current kit (M02, 6 abilities)
| Key | Ability | Element | Role | Resonance |
|---|---|---|---|---|
| LMB | Rune Cleave | Physical | melee builder, alternating sweeps | +12/hit |
| RMB | Ember Lance | Fire | fast projectile + Burn | +4/hit |
| Q | Earthbreaker | Physical | heavy AoE slam, big stagger | −40 |
| E | Storm Step | Lightning | offensive dash through enemies, Shocks path | +5/hit |
| R | Chain Spark | Lightning | instant jump-bolt (Tab target), 3 jumps, 4 vs Shocked | +4/hit |
| F | Fracture Rune | Frost | ground rune, 1.2s arm, AoE + Chill | +6/hit |
| SPC | Dodge | — | i-frame reposition, cancels recovery | — |

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
