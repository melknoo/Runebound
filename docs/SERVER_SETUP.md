# RUNEBOUND — Server-Laptop

Stand: 2026-09-25 (M09b). Der Laptop zuhause ist der dedizierte Koop-Server.
Er baut nichts, sondern zieht per `git pull` von `main`. Freunde erreichen ihn
**ohne Tailscale** über Tailscale Funnel und kommen nur mit einem persönlichen
Einladungscode herein. Du selbst verwaltest den Laptop weiter über Tailscale
(SSH).

## Wie Freunde reinkommen
```
Freund ──HTTPS/WebSocket──▶ Funnel-Relais ──Tailscale (vom Laptop aufgebaut)──▶ Laptop
Du (im Tailnet) ──────── dieselbe Adresse, direkt übers Tailnet ───────────────▶ Laptop
                         Laptop: tailscaled :443 → 127.0.0.1:7780 → Spielserver
```
- **Warum Funnel:** Starlink lässt von außen nichts rein. IPv4 läuft über CGNAT, und der Router blockt eingehendes IPv6 ohne Einstellmöglichkeit. Funnel gibt dem Laptop unter seinem `.ts.net`-Namen eine öffentliche HTTPS-Adresse. Die Verbindung dorthin baut der Laptop selbst nach außen auf. Funnel ist im Gratis-Plan von Tailscale enthalten.
- **Funnel kann nur TCP**, deshalb spricht der Server WebSocket (`RUNEBOUND_TRANSPORT=ws`) auf `127.0.0.1:7780`. tailscaled beendet TLS auf dem Laptop und reicht die Verbindung dorthin weiter.
- **Einladungscodes:** Wer keinen gültigen Code hat, wird im Handshake abgewiesen, bevor der Server irgendetwas von ihm liest. Details stehen in TECHNICAL_ARCHITECTURE „Access (M09b)“.
- **Die Adresse** ist dieselbe für alle: der MagicDNS-Name des Laptops. `tailscale funnel status` zeigt ihn an. Im Spiel trägt man sie ohne Port ein; ein Name ohne Port bedeutet dort WebSocket über HTTPS. Aus deinem Tailnet geht die Verbindung direkt, ohne Relais.

## Einrichtung (einmalig)
1. **Tailscale-Admin-Konsole:**
   - DNS → **HTTPS Certificates** aktivieren.
   - **Funnel** für den Laptop freischalten (Policy-Attribut `funnel`).
   - Beim Laptop **„Disable key expiry“** wählen.
2. **Auf dem Laptop:** `sudo tailscale set --operator=melvin`. Danach darf `melvin` Funnel ohne sudo steuern, auch per SSH vom Dev-PC aus.
3. **Umzug auf den abgeschotteten Dienst:**
   ```bash
   cd ~/Repositories/Runebound && git pull
   sudo tools/server/setup-service.sh
   ```
   Das Skript ist wiederholbar und erledigt Folgendes:
   - legt den Systembenutzer `runebound` an (ohne Passwort, ohne Login, ohne sudo/docker)
   - legt dessen Klon `/var/lib/runebound/Runebound` per HTTPS an (das Repo ist öffentlich, auf dem Server liegt kein Key)
   - kopiert Godot nach `/opt/godot`
   - legt `/etc/runebound/invites` an
   - installiert die Units `runebound-update` und `runebound-server`
   - übernimmt den Welt-Save
   - entfernt die alte 7777/udp-Regel
   - startet den Server
   - schaltet Funnel ein
4. **Codes anlegen:** `tools/server/invites.sh add melvin`, `tools/server/invites.sh add anna` und so weiter.

