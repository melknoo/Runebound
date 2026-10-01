# RUNEBOUND — Roadmap

Stand: 2026-09-29 · M01–M09 gebaut (M07/M07b abgenommen am 24.09., M08-Notizen am 28.09. umgesetzt).
**M09 Co-op ist gebaut und mit einem Freund angespielt.** Server-Laptop steht
(`docs/SERVER_SETUP.md`), gemessen: 4 kämpfende Spieler bei 60 Hz mit Reserve. **M09b (Freunde
ohne Tailscale) läuft.** Am 29.09. hat der Spieler die Richtung nach M09b festgelegt
(„Spieler-Leitlinien“ unten): zuerst drei Klassen mit Loadout, danach Substanz für Welt, Dungeons
und Story.

## Nordstern (aktualisiert 2026-09-29)
RUNEBOUND wird ein **Koop-Action-RPG für 2–5 Spieler** in einer stilisierten Pixel-Fantasy-Welt:
eigener Charakter in einer von **drei Klassen (Tank, Heiler, Damage Dealer)**, Fähigkeiten, die
gelernt statt geschenkt werden, und davon **nimmt man 4 aus etwa 12 mit**; Gold, Talente und
Loot; eine kleine, düstere Story mit Dungeons, Bossen und Rätseln, die sich an wenigen Stellen
**selbstironisch nicht ernst nimmt** („von einer KI geschrieben“). Gehostet auf einem eigenen
dedizierten Server (Linux-Laptop zuhause). Kein MMO.
Singleplayer bleibt vollständig spielbar, **außer den Koop-Dungeons** (3–5 Spieler, Extra-Content
mit eigenem Loot; die Story ist ohne sie komplett).

## Warum die Reihenfolge so ist
- **Fundament vor Welt:** Koop und mehrere Klassen kosten wenig, wenn die Nahtstellen früh sitzen
  (Klasse als Daten, Angreifer im Treffer, Spieler-Registry, Save-Split), und sehr viel, wenn die
  offene Welt erst auf „ein Spieler, eine Klasse" gebaut wird.
- **Koop vor weiteren Zonen:** die zweite und dritte Zone sollen das Mehrspieler-Muster kopieren,
  nicht das alte.
- **Story nach Koop:** Rätsel und Quests brauchen im Koop andere Regeln (geteilter Fortschritt,
  wer löst was). Erst wenn die stehen, lohnt sich Story-Content.
- **Klassen vor Rätseln und Quests (2026-09-29):** Fähigkeiten-Rätsel, Koop-Dungeons mit Rollen,
  Quest-Belohnungen und Folianten in Geheimnissen hängen alle am Fähigkeiten-Pool der drei Klassen.
  Wer sie vorher baut, baut sie zweimal.
- **Highlands als Vorlage vor neuen Zonen:** Unter-Biome, POI-Arten und Geheimnisse entstehen
  zuerst in der Zone, die du schon kennst; neue Zonen kopieren dann das bessere Muster.
- **Feel vor Content** bleibt: jeder Meilenstein endet mit Smoke grün + Captures + deinem Playtest.

## Spieler-Leitlinien (2026-09-29)
Die Wünsche des Spielers nach M09, in acht Fragerunden geklärt. „Setting, Musik und Atmosphäre
gefallen schon sehr, es fehlt Substanz.“ Details in den Design-Docs.
1. **Open World weniger eintönig** ([WORLD_DESIGN](WORLD_DESIGN.md) „Planned: the Highlands with
   substance“): heute optisch gleichförmig, zu wenig zu tun, zu wenig Leben, nichts zu entdecken.
   Gewünscht: Unter-Biome, mehr POI-Arten, harmlose Tiere und Kreaturen, neue Gegnerfamilien je
   Unter-Biom, Geheimnisse + Lore, erzählende Umgebung. Die Highlands zuerst, als Vorlage.
   Vorerst nicht gewählt: Wetter/Tageszeit, Welt-Events, NPCs draußen, mehr Musikstücke,
   Klangkulisse, Licht/Himmel. Die Musik gefällt so, wie sie ist.
2. **Dungeons abwechslungsreicher** ([WORLD_DESIGN](WORLD_DESIGN.md) „Planned: dungeons“):
   Fähigkeiten-, Mechanik- und Fallen-Rätsel, meist kurz, pro Dungeon ein größeres für ein
   Geheimnis; Geheimräume + Abzweige, Zwischenbosse. **Eigene Koop-Dungeons für 3–5 Spieler**,
   solo gesperrt, dort zählen die Rollen.
