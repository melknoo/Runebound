# RUNEBOUND — Handoff: von einem anderen Rechner weiterarbeiten

Stand: 2026-10-09 · Commit `f2da9a6` (`main` = `release` = GitHub). Für dich und für Claude auf dem zweiten Rechner. Claude lädt `CLAUDE.md` im Repo-Root von selbst, die Regeln und das Know-how stehen dort und in `docs/dev-notes/`.

## 1. Status
**Gebaut:** M01–M08, M09 Co-op, M09b (Funnel + Einladungscodes, am 2026-09-28 eingerichtet), M10 Tank + Elementar-Magier + Loadout, M10b Heiltränke, M11 Wurzel-Druide, M17a Menüs & Einstellungen (vorgezogen), M12 Highlands mit Substanz (gebaut 2026-10-02). Letzter Smoke-Lauf: 690 Checks grün (2026-10-02).

**Gates (liegen bei dir, alle offen):** Playtest M10 + M10b, M11, M12, M17a. Je ein „Gate walk“ in `docs/PROJECT_STATE.md`, im Spiel die Liste auf Taste **J**. Dazu das M09b-Gate: ein Freund spielt ohne Tailscale.

**Offene Probleme** (Details `docs/KNOWN_ISSUES.md`):
- Client-Crash nach Zonenwechsel in die Highlands auf dem RTX-2070-PC (Godot 4.6.1, Black Screen, Signal 11). Retest mit exakt 4.6.3 und frischem `.godot/` steht aus.
- Solo-Check L6 nach M12: Runebreaker 13–14 von 16 Kämpfen (stirbt an Ruine 3, Colossus knapp), Druide 15/16, Elementar-Magier 16/16.
- Net-Suite: `heal`, `handshake@ws`, `travel@ws` stürzen bei wenig freiem RAM ab, einzeln laufen sie grün.

**Server:** `release` steht auf `main` (Protokoll 13). Das Server-Journal vom 2026-10-02 zeigt Join und Zonenwechsel sauber. Heutiger Stand ungeprüft (ssh vom Haupt-PC lief am 2026-10-09 in ein Timeout: Tailscale aus oder Laptop aus).

**Wie es weitergeht:**
1. Playtest-Feedback einsammeln (die J-Liste liegt als `playtest.json` auf deinem Spiel-PC) und fixen.
2. RTX-2070-Retest (siehe Stufe B unten).
3. **M13 Dungeons mit Rätseln:** Hollow Cistern und Ember Warrens, danach der erste Koop-Dungeon (3–5 Spieler, solo gesperrt). Wie jeder Meilenstein: erst Plan mit Rückfragen an dich.
4. M14 Story & RPG (Dialoge, Quests, Meta-Würze, UI zweisprachig), M15 zwei weitere Zonen, M16 Endgame, M17 Politur.

Reihenfolge, Leitlinien und deine Entscheidungen: `docs/ROADMAP.md`.

Lesehilfe: In ROADMAP, PROJECT_STATE und KNOWN_ISSUES tragen einzelne ältere Abschnittsüberschriften noch „in progress“ oder stehen unter „Aktuell“ / „Geplant“, obwohl der Meilenstein gebaut ist. Maßgeblich sind dieser Status und die Köpfe der Dateien.

## 2. Fortschritt prüfen (ohne Setup)
- GitHub: `https://github.com/melknoo/Runebound/commits/main`. Status = oberer Teil von `docs/PROJECT_STATE.md`, Plan = `docs/ROADMAP.md`, Probleme = `docs/KNOWN_ISSUES.md`.
- Mit Klon: `git pull --rebase`, dann `git log --oneline -15`.
- Was du im Spiel angekreuzt hast, steht nur auf dem Rechner, auf dem du gespielt hast.

## 3. Rechner einrichten
**Stufe A, lesen:** `git clone https://github.com/melknoo/Runebound.git` (öffentlich, kein Login nötig).

