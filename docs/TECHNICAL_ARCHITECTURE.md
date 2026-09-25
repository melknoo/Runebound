# RUNEBOUND — Technical Architecture

Godot 4.6.3 stable, typed GDScript, Forward+. Physics 60 Hz.

## Decisions
- **Code-built scenes for M01.** Player, enemies, VFX and UI construct their
  node trees in `_ready()`. Rationale: the combat lab iterates on behavior and
  tuning, not art layout; hand-written .tscn files were the main friction in
  autonomous iteration. Revisit when real 3D assets replace primitive meshes.
- **No NavigationAgent yet.** Arena is open; enemies steer directly at the
  player via `move_and_slide`. Add navmesh when levels gain real layouts.
- **Hitstop is duck-typed** (`apply_hitstop(duration)` on Player/EnemyBase):
  entities freeze their own `_physics_process` without leaving the physics
  space. `process_mode = DISABLED` broke SpringArm raycasts (body removed
  from space) — do not go back to it.
- **Projectiles position BEFORE `add_child`.** Spawning at origin for one
  frame overlaps the arena floor and self-detonates.
- **Autoloads:** `GameFeel` (hitstop, camera feedback, damage numbers),
  `Sfx` (pooled positional audio, auto-scanned variant library).
  `VFX` is a static class, not an autoload.
- Tests are **scenes**, not `--script` MainLoops — autoloads only exist in
  scene runs.

## World & persistence (M04)
- **ZoneBase** (`scripts/world/zone_base.gd`) owns all bootstrap; zones
  (CombatLab, HubZone, AshenHighlands) override `_build_zone()`,
  `_environment_colors()`, `_player_spawn_point()`. World objects (Portal,
  EncounterSpawner, TreasureChest) find their zone via
  `get_tree().current_scene as ZoneBase`.
- **SaveGame** autoload: versioned JSON, `save_path` var (tests point it at a
  scratch file — never let tests touch the real save), debounced writes,
  `restore_player()` called by ZoneBase after spawn. Gear survives zone travel
  because `travel_to()` saves synchronously before `change_scene_to_file`.
- Ambient loops: WAVs are made loopable (tail-into-head crossfade in sfxgen)
  and get `AudioStreamWAV.loop_mode = LOOP_FORWARD` set at runtime on a
  duplicate of the imported stream.

## Look pipeline (M06)
- `assets/art_spec.json` is the single source of look parameters (sRGB
  palettes, color roles, texel densities, outline, emissive caps, marker
  heights, shadows); Python generators and ArtKit read it.
- Blender helpers in `tools/modelgen/lib/rig.py`: rigid-skinned parts, box UVs
  at a fixed texel density, 60 fps actions (slotted-action safe), GLB export
  without images. sRGB→linear happens before values reach Blender.
- `LookDev` (static registry) exposes switchable look variants to shot lists,
  perf A/B and the debug overlay (O = outline). Start values from the
  command line: `-- --look=<key>:<value>`.
- `ArtKit` hands out materials by role: terrain (world-mapped pixel shader),
  character bodies (baked 64 px/m atlas, toon, rim, stencil outline), props
  (32 px/m atlas, no outline), glow parts (unshaded, fog-exempt).
- `CharacterAnimator` plays rig clips from the owner's existing state
  (`Player.action_started`, `EnemyBase.state_entered`): manual advance,
  hitstop freeze, speed-matched locomotion, animation LOD. Enemies drive
  their AnimationPlayer directly. The player's "layered" profile builds an
  AnimationTree:
  - `base` is a Transition over idle / run (time-scaled) / full-body
    one-shots;
  - `upper` is a OneShot filtered to the upper-body bones (Chain Spark,
    Fracture Rune play over running legs);
  - `flinch` is a OneShot in ADD mode.
  A finished-looking one-shot is handed to locomotion once the owner is free
  (`free` callable) and moving, after a 0.1 s commit.
- Environment kit:
  - `SetPieces` builds POIs (bonfire, raider camp, collider wrapping). It
    matches prop surfaces by material name: `_glow` gets the emissive
    material, `_cloth` gets `ArtKit.sway_material`.
  - `Scatter.populate(zone, rules)` places items in bands around the
    obstacle footprints from `ZoneBase.scatter_obstacles()`.
    - Output is one MultiMeshInstance3D per item and 16 m chunk under
      `world/Dressing`.
    - Each chunk also stores its world positions as meta, because the
      headless renderer keeps no MultiMesh buffers.
