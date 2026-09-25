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

## Fixed in M06 (Step 0b, user-approved gameplay fixes)
- Dodge during Storm Step skipped the dash's end: collision mask stayed 0b001
  (player phased through enemies) and the path zap was lost. The dash now
  resolves on a dodge cancel (`Player._resolve_storm_step`).
- Debug style A (V) reparents the world; enemies dropped out of
  `EnemyBase.all_enemies` (Tab targeting, Chain Spark jumps, separation broke
  until reload). Registration moved to `_enter_tree`.
- Spire gallery ramp rose away from its platform (unreachable); rebuilt along
  +X onto the east platform's west edge (~19 deg). Vessel blink anchors (r 7
  circle) left the 10.75 m-deep chamber; now an ellipse (7 x 3.5) inside it.

## M06 open items (after Phase C)
- Style Gate and §71 gate verdicts are the user's, on the captures and in
  the final playtest. Implementer notes to look at:
  - The Spire's darkness needs judging in motion.
  - Runehold's cloud cover may still be busy.
- The Veilstalker's strafe and retreat loops play at a fixed rate (not
  speed-matched like run). They look right at the design speeds only.
- Legendary looks: only Cindermaw shows on the hero. Conductor's Oath and
  Glacier Heart have unique drop models and icons; visible armor and relics
  on the character are M07+.
- Warm-up enemies (frozen, under the floor, freed after 0.3 s) register in
  `EnemyBase.all_enemies` meanwhile. They are IDLE, so music and targeting
  ignore them, but a Tab press in the first 0.3 s of a zone could cycle
  onto one.
- Headless exit logs "N resources still in use" for audio streams still
  playing when the smoke test quits (zone music, ambience). Cosmetic.
- First fight of a session: 1–2 hitches of 50–140 ms; later fights stay
  under 25–50 ms worst frame. `perf_probe` now attributes spikes (fight step,
  GPU / render CPU / script time, pipeline compiles; `--prefire=` bisects).
  - The first Chain Spark compiles about 6 pipelines (Forward+ variants
    drawn for the first time; the Intel driver compiles synchronously).
  - The first Storm Step end shows up to ~100 ms of physics-side main-thread
    time, with no compiles. Intermittent, cause not isolated.
  - Already fixed (they were the bigger part):
    - CPU bursts, so no particle process shaders compile
    - a warm-up drawn inside the view frustum (VFX, bolt, an omni light,
      the rigged enemy types)
    - hit flash and telegraph glow change energy only
    - rig scenes kept loaded
  - Next idea: a short black load hold that renders a scripted fight burst
    before the zone fades in.
- Music: Highlands, Runehold and Spire each have explore and combat
  layers; bosses use their zone's combat layer and a victory stinger. None
  of it has been heard by a human yet. Mix levels are start values, to be
  set at the listening checkpoint.
- Camp tents are deferred: M06 adds no collision and a tent you can walk
  through breaks the rule — the M08 open zone gets POIs with collision.
- Headless only: freeing the lab's initial-wave Marauders while alive and
  animating (debug `reset_lab`, style-A reparent) logs `Parameter "material"
  is null` from the dummy renderer once per enemy. Normal deaths (animator
  stops, 0.22 s tween, then free) and freshly spawned rigs don't trigger it;
  the M05 model doesn't either. Cosmetic log line, cause not isolated yet.
- Test note: Highlands camp 1 triggers the moment the player lands at spawn
  (exactly 13.0 m = its radius, M04 design); the smoke test now checks that
  no far camp wakes up instead of relying on the airborne frames.

## M07 open items (implementer proposal, needs the user's playtest)
- With the F3 debug overlay open, number keys 1–6 both trigger their debug
  action (spawn, kill all ...) and cast their ability (debug keys are only
  active while the overlay shows).
- Seven slots mean more affixes in total, so the hero gets stronger than
  with three. Affix values are unchanged and need a balance pass in
  playtests.
- The XP curve, the XP values, the level cap and all 24 talents are start
  values.
- Enemy levels raise health only (+8 %/level). Damage scaling is an open
  design question.
- Tab targeting can't be used while the talent panel is open (input
  locked), like the inventory.

## M07b open items (needs the user's playtest)
- Learn order and prices (Earthbreaker L2 / 50 g first) are proposals. The
  v2 migration refunds the reached abilities as gold instead of granting
  them (user feedback 2026-09-24).
