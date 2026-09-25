# RUNEBOUND — Server-Laptop

Stand: 2026-09-25. Der Laptop zuhause ist das Deployment-Ziel für den dedizierten
Server (M09). Er baut nichts, sondern zieht per `git pull` von `main`.
Erreichbar ist er vorerst über Tailscale. Nichts im Server hängt an Tailscale
außer der Firewall-Regel.

## Ist-Zustand

| | |
|---|---|
| Hardware | Acer Aspire E5-573G, Intel Pentium 3556U (2 Kerne, 1,7 GHz), 7,7 GiB RAM, 219 GB SSD (141 GB frei), Akku BAT1 |
| Netz | nur WLAN `wlp3s0` (192.168.1.184), Ethernet `enp2s0` ungenutzt. Die WLAN-Verbindung ist systemweit (verbindet ohne Login) |
| System | Linux Mint 22.2 Xfce, Kernel 6.8.0-138, systemd 255 |
| Godot | `~/godot/godot` → `~/godot/Godot_v4.6.3-stable_linux.x86_64`, `4.6.3.stable.official.7d41c59c4` (SHA512 gegen die offizielle `SHA512-SUMS.txt` geprüft) |
| Repo | `/home/melvin/Repositories/Runebound`, Branch `main` |
| Smoke-Test | 373 ok / 0 failures, ca. 53 s. Import headless ca. 13 s, ohne Fehler |
| Starlink IPv4 | extern `145.224.72.22`. Die WAN-IP des Routers ist nicht auslesbar (Hop 2 antwortet nicht) → **vermutlich CGNAT**, noch unbestätigt |
| Starlink IPv6 | **globale IPv6 vorhanden** (`2a0d:3341:b123:ff08::/64`), ausgehend ok. Eingehend ungetestet |
| Tailscale | `100.101.57.51`, MagicDNS **`melvin-aspire-e5-573g.tail94658b.ts.net`**, Tailscale SSH an |
| netcheck | UDP ok, `MappingVariesByDestIP: false` (Hole-Punching klappt), kein Port-Mapping, DERP Frankfurt/Warschau. Der Dev-PC verbindet **direkt** (LAN), nicht über das Relay |
| Spiel-Port | **7777/udp** (`tools/server/server.env`) |
| Dienst | `runebound-server.service` installiert, **disabled** (enable erst nach M09) |
| Firewall | ufw: eingehend deny, ausgehend allow. Erlaubt nur auf `tailscale0`: 22/tcp, 7777/udp |
| Dauerbetrieb | Deckel ignoriert (logind-Drop-in `/etc/systemd/logind.conf.d/runebound.conf`), `IdleAction=ignore`, sleep/suspend/hibernate/hybrid-sleep maskiert. Xfce: nie schlafen, Deckel = nichts, Bildschirm aus nach 10/15 min |
| Updates | Mint-Auto-Updates aus, unattended-upgrades nicht installiert → **kein automatischer Neustart** |

## Dateien (`tools/server/`)
- `run_godot.sh import | smoke | serve` ist das Gegenstück zu `tools/run_godot.ps1`.
  - `GODOT` überschreibt den Godot-Pfad (Default `~/godot/godot`).
  - `smoke`-Exit-Codes: 3 = 8-min-Limit überschritten, 2 = Watchdog des Tests (300 s), 1 = `SCRIPT ERROR`/`Parse Error` im Output, sonst der Godot-Exit-Code.
- `server.env` enthält `RUNEBOUND_PORT=7777` und `RUNEBOUND_SCENE`. Seit M09 Phase 1 zeigt die Szene auf den echten Server (`res://scenes/dedicated_server.tscn`). Er hat seinen eigenen Welt-Save `~/.local/share/godot/app_userdata/RUNEBOUND/runebound_server.json` und loggt alle 60 s Tick-Zeiten, Spieler, Gegner und Traffic.
- `run_godot.sh net [szenario]` startet die Mehrprozess-Koop-Tests (Server + Headless-Clients) auch auf dem Laptop, `run_godot.sh serverperf [helden]` misst die Tick-Kosten.
- `runebound-server.sh` lädt `server.env` und prüft per `git fetch` auf neue Commits. Gibt es welche, verwirft es den Linux-Import-Churn in `.godot/`, macht `git pull --ff-only` und importiert neu. Schlägt der Pull fehl, bricht es laut ab. Danach startet es `exec godot --headless … $RUNEBOUND_SCENE`, den Port reicht es als Umgebungsvariable durch.
- `runebound-server.service` ist die systemd-Unit. Sie ist **kopiert**, nicht verlinkt, damit ein `git pull` eine root-geladene Unit nicht still ändert.
- `logind-runebound.conf` ist die Vorlage für den logind-Drop-in.

