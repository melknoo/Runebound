# RUNEBOUND — Combat Design (M01)

## Timing model
INPUT → ANTICIPATION → EXECUTION → IMPACT → RECOVERY → FEEDBACK
Input buffer 0.22s across all actions; dodge cancels melee recovery and cast
startup (never Earthbreaker's committed slam).

## Current tuning (all in resources/abilities/*.tres + player constants)
| | startup | active | recovery | damage | notes |
|---|---|---|---|---|---|
| Rune Cleave | 0.12 | 0.10 | 0.24 | 24 phys | +12 Resonance/hit, alternating swings, sphere r=1.5 @1.2m |
| Ember Lance | 0.14 | — | — | 18 fire + Burn 4/s·3s | 26 m/s projectile, cd 0.5, +4 Resonance/hit |
| Earthbreaker | 0.38 | 0.12 | 0.30 | 55 phys heavy | costs 40 Resonance, r=4 AoE, hop+slam, cd 4s |
| Storm Step | — | ≤0.12 | 0.08 | 10 lightning + Shock | 50 m/s dash, direction priority: 1) held movement input, 2) Tab target in view → gap-closer landing ~1.3m short, 3) camera aim. ~6m max, hard velocity cut at dash end (no slide). Phases through enemies, zaps path, cd 5s |
| Chain Spark | instant | — | — | 14 lightning + Shock | needs target (Tab or aim-nearest), jump range 6m, 3 jumps / 4 vs Shocked, cd 3s |
| Fracture Rune | 0.1 | 1.2 arm | — | 30 frost + Chill | ground-placed (aim, max 12m), r=3, rune = its own telegraph, cd 6s |
| Dodge | — | 0.24 | 0.08 | — | 15 m/s ease-out, i-frames 0.26s (user-tuned up from 0.22), cd 0.55s |

## Statuses
Burn 4dps·3s (Fire) · Chill −45% speed·3s (Frost) · Shock +20% dmg taken·4s
(Lightning). Owned by StatusEffectComponent per enemy; pips over the target
HP bar. See CLASS_DESIGN.md for interactions.

Movement: 6.8 m/s, accel 60, decel 55 (≈0.11s to full speed), rotation 14 rad/s.

## Resonance
Max 100. Build with melee (+12/hit) and Ember hits (+4); spend 40 on
Earthbreaker. Rhythm: ~3 cleave hits → one slam.

## Hit feedback stack
flash quad + pixel burst + squash tween + knockback + damage number + layered
SFX + 45ms duck-typed hitstop (melee) + camera impulse; Earthbreaker adds
trauma shake 0.55 + ground ring + cracks decal + 70ms hitstop.

## Aim
Center-screen ray (world+enemy). Soft assist: capsule sweep (r=0.8) along the
aim line, extended 8m past terrain hits — enemies near the line beat the
ground. Direct enemy ray hits are exact (no snap).

## Enemies
- Rusher: aggro 16m, 4.3 m/s, windup 0.55s (axe raise + heat glow + sting),
  slow tracking during windup so side-dodges win. 12 dmg.
- Caster: band 7–12m, retreats <7m, windup 0.9s (orb charge), bolt 9 m/s,
  12 dmg, strafes during 1.4s recovery.
- Assassin: 30 HP, 6 m/s, circles at 5m for 1.8s → 9.5 m/s dash-in →
  0.35s telegraphed stab (9 dmg) → 1.6s retreat. Punishes tunnel vision.
- Brute: 140 HP, 2.2 m/s, **stagger-resistant** (HEAVY only), 0.9s telegraphed
  slam r=2.5 (25 dmg heavy + knockback 8), barely tracks during windup.
Hit reactions: LIGHT squash · MEDIUM +0.3s stagger · HEAVY +0.6s stagger;
stagger interrupts wind-ups (telegraph cleanup via _on_interrupted).

## Enemy names (shown on the Tab target plate)
Cinder Marauder (rusher) · Duskweaver (caster) · Veilstalker (assassin) ·
Stonehulk (brute) · Hollow Warden · Ashvein Colossus · Vessel of the
Shattered Rune. Elites prefix their modifier ("Emberbound Cinder Marauder").
Plate colors: cream normal, gold elite, orange boss. Plate/bar height comes
from `EnemyBase.nameplate_height()` (scales with body; Vessel overrides).

## Elites (prototype)
×3 HP, ×1.25 scale, aura light + name label, gold target bar.
- Emberbound: fire patch (r=1.2, 3 dmg/0.5s, 3s) every 2s at its feet.
- Stormtouched: every 6s → 1s yellow disc → shock nova r=4 (10 dmg).