- Fixed 2026-09-24 after the first playtest: debug `[9]` kept abilities and
  gold; `reset` was undone by a still-running game (the script now refuses
  while the game runs); Jacquard titles were unreadable (Pixelify 40 px
  everywhere, `UiTheme.TITLE`); every window has an X button now.
- Fixed 2026-09-24 (second pass): Pixelify's digits are off its pixel grid
  and rasterized 2 as 3, 5 as S. The UI font is now Runebound Pixel
  (Pixelify letters + grid-exact 5x7 digits, `tools/fontgen/numerals.py`).
- Fracture Rune now goes through the player's hit roll (gear %, crit, talent
  multipliers): a small buff to check in play.
- Esc: HeroUI / TrainerUI consume `toggle_cursor` first (later-added nodes
  get `_unhandled_input` first); if the cursor still toggles under an open
  window, make Player skip the toggle while `input_locked`.
- While the F1 overlay shows, C / L / 0 belong to it (reset cooldowns, learn
  all, +500 gold); the hero window ignores keys until it closes. The overlay
  comments used to say F3; the key is F1.
- Resonance fills with nothing to spend on until Earthbreaker (level 2); the
  cost tick is hidden until then and Sigrun's toast points to the hub.
- Sigrun borrows the Runebreaker rig (bronze tint); a real NPC model and her
  story come with M11.

## M08 open items (played by the user; notes follow after M09)
- The user played M08 and has a few small notes; they are scheduled right
  after M09 (2026-09-25) and get listed here when they arrive.
- Camp respawn is 10 minutes (`respawn_min` per POI, default in
  EncounterSpawner), the re-arm radius 45 m, the leash 26 m (ambush 30,
  patrol 40): start values.
- Camp density and compositions (8 camps, 2 ambushes, 1 patrol) and the
  level bands (south 1 / middle 2 / north 3) are the first proposal; the
  route grades (24 deg) and the rim height too.
- The rim mountains are smooth heightmap slopes with basalt sides; from the
  plateau they read as a wall. Candidates: more ridge rocks on the rim,
  heavier haze, a second rock texture band.
- Telegraph discs tilt with the ground; on steep slopes off the pads the
  disc and the actual hit volume (a flat radius) can disagree at the edge.
  Every combat POI sits on a flat pad, so this only shows in chases.
- Storm Step keeps `velocity.y = 0`: over a crest the dash flies level and
  drops after; Earthbreaker's jump works on slopes.
- No navmesh: enemies steer straight; the leash (return home + heal) covers
  stuck enemies and long chases. A navmesh is the M10 candidate if pads and
  passes are not enough.
- The map shows what the character has seen (no fog-of-war layer); the two
  sealed gates are placeholders until M10/M11 give them dungeons.
- Portal labels of the two arena gates overlap from a distance (the gates
  are 8 m apart). The boss bar hides the compass; that is intended.
- Camp clear time is wall-clock (`Time.get_unix_time_from_system`): a clock
  set back only delays a respawn, never spawns one on top of anyone.
- Debug overlay keys (F1) unchanged; M is the map. F, G, H, T, Z, X, B, P
  stay free.

## M09 open items (co-op in progress)
- Co-op clients cannot travel yet (portals and shrines say so); party travel
  with the countdown comes in phase 5.
- A client sees no enemies yet (phase 3 replicates them); chests still open
  locally on a client (personal loot, phase 4 makes them server-side).
- Zone discovery XP uses world flags: in co-op a client gets it again each
  session until save v5 moves it into the character (phase 4).
- ENet can drop up to ~1 s of unreliable packets right after a zone build
  (throttle recovering); harmless for snapshots, the join state is reliable.
- The work network reaches the laptop only through Tailscale's DERP relay
  (Frankfurt, pings 40-208 ms); home connections are expected to go direct.

## Technical
- Two game instances at once on the dev iGPU crashed the one in the
  background with "Vulkan device was lost" (Windows GPU resets,
  LiveKernelEvent, 2026-09-23). Play and measure with one instance; the
  Godot editor alone is fine. `run_godot.ps1` warns when another game is
  running.
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
- Smoke tests that watch `_process` effects (pickups, camera yaw) must wait
  on `process_frame`: several physics steps can pass in one slow headless
  frame without an idle frame in between.
- `Node.add_child` without `force_readable_name` names duplicates
  `@Blocker@12`; tests that count nodes by name prefix need
  `add_child(node, true)`.

## Test debt
- tests/debug_ember.gd / debug_camera.gd are throwaway diagnostics; delete or
  fold into smoke test when convenient.
- Capture run asserts nothing automatically — it relies on eyeball review of
  captures/.