## Bedienung (auf dem Laptop oder per SSH)
```bash
sudo systemctl start runebound-server      # starten (pullt + importiert vorher)
sudo systemctl stop runebound-server       # stoppen
sudo systemctl restart runebound-server    # Update einspielen = neu starten
systemctl status runebound-server          # Zustand
journalctl -u runebound-server -f          # Log live
journalctl -u runebound-server -b          # Log seit dem Boot
```
- **Update:** Der Pull passiert beim Start, `restart` reicht also. Seit M09 Phase 1 läuft danach der echte Server dauerhaft (bis `stop`). Koop ist aber erst mit M09 Phase 3+ spielbar.
- **Nach M09:** `sudo systemctl enable --now runebound-server` (die Szene ist schon umgestellt). Bis dahin startet der Dienst nur von Hand.
- **Unit geändert:**
  ```bash
  sudo install -m 644 tools/server/runebound-server.service /etc/systemd/system/
  sudo systemctl daemon-reload
  ```
- **Smoke-Test von Hand:** `tools/server/run_godot.sh smoke; echo $?` (0 = grün).
- **Godot updaten** (immer exakt die Version des Dev-Rechners):
  ```bash
  V=4.6.4-stable   # Beispiel
  cd ~/godot
  curl -LO https://github.com/godotengine/godot/releases/download/$V/Godot_v${V}_linux.x86_64.zip
  curl -LO https://github.com/godotengine/godot/releases/download/$V/SHA512-SUMS.txt
  grep "Godot_v${V}_linux.x86_64.zip" SHA512-SUMS.txt | sha512sum -c
  unzip -o Godot_v${V}_linux.x86_64.zip && chmod +x Godot_v${V}_linux.x86_64
  ln -sfn Godot_v${V}_linux.x86_64 godot && ./godot --headless --version
  cd ~/Repositories/Runebound && tools/server/run_godot.sh import && tools/server/run_godot.sh smoke
  ```

## Koop-Betrieb (ab M09)
Der Server ist seit M09 ein echtes Spiel: `RUNEBOUND_SCENE` startet `res://scenes/dedicated_server.tscn`. Er hält genau eine Zone (die, in der seine Welt zuletzt war), bis 5 Spieler und eine eigene Welt (`~/.local/share/godot/app_userdata/RUNEBOUND/runebound_server.json`: Bosse, Camps, Zone). Die Charaktere bleiben auf den Rechnern der Spieler.

**Einschalten (einmalig):**
```bash
sudo systemctl enable --now runebound-server
journalctl -u runebound-server -f      # "listening on *:7777/udp ..." und die Zone
```
Danach startet er bei jedem Boot selbst und holt vorher den neuesten Stand (`git pull` + Import).

**Update einspielen:** `sudo systemctl restart runebound-server`. Alle Spieler fliegen dabei sofort raus (der Server meldet sich sauber ab) und landen mit Begründung im Titel; ihr Charakter ist gespeichert. Spieler brauchen denselben Stand wie der Server: Bei anderer Protokoll- oder Godot-Version lehnt der Server mit einer lesbaren Meldung ab („Version mismatch ... git pull“).

**Log:** Alle 60 s eine Zeile `tick p50 / p95 / max ms | players | enemies (asleep) | out / in KB/s`, dazu Beitritte, Abgänge, Gruppenreisen.

**Welt zurücksetzen** (Bosse wieder da, Camps voll, Start im Hub): Dienst stoppen, `runebound_server.json` löschen, Dienst starten.

**Spielen:** Im Titel „Join co-op“ → Name → `melvin-aspire-e5-573g.tail94658b.ts.net` (Port 7777 ist Standard). Die Adresse wird gemerkt.

**Tests auf dem Laptop:** `tools/server/run_godot.sh smoke` (Singleplayer), `tools/server/run_godot.sh net` (Koop, Server + Headless-Clients lokal), `tools/server/run_godot.sh serverperf 5` (Tick-Kosten).

## Vom Dev-Rechner aus
```powershell
ssh -t melvin@melvin-aspire-e5-573g "sudo systemctl restart runebound-server && journalctl -u runebound-server -n 30 --no-pager"
```
`-t`, weil sudo nach dem Passwort fragt. SSH läuft über Tailscale SSH. Die Tailscale-Policy kann gelegentlich eine Bestätigung im Browser verlangen.