## Einladungscodes
```bash
tools/server/invites.sh add NAME      # neuer Code, wird einmal angezeigt
tools/server/invites.sh show NAME     # Code noch mal anzeigen
tools/server/invites.sh rotate NAME   # neuer Code, der alte gilt sofort nicht mehr
tools/server/invites.sh remove NAME   # zurückziehen (ist NAME online, fliegt er raus)
tools/server/invites.sh list          # wer hat einen Code (ohne Codes)
```
- Die Liste ist `/etc/runebound/invites` und gehört dir, der Server kann sie nur lesen. Sie kommt nie ins Repo.
- Der Server liest sie alle 2 s neu, Änderungen wirken sofort. Das Journal zeigt `invites: N loaded`.
- Ein Code hat 16 Zeichen (80 Bit). Raten ist aussichtslos. Groß-/Kleinschreibung, Bindestriche und 0/O bzw. 1/I sind beim Eintippen egal.
- **Ein Code ist geleakt:** `invites.sh rotate NAME` und dem Freund den neuen Code schicken. Wer mit dem alten spielt, fliegt innerhalb von 2 s.
- Meldet sich derselbe Code ein zweites Mal an, fliegt die ältere Sitzung.

## Für Freunde (zum Weiterleiten)
> **RUNEBOUND mitspielen:**
> 1. Godot **4.6.x** installieren (godotengine.org, „Standard“, nicht .NET).
> 2. Das Spiel holen: `git clone https://github.com/melknoo/Runebound.git` oder auf GitHub „Code → Download ZIP“. Danach in Godot den Ordner importieren und starten (F5).
> 3. Im Titel „Join co-op“ wählen und diese drei Dinge eintragen:
>    - deinen Namen
>    - als Server die Adresse, die ich dir schicke (ohne Port)
>    - deinen Einladungscode
>
>    Das Spiel merkt sich alles.
> 4. Den Code nicht weitergeben, er gehört nur dir.

## Was ist von außen erreichbar?
- **Nur die Funnel-Adresse** (HTTPS über die Tailscale-Relais). Dahinter liegt nur der Spielserver auf `127.0.0.1:7780`.
- **Am Router und am Laptop ist kein Port offen.** ufw: eingehend alles verboten außer 22/tcp auf `tailscale0` (SSH für dich).
- **Die Heim-IP bleibt verborgen.** Freunde sehen nur die Relais von Tailscale.
- **Der Spielserver** läuft als `runebound` in einer systemd-Sandbox (`systemd-analyze security runebound-server`: 1,3 „OK“, vorher 9,2 „UNSAFE“):
  - Netz nur zu localhost, System schreibgeschützt, keine Home-Verzeichnisse, keine Rechte.
  - Schreiben darf er nur in `/var/lib/runebound`.
  - Er kommt weder an deinen GitHub-Key noch an docker oder sudo, noch in dein LAN.
- **Das Update** (`runebound-update`: git pull + Import) läuft vor jedem Start im selben Benutzer. Es darf zu GitHub, ist sonst genauso abgeschottet.
- **Restrisiken:**
  - Die Funnel-Adresse ist öffentlich auffindbar (über die Zertifikats-Logs). Scanner treffen dann auf den Einladungs-Handshake.
  - Andere Dienste auf dem Laptop, die auf localhost lauschen (zum Beispiel `:3000`), wären für den Spielserver erreichbar.
  - Funnel hängt am Gratis-Angebot von Tailscale.

## Ist-Zustand

| | |
|---|---|
| Hardware | Acer Aspire E5-573G, Intel Pentium 3556U (2 Kerne, 1,7 GHz), 7,7 GiB RAM, 219 GB SSD, Akku BAT1 |
| Netz | nur WLAN `wlp3s0`, Ethernet ungenutzt. Die WLAN-Verbindung ist systemweit (verbindet ohne Login) |
| System | Linux Mint 22.2 Xfce, Kernel 6.8, systemd 255 |
| Starlink | Residential: CGNAT (kein eingehendes IPv4), der Router blockt eingehendes IPv6 → Funnel |
| Godot | Dienst: `/opt/godot/godot` (Kopie). Tests: `~/godot/godot` → `Godot_v4.6.3-stable_linux.x86_64` (SHA512 gegen die offizielle Liste geprüft) |
| Klone | Dienst: `/var/lib/runebound/Runebound` (Benutzer `runebound`, HTTPS). Deiner: `~/Repositories/Runebound` (Tests, Werkzeuge, SSH-Key) |
| Tailscale | MagicDNS-Name des Laptops, Tailscale SSH an, Funnel `https://<name>` → `127.0.0.1:7780` |
| Dienste | `runebound-update` (oneshot vor jedem Start) + `runebound-server` (enabled, startet beim Boot) |
| Firewall | ufw: eingehend deny, ausgehend allow. Erlaubt nur 22/tcp auf `tailscale0` |
| Dauerbetrieb | Deckel ignoriert (logind-Drop-in `/etc/systemd/logind.conf.d/runebound.conf`), `IdleAction=ignore`, sleep/suspend/hibernate/hybrid-sleep maskiert |
| Updates | Mint-Auto-Updates aus, unattended-upgrades nicht installiert → **kein automatischer Neustart** |