- Settlement and interior builders (Phase C), all static in `SetPieces`, all
  wrapping existing colliders without adding any:
  - `masonry_wall(body, role, pier_every, end_piers)` swaps the box to a
    terrain role and adds one merged mesh (cap course plus piers). It
    returns the pier offsets, so banners and arches go between them.
  - `hut(body, roof, wall_role, roof_role, door_back)` builds a sod gable
    around the roof slab (`gable_mesh`) and adds the trim prop.
  - `hearth(zone, pos, stones, logs)` and `wall_banner(zone, face, inward)`.
  - Kit props live in `assets/models/env/<kit>/` (highlands, runehold,
    spire, common). `prop_path()` searches the kits. A prop part with its
    own baked atlas (e.g. `treasure_chest_lid`) gets that atlas;
    `glow_object()` in the generator exports animated emissive nodes
    (`flames`, `orbit`).
- `terrain_pixel` extras are shader-side and cost nothing when unused:
  - Paving: `paved_circles` / `paved_paths`, set via `ArtKit.paved`.
  - Rune inlays: `rune_lines`, set via `ArtKit.inlaid`.
  - Each top layer samples at its own tile size (`textureSize`).
- ZoneLook presets: `ZoneLook.runehold()` (hub and lab) and
  `ZoneLook.spire_interior()`. `interior = true` builds a colour background
  and one cold top light with shadows; the rim is skipped at energy 0.
  - GDScript gotcha: a static func must not share a name with an exported
    property (`spire` vs `spire_interior`); the class then fails to parse
    everywhere.
- Enemy rigs (all types) go through `EnemyBase._setup_rigged_visual`.
  - Pivot tweens the clips replace run on invisible stand-ins
    (`ArmsPivotStandIn`, `BladePivotStandIn`).
  - Code-owned surfaces (the Colossus' veins on slot 2) keep emission on and
    ramp energy only.
  - `ZoneBase.make_enemy(id)` is the one factory (spawn, warm-up, shot
    runner).
  - Zones list the types they warm up in `_warm_up_ids()`.
- CharacterAnimator state entries:
  - `"~clip"` loops a clip for as long as the state lasts (strafe, dash,
    retreat, charge, stun, p2_idle). A running one-shot plays out first.
  - A Callable picks the clip (the Colossus' WINDUP is either a slam or a
    charge).
  - `rate` is a Callable that scales a one-shot's playback (the enraged
    slam).
  - Zones and enemies may call `play_one_shot` for presentation beats
    (roar, shatter, fan).
- `MusicDirector.stinger(key)` plays `assets/music/stinger_<key>.wav` once
  over the ducked zone music (boss deaths).
- Clip authoring (`tools/modelgen/`): poses are FK Euler dicts plus intents
  (`_reach.R`, `_blade.R`, see `lib/pose.py`). Every key is a full pose over
  the stance. `--sheets` renders contact sheets for review.
- VFX (`scripts/systems/vfx.gd`, static):
  - `telegraph_disc` / `telegraph_lane` draw enemy danger with
    `threat_marker.gdshader` and tween its `progress`.
  - `player_ring` / `ground_ring` draw dashed player marks and shockwaves
    with `player_ring.gdshader`.
  - `burst()` uses CPUParticles3D; GPU bursts stay behind LookDev
    `vfx_cpu` for A/B.
  - Quads, arc meshes and materials are cached, and cleared in
    `GameFeel._exit_tree`.
  - `VFX.warm_up(root, spot)` draws every effect once. `spot` must be inside
    the view frustum: culled draws compile nothing.
- Audio:
  - The `Sfx` autoload creates the buses at runtime (no
    `default_bus_layout`, no `project.godot` change) and routes by key
    (`Sfx.bus_for`).
  - It also hosts `MusicDirector` (`MusicDirector.instance`).
  - Zones return a music key from `_zone_music()`; ZoneBase starts it on
    ready and fades it on travel.
  - Looping WAVs are looped by their `.import` (`edit/loop_mode=2`), never
    at runtime.
- UI: `UiTheme` (static) builds the Theme.
  - Fonts get pixel rendering set on the FontFile at runtime; the same
    options in the `.import` file crash Godot 4.6.3's headless font
    reimport.
  - `UiTheme.apply(root)` is used on the HUD, tooltip and inventory roots.
  - `UiTheme.label3d()` sets up world labels (fixed_size, `pixel_size` from
    the camera FOV and viewport height).
  - The UI kit comes from `tools/texgen/ui.py`.