## Freunde (über Tailscale)
1. Ich teile den Laptop (einmalig in der [Tailscale-Admin-Konsole](https://login.tailscale.com/admin/machines)):
   - **Machines** → Zeile `melvin-aspire-e5-573g` → Menü **„…“** → **Share…** → Einladung per E-Mail oder Link kopieren und dem Freund schicken.
   - Im selben Menü **„Disable key expiry“**, sonst fliegt der Laptop am 2026-12-31 aus dem Tailnet.
2. Der Freund installiert Tailscale (tailscale.com/download), meldet sich an und nimmt die Einladung an.
3. Im Spiel `melvin-aspire-e5-573g.tail94658b.ts.net:7777` eintragen. Löst der Name nicht auf, geht auch `100.101.57.51:7777`.

Geteilte Nutzer sehen nur diesen einen Rechner und können sich nicht per SSH anmelden. Die Firewall lässt über Tailscale ohnehin nur 22/tcp und 7777/udp durch.

## Später: nativ ohne Tailscale
Für den Wechsel ändern sich nur zwei Dinge:
- **im Client** die Serveradresse (Hostname),
- **auf dem Laptop** eine zusätzliche ufw-Regel.

`runebound-server.sh`, der Dienst und der Port bleiben gleich.

- **(a) Kleiner VPS mit WireGuard-Tunnel zum Laptop, der 7777/udp weiterleitet.**
  - Vorteil: feste öffentliche IPv4 für alle Freunde, ohne App, unabhängig von Starlink-CGNAT. Kostet ca. 4–5 €/Monat.
  - Nachteil: ein zusätzlicher Hop (etwas mehr Latenz), und man muss einen VPS pflegen.
  - Zusatzregel: `sudo ufw allow in on wg0 to any port 7777 proto udp`.
- **(b) Starlink-Tarif mit öffentlicher IPv4.**
  - Vorteil: keine zusätzliche Infrastruktur, direkte Verbindung mit der geringsten Latenz.
  - Nachteil: teurerer Tarif. Die IP kann trotzdem wechseln, dann braucht es einen Namen dafür.
  - Zusatzregel: `sudo ufw allow in on wlp3s0 to any port 7777 proto udp`, dazu eine Portweiterleitung im Router.
- **(c) IPv6 direkt** (eine globale IPv6 ist vorhanden, siehe oben).
  - Vorteil: kostenlos und ohne Weiterleitung.
  - Nachteil: Jeder Freund braucht selbst funktionierendes IPv6. Das Starlink-Präfix kann wechseln. Ob der Starlink-Router eingehendes IPv6 durchlässt, ist ungetestet.
  - Zusatzregel wie bei (b), sie gilt für IPv4 und IPv6.

**Anforderungen an M09:**
- Die Serveradresse im Spiel ist ein Textfeld mit „zuletzt benutzt“. Keine feste IP und kein fester Hostname im Code.
- Der Port ist Default 7777, im Feld mit `host:port` änderbar.
- Der Server liest `RUNEBOUND_PORT` und bindet auf alle Interfaces (`*`, IPv4 + IPv6), nicht auf die Tailscale-IP.

## Offen / manuell
- **Tailscale-Admin-Konsole:** den Laptop teilen und die Key-Expiry abschalten (siehe oben).
- **CGNAT bestätigen:** Starlink-App → Einstellungen → Router → Erweitert / Debug-Daten → WAN-IPv4. Eine Adresse in `100.64.0.0/10` bedeutet CGNAT.
- **Firewall-Regeln einmal ansehen:** `sudo ufw status verbose`. Erwartet werden zwei ALLOW-Regeln auf `tailscale0` (v4 + v6).
- **Keine Ladegrenze:** Der Akku kann keine Ladegrenze (`charge_control_end_threshold` fehlt) und steht im Dauerbetrieb auf 100 %. Wer ihn schonen will, lässt ihn einmal auf ~80 % laufen und zieht dann den Stecker nur kurz, oder nimmt ihn raus (der Akku überbrückt dann aber keine Stromausfälle mehr).
- **Nach Stromausfall:** Ein BIOS-„Power on after AC loss“ hat dieser Acer vermutlich nicht. Nach einem Neustart starten Tailscale und (nach M09) der Dienst von selbst, einen Login braucht es nicht.
- **Netzwerk:** Nur WLAN. Ein LAN-Kabel am Router wäre stabiler und hätte weniger Latenz-Spitzen. Optional das WLAN-Powersave abschalten (`wifi.powersave = 2` in NetworkManager).
- **Aus dem LAN gesperrt:** sshd :22 und die `web-ui.js` auf :3000 sind aus dem LAN nicht mehr erreichbar (bewusst). Bei Bedarf: `sudo ufw allow in on tailscale0 to any port 3000 proto tcp`.
- **Docker:** Von Docker veröffentlichte Container-Ports umgehen ufw. Heute laufen keine Container.
- **`.godot/` ist seit M09 nicht mehr im Repo** (`.gitignore`). Der erste Pull danach löscht die getrackten Cache-Dateien, der anschließende Import baut sie neu (einmalig ca. 15 s). `runebound-server.sh` verwirft Import-Churn nur noch, falls noch getrackte Kopien existieren. `.gitattributes` hält die Server-Dateien auf LF.
- **System-Updates** laufen manuell: `sudo apt update && sudo apt upgrade`, danach selbst neu starten, wenn nötig.