3. **Story mit Meta-Würze** ([STORY_DESIGN](STORY_DESIGN.md)): die Story bleibt ernst und düster;
   seltene, explizite Brüche der vierten Wand („Ich wurde von einer KI geschrieben“), Ton
   selbstironisch-liebevoll, in NPC-Dialogen, Items + Quests und Lore-Objekten. Dialoge mit
   Antwortoptionen (meist Geschmack). Alle Texte **Deutsch + Englisch mit Sprachwahl**.
4. **Drei Klassen + Loadout** ([CLASS_DESIGN](CLASS_DESIGN.md) „Three roles“): Runebreaker wird
   **Tank** (Bedrohung + Spott), ein **Elementar-Magier** (Fernkampf-DD) übernimmt Ember Lance,
   Chain Spark, Fracture Rune und Storm Step, ein **Wurzel-Druide** heilt (gezielt, Zonen, Schilde
   + Buffs). LMB und Dodge fest, **4 freie Slots (RMB, 1, 2, 3) aus etwa 12**, Wechsel überall
   außerhalb des Kampfs. Rollen: solo weich, Koop-Dungeons fordern sie.
5. **Icons:** bleiben beim Generator (`tools/texgen/ui.py`), entschieden am 2026-09-29 nach einem
   Vergleich mit PixelLab (Nebenstrang unten).

## Abgeschlossen
- **M01 Combat Lab** — Controller, Kamera, Dodge, Rune Cleave, Ember Lance, Earthbreaker, Feedback-Stack.
- **M02 Combat Depth** — 6-Fähigkeiten-Kit, Status-Effekte, Assassin/Brute, Elites.
- **M03 Loot & Builds** — Items, Rarities, Affixe, Legendaries, Inventar.
- **M04 World & Persistence** — Runehold, Ashen Highlands, Colossus, SaveGame.
- **M05 The Shattered Spire** — Dungeon, Hollow Warden, Vessel (2 Phasen), World-Flags.
- **M06 Visual & Audio Identity** — Rigs + Animationen, Environment-Kit, Licht, HUD-Theme, Musik je Zone. Style Gate ✅
- **M07 Progression** — Leveling (Cap 25), 24-Node-Talentbaum (Storm / Ember / Runic Warden),
  Item-Level, Fähigkeiten 7–8 als Talent-Unlocks, SaveGame v2.
- **M07b Character Foundations** — eine Startfähigkeit, Trainerin Sigrun, Gold, Helden-Fenster,
  Klassen-/Koop-Nahtstellen, SaveGame v3. Vom Spieler abgenommen.

## Aktuell

### M09 — Co-op (2–5 Spieler, dedizierter Server) — gebaut, Gate beim Spieler
Plan vom 2026-09-25 (vom Spieler freigegeben). Architektur:
- **Zwei Rollen:** Autorität und Client. Singleplayer ist die Autorität mit lokalem Helden
  (`OfflineMultiplayerPeer`, der heutige Codepfad). Der dedizierte Server ist die Autorität ohne
  Helden (Headless auf dem Laptop, `tools/server/`). Clients sehen die Welt als Puppets.
- **Hybride Autorität** (ersetzt „Bewegung/Fähigkeiten als Intents zum Server“): Der Server besitzt
  Gegner, Camps, Bosse, Welt-Flags, Truhen, Belohnungswürfe und Zonenwechsel. Jeder Client besitzt
  seinen Helden: Bewegung, Fähigkeiten, Treffererkennung gegen die Gegner-Puppets, eigene HP und
  Charakterdaten aus dem eigenen Save. Grund: 30–120 ms RTT über Starlink/Tailscale, unter Freunden
  kein Anti-Cheat nötig; der eigene Held fühlt sich exakt wie im Singleplayer an. Gegner-Treffer
  auf Helden bestätigt der Besitzer (Ausweichen zählt so, wie man es sieht).
- **Eigene Replikationsschicht** im Autoload `Net` (ENet, Auth-Handshake, 20-Hz-Snapshots,
  reliable Events, Zonen-Epoche); Gegner präsentieren sich über Zustands-Events.
- **Adresse:** Textfeld `host:port` mit „zuletzt benutzt“, Default-Port 7777, nie fest im Code.
  Der Server bindet `*` (IPv4 + IPv6) auf `RUNEBOUND_PORT`.

