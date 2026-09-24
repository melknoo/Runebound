# RUNEBOUND — World Design (M04)

Compact and dense over large and empty (§50–52). All zones extend `ZoneBase`
(code-built greybox + pixel textures); travel via walk-in Portals with fade +
save. Player gear persists through `SaveGame` (see TECHNICAL_ARCHITECTURE).

## RUNEHOLD (hub — scenes/hub.tscn)
34x34 safe settlement, warm dawn palette. Campfire heart (flicker light,
ember loop, crackle ambience), three stone shelters with rune lintels.
Portals: ASHEN HIGHLANDS (north), TRAINING GROUNDS / Combat Lab (east).
New game and every return lands here. No enemies, ever.

## ASHEN HIGHLANDS (region — scenes/ashen_highlands.tscn)
100x70, ember-haze sky, cracked ash ground with ember flecks, ridge pockets
funneling a S→N path. Ambient wind loop.
- Camps (EncounterSpawner, trigger once per visit), escalating:
  2 rushers → rusher/caster/rusher → 2 assassins+caster → brute/rusher/caster.
- Elite pocket east: elite + 2 rushers.
- Chests: west detour behind a ridge (curiosity reward), NE corner (rare bias).
- Rune monolith landmarks for orientation.
- North: boss arena between half-walls.

## ASHVEIN COLOSSUS (mini-boss)
600 HP, stagger-resistant (HEAVY only), boss bar on HUD. Kit:
- **Slam**: 0.9s telegraphed disc (r3.2, 28 dmg heavy).
- **Charge**: 0.8s red lane telegraph → 14 m/s rush, 30 dmg contact,
  extra stun when it slams a wall (punish window).
- **Enrage <50%**: faster (3.4 m/s), 0.65s slams, drops fire patches, red aura.
Death: guaranteed legendary + unseals the north portal to Runehold.

## THE SHATTERED SPIRE (dungeon — scenes/shattered_spire.tscn)
Interior, near-black with violet fog; teal crystal torches + glowing floor
runes carry all light — telegraphs must read in the dark. Deep drone ambience.
Gated behind `colossus_defeated` (portal in the Highlands boss arena; shortcut
portal appears in Runehold). 50x72, four sections with door-gap dividers:
1. **Entry hall**: rusher/caster/warden camp.
2. **Broken gallery**: raised side platforms with casters (ramp up to the east
   platform from its west edge, x 2.8 to 8; west platform is ranged-only),
   assassins below; west alcove: warden-guarded chest (rare bias).
3. **Rune vault**: elite camp + second chest.
4. **Boss chamber**: torch ring, sealed exit portal.

## VESSEL OF THE SHATTERED RUNE (major boss)
1400 HP, stagger-resistant, floating crystal construct (violet/teal identity
vs. the Colossus' orange). Two phases:
- **P1 Construct**: telegraphed slams, 3 shadow runes around the player
  (1.2s arm → r2.5 blast), summons 2 rusher adds (~20s, max 3).
- **P2 Shatter (<50%)**: 1s invulnerable transition burst, then blinks
  between 5 arena anchors (centre + 7 x 3.5 m ellipse inside the chamber), 3-bolt rune fans, 4 shadow runes, expanding hazard
  ring from the arena center (~10s) — pure timing dodge.
Death: legendary + 2 rares, `spire_cleansed` flag, exit unsealed. Once
cleansed the Vessel stays dead (world flag).

## HOLLOW WARDEN (dungeon enemy)
90 HP construct, halves frontal damage (spark/clink feedback), exposed rune
core on its back, slow turner — flanking and Storm Step counter it.
Telegraphed full-circle spin (r2.4).

## Rules going forward
Every zone must answer: where does the player go next (readable path), what
rewards curiosity (detours), what escalates (camp order).

**Open, but dense** (changed 2026-09-23, see ROADMAP M08/M09): the world
becomes several large, freely explorable zones (~300–500 m) linked through
Runehold, not one seamless streamed world. Size is allowed, emptiness is not:
there should be a point of interest roughly every 50–80 m, several routes
instead of a single corridor, and landmarks visible from far away for
orientation. The current layouts above are the vertical-slice versions;
Ashen Highlands gets rebuilt as an open zone in M08.
