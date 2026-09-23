# Shared Godot resolution + shortcuts for RUNEBOUND.
# Usage:
#   .\tools\run_godot.ps1 import        # import assets headless
#   .\tools\run_godot.ps1 smoke        # run headless smoke test
#   .\tools\run_godot.ps1 play         # run the game windowed
#   .\tools\run_godot.ps1 capture      # automated playtest with screenshots
param([string]$Mode = "smoke")

$godot = $env:GODOT
if (-not $godot) {
	$godot = "C:\Users\mknop\Downloads\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe"
}
if (-not (Test-Path $godot)) { Write-Error "Godot not found: $godot"; exit 1 }

$proj = Split-Path $PSScriptRoot -Parent

switch ($Mode) {
	"import"  { & $godot --headless --path $proj --import }
	"smoke"   { & $godot --headless --path $proj res://tests/smoke_test.tscn }
	"play"    { & $godot --path $proj }
	"capture" { & $godot --path $proj --resolution 1600x900 res://scenes/combat_lab.tscn -- --capture }
	"worldcapture" { & $godot --path $proj --resolution 1600x900 res://scenes/hub.tscn -- --worldcapture }
	default   { Write-Error "unknown mode $Mode"; exit 1 }
}
exit $LASTEXITCODE