## Dateien (`tools/server/`)
- **`setup-service.sh`:** die einmalige Einrichtung (siehe oben), wiederholbar.
- **`invites.sh`:** verwaltet die Einladungscodes.
- **`runebound-server.sh update | start`:** `update` macht `git fetch` und `pull --ff-only` und importiert, wenn sich Projektdateien geändert haben. Ohne Netz startet der Server mit dem bisherigen Stand. `start` ersetzt sich durch `godot --headless … $RUNEBOUND_SCENE`.
- **`runebound-update.service` / `runebound-server.service`:** die Units. Sie werden **kopiert**, nicht verlinkt, damit ein `git pull` keine root-geladene Unit still ändert.
- **`server.env`:** `RUNEBOUND_TRANSPORT=ws`, `RUNEBOUND_PORT=7780`, `RUNEBOUND_SCENE`, `RUNEBOUND_INVITES` (nur der Pfad).
- **`run_godot.sh import | ensure-import | smoke | net | serverperf | serve`:** das Gegenstück zu `tools/run_godot.ps1`. `GODOT` überschreibt den Godot-Pfad (Default `~/godot/godot`). `serve` nur benutzen, wenn der Dienst gestoppt ist (derselbe Port).
- **`logind-runebound.conf`:** die Vorlage für den logind-Drop-in.

## Bedienung (auf dem Laptop oder per SSH)
```bash
sudo systemctl restart runebound-server    # Update einspielen: holt den Stand, importiert, startet neu
sudo systemctl stop runebound-server       # stoppen
systemctl status runebound-server          # Zustand
journalctl -u runebound-server -f          # Spiel-Log live
journalctl -u runebound-update -n 30       # letztes Update (pull, Import)
tailscale funnel status                    # die öffentliche Adresse
systemd-analyze security runebound-server  # Sandbox-Bewertung
```
- **Units geändert** (nach einem Pull, der `tools/server/*.service` ändert): `sudo tools/server/setup-service.sh` noch einmal laufen lassen.
- **Godot updaten** (immer dieselbe Version wie auf dem Dev-Rechner):
  ```bash
  V=4.6.4-stable   # Beispiel
  cd ~/godot
  curl -LO https://github.com/godotengine/godot/releases/download/$V/Godot_v${V}_linux.x86_64.zip
  curl -LO https://github.com/godotengine/godot/releases/download/$V/SHA512-SUMS.txt
  grep "Godot_v${V}_linux.x86_64.zip" SHA512-SUMS.txt | sha512sum -c
  unzip -o Godot_v${V}_linux.x86_64.zip && chmod +x Godot_v${V}_linux.x86_64
  ln -sfn Godot_v${V}_linux.x86_64 godot && ./godot --headless --version
  sudo ~/Repositories/Runebound/tools/server/setup-service.sh   # kopiert es nach /opt/godot
  ```

## Koop-Betrieb
Der Server hält genau eine Zone (die, in der seine Welt zuletzt war), bis zu 5 Spieler und eine eigene Welt (`/var/lib/runebound/.local/share/godot/app_userdata/RUNEBOUND/runebound_server.json`: Bosse, Camps, Zone). Die Charaktere bleiben auf den Rechnern der Spieler.

