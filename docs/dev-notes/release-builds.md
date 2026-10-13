# Player builds (Windows)

How friends get the game without Godot or git: a GitHub release with an installer and a portable ZIP, built only by GitHub Actions from the public source. Built 2026-10-13. Player instructions (German): [SERVER_SETUP.md](../SERVER_SETUP.md) "Freunde".

## The flow
1. `tools\run_godot.cmd release` ships main to the `release` branch (the laptop server deploys it) and tags that commit `v0.<protocol>.<n>`: the middle number is `Net.PROTOCOL`, `n` counts releases per protocol. A commit that already has a `v*` tag gets none.
2. The tag starts [.github/workflows/windows-release.yml](../../.github/workflows/windows-release.yml) (`windows-2025` runner): checks the tag matches `Net.PROTOCOL`, runs `tools/dist/build_windows.ps1 -Pinned`, uploads the files as a run artifact, attests their provenance and creates the release with a German text (`tools/dist/release_notes.md` + the commit subjects since the previous release).
3. The game's title screen asks GitHub for the newest release (`UpdateCheck`) and offers the download page.

`Actions -> Windows release -> Run workflow` builds a test version (`0.0.0-test`) without publishing: the files are in the run's artifact for 14 days.

Local: `tools\run_godot.cmd dist [version]` runs the same script with this PC's Godot and templates (version `0.<protocol>.0-local`), output in `build\dist` (git-ignored). It rewrites `project.godot` (`config/version`) and `export_presets.cfg` (file version, template path) for the export and restores both afterwards: do not save the project in the editor meanwhile.

## build_windows.ps1
- **Godot:** `-Godot`, else `GODOT`; with `-Pinned` (CI) or none found the pinned editor zip into `build\cache\godot-<v>` in self-contained mode (`._sc_`: its settings never touch `%APPDATA%`).
- **Template:** only `windows_release_x86_64.exe`, from the local templates folder or extracted from the pinned `.tpz` (1.2 GB, deleted after extraction). Its SHA256 must match `entry_sha256` in both cases.
- **Export:** `--import`, `--export-release Windows`, then `tools/dist/licenses.gd` writes `LICENSES.txt` (Godot's licence and third-party notices as the engine reports them, the fonts' OFL texts). `README.txt` (DE+EN) comes from `tools/dist/README.txt`.
- **Export check:** the exported exe runs `--headless -- --export-check --out=<json>` (`scripts/systems/export_check.gd`, handed over by the title screen, a test-run flag): terrain heights, biome textures and mask, all JSON tables, classes, talents, sounds, every scene, then a 6-second Highlands boot; script errors or failed `res://` loads logged meanwhile (a `Logger`) fail it. The report must say the version the script set.
- **Installer:** Inno Setup, installed portable (`/PORTABLE=1 /CURRENTUSER`, no registry entry) into `build\cache\innosetup-<v>`; script `tools/dist/runebound.iss`. Per-user install to `%LOCALAPPDATA%\Programs\RUNEBOUND`, no admin, start-menu entries "RUNEBOUND" and "RUNEBOUND (DirectX 12)" (`--rendering-driver d3d12`, the KNOWN_ISSUES workaround), optional desktop icon, uninstaller. The `AppId` GUID is fixed forever (updates install over the old version). Saves live in `%APPDATA%\Godot\app_userdata\RUNEBOUND` and survive both.
- **Output:** `Runebound-<v>-windows.zip` (a `Runebound` folder), `Runebound-<v>-setup.exe`, `SHA256SUMS.txt`, `export_check.json`. About 50 + 40 MB; the whole workflow ran in about 2 minutes (first test run 2026-10-13: downloads 20 s, import 15 s, export check 8 s).

## Trust (why no paid signature)
Decided by the user 2026-10-13: unsigned but transparent. SmartScreen warns ("More info -> Run anyway"); the release text explains it. Instead:
- The build runs only on GitHub from the tagged public commit; the release links the commit and the run log.
- Only first-party actions (`checkout`, `cache`, `upload-artifact`, `attest-build-provenance`), pinned by commit SHA; minimal token permissions.
- Every downloaded tool is pinned in [tools/dist/pins.json](../../tools/dist/pins.json): Godot editor and templates by the SHA512 from Godot's own `SHA512-SUMS.txt`, Inno Setup by SHA256 (equal to the winget manifest; the installer is Authenticode-signed by Pyrsys B.V.).
- `SHA256SUMS.txt` and a GitHub provenance attestation: `gh attestation verify <file> --repo melknoo/Runebound`.
- Cross-check 2026-10-13: the Windows template extracted in CI from the official `.tpz` had the same SHA256 as the one the editor had installed on the main PC (`entry_sha256`).
Options for later: SignPath Foundation signs open-source projects for free (needs an OSI licence for everything incl. assets, an application, a code-signing-policy page; the publisher shown is "SignPath Foundation"); a paid OV certificate (~200-400 EUR/year); Azure Artifact Signing is open to companies in the EU, not to individuals.

## Upgrading Godot or Inno Setup
1. Godot: take both SHA512 lines from `https://github.com/godotengine/godot-builds/releases/download/<v>/SHA512-SUMS.txt`, update `pins.json` (`version`, `template_dir`, URLs, hashes), install the templates locally, set `entry_sha256` to the SHA256 of the new `windows_release_x86_64.exe`. The server and every client must move together (`Net.godot_minor`).
2. Inno Setup: the new installer's URL from `jrsoftware/issrc` releases and its SHA256 (compare with the winget manifest: `winget show JRSoftware.InnoSetup --version <v>`).
3. A new `pins.json` changes the CI cache key, so the first build downloads everything again.
4. Run `dist` locally, then the workflow by hand before the next tag.

## Pitfalls
- An export packs only the **imported** copy of a PNG, never the file: read pixels through `ArtKit.png_image()` (imported texture -> `get_image()`, the same pixels headless, checked 2026-10-13), never `FileAccess` on a `.png`. Raw data files need an include filter in `export_presets.cfg` (`*.r16` for the heightmap). JSON files are resources and export by themselves.
- `tests/`, `tools/`, `docs/` are not exported: game code loads test scripts through `ZoneBase.test_node()` (null in a player build).
- The release exe is a GUI program: no stdout. The export check reports through its JSON file and exit code; `Start-Process` needs `$p.Handle` touched before `WaitForExit(ms)`, else `ExitCode` stays empty.
- `config/version` is `dev` in the repo; only builds carry a real version (`Net.game_version()`, the title screen footer).
- Godot 4.6 sets the exe icon and version info itself (`application/modify_resources`), no rcedit. File versions must be four numbers (`0.15.2.0`).
