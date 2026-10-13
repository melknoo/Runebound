# RUNEBOUND player build for Windows: export, self-check, ZIP, installer, checksums.
# One script for CI (.github/workflows/windows-release.yml) and local runs
# (tools\run_godot.cmd dist). Every downloaded tool is pinned by hash in
# tools/dist/pins.json. Output in build\dist:
#   Runebound-<version>-windows.zip, Runebound-<version>-setup.exe, SHA256SUMS.txt
#   (plus export_check.json, the exported game's self-check)
# Usage: powershell -File tools\dist\build_windows.ps1 -Version 0.15.0 [-Pinned] [-NoInstaller]
#   -Pinned       ignore a local Godot and its templates, use only the pinned downloads (CI)
#   -NoInstaller  ZIP only
# docs/dev-notes/release-builds.md
param(
	[Parameter(Mandatory = $true)][string]$Version,
	[string]$Godot = "",
	[switch]$Pinned,
	[switch]$NoInstaller
)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"  # Invoke-WebRequest crawls with a progress bar

$proj = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$pins = Get-Content -Raw (Join-Path $PSScriptRoot "pins.json") | ConvertFrom-Json
$cache = Join-Path $proj "build\cache"
$dist = Join-Path $proj "build\dist"
$stage = Join-Path $dist "Runebound"
$checkTimeoutMs = 300000

if ($Version -notmatch '^\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?$') { throw "Version must look like 0.15.0 or 0.15.0-local, got '$Version'" }
$fileVersion = (($Version -split '-')[0]) + ".0"
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Step([string]$text) { Write-Host ""; Write-Host "== $text" -ForegroundColor Cyan }

# A download into build\cache, kept only when its hash matches the pin.
function Get-Pinned([string]$url, [string]$algo, [string]$hash, [string]$name) {
	New-Item -ItemType Directory -Force $cache | Out-Null
	$file = Join-Path $cache $name
	if ((Test-Path -LiteralPath $file) -and (Get-FileHash -Algorithm $algo -LiteralPath $file).Hash -eq $hash) { return $file }
	Write-Host "download $url"
	Invoke-WebRequest -Uri $url -OutFile "$file.part" -UseBasicParsing
	$got = (Get-FileHash -Algorithm $algo -LiteralPath "$file.part").Hash
	if ($got -ne $hash) {
		Remove-Item -LiteralPath "$file.part"
		throw "$name`: $algo mismatch (got $got, pinned $hash) - not using it"
	}
	Move-Item -Force -LiteralPath "$file.part" $file
	return $file
}

function Invoke-Godot([string[]]$arguments) {
	& $script:Godot @arguments
	if ($LASTEXITCODE -ne 0) { throw "Godot failed (exit $LASTEXITCODE): $($arguments -join ' ')" }
}

function Write-Utf8([string]$path, [string]$text) {
	[IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding $false))
}

# --- Godot editor (exports headless) -----------------------------------------
Step "Godot $($pins.godot.version)"
if (-not $Pinned -and $Godot -eq "") {
	$Godot = $env:GODOT
	if (-not $Godot) { $Godot = [Environment]::GetEnvironmentVariable("GODOT", "User") }
	if (-not $Godot) { $Godot = [Environment]::GetEnvironmentVariable("GODOT", "Machine") }
}
if (-not $Godot -or -not (Test-Path -LiteralPath $Godot)) {
	$zip = Get-Pinned $pins.godot.editor.url "SHA512" $pins.godot.editor.sha512 "godot-$($pins.godot.version)-win64.zip"
	$dir = Join-Path $cache "godot-$($pins.godot.version)"
	$Godot = Join-Path $dir $pins.godot.editor.exe
	if (-not (Test-Path -LiteralPath $Godot)) { Expand-Archive -LiteralPath $zip -DestinationPath $dir -Force }
	# Self-contained mode: editor settings and caches stay in $dir\editor_data, never in %APPDATA%.
	New-Item -ItemType File -Force (Join-Path $dir "._sc_") | Out-Null
}
$godotVersion = (& $Godot --version | Select-Object -Last 1).Trim()
$wanted = $pins.godot.template_dir  # 4.6.3.stable
if (-not $godotVersion.StartsWith($wanted)) { throw "Godot $godotVersion at $Godot, need $wanted" }
Write-Host "$Godot ($godotVersion)"

