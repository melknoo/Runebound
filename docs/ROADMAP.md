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

### M06 — Visual & Audio Identity Pass ("schick machen") — umgesetzt, Gates beim Spieler
Gold-Standard (Highlands Süd) → Gate 0 ✅ → Propagation auf Runehold,
Trainingsgelände, Spire, alle Gegner, Portale/Truhen/Loot, Musik je Zone.
Offen: Style-Gate-Urteil + finaler Playtest + Hör-Checkpoint.
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
- **Wichtig für die Zukunft:** Das Environment-Kit wird modular und
  wiederverwendbar gebaut. Die heutigen Zonen-Layouts werden nicht
  über-dekoriert, weil die Highlands in M08 zur offenen Zone umgebaut werden.

> **Kurswechsel 2026-09-23 (nach Spieler-Feedback):** Die Slice fühlt sich
> schlauchig an. Gewünscht sind Leveling, ein Talentbaum und eine größere,
> frei erkundbare Welt. Entschieden: **mehrere große offene Zonen**, die über
> den Hub verbunden sind (keine nahtlose Streaming-Welt), und ein Talentbaum
> mit **3 Spec-Ästen**. Progression kommt vor der Welt, weil die Welt
> Level-Bereiche braucht und Erkunden sich über XP lohnen muss.

### M07 — Progression: Leveling & Talentbaum — begonnen (Vorschlag, wartet auf dein Review)
- **Leveling:** XP aus Kills, Camps, Truhen und Entdeckungen; Level-Cap
  ~20–30; Enemy- und Item-Level, damit Loot mit dem Spieler skaliert.
- **Talentbaum:** 1 Punkt pro Level, 3 Äste Storm / Ember / Runic Warden
  (20–30 Nodes), die das Verhalten ändern statt nur Prozente zu geben (z. B.
  „Ember Lance spaltet sich beim Treffer“). Umskillen jederzeit.
- Abilities 7–8 (Runic Guard, Resonance Burst) werden als Talent-Unlocks
  eingeführt.
- Mehr Legendaries + Affix-Tiefe, Item-Vergleich-UX-Polish.
- Technik: `ProgressionComponent` am Player, Talent-Nodes data-driven wie
  `AbilityData` (.tres), Hooks über die bestehenden Equipment-Getter;
  SaveGame-Versions-Bump mit Migration.

### M08 — Open World I: Ashen Highlands, offen
- Die bestehende Region wird zur frei erkundbaren Zone (~300–500 m):
  Heightmap-Terrain statt Greybox-Blöcke, mehrere Wege statt eines S→N-Pfads.
- Etwa alle 50–80 m ein interessanter Ort (POI): Camps, Ruinen, Events,
  Truhen, Mini-Dungeon-Eingänge, Rätsel/Geheimnisse.
- Respawnende Camps, Wegpunkte + Schnellreise, Karte + Kompass,
  Level-Bereiche innerhalb der Zone.
- Terrain-, Sichtweiten-, LOD- und Perf-Technik wird hier einmal sauber gelöst
  (Enemies nur in Spielernähe aktiv, Stresstest auf der Dev-GPU, Ziel 60 FPS).

### M09 — Open World II: zwei weitere Zonen
Mit der M08-Technik: zwei neue Regionen mit eigener Identität (Palette,
Gegnerfamilie, Wetter), je ein Dungeon + Boss. Der Hub verbindet alle Zonen
per Portal und Schnellreise.

### M10 — Endgame: Shattered Expeditions
Wiederholbare 10–20-min-Runs: prozedurale Encounter-Zusammenstellung aus dem
Kit und allen Zonen, Difficulty-Tiers mit Mechanik- (nicht nur Zahlen-)
Eskalation, Risk/Reward-Modifier, Ziel-Loot. Setzt Level-Cap und Talente voraus.

### M11 — Release-Politur
Main Menu, Settings (Rebinding, Sensitivity, Shake/Flash-Regler,
Accessibility), Damage-Number-Optionen, Performance-Pass auf Zielhardware,
Balancing-Runde, Bugfest.

## Prinzip bleibt
Jeder Meilenstein endet mit Smoke-Tests grün + Capture-Review + deinem
Playtest als Gate. Reihenfolge M05↔M06 ist tauschbar, wenn dir Optik
wichtiger ist als der Dungeon — sag einfach Bescheid.