- Materials that effects light up (hit flash, axe telegraph) keep emission
  enabled at energy 0 (`ArtKit.KEEP_EMISSION`). Toggling `emission_enabled`
  compiles a new shader variant on first use.

## Progression (M07)
- `Progression` (child of Player) holds level, XP and talent ranks and
  caches the stat and power totals.
  - `Player.stat(key)` = `Equipment.stat` + `Progression.stat`.
  - `Player.has_power(id)` checks both, so a legendary can grant a
    talent's behavior.
  - Every ability hook (and `EmberLanceProjectile`) reads through these.
- Talents are `TalentData` resources (`resources/talents/`, generated from
  one table by `tools/talents/generate_talents.py`).
  - A talent is either a numeric stat (`stat` + `per_rank`) or a behavior
    (`power`, checked in the ability code).
  - `Progression.tree()` loads them once.
- Player hits carry `HitInfo.from_player`, `ability` and `burn_mult`. The
  conditional talent damage is applied in `EnemyBase.take_hit` via
  `Player.talent_damage_mult` (Shocked, Burning, Ember Lance).
- The barrier (`Player.grant_barrier`) absorbs damage before health in
  `Player.take_hit`. Unbroken triggers there while the dodge's i-frames
  are on.
- XP awards live in `ZoneBase._on_enemy_died`, `EncounterSpawner` (camp
  clear), `TreasureChest.open` and `ZoneBase._discover` (first visit,
  flag `discovered_<scene>`).
- Levels: zones map areas in `_enemy_level(enemy, pos)` (applied in
  `_spawn_enemy` before `_ready`, which scales health), and
  `ItemGenerator.apply_item_level` scales drops.
- `InputSetup.ensure()` adds the M07 input actions at runtime (N, G, H),
  so `project.godot` stays untouched.
- SaveGame v2: `SaveGame.migrate()` upgrades v1 saves.

## Multi-class / multi-player seams (M07b)
The game stays single-player today; these seams make a second class a data
addition and later co-op (server authority, ENet, headless Linux server) a
matter of adding replication rather than untangling. Rule: **the
Runebreaker's behavior stays where it is; only the lists and identities other
systems read became data or registries.**
- `ClassData` (`resources/classes/*.tres`): abilities in HUD order, starting
  kit, talent branch names, rig, material, resource label/cap. ZoneBase sets
  `player.class_data` before `add_child` from `SaveGame.active_class_id()`;
  a bare `Player.new()` falls back to the default class.
- **One ability id space:** internal keys equal `AbilityData.id`
  (`rune_cleave`, `ember_lance`, ...); icons are `assets/ui/icons/<id>.png`.
  `AbilityData.input_action` names the key, `unlock` (START / TRAINER /
  TALENT) plus `learn_level` / `learn_price` / `unlock_power` how it is known.
- `Player.knows(id)` is the single gate (dodge always; TALENT via
  `has_power(unlock_power)`; else `known_abilities`). `_try_or_buffer` never
  buffers an unknown action. `_register_actions()` maps ids to `try_*`
  Callables (no dispatch `match`); `cooldown_fraction` reads the data.
  Class 2 = `extends Player`, overriding `_register_actions`,
  `_load_abilities`, `_anim_profile`; the Runebreaker's `try_*` then move
  into `runebreaker.gd` mechanically. Not before a second class exists.
- **Input seam:** `PlayerIntent` (move_dir, pressed) is filled once per
  physics tick by an `InputSource` (`LocalInputSource` = keyboard/mouse
  through the camera basis; tests script one; a peer will send one). Player
  reads only the intent; the input buffer sits behind it.
- **Attacker identity:** `HitInfo.attacker_id` (instance id, not a
  reference: statuses and Wildfire resolve later and an int serializes).
  `EnemyBase.take_hit` takes the talent multiplier from the attacker and
  remembers `last_attacker_id`; Wildfire uses the burn's owner
  (`StatusEffectComponent.burn_source_id`); XP, gold and loot go to the
  killer (`ZoneBase._on_enemy_died`). FractureRune rolls through
  `roll_ability_hit` like every ability.