# --- Export template (only the Windows release one is needed) ----------------
Step "Export template"
$template = ""
if (-not $Pinned) {
	$local = Join-Path $env:APPDATA "Godot\export_templates\$wanted\windows_release_x86_64.exe"
	if (Test-Path -LiteralPath $local) { $template = $local }
}
if ($template -eq "") {
	$template = Join-Path $cache "windows_release_x86_64-$($pins.godot.version).exe"
	if (-not (Test-Path -LiteralPath $template) -or
			(Get-FileHash -Algorithm SHA256 -LiteralPath $template).Hash -ne $pins.godot.templates.entry_sha256) {
		$tpz = Get-Pinned $pins.godot.templates.url "SHA512" $pins.godot.templates.sha512 "godot-$($pins.godot.version)-templates.tpz"
		$archive = [IO.Compression.ZipFile]::OpenRead($tpz)
		try {
			$entry = $archive.GetEntry($pins.godot.templates.entry)
			if ($null -eq $entry) { throw "$($pins.godot.templates.entry) missing in $tpz" }
			[IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $template, $true)
		} finally { $archive.Dispose() }
		Remove-Item -LiteralPath $tpz  # 1.2 GB for every platform; the one template stays (and is hash-checked)
	}
}
$templateHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $template).Hash
if ($templateHash -ne $pins.godot.templates.entry_sha256) {
	throw "Export template $template has SHA256 $templateHash, pinned $($pins.godot.templates.entry_sha256). Reinstall the templates or run with -Pinned."
}
Write-Host "$template (SHA256 ok)"

