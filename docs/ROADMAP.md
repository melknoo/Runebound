# RUNEBOUND — Roadmap

Stand: 2026-09-23 · M01–M04 abgeschlossen (Combat Lab, Combat Depth,
Loot & Builds, World & Persistence — alle vom Spieler getestet).

## Warum sieht es noch nach Greybox aus?
Bewusste Entscheidung nach der Master-Direktive: **Feel vor Content, Assets
erst wenn Gameplay sie braucht.** Optik entsteht in zwei Strömen:
1. **Inkrementell (läuft bereits):** Pixel-Texturen, VFX-Sprache, Blender-
   Charaktermodelle, Palette, Post-Processing (Style C) — alles, was Combat-
   Readability direkt dient.
2. **Der große Visual-Pass (M06):** kommt direkt NACH der kompletten Vertical
   Slice. Grund: Erst dann steht die vollständige Asset-Liste (alle Zonen,
   Gegner, Props) — nichts wird zweimal gebaut, und der Look wird in einem
   Guss kohärent statt stückweise.

## Meilensteine

### M05 — The Shattered Spire ✅ (2026-09-23)
Dungeon mit 4 Sektionen, Hollow Warden (Flanking-Gegner), Vessel of the
Shattered Rune (2 Phasen), World-Flags. Vertical Slice content-complete.

### M06 — Visual & Audio Identity Pass ("schick machen")
- **Charaktere:** richtige stilisierte Modelle mit Rigs + Animationen
  (Blender-Pipeline: Walk/Run/Attack-Cycles statt Prozedural-Tweens),
  Spieler-Rüstung, die Equipment-Slots sichtbar spiegelt (Weapon-Modelle!).
- **Environment-Kit:** modulare Blender-Props (Felsen, Ruinen, Vegetation,
  Banner), Ersatz der Greybox-Blöcke in allen Zonen, Detail-Streuung.
- **Licht & Himmel:** Zonen-Lighting-Pass, bessere Skyboxen, Godrays/Partikel-
  Atmosphäre.
- **UI-Theme:** Pixel-Fantasy-Skin für HUD/Inventar/Bossbar, Ability-Icons,
  Item-Icons.
- **Musik:** Hub-Theme, Region-Theme, Boss-Theme (Synth-Pipeline oder extern).
- Abschluss: Visual Quality Gate aus der Master-Direktive (§71).

### M07 — Spezialisierungen & Kit-Ausbau
Storm / Ember / Runic Warden (20–30 sinnvolle Nodes, verhaltensändernd statt
nur Prozente), Abilities 7–8 (Runic Guard, Resonance Burst), mehr Legendaries
+ Affix-Tiefe, Item-Vergleich-UX-Polish.

### M08 — Endgame: Shattered Expeditions
Wiederholbare 10–20-min-Runs: prozedurale Encounter-Zusammenstellung aus dem
Kit, Difficulty-Tiers mit Mechanik- (nicht nur Zahlen-) Eskalation,
Risk/Reward-Modifier, Ziel-Loot.

### M09 — Release-Politur der Slice
Main Menu, Settings (Rebinding, Sensitivity, Shake/Flash-Regler,
Accessibility), Damage-Number-Optionen, Performance-Pass auf Zielhardware,
Balancing-Runde, Bugfest.

## Prinzip bleibt
Jeder Meilenstein endet mit Smoke-Tests grün + Capture-Review + deinem
Playtest als Gate. Reihenfolge M05↔M06 ist tauschbar, wenn dir Optik
wichtiger ist als der Dungeon — sag einfach Bescheid.