Regeln (Spieler-Entscheidungen 2026-09-25):
- **Persönlicher Loot:** jeder sieht nur seine Drops; jeder Held in ~60 m um einen Kill bekommt volle
  XP und einen eigenen Gold-/Loot-Wurf. Truhen öffnen einmal, mit einem Beutel pro Held.
- **Zonenwechsel gemeinsam:** einer löst aus, 5-s-Countdown (abbrechbar), die ganze Gruppe reist.
  Der Server hält genau eine Zone. Schrein-Hops innerhalb der Zone sind persönlich.
- **Skalierung:** Gegner-HP +70 % pro weiterem Spieler (Datenwert), Schaden bleibt.
- Welt-Flags und Camps leben auf dem Server, Charaktere beim Spieler.

Phasen (jede endet mit Smoke grün, Netztests grün, Doku, Commit + Push):
0. Aufräumen (`.godot/` aus dem Repo) + Leistungs-Spike auf dem Laptop (4 Bot-Helden, alle Camps).
1. Netz-Fundament: `Net`, dedizierter Server, Titelbildschirm (Singleplayer / Koop beitreten),
   Mehrprozess-Testharness `run_godot net`.
2. Helden in einer Welt: Heldenzustand, fremde Helden, Server-Proxies, Namensschilder, Party-HUD.
3. Gegner: 3a Kern (Rusher, Caster, Bolt, Treffer-/Hurt-Pfade), 3b alle Gegner, Hazards, Bosse,
   HP-Skalierung.
4. Belohnungen und Welt (persönlicher Loot, Truhen, Camps, Flags, Save v5).
5. Gruppen-Ablauf (Reise-Countdown, Tod, Nachzügler, Disconnect).
6. Gates: `run_godot coop` (Server + Bots + ein Fenster), 10 min stabil mit 5 Helden, Netsim
   100 ms / 2 % Verlust, Server-Leistung auf dem Laptop, WAN-Test über Tailscale, Deploy, dein
   Playtest.

Stand 2026-09-25: alle Phasen gebaut. Smoke 401 grün, 13 Mehrprozess-Netztests grün (plus
10-min-Soak), Laptop unter Last p95 8–11 ms. Gate: dein Playtest (PROJECT_STATE „Gate walk“:
`tools\run_godot.cmd coop`, dann der Laptop, dann ein Freund).

Nicht in M09: Listen-Host, Passwort (Tailscale regelt den Zugang; kommt mit „nativ ohne
Tailscale“), Chat, Interest-Management, Prediction.

### M09b — Freunde ohne Tailscale — in Arbeit
Plan vom 2026-09-25 (vom Spieler freigegeben): Der Laptop bleibt der Server, kein Mietserver, kein
Tunnel-Dienst. Starlink lässt nichts herein (CGNAT, Router blockt eingehendes IPv6), deshalb:
- **Tailscale Funnel** gibt dem Laptop eine öffentliche HTTPS-Adresse. Freunde brauchen kein
  Tailscale, am Laptop öffnet sich kein Port, die Heim-IP bleibt verborgen.
- **WebSocket-Weg** neben ENet, weil Funnel nur TCP kann. Ein Servername ohne Port bedeutet
  `wss://`.
- **Einladungscodes statt Accounts:** ein persönlicher Code pro Freund
  (`tools/server/invites.sh`), HMAC-Challenge-Response im Handshake. Zurückziehen wirkt sofort.
- **Abgeschotteter Dienst:** eigener Benutzer `runebound`, systemd-Sandbox, Netz nur 127.0.0.1.
Phasen:
0. Funnel messen (RTT, Hänger, Bandbreite).
1. Einladungscodes (gebaut).
2. WebSocket (gebaut).
3. Dienst + Funnel (am 28.09. auf dem Laptop eingerichtet; der Spieler ist ohne Tailscale beigetreten).
4. Doku, Freunde einladen, Gate: Ein Freund spielt ohne Tailscale (offen).
Nicht in M09b: direktes UDP per Hole-Punching (nur falls Funnel zu langsam ist), IPv6 direkt,
Accounts.

### M08 — Open World I: Ashen Highlands, offen (angespielt; Notizen am 28.09. umgesetzt)
Sichtbar:
- **Heightmap-Terrain 384 × 384 m** aus einem deklarativen Layout gebacken (`tools/worldgen`):
  Südhänge → Nordplateau, Randgebirge, Grate mit Felsen, eingeschnittene Trampelpfade, flache
  Kampf-Pads unter jedem POI. Kamera-Far 560 m, Dunst am Rand.