- **Player registry:** `ZoneBase.players` / `local_player` (`player` is a
  read/write alias), `add_player`, `remove_player`, `nearest_player(pos)`,
  `players_within(pos, r)`. `EnemyBase.target` (`player` alias) is re-picked
  every 0.3 s in the roaming states when `auto_retarget` is set (only by
  `_spawn_enemy`): the recent attacker if close, else the nearest hero. Boss
  triggers, camps, novas, the charge and the Vessel ring use the registry.
- **Local-only presentation:** `Player.is_local`; `feel_shake`,
  `feel_impulse`, `ui_denied` and the pickup toast check it. World shakes
  (boss slams) stay unconditional. `peer_id` is reserved (1 = server/local).
- **Save v3:** `world {zone, flags}` / `characters [...]` / `active`
  (PROGRESSION_DESIGN.md). Talents carry `class_id` (`Progression.tree_for`);
  ability-specific affixes and legendaries carry `"class"`
  (`AffixPool.defs_for_slot(slot, class_id)`, `legendaries_for`).
- **Rules (kept in M08):** spawn enemies only through `_spawn_enemy` /
  `make_enemy`; activation, spawners and triggers use `players_within` /
  `nearest_player`, never `zone.player` (that is HUD, camera, targeting,
  prompts, debug); new hits go through `roll_ability_hit`; save additions go
  into `world` or `characters[i]`.
- UI: `HeroUI` (layer 8) hosts `InventoryUI`, `CharacterTab` and `TalentUI`
  as pages (I / C / N, Esc closes; `zone.inventory_ui` / `talent_ui` stay as
  aliases). `TrainerUI` is a separate panel opened by `TrainerNpc` (`Npc`
  base: prompt, nameplate, re-tinted rig). `StatSheet` (static) holds the
  sheet's formulas; the HUD tooltip uses it too. `WorldPickup` is the base of
  `ItemDrop` and `GoldDrop`.