**Stufe B, spielen und testen:**
1. Godot **4.6.3-stable** (Windows 64, nicht 4.6.1) von `https://github.com/godotengine/godot/releases/tag/4.6.3-stable` entpacken.
2. Umgebungsvariable `GODOT` auf die volle Pfadangabe der `Godot_v4.6.3-stable_win64_console.exe` setzen (`setx GODOT "<Pfad>"`, danach ein neues Terminal).
3. Im Klon: `tools\run_godot.cmd import`, dann `tools\run_godot.cmd smoke` (muss grün enden, dauert einige Minuten), dann `tools\run_godot.cmd play` (startet mit `--dev`: F1 und die Playtest-Liste J gehen; sonst unter Settings -> Gameplay -> Developer tools einschalten).
4. Crash-Retest: vorher `.godot\` im Klon löschen (der Import-Cache aus 4.6.1 ist veraltet), ins Spiel, aus Runehold in die Highlands reisen. Bleibt der Crash: Windows-Ereignisanzeige (System, `nvlddmkm`) zur Crash-Zeit ansehen, dann `--rendering-driver d3d12` probieren.

**Stufe C, mit Claude entwickeln:**
- Claude Code (CLI oder VS-Code-Erweiterung) im Klon starten, zuerst `git pull --rebase`.
- Git: Push-Rechte (SSH-Key bei GitHub hinterlegen oder `gh auth login`), `git config user.name` und `user.email`. Git-for-Windows-Standard `core.autocrlf=true` lassen, das Repo hat gemischte Zeilenenden.
- Python 3 und `pip install numpy pillow fonttools` für die Generatoren in `tools/`. Fertige Assets liegen im Repo, Generatoren brauchst du nur für Neues.
- Blender 5.2 (Standardpfad `C:\Program Files\Blender Foundation\Blender 5.2`) und uv (`uvx`) für Modelle und den Blender-MCP. MCP einmalig aus **cmd** registrieren (nicht aus Bash/PowerShell, wegen der Pfad-Schreibweise), Befehl und Hintergrund in `docs/ASSET_MANIFEST.md` („Registration“) und `docs/dev-notes/workflow.md`; danach eine neue Claude-Sitzung. Das Live-Loop-Beispiel in `docs/ASSET_MANIFEST.md` nennt `D:\fable_test`, dort deinen Klonpfad einsetzen. Den PixelLab-MCP brauchst du nicht (Icons kommen aus `tools/texgen/ui.py`).
- Server/Deploy: `RUNEBOUND_SERVER_SSH` auf `user@laptop` setzen (Tailscale nötig), sonst gilt der Standard in `tools/run_godot.ps1`. `release` und `deploy` nur auf deinen Wunsch.
- Linux (Laptop): `tools/server/run_godot.sh import|smoke|serve`, Godot unter `~/godot/godot` oder `GODOT`.

## 4. Was nicht mitreist
Spielstände, `settings.cfg` und `playtest.json` (`%APPDATA%\Godot\app_userdata\RUNEBOUND\`), die `.env`, MCP-Registrierungen, Claudes lokales Memory, die claude-mem-Datenbank, `.godot/` (wird beim Import neu gebaut). Die `playtest.json` kannst du bei Bedarf kopieren oder Claude die Problempunkte direkt nennen.

## 5. Zwei Rechner ohne Chaos
Sitzungsstart `git pull --rebase`, Ende commit + push (Claude pusht nach jedem fertigen Stück). Nicht zwei Rechner am selben Stück. Neue dauerhafte Lehren stehen in `docs/dev-notes/` oder `CLAUDE.md`, nicht nur im lokalen Memory.

## 6. Privates Bundle (optional)
Auf dem Haupt-PC liegt außerhalb des Repos `D:\fable_test_handoff\`: `memory\` (Claudes Memory 1:1), `plans\` (die 16 Planungsdateien mit deinen Antworten je Meilenstein) und `README.txt`. Zum Weiterarbeiten reicht das Repo, das Bundle ist Backup und Fallback. Zurückspielen: die Memory-Dateien nach `%USERPROFILE%\.claude\projects\<Schlüssel>\memory\` kopieren. Der Schlüssel ist der Klonpfad, jedes Zeichen außer Buchstaben und Ziffern durch `-` ersetzt (`d:\fable_test` wird `d--fable-test`). Einfachster Weg: Claude einmal im Klon starten und den neu angelegten Ordner unter `%USERPROFILE%\.claude\projects\` nehmen. Das Bundle enthält keine Schlüssel; die `.env` (nur für PixelLab) kopierst du bei Bedarf selbst.