- **32 POIs an fünf Routen** (alle 50–80 m): 8 Camps, 2 Hinterhalte (Pack erscheint um den
  Spieler), 1 Elite-Patrouille, 3 Ruinen mit Truhen, 4 freie Truhen, 5 Wegpunkt-Schreine,
  Landmarken, 2 versiegelte Dungeon-Tore (Platzhalter für M13), Colossus-Arena. Level-Bänder
  Süd 1 / Mitte 2 / Nord + Emberfall Ridge 3.
- **Camps leben:** gecleart → im Save gemerkt → nach ~10 min wieder da, aber nie, solange ein Held
  in 45 m steht. Camp-Gegner haben eine Leine (gehen heim und heilen).
- **Wegpunkte + Schnellreise:** Schrein berühren = attunen (+40 XP), `[E] Travel` listet Runehold
  und alle attunten Schreine; Tore setzen dich vor das Tor, durch das du kamst; Tod = zurück zum
  nächsten attunten Schrein. Runehold hat seinen eigenen Schrein.
- **Kompass** oben im HUD und **Karte auf M** mit allem, was der Charakter gesehen hat.
Unsichtbar: Boden-Seam (nichts kodiert mehr y = 0), `EncounterSpawner` v2, `EnemyBase.RETURN`,
SaveGame v4, `WaypointRegistry`, Ankunfts-Hints, Runner-Positionen per POI-ID.
Angespielt vom Spieler; seine Notizen sind am 28.09. umgesetzt (PROJECT_STATE „M08 notes“). Offen: KNOWN_ISSUES
„M08 open items" (Respawn-Minuten, Camp-Dichte, Randgebirge-Look, NavMesh später).

### M07b — Character Foundations (abgenommen)
Sichtbar:
- Start mit **einer** Fähigkeit (Rune Cleave + Dodge). Earthbreaker, Ember Lance, Storm Step,
  Chain Spark, Fracture Rune lernt man bei der **Trainerin Sigrun Runewright in Runehold** gegen
  Gold + Mindestlevel (L2 / 3 / 4 / 5 / 7).
- **Gold** als Währung: Drops von Gegnern (≈ halbe XP), Truhen, Bossen; Auto-Pickup; HUD-Zähler.
- **Helden-Fenster** mit Tabs Inventar (I) / Charakter (C) / Talente (N): Stats, effektiver Schaden
  pro Fähigkeit (mit Crit, Gear, Talenten), Cooldowns, Kosten, Verteidigung, Ausrüstung.
Unsichtbar (Nahtstellen für Klassen und Koop, kein Netcode):
- Klasse als Daten (`ClassData`), ein Fähigkeits-ID-Raum, `knows()`-Gate.
- Angreifer-ID auf jedem Treffer (Talent-Boni, XP, Loot gehen an den Schützen).
- Spieler-Registry in der Zone; Gegner zielen auf den nächsten Spieler / letzten Angreifer.
- Input-Intent-Schicht (lokal heute, Netzwerk-Peer später).
- Spieler-eigene Präsentation nur lokal (`is_local`).
- SaveGame v3: Welt-Flags und Charaktere getrennt; Talente/Affixe klassen-gefiltert.
Stand 2026-09-24: alles gebaut, Smoke grün, Shot-Liste `m07b_character` gesichtet.
Gate: dein Playtest (`tools\run_godot.cmd reset` → `play`: Fresh Start → Gold sammeln → Sigrun →
Earthbreaker lernen → C-Fenster).

## Geplant

Neu geordnet am 2026-09-29 nach den Spieler-Leitlinien. M10 und M11 sind entschieden (Klassen
zuerst, Tank und Magier zusammen, der Druide direkt danach). Die Reihenfolge ab M12 ist ein
Vorschlag und bleibt tauschbar. Frühere Nummern: die „Zweite Klasse“ war M12, Open World II war
M10, Story & RPG war M11, Endgame M13, Release-Politur M14.

### Nebenstrang vor M10 — Icon-Quelle (entschieden 2026-09-29)
**Spieler-Entscheidung: Die Icons kommen weiter aus dem Generator.** `tools/texgen/ui.py`
zeichnet jedes Icon in Code: 20×20-Kunst, Rollenfarben aus `art_spec.json`, Tintenumriss,
gespeichert in 2×. M10 und M11 brauchen zusammen etwa 30 neue Fähigkeits-Icons.

