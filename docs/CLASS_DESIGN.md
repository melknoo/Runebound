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

## Planned (M03+): Runic Guard (barrier, F-alternative), Resonance Burst
(finisher), specializations Storm / Ember / Runic Warden.
