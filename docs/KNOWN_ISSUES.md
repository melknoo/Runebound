# Known Issues / Technical Debt

## Feel (needs human playtest)
- Camera sensitivity/zoom defaults unvalidated with a real mouse.
- Ember Lance roots the player for its 0.14s startup — may feel sticky while
  kiting; candidate: allow slow walk during cast.
- Dodge buffered during melee recovery cancels immediately — intended, but
  verify it feels trustworthy rather than twitchy.
- Rusher eye glow too small to read at combat distance; enlarge on next
  Blender pass.
- Player armor reads lighter in-game than the palette spec — kept for
  readability against the dark arena; revisit with the style lock.

## M02 feel questions (for the user's next playtest)
- Storm Step has no i-frames (deliberate: dodge defends, Step attacks) —
  verify that reads as fair.
- Chain Spark is instant with no cast state; may feel weightless — candidate:
  50ms self-hitstop on cast.
- Fracture Rune at max range vs a Chilled chasing enemy may detonate behind
  it; arm time 1.2s is the tuning knob.
- Brute/knight models render lighter than palette spec (same known lighting
  issue as M01).

## M03 feel questions (for the user's next playtest)
- Drop rates are lab-tuned (trash 20%) — may flood the arena in long sessions.
- Inventory doesn't pause combat (ARPG-style); enemies keep attacking while
  the panel is open. Intended, but verify it doesn't feel unfair.
- No "item level"/power progression yet — two Rares of the same affix are
  equal; fine until M04 world progression.
- Discard deletes permanently (no drop-back-to-ground).

## M04 feel questions (for the user's next playtest)
- First camp sits ~13m from the highlands spawn — triggers almost immediately.
  Intentional density, but verify it doesn't feel ambush-y.
- Colossus charge: contact check is distance-based (2m) — verify side-dodges
  feel fair at 14 m/s.
- Camps re-arm on every zone visit (no world-state persistence yet) — farming
  loop by design for now.
- Player death in the highlands respawns at zone entry with full HP; no
  penalty. Fine for now, revisit with difficulty tuning.

## M05 feel questions (for the user's next playtest)
- Vessel P2 hazard ring: 0.8m edge tolerance at RING_EXPAND_TIME 2.6s — is
  the dodge window readable enough in the dark?
- Shadow runes always include one directly under the player — verify it feels
  dodgeable, not cheap, with 4 runes in P2.
- Warden frontal block: does the spark/clink feedback read as "go around"?
- Spire gallery casters on platforms: fair with the camera at range?

## Technical
- Mass spawn of ~26 enemies in one frame spikes ~100ms (stress test only).
  If real encounters spawn waves, stagger spawns or pool enemies.
- `TIME_PHYSICS_PROCESS` monitor readings look implausible (>frame time);
  don't trust it — measure with frame deltas.
- Style A (SubViewport) reparents the world at runtime; positional audio
  listener behavior in that mode is unverified.
- Damage-number Label3D nodes are allocated per hit; pool if profiling ever
  shows churn.
- Burn DoT stacking is "strongest wins, duration refreshes" — placeholder
  until the status-effect system (M02).
- Enemy separation is O(n²) across all enemies (fine ≤~60; grid-bucket it
  beyond that).

## Test debt
- tests/debug_ember.gd / debug_camera.gd are throwaway diagnostics; delete or
  fold into smoke test when convenient.
- Capture run asserts nothing automatically — it relies on eyeball review of
  captures/.