Grundlage war ein Vergleich derselben drei Motive (Spott, Frostnova, Heilzone) auf beiden Wegen.
Jedes Icon stand im echten HUD-Slot und lief durch einen ART_BIBLE-Check (Raster, Palette, Umriss):
- **Generator:** Alle drei bestehen jeden Check und treffen die Formsprache des Sets. Dem Spieler
  gefielen sie am besten.
- **PixelLab pixen** (nativ 20×20): der beste KI-Weg. pixen wählt aber eigene Farben (12 bis 56
  statt 4 bis 6). Erst nach dem Runden auf die Rollenfarben und einem neuen Umriss bestehen die
  Icons die Checks.
- **PixelLab pixflux** (erzwungene Palette): Die Leinwand ist mindestens 32×32, beim
  Herunterrechnen auf 20×20 gehen Details verloren. 3 von 7 Versuchen waren brauchbar.
- **PixelLab Pro:** Ein Aufruf mit 64 Kandidaten brachte keinen brauchbaren. Die Stilvorlage war
  ein 2×2-Blatt aus vier Icons, und das Modell übernahm dessen Aufteilung.
- **Kosten:** 30 der 40 Test-Generationen, bezahlt 0 $ (zum Listenpreis etwa 0,17 $). Die Lizenz
  wäre kein Hindernis gewesen: Die Bilder gehören dem Nutzer, kommerzielle Nutzung ist frei.

Umsetzung: Die neuen Icons entstehen zusammen mit ihren Fähigkeiten als Funktionen in `ui.py`.
In M10 kommen die Tank- und Magier-Icons, in M11 die Druiden-Icons. Die drei Vergleichs-Entwürfe
(`icon_taunt`, `icon_frost_nova`, `icon_healing_zone`) stehen schon in `ui.py`. `main()` speichert
sie erst, wenn ihre Fähigkeit eine ID hat. Für den Druiden kommt in M11 eine Farbrolle `nature` in
`art_spec.json`. Bis dahin gilt die vorläufige Rampe `NATURE` in `ui.py` (#2E6B34 / #7ED957 /
#E4FFC4, deutlich gelber als das Spieler-Türkis). Der PixelLab-MCP-Server bleibt registriert (Scope `local`, der Key
liegt als `PIXELLAB_API_KEY` in der git-ignorierten `.env`, nie in einem `.mcp.json` im Repo). Für
Icons wird er nicht gebraucht.

