# RUNEBOUND — Roadmap

Stand: 2026-09-25 · M01–M09 gebaut (M07/M07b abgenommen am 24.09., M08 angespielt: kleine Notizen
folgen nach M09). **M09 Co-op ist gebaut und mit einem Freund angespielt.** Server-Laptop steht
(`docs/SERVER_SETUP.md`), gemessen: 4 kämpfende Spieler bei 60 Hz mit Reserve. **M09b (Freunde
ohne Tailscale) läuft.**

## Nordstern (aktualisiert 2026-09-24)
RUNEBOUND wird ein **Koop-Action-RPG für 2–5 Spieler** in einer stilisierten Pixel-Fantasy-Welt:
eigener Charakter mit Klasse, Fähigkeiten, die gelernt statt geschenkt werden, Gold, Talente und
Loot; eine kleine, gut erzählte Story mit Dungeons, Bossen und Rätseln, die man zusammen löst.
Gehostet auf einem eigenen dedizierten Server (Linux-Laptop zuhause). Kein MMO.
Singleplayer bleibt jederzeit vollständig spielbar.

## Warum die Reihenfolge so ist
- **Fundament vor Welt:** Koop und mehrere Klassen kosten wenig, wenn die Nahtstellen früh sitzen
  (Klasse als Daten, Angreifer im Treffer, Spieler-Registry, Save-Split), und sehr viel, wenn die
  offene Welt erst auf „ein Spieler, eine Klasse" gebaut wird.
- **Koop vor weiteren Zonen:** die zweite und dritte Zone sollen das Mehrspieler-Muster kopieren,
  nicht das alte.
- **Story nach Koop:** Rätsel und Quests brauchen im Koop andere Regeln (geteilter Fortschritt,
  wer löst was). Erst wenn die stehen, lohnt sich Story-Content.
- **Feel vor Content** bleibt: jeder Meilenstein endet mit Smoke grün + Captures + deinem Playtest.

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
3. Dienst + Funnel (Skript gebaut, Lauf auf dem Laptop offen).
4. Doku, Freunde einladen, Gate: Ein Freund spielt ohne Tailscale.
Nicht in M09b: direktes UDP per Hole-Punching (nur falls Funnel zu langsam ist), IPv6 direkt,
Accounts.

### M08 — Open World I: Ashen Highlands, offen (angespielt; Notizen folgen nach M09)
Sichtbar:
- **Heightmap-Terrain 384 × 384 m** aus einem deklarativen Layout gebacken (`tools/worldgen`):
  Südhänge → Nordplateau, Randgebirge, Grate mit Felsen, eingeschnittene Trampelpfade, flache
  Kampf-Pads unter jedem POI. Kamera-Far 560 m, Dunst am Rand.
- **32 POIs an fünf Routen** (alle 50–80 m): 8 Camps, 2 Hinterhalte (Pack erscheint um den
  Spieler), 1 Elite-Patrouille, 3 Ruinen mit Truhen, 4 freie Truhen, 5 Wegpunkt-Schreine,
  Landmarken, 2 versiegelte Dungeon-Tore (Platzhalter für M10/M11), Colossus-Arena. Level-Bänder
  Süd 1 / Mitte 2 / Nord + Emberfall Ridge 3.
- **Camps leben:** gecleart → im Save gemerkt → nach ~10 min wieder da, aber nie, solange ein Held
  in 45 m steht. Camp-Gegner haben eine Leine (gehen heim und heilen).
- **Wegpunkte + Schnellreise:** Schrein berühren = attunen (+40 XP), `[E] Travel` listet Runehold
  und alle attunten Schreine; Tore setzen dich vor das Tor, durch das du kamst; Tod = zurück zum
  nächsten attunten Schrein. Runehold hat seinen eigenen Schrein.
- **Kompass** oben im HUD und **Karte auf M** mit allem, was der Charakter gesehen hat.
Unsichtbar: Boden-Seam (nichts kodiert mehr y = 0), `EncounterSpawner` v2, `EnemyBase.RETURN`,
SaveGame v4, `WaypointRegistry`, Ankunfts-Hints, Runner-Positionen per POI-ID.
Angespielt vom Spieler; seine kleinen Notizen werden direkt nach M09 umgesetzt. Offen: KNOWN_ISSUES
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

### M10 — Open World II: zwei weitere Zonen
Mit der M08-Technik: zwei neue Regionen mit eigener Identität (Palette, Gegnerfamilie, Wetter),
je ein Dungeon + Boss. Alles von Anfang an im Koop gebaut und getestet.

### M11 — Story & RPG
- NPCs mit Dialog (Sigrun bekommt als Erste eine Geschichte), Quest-System (Haupt- + Nebenquests,
  Journal), Story-Bogen um die Shattered Rune über Hub und drei Zonen.
- **Koop-Rätsel** in den Dungeons (Platten, Runen-Sequenzen, geteilte Mechaniken), die allein
  lösbar bleiben.
- Mehr Dungeons (klein, 10–15 min) und Boss-Varianten; Händler (Gold-Senke: Tränke, Reparatur,
  Umskillen kostet später Gold?).

### M12 — Zweite Klasse
Erste echte Nutzung der ClassData-Seams: eine zweite Klasse mit eigenem Kit (6 Fähigkeiten +
2 Talent-Unlocks), Rig, Talentbaum (3 Äste), klassen-eigenen Affixen/Legendaries, Trainer-Angebot.
Charakterwahl-/Erstell-Screen, mehrere Charaktere pro Save. Weitere Klassen danach nach demselben
Muster.

### M13 — Endgame: Shattered Expeditions
Wiederholbare 10–20-min-Runs (Koop): prozedurale Encounter aus Kit und Zonen, Difficulty-Tiers mit
Mechanik-Eskalation, Risk/Reward-Modifier, Ziel-Loot. Setzt Cap, Talente und Klassen voraus.

### M14 — Release-Politur
Hauptmenü, Settings (Rebinding, Sensitivity, Shake/Flash, Accessibility), Damage-Number-Optionen,
Performance-Pass auf Zielhardware (Server-Laptop + Clients), Balancing-Runde, Bugfest, Server-Setup-
Anleitung.

## Prinzip bleibt
Jeder Meilenstein endet mit Smoke-Tests grün + Capture-Review + deinem Playtest als Gate. Zahlen sind
Daten und werden nach deinem Feedback getunt, nicht vorher diskutiert. Die Reihenfolge M09 ↔ M10 ist
tauschbar, wenn dir Content wichtiger ist als früher Koop — sag Bescheid.
