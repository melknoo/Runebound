## Download
- **Installer:** `Runebound-{VERSION}-setup.exe` – installiert ohne Adminrechte nach `%LOCALAPPDATA%\Programs\RUNEBOUND`, mit Startmenü-Eintrag und Deinstallation.
- **Ohne Installation:** `Runebound-{VERSION}-windows.zip` entpacken und `Runebound.exe` starten.

Spielstände bleiben bei Updates erhalten (`%APPDATA%\Godot\app_userdata\RUNEBOUND`). Online spielen geht mit Servern, die Netzprotokoll **{PROTOCOL}** sprechen – die mittlere Zahl der Version.

## Windows-Warnung
Das Spiel hat keine kostenpflichtige Code-Signatur. Windows SmartScreen meldet deshalb „Der Computer wurde durch Windows geschützt“: **Weitere Informationen → Trotzdem ausführen**.

## Woher die Dateien kommen
Gebaut ausschließlich von GitHub Actions aus dem öffentlichen Quellcode, Commit [`{SHORT_SHA}`](https://github.com/{REPO}/commit/{SHA}) ([Build-Protokoll]({RUN_URL})). Verwendet werden nur offizielle Werkzeuge mit festgeschriebenen Prüfsummen ([tools/dist/pins.json](https://github.com/{REPO}/blob/{SHA}/tools/dist/pins.json)): die Godot-Engine 4.6.3 und Inno Setup.

Selbst prüfen (optional):
- Prüfsumme: `Get-FileHash Runebound-{VERSION}-setup.exe` in PowerShell, der Wert muss in `SHA256SUMS.txt` stehen.
- Herkunft: `gh attestation verify Runebound-{VERSION}-setup.exe --repo {REPO}` (GitHub CLI) bestätigt, dass genau diese Datei von diesem Repository gebaut wurde.

## Änderungen{SINCE}
{CHANGES}