### M10 — Drei Rollen I: Tank + Elementar-Magier + Loadout (gebaut, dein Playtest offen)
Ersetzt die alte „Zweite Klasse“. Details: CLASS_DESIGN „Three roles“.
**Entscheidungen des Spielers (2026-09-29):** 8 Pool-Fähigkeiten je Klasse jetzt, die übrigen
~4 kommen ab M12–M14 aus Bossen, Quests und Folianten; Block = halten (vorn −75 %) + Parade in
den ersten 0,3 s; der Magier baut **Äther** auf und gibt es aus (eigene Farbe); **jeder
Charakter hat seine eigene Welt**.
**Stand:** Phase 1 gebaut (Klassen-Chassis, Runenbolzen, Loadout mit Tab K, Charakterwahl,
SaveGame v6 mit Welt je Charakter, zweite Trainerin Maren, Talentbäume je Klasse, Items je
Klasse, Bots je Klasse). Phase 2 gebaut (Tank: Bedrohung mit Aggro-Zeichen im Koop, Spott,
Runenwall mit Parade, Runen-Herausforderung, Wächtersprung, Runenkette, Schutzrune, alle
Tank-Talente, Legendary „Warden's Oath“; Smoke 485 grün, Netz-Szenario `threat`). Phase 3
gebaut (eigenes Magier-Rig mit 13 Clips, Frostnova, Flammenwand, Kugelblitz, Glutsturz, der
Frost-Ast mit Wurzeln/Einfrieren, Cinderfall; Smoke 500 grün, Netz-Suite grün; die
Look-Vorschau des Rigs geht an dich). Phase 4 gebaut (Shot-Liste `m10_classes`, Solo-Check
beider Klassen per Bot: beide schaffen alle Camps und den Colossus auf Stufe 4 und 6 ohne Tod,
Perf-Vergleich mit dem Stand vor M10, Playtest-Gruppe „M10: Klassen & Heiltränke“, Gate-Walk in
PROJECT_STATE). Offen für dich: der Playtest, der Look des Magiers und zwei Fragen aus dem
Solo-Check: Heilung zwischen Kämpfen (entschieden 2026-09-30: **keine Regeneration außerhalb
des Kampfs**, sonst wartet man einfach; stattdessen **Verbrauchsgüter** wie Heiltränke und Essen,
die einen Teil des Lebens heilen – als M10b gebaut, siehe unten) und der Colossus womöglich zu
leicht.

### M10b — Heiltränke (gebaut 2026-09-30, dein Playtest offen)
**Entscheidungen des Spielers (2026-09-30):** keine Regeneration außerhalb des Kampfs;
Verbrauchsgüter jetzt als kleines M10b; trinken **nur aus dem Inventar** (Rechtsklick, keine
Taste); Heilung **über ein paar Sekunden**; Quellen **Drops, Truhen und ein Händler**.
**Stand:** Heiltrank (35 % des Lebens über 4 s, einer nach dem anderen, 5 im Gepäck, kein
Inventarplatz), Drops pro Held (Kleinzeug 5 %, Brute 15 %, Elite 30 %, Boss immer 2, Truhe 60 %),
**Ylva Ashbrew** in Runehold verkauft sie für 30 Gold, Zähler im HUD neben dem Gold, rote Flasche
am Boden, im Koop als persönliche Beute (PROTOCOL 11). **Essen** kommt in M12 mit den Tieren
dazu (dieselbe Tabelle).
**Werkzeug:** Posen, Silhouetten und das Magier-Rig entstehen im Live-Blender-Loop
(`tools/modelgen/live.py` über den Blender-MCP: bauen, posieren, Screenshot); jedes Ergebnis
wandert zurück ins Skript, das Skript bleibt die einzige Quelle.
- **Runebreaker wird Tank:** Rune Cleave, Earthbreaker, Runic Guard und Resonance Burst bleiben;
  neu kommen Spott, Block und Schadensreduktion. **Bedrohung + Spott:** Gegner merken sich, wer
  am meisten droht, Tank-Fähigkeiten drohen extra, ein Spott zieht sofort.
- **Elementar-Magier (Fernkampf-DD):** erbt Ember Lance, Chain Spark, Fracture Rune und Storm
  Step, dazu neue Zauber; eigener Grundangriff, Rig, Trainer.
- **Loadout:** LMB-Grundangriff und Dodge sind fest, **4 freie Slots (RMB, 1, 2, 3) aus einem
  Pool von etwa 12 je Klasse**. Wechsel überall außerhalb des Kampfs (die 3-s-Regel des Sprints).
  Neue Fähigkeiten kommen vom Trainer, aus Quests und von Bossen, aus Geheimnissen und Dungeons
  (Folianten) und über den Talentbaum. In M10 zuerst Trainer + Talentbaum, die anderen Quellen
  kommen mit M12–M14.
- Charakterwahl-/Erstell-Screen, mehrere Charaktere pro Save (je eine Klasse), klassen-eigene
  Talentäste, Affixe und Legendaries, Save-Migration für bestehende Runebreaker.

### M11 — Drei Rollen II: Wurzel-Druide (Heiler) (gebaut, dein Playtest offen)
Pflanzen aus verbrannter Erde, Totems, Dornen. Heilt **gezielt** (Verbündeter unter dem
Fadenkreuz, sonst der mit dem wenigsten Leben in Reichweite, allein man selbst), mit **Zonen am
Boden** und **Schilden + Buffs**. Genug eigener Schaden, um die Story solo zu schaffen. Eigenes
Kit (etwa 12), Rig, Talentbaum, Trainer.
**Entscheidungen des Spielers (2026-09-30):** 8 Pool-Fähigkeiten + LMB jetzt, der Rest ab
M12–M14; die Ressource **Saft** ist ein Vorrat, der **nur im Kampf** nachläuft; LMB
**Dornensalve**; **Leben und Saft reisen mit** (Reisen heilt nicht mehr, voll wird man nur
durch Tod, Tränke, Heilung und das Herdfeuer in Runehold); **Heilen droht ein wenig** (die
Hälfte des Geheilten, verteilt auf die Gegner, die schon kämpfen).
**Stand:** Phase 1 gebaut (Heil-Pipeline für Verbündete, freundliches Ziel mit Markierung,
Heil-Aggro, Vorrat-Ressource, Leben/Saft im Save und über Reisen, Herdfeuer, Barriere im
Party-Panel, Klasse mit Dornensalve und Knospe der Heilung, Trainerin Hild Ashroot, alle Icons
und Sounds; Netz-Szenario `heal`, PROTOCOL 12). Phase 2 gebaut (die übrigen 7 Fähigkeiten,
24 Talente, 3 Legendaries, Affixe, Bot-Heiler). Phase 3 gebaut (eigenes Rig mit 13 Clips, der
Look ist von dir abgenommen). Phase 4 gebaut (Solo-Check: der Druide schafft alles allein auf
Stufe 4 und 6 ohne Tod; Shots `m11_druid`, Docs, Playtest-Gruppe „M11: Druide & Heilen“,
Gate-Walk in PROJECT_STATE). Smoke 555 grün, Netz-Suite grün.

### M17a — Menüs & Einstellungen (aus M17 vorgezogen, gebaut, dein Playtest offen)
Anlass (2026-10-01): Wer im Titel einen Charakter wählt, landet sofort solo im Spiel; im Spiel
gibt es kein Esc-Menü und nirgends Einstellungen. **Entscheidungen des Spielers (2026-10-01):**
erst der Charakter, dann **Allein spielen** oder **Online spielen**; „Weiter“ spielt den letzten
Charakter so wie zuletzt; das **Esc-Menü pausiert solo**, online läuft die Welt weiter (der Held
steht still); Einstellungen **Audio + Grafik, Maus & Kamera, Komfort und Tastenbelegung**; im
Titel eine **lebendige Szene** (Lagerfeuer bei Nacht, der gewählte Charakter in seinem Rig);
Menüs **Englisch** wie der Rest (die Sprachwahl bleibt bei M12); **online gilt der
Charaktername**; **Entwickler-Werkzeuge** (F1, J-Liste) als Schalter, Standard aus
(`run_godot play` / `coop` schalten sie an). Kein Protokoll-Wechsel geplant.
Phasen: 1 Einstellungs-Kern + Fenster, 2 Esc-Menü, 3 Hauptmenü + Lagerfeuer-Szene,
4 Tastenbelegung, 5 Abschluss.
**Stand:** Phase 1 gebaut (`GameSettings`, Einstellungsfenster mit vier Tabs, im Titel unter
„Settings“). Phase 2 gebaut (Esc-Menü: solo pausiert, online läuft die Welt, zurück zum Titel
speichert, Esc schließt zuerst offene Fenster). Phase 3 gebaut (Hauptmenü: Charakter wählen, dann
allein oder online; „Weiter“ wie zuletzt; Lagerfeuer-Szene bei Nacht mit dem Rig des gewählten
Charakters; online gilt der Charaktername). Phase 4 gebaut (Tastenbelegung: zwei Tasten je Aktion,
Konflikte, Zurücksetzen; HUD und Hinweise zeigen die eigene Belegung). Phase 5 gebaut (Doku,
Playtest-Gruppe „M17a: Menüs & Einstellungen“, Gate-Walk in PROJECT_STATE).

### M12 — Highlands mit Substanz (in Arbeit)
Die Highlands werden die Vorlage für jede weitere Zone (WORLD_DESIGN „Planned: the Highlands
with substance“): **Unter-Biome** mit eigenem Look, **neue POI-Arten** (Mini-Rätsel draußen,
Prüfungs-Schreine, Nester, verfluchte Orte, kleine Höhlen), **harmlose Tiere und Kreaturen**,
**neue Gegnerfamilien je Unter-Biom**, **Geheimnisse + Lore** (versteckte Höhlen, Kletterwege,
Gräber, Notizen, Geister, Sammelkram, Folianten), **erzählende Umgebung**. Mit den ersten
Lore-Texten kommt die **Text-Tabelle Deutsch/Englisch** mit Sprachwahl; ab da ist jeder neue
Spielertext zweisprachig.
**Entscheidungen des Spielers (2026-10-01):**
- **3 Unter-Biome:** das verlassene Dorf (Westreach, Stufe 2), der verbrannte Wald (Nordwesten,
  Stufe 3), das Knochenfeld (Emberfall Ridge, Stufe 3). Süden, Mitte und Cinder Flats bleiben
  Asche mit Raidern.
- **2 neue Gegnertypen je Familie** (6 Gegner, eigene Rigs, Sounds und Mechaniken).
- **Tiere sind Kulisse** (fliehen oder schauen zu, nie angreifbar, lokal je Maschine).
- **Essen wird gesammelt** (Sammelstellen, Camp-Kochtöpfe, Ylva). Es heilt nur außerhalb des
  Kampfs, etwa 50 % über 8 s; ein Treffer bricht ab; bis zu 10 im Gepäck.
- **Ein Foliant** lehrt jede Klasse ihre neue Fähigkeit (3 neue).
- **Alle vier Rätselarten draußen:** Feuerschalen, Felsbrocken, Runensteine, Dodge-Lauf.
- **Prüfungs-Schreine:** Kampfwelle mit Bedingung, Lohn ein dauerhafter Runensegen plus XP.
- **Sprache:** nur die neuen Texte zweisprachig (Menüs und HUD bis M14 Englisch), der erste
  Start folgt der Systemsprache; Settings → Gameplay → Language.

Phasen: 0 Text-Tabelle + Sprachwahl + Lesefenster, 1 Layout + Biom-Look + Props + erzählende
Szenen, 2 Interaktion + Lore + Geister + Chronik + Splitter + Essen, 3 POI-Zustand im Koop + die
vier Rätsel + Grotten + Kletterpfade, 4 Gegner Dorf + Wald, 5 Gegner Knochenfeld + Tiere,
6 Nester + verfluchte Orte + Prüfungs-Schreine, 7 Foliant + 3 Fähigkeiten, 8 Abschluss.
**Stand:** Phase 0 gebaut (Text-Tabelle als JSON, Sprachwahl, Lesefenster). Phase 1 gebaut (drei
Unter-Biome mit eigenem Boden, Wald, Dorf, Knochenfeld-Skelett und erzählenden Szenen; PROTOCOL 13). Phase 2 gebaut
(Lore-Objekte, zwei Geister, Chronik auf L, 12 Runensplitter, Glutknollen als Essen, Fokus-Prompt).

### M13 — Dungeons mit Rätseln
- **Hollow Cistern und Ember Warrens** (die zwei versiegelten Tore der Highlands) werden Dungeons
  mit Fähigkeiten-, Mechanik- und Fallen-Rätseln (meist unter 2 min, pro Dungeon ein größeres für
  ein Geheimnis), Geheimräumen, Abzweigen und Zwischenbossen. Allein und mit jeder Klasse lösbar.
- **Der erste Koop-Dungeon:** für 3–5 Spieler, solo gesperrt, eigener Loot, Rollen zählen (ohne
  Tank oder Heiler wird es deutlich schwerer).

### M14 — Story & RPG
- NPCs mit Dialog und **Antwortoptionen** (meist Geschmack: andere Reaktion, kleine Belohnung, ein
  Extra-Satz), Quest-System (Haupt- + Nebenquests, Journal), Story-Bogen um die Shattered Rune
  über Hub und Zonen; Sigrun bekommt als Erste eine Geschichte.
- **Meta-Würze** nach STORY_DESIGN: seltene, explizite Brüche, selbstironisch-liebevoll.
- Die bestehende UI wird zweisprachig nachgezogen; Händler (Gold-Senke: Tränke, Reparatur,
  Umskillen kostet später Gold?).

### M15 — Open World II: zwei weitere Zonen
Mit der M08-Technik und dem M12-Muster: zwei neue Regionen mit eigener Identität (Palette,
Unter-Biome, Gegnerfamilien), je ein Dungeon + Boss. Alles von Anfang an im Koop gebaut und
getestet.

### M16 — Endgame: Shattered Expeditions
Wiederholbare 10–20-min-Runs (Koop): prozedurale Encounter aus Kit und Zonen, Difficulty-Tiers mit
Mechanik-Eskalation, Risk/Reward-Modifier, Ziel-Loot. Setzt Cap, Talente und Klassen voraus.

### M17 — Release-Politur
Hauptmenü, Settings (Rebinding, Sensitivity, Shake/Flash, Damage-Number-Optionen) sind als M17a
vorgezogen; hier bleiben Accessibility,
Performance-Pass auf Zielhardware (Server-Laptop + Clients), Balancing-Runde, Bugfest, Server-Setup-
Anleitung.

## Prinzip bleibt
Jeder Meilenstein endet mit Smoke-Tests grün + Capture-Review + deinem Playtest als Gate. Zahlen sind
Daten und werden nach deinem Feedback getunt, nicht vorher diskutiert. Jeder Meilenstein bekommt
vor dem Bau seinen eigenen Plan mit Rückfragen.