**Godot-Version:** Server und Spieler brauchen dieselbe Godot-Hauptversion 4.6, die Patch-Version darf abweichen (das Log vermerkt es). Empfohlen ist überall 4.6.3.

**Update einspielen:** `sudo systemctl restart runebound-server`.
- Alle Spieler fliegen dabei sofort raus und landen mit Begründung im Titel. Ihr Charakter ist gespeichert.
- Spieler brauchen denselben Stand wie der Server. Bei einer anderen Protokoll- oder Godot-Version lehnt der Server mit einer lesbaren Meldung ab.
- Ein manuelles `git pull` im Dienst-Klon ist unnötig. Das Update-Skript importiert immer dann, wenn sich seit dem letzten Import Projektdateien geändert haben (Stempel `.godot/runebound_import.stamp`). Kompilieren Skripte trotzdem nicht, beendet sich der Server mit einer klaren Meldung.

**Log:**
- Alle 60 s eine Zeile: `tick p50 / p95 / max ms | players | enemies (asleep) | WebSocket | refused N`.
- Dazu Beitritte (mit dem Namen der Einladung), Abgänge, Kicks, Gruppenreisen und die Einladungsliste.

**Welt zurücksetzen** (Bosse wieder da, Camps voll, Start im Hub): Dienst stoppen, `runebound_server.json` löschen (`sudo rm`), Dienst starten.

**Tests auf dem Laptop** (in deinem Klon):
- `tools/server/run_godot.sh smoke` (Singleplayer)
- `tools/server/run_godot.sh net` (Koop, Server + Headless-Clients lokal, auch über WebSocket)
- `tools/server/run_godot.sh serverperf 5` (Tick-Kosten)

## Vom Dev-Rechner aus
```powershell
ssh -t melvin@melvin-aspire-e5-573g "sudo systemctl restart runebound-server && journalctl -u runebound-server -n 30 --no-pager"
ssh melvin@melvin-aspire-e5-573g "~/Repositories/Runebound/tools/server/invites.sh add anna"
```
- `-t` braucht es für sudo, weil sudo nach dem Passwort fragt. `invites.sh` braucht kein sudo.
- SSH läuft über Tailscale SSH. Die Policy kann gelegentlich eine Bestätigung im Browser verlangen.
- **Funnel-Messung:** `tools\run_godot.cmd wsspike <name>.ts.net` misst Echo-RTT und Download durch Funnel. Der Laptop braucht dafür `tests/ws_spike.gd -- --serve=7780` statt des Dienstes (TECHNICAL_ARCHITECTURE „Access“).

## Offen / manuell
- **Keine Ladegrenze:** Der Akku kann keine Ladegrenze (`charge_control_end_threshold` fehlt) und steht im Dauerbetrieb auf 100 %. Wer ihn schonen will, nimmt ihn heraus. Dann überbrückt er aber keine Stromausfälle mehr.
- **Nach Stromausfall:** Ein BIOS-„Power on after AC loss“ hat dieser Acer vermutlich nicht. Nach einem Neustart starten Tailscale, Funnel und der Dienst von selbst, ein Login ist nicht nötig.
- **Netzwerk:** Nur WLAN. Ein LAN-Kabel am Router wäre stabiler. Optional das WLAN-Powersave abschalten (`wifi.powersave = 2` in NetworkManager).
- **Aus dem LAN gesperrt:** sshd :22 und die `web-ui.js` auf :3000 sind aus dem LAN nicht erreichbar (bewusst).
- **Docker:** Von Docker veröffentlichte Container-Ports umgehen ufw. Heute laufen keine Container.
- **System-Updates** laufen manuell: `sudo apt update && sudo apt upgrade`, danach selbst neu starten, wenn nötig.
- **Die alte Unit** (Benutzer `melvin`, Klon in deinem Home) ersetzt `setup-service.sh`. Dein Klon bleibt für Tests und Werkzeuge.