# --- Export ------------------------------------------------------------------
if (Test-Path -LiteralPath $dist) { Remove-Item -Recurse -Force -LiteralPath $dist }
New-Item -ItemType Directory -Force $stage | Out-Null
$projectFile = Join-Path $proj "project.godot"
$presetFile = Join-Path $proj "export_presets.cfg"
$projectBytes = [IO.File]::ReadAllBytes($projectFile)
$presetBytes = [IO.File]::ReadAllBytes($presetFile)
try {
	# The version and the template go into the working copy for this export only.
	Step "Import"
	$text = [IO.File]::ReadAllText($projectFile)
	Write-Utf8 $projectFile ($text -replace 'config/version="[^"]*"', "config/version=`"$Version`"")
	$text = [IO.File]::ReadAllText($presetFile)
	$text = $text -replace 'application/file_version="[^"]*"', "application/file_version=`"$fileVersion`""
	$text = $text -replace 'application/product_version="[^"]*"', "application/product_version=`"$fileVersion`""
	$text = $text -replace 'custom_template/release="[^"]*"', ("custom_template/release=`"" + ($template -replace '\\', '/') + "`"")
	Write-Utf8 $presetFile $text
	Invoke-Godot @("--headless", "--path", $proj, "--import")

	Step "Export $Version"
	Invoke-Godot @("--headless", "--path", $proj, "--export-release", "Windows", (Join-Path $stage "Runebound.exe"))
	Step "Licences"
	Invoke-Godot @("--headless", "--path", $proj, "--script", "res://tools/dist/licenses.gd", "--", "--out=$(Join-Path $stage 'LICENSES.txt')")
} finally {
	[IO.File]::WriteAllBytes($projectFile, $projectBytes)
	[IO.File]::WriteAllBytes($presetFile, $presetBytes)
}
foreach ($f in @("Runebound.exe", "Runebound.pck", "LICENSES.txt")) {
	if (-not (Test-Path -LiteralPath (Join-Path $stage $f))) { throw "export produced no $f" }
}
$readme = [IO.File]::ReadAllText((Join-Path $PSScriptRoot "README.txt")).Replace("{VERSION}", $Version)
Write-Utf8 (Join-Path $stage "README.txt") (($readme -replace "`r`n", "`n") -replace "`n", "`r`n")

# --- The exported game checks itself ------------------------------------------
Step "Export check"
$report = Join-Path $dist "export_check.json"
$game = Start-Process -FilePath (Join-Path $stage "Runebound.exe") -PassThru -NoNewWindow `
	-ArgumentList @("--headless", "--", "--export-check", "--out=`"$report`"")
$null = $game.Handle  # without the handle cached, ExitCode stays empty after WaitForExit(timeout)
if (-not $game.WaitForExit($checkTimeoutMs)) {
	$game.Kill()
	throw "export check timed out after $($checkTimeoutMs / 1000) s"
}
$game.WaitForExit()
if (-not (Test-Path -LiteralPath $report)) { throw "export check wrote no report (exit $($game.ExitCode))" }
$result = Get-Content -Raw -LiteralPath $report | ConvertFrom-Json
foreach ($c in $result.checks) {
	Write-Host ("  {0} {1}  {2}" -f $(if ($c.ok) { "ok  " } else { "FAIL" }), $c.name, $c.detail)
}
foreach ($e in $result.errors) { Write-Host "  logged: $e" }
if (-not $result.ok -or $game.ExitCode -ne 0) { throw "export check failed (exit $($game.ExitCode)), see $report" }
if ($result.version -ne $Version) { throw "export check saw version '$($result.version)', expected $Version" }

# --- ZIP ---------------------------------------------------------------------
Step "ZIP"
$zipOut = Join-Path $dist "Runebound-$Version-windows.zip"
[IO.Compression.ZipFile]::CreateFromDirectory($stage, $zipOut, [IO.Compression.CompressionLevel]::Optimal, $true)
$outputs = @($zipOut)

# --- Installer (Inno Setup, installed portable into build\cache) ---------------
if (-not $NoInstaller) {
	Step "Installer (Inno Setup $($pins.inno_setup.version))"
	$innoDir = Join-Path $cache "innosetup-$($pins.inno_setup.version)"
	$iscc = Join-Path $innoDir "ISCC.exe"
	if (-not (Test-Path -LiteralPath $iscc)) {
		$installer = Get-Pinned $pins.inno_setup.url "SHA256" $pins.inno_setup.sha256 "innosetup-$($pins.inno_setup.version).exe"
		$setup = Start-Process -FilePath $installer -Wait -PassThru -ArgumentList @(
			"/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/SP-", "/CURRENTUSER", "/PORTABLE=1", "/DIR=`"$innoDir`"")
		if ($setup.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $iscc)) { throw "Inno Setup install failed (exit $($setup.ExitCode))" }
	}
	$base = "Runebound-$Version-setup"
	& $iscc /Q "/DAppVersion=$Version" "/DFileVersion=$fileVersion" "/DSourceDir=$stage" "/DOutputDir=$dist" "/DOutputBase=$base" (Join-Path $PSScriptRoot "runebound.iss")
	if ($LASTEXITCODE -ne 0) { throw "ISCC failed (exit $LASTEXITCODE)" }
	$outputs += (Join-Path $dist "$base.exe")
}

# --- Checksums ---------------------------------------------------------------
Step "SHA256SUMS.txt"
$sums = foreach ($f in $outputs) {
	"{0}  {1}" -f (Get-FileHash -Algorithm SHA256 -LiteralPath $f).Hash.ToLower(), (Split-Path $f -Leaf)
}
[IO.File]::WriteAllText((Join-Path $dist "SHA256SUMS.txt"), (($sums -join "`n") + "`n"))
foreach ($f in $outputs) {
	Write-Host ("{0,8:N1} MB  {1}" -f ((Get-Item -LiteralPath $f).Length / 1MB), $f)
}
Write-Host ""
Write-Host "RUNEBOUND $Version built: $dist" -ForegroundColor Green