## Open world (M08)
The Ashen Highlands are a 384 m heightmap zone built from data; M10's zones
copy the pattern.
- **Bake** (`tools/worldgen/highlands_layout.py` → `bake.py`): base fbm
  relief, Gaussian ridges, plateaus, a rim wall, graded routes (profiles
  smoothed, clamped to `grade_max`, fixed to the flat pads they cross and to
  earlier routes at junctions; the nearest segment wins per cell), flat POI
  pads (pads first, routes, pads again with route corridors kept), a test
  bump and a 25-degree test ramp for the smoke test. Outputs in
  `assets/world/highlands/`: `height.r16` (uint16 LE, row 0 = north,
  `height_max` scale; Godot's PNG loader would cut 16-bit to 8), `path_mask.png`
  (2 px/m trails + trampled camp floors), `map.png` (pixel-style map, no
  markers) and `layout.json` (the layout plus baked POI heights). The bake
  asserts pad flatness, route grade, camp spacing and POI density, and is
  byte-identical on rerun.
- **`Terrain`** (`scripts/world/terrain.gd`): decodes the grid (index
  `iz * res + ix`, sample (0, 0) at `origin`), builds 144 chunks x 3 LODs
  (1 / 2 / 4 m, `visibility_range` switches at 72 / 150 m with hysteresis,
  skirts hide LOD cracks, smooth normals so `terrain_pixel`'s slope blend
  works unchanged, only LOD0 casts shadows) plus one `HeightMapShape3D`
  (centred on its body: `origin + (res-1)/2`, 1 m cells, no scale) and four
  border walls. `height_at` / `normal_at` (bilinear), `footprint_range`
  (min/max ground under a yawed box). LookDev keys `terrain_lod`,
  `terrain_shadows`. Build time ~150 ms.
- **Ground seam:** nothing hard-codes the floor height any more.
  `ZoneBase.ground_y(pos)` (terrain or 0) is for build time (no physics
  shapes yet); `ground_point(pos, lift)` raycasts world layer 1 (+2 … -6 m)
  and falls back to `ground_y`; `zone_of(node)` / `ground_under(node, pos,
  lift)` for enemies and abilities. `VFX.ground_hit(root, pos)` returns
  {position, normal} and every ground plane (telegraph discs and lanes,
  threat rings, ground / player rings) places and tilts itself with it
  (`snap_ground` is off during the warm-up under the floor). Drops, spawns,
  fire patches, shadow runes, the frost field and the Fracture Rune go
  through the seam; enemies snap to floors like the player
  (`floor_snap_length 0.4`).
- **`ZoneLayout`** reads `layout.json` (POIs by id / type, routes, areas,
  `level_at` from the 8x8 band grid, bounds). **`PoiBuilder`** turns each
  POI into nodes: `portal` (Portal with `face_yaw` + `arrival`), `camp` /
  `ambush` / `elite_patrol` (EncounterSpawner), `chest`, `landmark`
  (monolith / charred grove / bone field), `ruin` (`_add_box` walls with
  `masonry_wall` trim, rubble rocks, chest, optional ambush), `arena`
  (rock ring, boss trigger, gates), `dungeon` (locked Portal between rocks),
  `waypoint`. Shared pieces: `blocker` (invisible collider under tall
  props), `rock` (hull box sunk to the lowest ground of its footprint,
  grown to clear the highest; `RockHull.foot_sink`), `prop` (kit prop on
  the ground with a 110 m visibility range), `apply_range`. Ridge rocks
  follow the layout's ridge lines, rim trees stand on blockers, scatter
  hugs obstacles and fills open ground (`Scatter` `field` items with
  `slope_max`, tilted to the slope). `ArtKit.masked()` gives the ground
  role the trail mask (shader uniform `use_mask`).
- **Camps** (`EncounterSpawner` v2): ARMED / ACTIVE / CLEARED; proximity
  checks every 0.5 s; `trigger()` spawns one enemy per physics frame
  (`spawn_frames` records them) around `home` or, for ambushes, on a ring
  around the hero who walked in; a clear writes `world.camps[camp_id]
  .cleared_at`; `check_rearm` resets after `respawn_minutes` while
  `players_within(home, rearm_radius)` is empty; a `patrol` path makes the
  home roam while nobody fights. `home` resolves lazily (zones set the
  position after `add_child`). Members get `home` + `leash`.
- **Leash** (`EnemyBase`): `AIState.RETURN` handled centrally in
  `_physics_process` (beyond `leash`, target out of reach, or stuck while
  chasing): walk home, `heal_full`, `clear_all`, IDLE. Subclass state
  machines and rig profiles never see it (`@loco` keeps playing). Bosses
  keep `leash 0`.
- **SaveGame v4:** `world.camps {id: {cleared_at}}` (debounced),
  `characters[i].waypoints` and `map_discovered`; v3 → v4 adds them empty.
  `pending_arrival` is transient.
- **Waypoints:** `Waypoint` (shrine prop on a collider, attunes every hero
  within 6 m, lit crystals, `[E] Travel`), `WaypointRegistry` (hub +
  layout waypoints, keys `<scene basename>:<poi id>`), `WaypointUI`
  (grouped list), `ZoneBase.fast_travel(key)` (fade + hop, or
  `travel_to(scene, arrival)`), `_arrival_point(id)` (a step in front of
  the node with meta `poi_id`), `_fade_then`. Zones override
  `_on_player_died` for shrine respawns.
- **Map + compass:** `ZoneBase.map_texture / map_bounds / map_markers /
  compass_markers` (defaults: none); `MapUI` (M, `world_to_map`), `Compass`
  (heading from the camera basis, bearing helpers, icon cache
  `Compass.icon`), `Hud.area_name`. Discovery: the Highlands tick every
  0.5 s over `players_within(pad + 15)`.
- **Runners:** `perf_probe` / `shot_runner` positions may be
  `{"poi": id, "offset": [dx, dy, dz]}` (`ZoneBase.poi_position`, offset y
  = lift above the ground); shot verbs `map`, `waypoint`, `close`, action
  `discover`; the runner hides the boss bar when it clears a wave.
- **Not in M08:** navmesh (open pads + leash instead), fog-of-war on the
  map, per-portal arrival in the Spire.

## Co-op (M09)
Plan and rules: ROADMAP.md M09. Roles, not machines: **authority**
(singleplayer = OFFLINE with a local hero; the dedicated server = SERVER
without one) and **client** (a hero in the server's world). Game code asks
`Net.is_authority()` / `is_client()` / `is_dedicated()` / `has_view()`,
never `DisplayServer` (headless bot clients are clients).
- **Hybrid authority:** the server owns enemies, camps, bosses, world flags,
  chests, reward rolls and zone changes; each client owns its hero (movement,
  abilities, hit detection against enemy puppets, its own HP, its character
  from its own save). Enemy hits on a hero are confirmed by its owner.
- **`Net`** is the only RPC endpoint (`/root/Net` exists on every peer;
  code-built nodes are addressed by net id / POI id, never by path). Kinds in
  `NetMsg`, payloads are plain Arrays; `Net.on(kind, handler(from, payload))`.
  `send_to_server` runs the handler locally on the authority (no RPC to
  itself), `send_to_peer` / `broadcast_zone` only reach clients that reported
  ZONE_READY for the current zone epoch; stale-epoch messages are dropped.
  Channels: 0 reliable events, 1 unreliable hero state, 2 unreliable
  snapshots. Bump `Net.PROTOCOL` with any message change: the auth handshake
  refuses other versions before any RPC runs. Godot versions must share
  major.minor (`Net.godot_minor`: 4.6.1 joins a 4.6.3 server; patch
  releases are network compatible); `--godot=` / `--protocol=` fake them in
  tests. `Net.broken_scripts()` (REQUIRED_SCRIPTS that fail to compile) stops
  the dedicated server and greys out the title screen with a hint.
- **Imports before runs:** a new class_name script, scene or asset is unknown
  to a game or headless run until an import rescans the project. `run_godot`
  (ps1 and sh, every mode but import/reset) and `runebound-server.sh` import
  first whenever a project file is newer than `.godot/runebound_import.stamp`
  (written after each import).
- **Access (M09b, invite codes):** friends reach the server without
  Tailscale, so the game decides who gets in (`NetAuth`,
  `scripts/net/net_auth.gd`). Every friend has a personal 16-character
  base32 code (80 bits) from `tools/server/invites.sh`; the server reads
  its invite list (`RUNEBOUND_INVITES` / `--invites=`, lines `name code
  added`, never in the repo) every 2 s. Handshake: on `peer_authenticating`
  the server sends a challenge (16 random bytes, plus a readable "update your
  game" reason that protocol-7 games show); the client answers `"RBJ1" |
  flags | HMAC-SHA256(SHA-256(salt + code), magic + nonce + hello) | hello`;
  the server checks size (<= 2 KB) and magic, then the MAC against every
  invite, and only then decodes the hello and runs the old checks. The code
  never travels, answers cannot be replayed, strangers never reach
  `bytes_to_var`. A revoked or changed code ends that session (KICK with a
  reason, the client lands in the title); a code joining again replaces its
  older session (and does not count against "full"). Without an invite list
  the server is **open and binds 127.0.0.1** (tests, `run_godot coop` /
  `server`). Waiting room: at most `PENDING_MAX` 8 unverified connections,
  a new one pushes the oldest out; `AUTH_TIMEOUT` 8 s; ENet slots players +
  24; `server_relay` off (clients only talk to the server); refusals logged
  5 a minute, the rest counted in the 60 s line. ENetMultiplayerPeer resets
  connections without a peer id >= 2 in the connect data before any of this
  (plain ENet noise never reaches the handshake). Tests: `--invite=` (client),
  `--auth=junk|junk_magic|old|silent` (hand-made answers), net scenarios
  `invite`, `invite_live`, `auth_garbage` (codes in `tests/net_test_codes.gd`).
- **ENet:** bind `*` (or 127.0.0.1 when open), peer
  timeouts 15-30 s (zone builds block the main loop), packet throttle off
  (`throttle_configure(5000, 32, 0)`). After a zone build ENet may still drop
  up to about a second of unreliable packets until its throttle sees a fresh
  RTT sample; the join state therefore always goes reliable.
- **Dedicated server:** `scenes/dedicated_server.tscn` (`tools/server/
  server.env`), `Engine.max_fps = 60`, world save `user://runebound_server
  .json` (`SaveGame.use_server_save`). ZoneBase skips environment, hero,
  camera, UI, music and warm-up; VFX effects, `Sfx.play`, floating text and
  enemy rigs return early (telegraph markers stay: gameplay reads them).
  Logs `tick p50/p95/max`, players, enemies (asleep), KB/s every 60 s.
- **SaveGame online session:** `begin_online_session(flags)` swaps in the
  server's flags; `_collect()` writes the stashed own world while `online`;
  `end_online_session()` restores it.
- **Heroes (`NetWorld`, `Player.net_role`):** OWNER / PUPPET / PROXY, set
  before `add_child`. Non-owners get an inert `InputSource`, no body
  collision, return at the top of `_physics_process`, never emit
  `player_died`; `apply_net_state(pos, yaw, vel, state, hp, hp_max)` poses
  them (`health.is_dead` follows the HP). Puppets have no hurtbox; proxies
  keep one (enemies target and hit them on the server) and no rig
  (`_build_visual` returns early without a view). Messages: HERO_STATE
  (client, 30 Hz, unreliable, seq-ordered), SNAPSHOT (server, 20 Hz, every
  hero but the receiver's), HERO_SPAWN / HERO_DESPAWN (on ZONE_READY and
  leave), HERO_ACTION (relayed `action_started`), CHARACTER (the client's
  `character_dict`, sent after ZONE_READY and debounced after changes,
  applied with `SaveGame.apply_character`, level to the roster).
  `NetWorld.sample_at` interpolates 100 ms behind the server clock (clock
  offset from the least-delayed snapshot), extrapolates 150 ms, snaps when
  `Player.teleports` changed (bumped by the owner on any jump > 6 m).
- **Enemies:** server-side `NetWorld.register_enemy` (net id u16) hooks
  `state_entered` (ENEMY_STATE with pose), `health.damaged` (ENEMY_HIT),
  `health.dot_damaged` (ENEMY_DOT for the burn owner's numbers),
  `enemy_died` (ENEMY_DEATH with the killer's peer) and `tree_exiting`
  (ENEMY_DESPAWN). Clients build puppets with `ZoneBase.make_enemy(type_id)`
  + `net_puppet = true` (+ EliteModifier by kind, sim gated off). Puppet
  rules: `_physics_process` returns (only the hitstop timer runs),
  `take_hit` -> `_forward_hit` (HIT), `status.apply_*` -> `forward_status`
  (STATUS), `apply_net_pose` from snapshots, `net_enter_state` from events
  (runs `_enter_state` for the animator and `_present_state` with the
  server's pose), `present_hit / present_dot / present_death`. The server
  applies a client's HIT with `attacker_id` = that client's proxy (talent
  math, kill credit and loot unchanged) after a 45 m sanity check.
  **Rule for new enemy code:** anything that only looks or sounds goes into
  `_present_state` (or a `present_*` helper), using `present_origin()` /
  `present_forward()`; simulation stays in the state machine. Attacks set
  `hit.area_center / area_radius` and hit every hero inside.
- **Named actions and hazards:** `play_fx(fx)` runs `_present_fx(fx)` (and
  the elite affix's `present_fx`) locally and emits `fx_played`, which the
  server sends as ENEMY_FX (with the pose); puppets run the same
  presentation (`net_play_fx`). Use it for looks that are not a state of
  their own. `blink_in` makes the client snap the puppet. FirePatch and
  ShadowRune register as hazards on the server (HAZARD) and exist as
  `visual_only` copies on clients. Health scaling (`HP_PER_EXTRA_HERO` 0.7)
  lives in NetWorld (`base_max_health` meta, ENEMY_SCALE on joins/leaves).
  `ZoneBase.setup_enemy_puppet(e)` gives boss puppets their bar (zones
  extend it: the Spire sets the Vessel's arena).
- **Enemy hits on heroes:** a PROXY's `take_hit` forwards the hit (HURT) to
  its owner; the owner applies it through its own `take_hit` (so dodge
  i-frames refuse it) unless its hero is more than `HURT_MARGIN` (1.2 m)
  outside the struck area.
- **Rewards and world state:** `ZoneBase.give_reward` is the only way to
  hand a hero XP, gold or items (`receive_reward` on the machine that owns
  the hero; GRANT with `ItemData.to_dict` for proxies). Recipients:
  `heroes_near(pos, REWARD_RADIUS 60)` for kills in co-op, the killer
  offline; `party()` for camp bonuses and boss loot; chests use
  `heroes_near(chest, 12)`. Chests are keyed by `net_key()` (position,
  identical on every peer). `SaveGame.set_flag` emits `flag_set`; the server
  sends FLAG, clients set the session flag and call the zone's
  `apply_world_flag(flag)`, which the authority calls itself after a boss.
  Save v5 keeps `discovered` zones per character.
- **Party travel:** clients' `ZoneBase.travel_to` sends TRAVEL_REQUEST;
  the server's NetWorld counts down (TRAVEL_COUNTDOWN / TRAVEL_CANCEL /
  TRAVEL_CANCELLED, action `party_cancel` = X) and calls
  `Net.change_zone(scene, arrival)`: epoch + 1 and `zone_scene` set before
  the scene changes, TRAVEL_GO (any epoch) to every client, server save,
  deferred scene change. `Net.zone_entered` only bumps the epoch for the
  first zone; `NetWorld.adopt_ready_peers()` runs at the end of the server's
  zone build. Clients: `ZoneBase.party_travel_go` (save, fade) then
  `Net._enter_zone(scene, epoch, arrival)`. `fast_travel` inside a zone moves
  only the local hero online. Late joiners: welcome `spawn_at` from
  `NetWorld.spawn_hint()` -> `Net.pending_spawn`. `Net._exit_tree` on the
  server disconnects every peer and flushes, so clients see the end at once.
  `_send_now` skips peers ENet is tearing down.
- **Hero effects:** `Player.hero_fx(kind, args)` plays a `HeroFx` entry for
  the acting hero and, for this machine's hero in co-op, sends HERO_FX; the
  server relays it and every other client plays the same entry on its
  puppet. Projectile and rune entries spawn `visual_only` copies on puppets
  (world collision only, no hits). **Rule:** a new ability look goes through
  `hero_fx` (a new HeroFx entry), never straight to VFX, unless only its own
  player should see it (hit feedback, footsteps).
- **Tools:** `run_godot coop [bots]` (local server + companion bots +
  window), net scenarios `soak` (10 min, by name) and the probe's `load`
  mode for the server laptop (camps re-arm after 5 s, enemies x10 health).
- **AI sleep** (`EnemyBase.SLEEP_RADIUS` 60 m): idle, standing enemies with no
  hero near skip `_physics_process`; checks every 0.5 s (spread by instance
  id), a hit wakes them.
- **Tests:** `tests/net_test.tscn` (orchestrator, one process per role via
  `OS.create_process`, logs in `user://net_test/`), `tests/net_client.gd`
  (headless client driver that survives the zone change),
  `tests/net_server_probe.gd` (server side). `tests/server_perf.tscn`
  (`--heroes=N --dedicated --strip=anim,ui,sleep,enemies --tanky=K`).

## Physics layers
1 world · 2 player · 3 enemy · 4 player_hurtbox · 5 enemy_hurtbox · 6 projectile
Melee hits = shape queries against hurtbox layers; projectiles = Area3D.

## Data
`AbilityData` Resource (.tres in resources/abilities/) carries all ability
tuning: timing (startup/active/recovery), damage, type, weight, knockback,
resonance cost/gain, crit. Behavior lives in Player; numbers live in data.

## Testing
- `smoke` runs under an 8-minute hard limit (exit code 3): a compile error
  before the test's own watchdog starts would otherwise idle forever.
- Shot lists can spawn bosses (`colossus`, `vessel`) and start an attack on
  a frozen enemy (`"call": "_start_windup"`), so windups are caught at any
  fraction. `{"do": "legendary"}` drops a legendary.
- `tools\run_godot.ps1 import|smoke|play|capture|worldcapture|stress`
  (`tools\run_godot.cmd <mode>` does the same where the PowerShell execution
  policy blocks .ps1 files). Windowed modes warn when another game instance
  is running (GPU contention on the iGPU). Smoke quits with code 2 after a
  300 s watchdog.
- Debug a copied save without touching the real one:
  `-- --save=user://<file>.json` (no wipe, no fixed seed).
- `tools\run_godot.ps1 shots <list>` — data-driven screenshots from
  `tests/shots/<list>.json` (zone, camera, spawns, actions, LookDev variants).
- `tools\run_godot.ps1 perf <scenario> [label]`: scripted fight from
  `tests/perf/<scenario>.json` (M08: `highlands_open`, `highlands_vista`;
  `highlands_south` now at camp 1).
  - Reports the median of repeats with GPU/CPU render time, keeps history in
    `captures_perf/`, and exits 1 below `budget_fps`.
  - Frames over 50 ms are listed with the fight step that preceded them,
    their GPU / render-CPU / script time and new pipeline compiles.
  - `-- --prefire=a,b` runs abilities or effects once before recording, to
    bisect first-use hitches.
- Windowed test modes run with `--quit-after 30000`, so a run whose runner
  never attaches (for example after a script compile error) can't hang.
- Automated runs (`--capture/--worldcapture/--shots/--perf/--stress`) use the
  scratch save and a fixed RNG seed from the first frame (SaveGame autoload).
- `tests/rig_spike.tscn` — rig/animation pipeline checks (headless) and
  `-- --spike-visual` captures + crowd perf (windowed).
- `tests/smoke_test.tscn` — headless functional pass (must stay green)
- `tests/playtest_capture.gd` — windowed automated playtest, screenshots to
  `captures/` (run with `capture` mode) for visual review
