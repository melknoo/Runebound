# Known Issues / Technical Debt

> **Playtest points** (feel, balance, looks) are also in the game: key J opens
> the PLAYTEST log (`resources/playtest/checklist.json`), the user ticks them
> there (passt / Problem + note, saved in user://playtest.json). When a point
> is added or resolved here, update the checklist too (keep ids stable).

## Probably resolved: client crash after zone travel (reported 2026-10-02, retested 2026-10-09)
- **Symptom:** a client on a second PC (NVIDIA GeForce RTX 2070, Windows,
  Vulkan 1.4 Forward+, **Godot 4.6.1**) joined the laptop server, travelled
  from Runehold into the Ashen Highlands, went to a black screen and exited
  with signal 11 5-10 s after arriving; a second run died ~55 s after joining
  while standing still. The Godot backtrace has no symbols ("no debug info in
  PE/COFF executable").
- **The server side is clean:** the journal shows the zone loaded, the hero
  spawned, then the client simply left; ticks stayed normal. So the crash is
  client-side.
- **Cause (Windows Event Viewer, 2026-10-09):** at the crash time the System
  log has 21 `nvlddmkm` events 153 "Restarting TDR occurred" within 35 s: the
  GPU hung for over 2 s and Windows reset the driver. In the same second
  **two** Godot 4.6.1 processes crashed with 0xc0000005, one in
  `nvoglv64.dll` (NVIDIA's Vulkan driver), one in `nvwgf2umx.dll`. The game
  had been started from the Godot editor with its game embedded ("Embedded
  window only supports Windowed mode" in the log), so editor and game were
  two Vulkan processes on one GPU - the same family as the iGPU's "Vulkan
  device was lost" (Technical, below). Not the game's code.
- **Retest 2026-10-09 on that PC** (Godot 4.6.3, fresh `.godot/`, driver
  591.86, game started standalone, no editor): smoke 690 green; three
  windowed `worldcapture` runs (Runehold -> Highlands -> Spire through the
  real `travel_to`), the 43 `m12_highlands` shots and `perf highlands_vista`
  (median 235 FPS, GPU 1.2 ms, 573 draw calls) all ended cleanly with no new
  `nvlddmkm` event and no crash. The first perf round had one 147 ms hitch
  (105 pipeline compiles, CPU side).
- **Left:** the user's own online run on that PC (`run_godot coop`, then the
  laptop server), started standalone (J list point `c_second_pc`). If a TDR comes back: the same run with
  `--rendering-driver d3d12`, a `--verbose` log, then the zone warm-up
  (`VFX.warm_up`, the scatter MultiMeshes, the biome texture arrays during the
  0.35 s fade).

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
- ~~Drop rates are lab-tuned (trash 20%)~~ — retuned 2026-09-28 after the
  user's M08 notes (docs/ITEMIZATION.md).
- Inventory doesn't pause combat (ARPG-style); enemies keep attacking while
  the panel is open. Intended, but verify it doesn't feel unfair.
- No "item level"/power progression yet — two Rares of the same affix are
  equal; fine until M04 world progression.
- Discard deletes permanently (no drop-back-to-ground).

## M04 feel questions (for the user's next playtest)
- First camp sits ~13m from the highlands spawn — triggers almost immediately.
  Intentional density, but verify it doesn't feel ambush-y.
- ~~Colossus charge: contact check is distance-based (2m)~~ — since the M08
  notes (2026-09-28) it hits inside its drawn lane only (half width 1.5 m +
  0.2), and the lane stays on the ground for the whole run.
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
- Resolved 2026-10-01 (M17a): Esc closes an open window first, else opens
  the Esc menu (PauseMenu sits before the windows in the tree); the hero no
  longer toggles the cursor, and windows close on Esc even while the F1
  panel shows.
- While the F1 overlay shows, C / L / 0 belong to it (reset cooldowns, learn
  all, +500 gold); the hero window ignores keys until it closes. The overlay
  comments used to say F3; the key is F1.
- Resonance fills with nothing to spend on until Earthbreaker (level 2); the
  cost tick is hidden until then and Sigrun's toast points to the hub.
- Sigrun borrows the Runebreaker rig (bronze tint); a real NPC model and her
  story come with M14.

## M08 open items (played by the user; the notes were built 2026-09-28, see below)
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
  stuck enemies and long chases. A navmesh is an M12 candidate (the Highlands
  with substance) if pads and passes are not enough.
- The map shows what the character has seen (no fog-of-war layer). M13:
  the east gate leads into the Hollow Cistern; the Ember Warrens' gate stays
  sealed until they are built.
- Portal labels of the two arena gates overlap from a distance (the gates
  are 8 m apart). The boss bar hides the compass; that is intended.
- Camp clear time is wall-clock (`Time.get_unix_time_from_system`): a clock
  set back only delays a respawn, never spawns one on top of anyone.
- Debug overlay keys (F1) unchanged; M is the map. F, G, H, T, Z, X, B, P
  stay free.

## M08 notes follow-up (built 2026-09-28, needs the user's playtest)
- Enemies no longer turn during a wind-up: stepping out of a marker always
  works now. If fights feel too easy, lengthen or shrink markers rather
  than bringing back tracking.
- Sprint x1.45 and the 3 s combat lock are first guesses.
- Only the Highlands have a map; Runehold's travel panel shows the list only.
- The new drop rates may feel stingy in the arena; tune in `ItemGenerator`.

## M09 open items (needs the user's playtest)
- Numbers to feel in play: party countdown 5 s, reward radius 60 m, chest
  purse radius 12 m, enemy health +70 % per extra hero, hurt margin 1.2 m.
- Remote heroes: split-lance shards and the Glacier Heart frost field are
  not mirrored (their damage is; only the look is missing on the others'
  screens); equipment looks (Cindermaw's molten blade) are not either.
- The Vessel's expanding ring hits by band, not by sphere: a forwarded ring
  hit carries no area, so only i-frames refuse it on the owner's side.
- Free chests reset with the server's session (like singleplayer, not
  saved); since M13 dungeon, puzzle and grotto chests open once per world.
- Party travel is one-way per request: walking back through the gate right
  after arriving starts a new countdown for everybody.
- A server killed hard (power, crash) is noticed by clients only after the
  ENet timeout (15-30 s); a normal stop disconnects everyone at once.
- ENet can drop up to ~1 s of unreliable packets right after a zone build
  (throttle recovering); harmless for snapshots, the join state is reliable.
- The work network reaches the laptop only through Tailscale's DERP relay
  (Frankfurt, pings 40-208 ms); home connections are expected to go direct.
- The laptop server shows single tick spikes up to ~60 ms under full load
  (p95 stays near 10 ms); watch the journal's minute lines in real sessions.

## M17a open items (menus & settings, built 2026-10-01, needs the user's playtest)
- The title scene (campfire at night) is a first composition: camera
  framing, how dark the night reads, the fire's strength and the music
  (Runehold's track) want the user's eye.
- Freeing an outlined rig together with its materials made the renderer log
  "material is null" (seen when the title swaps the hero's rig; HeroPreview
  now drops the materials first). Check whether enemy deaths in a windowed
  run log the same.
- Settings: window size presets only apply in windowed mode; the UI does not
  scale with the window (fixed pixel font sizes), so very large windows show
  a small HUD.

## M11 open items (built, needs the user's playtest)
- **Travel no longer heals** (every class): health carries across zones and
  in the save; only death, draughts, heals and the Runehold hearth refill
  it. Watch whether a hurt return to Runehold feels right, and whether the
  hearth (10 %/s within 6 m, out of combat) is easy to find.
- Druid numbers to feel: Sap 100, 5 a second in a fight; Mending Bloom 30
  for 14 Sap; Barkskin 35 + 2 per level; Regrowth 40 over 8 s; Thorn Volley
  3 x 5 damage every 0.45 s; Renewal Grove 4 a second; Totem +15 %; Wild
  Bloom 30 % for 50 Sap. The druid bot beats every Highlands camp and the
  Colossus alone at level 4 and 6 (0 deaths, it heals itself).
- The heal target prefers the crosshair: an ally counts within 1.2 m of the
  aim ray. Check it picks the one you mean in a crowded fight, and that the
  green chevron is enough (no "heal on me" key yet).
- Thornfield slows with Chill (-45 %), the frost status; a thorn-own slow
  would need a new status in the net codec.
- Heals from zones (grove, totem pulses) make no threat; the targeted heals
  do (half the healed amount).
- Barkskin shows the barrier's teal ring (the barrier is shared with Runic
  Guard); a bark look of its own may come later.
- The solo-check tank now dies at the Colossus about one run in three (6-19 %
  left, 420-550 damage over the Highlands at L6). The same check on the
  build before M11 did the same (430 / 547): it is the bots' variance with
  rolled gear, not a change of M11. Still a hint that the tank alone is
  thin at the Colossus without draughts (the solo check drinks none).
- Not measured: a perf A/B for M11 (the new effects are small meshes and
  CPU particles; the lab run was not repeated).

## M10 open items (phases 1-4 built, needs the user's playtest)
- **No healing between fights yet (superseded: draughts M10b, druid M11, food M12):** a hero's health comes back only by
  dying (shrine respawn) or changing zones. In the solo check (bots, level
  4-6, rolled gear) the tank takes about 2.4 health bars over every
  Highlands camp plus the Colossus, the Elementalist about 0.7 (a kiting bot
  is rarely reached); alone, a tank would die about twice on the way.
  **Decided (user, 2026-09-30): no regeneration out of combat** (waiting
  for full health would answer every fight). Healing between fights comes
  from **consumables**: M10b built the Healing Draught (35 % over 4 s, 5 in
  the bag, drops + chests + Ylva for 30 gold); food came with M12 (the Ember Tuber).
- M10b numbers to feel: draught drop chances (5 / 15 / 30 %, bosses 2,
  chests 60 %), the price (30 gold), 35 % over 4 s, the cap of 5. Drinking
  only from the inventory is slow on purpose (the user's choice) - in a
  fight the window stays open while enemies keep swinging.
- **The Colossus may be too easy now:** one bot beats it in 13-19 s at
  level 4-6 (696 health at L3; enemy damage does not scale with level yet).
- The solo-check bots never read telegraphs (they dodge at random): their
  numbers are a floor and a class comparison, not a player's result.
- The Elementalist's rig (phase 3) has been reviewed on contact sheets only;
  the user's look preview is pending.
- Casting on the move keeps the hero facing its aim for 0.45 s; a backwards
  strafe plays the forward run clip (neither rig has a backwards run).
- Numbers to feel: Rune Bolt 10 damage every 0.3 s (+3 Aether a hit), the
  Elementalist's 85 health, the trainer prices (Ember Lance L2 50 g ...
  Ember Fall L9 1,000 g).
- Elementalist numbers to feel (phase 3): Frost Nova 25 Aether / 5 m / 10 s,
  Flame Wall 8 per 0.5 s for 4 s, Ball Lightning 9 per 0.5 s for 3 s at
  6 m/s, Ember Fall 40 Aether / 60 damage / 0.9 s fall / 14 s. Deep Freeze
  roots 1 s, Absolute Zero 2 s; a rooted enemy still strikes what is in
  reach.
- Flame Wall and Ember Fall land at the camera's aim point, clamped to their
  reach (12 m / 16 m); aimed at the sky they fall at the reach in the aim
  direction.
- Ball Lightning stops at the first wall on its path and crackles there
  until it fades.
- Tank numbers to feel (phase 2): block -75 % in a 70-degree frontal arc,
  parry window 0.3 s, Rune Challenge 4 s taunt / 12 s cooldown, threat x2,
  120 health, Warden's Leap 10 m / Rune Chain 16 m. A parry counters a
  caster at any range (its bolt's shooter) - intended as a reward, check it
  doesn't feel odd.
- Warden's Leap flies over enemies (no collision in the air) and lands at
  the camera's aim point; on a cliff edge it lands where the ground is.
- Rune Chain only pulls enemies that are not stagger-resistant (brutes,
  wardens and bosses are taunted, not moved).
- The aggro "!" shows only with two or more heroes in the zone.
- Perf and stress now fight as the Elementalist: full-combat numbers from
  before M10 are not comparable (the rotation changed).
- Headless only: swapping the hero's class in tests logs "Parameter
  material is null" from the dummy renderer when the old rig is freed
  (cosmetic, like the lab's initial wave).

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
- tests/debug_camera.gd is a throwaway diagnostic; delete or fold into the
  smoke test when convenient (debug_ember went with M10).
- Capture run asserts nothing automatically — it relies on eyeball review of
  captures/.

## M13 open items (in progress)
- **Phase 0 is a greybox:** the Cistern's camps are raiders and wardens,
  the walls and floors wear the Spire's materials, the lights are bare
  omnis; water, puzzles, the Drowned, the bosses and the look come in
  phases 2-5. Gates (`gate` doors) without inputs stand open until the
  puzzle kit wires them; the secret wall and the shortcut are solid plugs.
  Both arenas field the placeholder "Arena Warden" (one slam).
- Element charges are personal and local: a druid charged with fire lights
  a kiln, but the charge does not change its hits on enemies (puzzles
  only, by design for now). The Elementalist needs a fire / frost /
  lightning spell slotted to skip the sources.
- Trap numbers to feel: blades 14 per hit, 5 strips over 3 s; the
  collapsing floor's rows down 1.5 s of every 4 s (even, then odd).
- Boss reset: 6 s with nobody alive in the room. A hero who kites the boss
  to a door and steps out resets it too - by design for now.
- **Protocol 14:** ship a release before the next co-op session.
- The gate labels are built once: a language switch shows on the next zone
  load.

## M12 open items
- **Forest balance:** the Runebreaker solo-check bot (no healing between
  fights, no draughts) dies at ruin 3 after clearing everything before it;
  final L6 check over 16 fights: Runebreaker 13-14, Druid 15 (ruin 3 runs out of time), Elementalist 16. Tune the cinderbark slam
  (24) or the wisps after the user's playtest.
- **Cinderbark readability:** standing as a tree it is meant to be missed;
  whether its ember tell is enough to spot it is a playtest question.
- **No navmesh:** the cinderbark walks straight; the forest keeps 14 m
  clearings around combat pads.
- **The carrion brood may be too easy:** in the solo check camp 7 cost each
  class only 14-28 damage (the jackals' leap is telegraphed and short, the
  vulture strikes once per dive). Tune after the playtest (bite 9, dive 14,
  the pack gap 0.9 s).
- **Draw calls in wide views:** `highlands_vista` went from 373 to 575 draw
  calls with M12 (66 instead of 70 FPS on the iGPU). Candidates if it
  matters: more repeated props as MultiMesh, a shorter visibility range for
  small dressing.
- **Trials and nests want a playtest:** a trial's time (70-75 s for two
  waves) and its 4 allowed hits, the nests' eight brood each (XP per
  brood), the graveyard's risen (one every 6 s, up to three) are first
  numbers.
- **Net suite under load:** the full suite starts many headless Godot
  processes in a row; on a busy PC scenarios fail for lack of time or memory
  (`travel`: the 5 s countdown runs out before a client handles it; at the
  M12 wrap-up `heal`, `handshake@ws` and `travel@ws` crashed "Out of memory"
  with 1 GB of 32 free). They pass on their own; a failing run's logs are
  kept in `net_test/failed/<scenario>/`.
