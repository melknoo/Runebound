# Shared Godot resolution + shortcuts for RUNEBOUND.
# Usage:
#   .\tools\run_godot.ps1 import                 # import assets headless
#   .\tools\run_godot.ps1 smoke                  # headless smoke test (fails on SCRIPT ERROR too)
#   .\tools\run_godot.ps1 play                   # run the game windowed
#   .\tools\run_godot.ps1 reset                  # delete the save: fresh character on next start
#   .\tools\run_godot.ps1 capture                # automated lab playtest with screenshots
#   .\tools\run_godot.ps1 worldcapture           # hub -> highlands -> spire screenshot tour
#   .\tools\run_godot.ps1 shots <list>           # data-driven shots: tests/shots/<list>.json
#   .\tools\run_godot.ps1 perf <scenario> [label] # scripted fight: tests/perf/<scenario>.json
#   .\tools\run_godot.ps1 stress                 # lab stress test (exit 1 below budget)
param([string]$Mode = "smoke", [string]$Name = "", [string]$Label = "")

$godot = $env:GODOT
if (-not $godot) {
	$godot = "C:\Users\mknop\Downloads\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe"
}
if (-not (Test-Path $godot)) { Write-Error "Godot not found: $godot"; exit 1 }

$proj = Split-Path $PSScriptRoot -Parent

# Other game instances share this iGPU: two windowed games at once crashed with
# "Vulkan device was lost" (Windows GPU resets, 2026-09-23), and any extra run
# (even a hung headless one) distorts perf numbers. The editor is fine.
function Show-OtherGodot {
	$procs = @(Get-CimInstance Win32_Process -Filter "Name like 'Godot%'" -ErrorAction SilentlyContinue |
		Where-Object { $_.Name -notmatch "_console" -and $_.CommandLine -notmatch "--editor(\s|$)" })
	foreach ($p in $procs) {
		$age = [int]((Get-Date) - $p.CreationDate).TotalMinutes
		Write-Warning ("Godot already running (PID {0}, {1} min): {2}" -f $p.ProcessId, $age, $p.CommandLine)
	}
	if ($procs.Count -gt 0) {
		Write-Warning "Close it first - two games on this iGPU can crash with 'device lost' and skew perf numbers."
	}
}

# Zone scene named inside a shots/perf JSON file.
function Get-ListZone([string]$jsonPath) {
	if (-not (Test-Path $jsonPath)) { Write-Error "not found: $jsonPath"; exit 1 }
	$json = Get-Content $jsonPath -Raw | ConvertFrom-Json
	if ($json.zone) { return $json.zone }
	return "res://scenes/combat_lab.tscn"
}

if ($Mode -notin @("import", "smoke")) { Show-OtherGodot }

# Automated windowed runs get a hard frame cap (about 8 min at 60 FPS): a
# script that fails to compile never attaches its runner, and the game would
# otherwise idle forever.
$cap = @("--quit-after", "30000")

switch ($Mode) {
	"import"  { & $godot --headless --path $proj --import }
	"reset"   {
		# Fresh start for testing: deletes the real save (gear, level, talents,
		# world flags). Scratch saves from test runs are left alone.
		$save = Join-Path $env:APPDATA "Godot\app_userdata\RUNEBOUND\runebound_save.json"
		# A running game rewrites the save when it quits, which undoes the reset.
		$running = @(Get-CimInstance Win32_Process -Filter "Name like 'Godot%'" -ErrorAction SilentlyContinue |
			Where-Object { $_.CommandLine -notmatch "--editor(\s|$)" -and $_.CommandLine -notmatch "--headless" })
		if ($running.Count -gt 0) {
			Write-Warning "The game is still running (PID $($running[0].ProcessId)). Close it first, then reset - it saves again on quit."
			exit 1
		}
		if (Test-Path $save) { Remove-Item $save -Force; Write-Output "Save deleted: $save" }
		else { Write-Output "No save to delete ($save)" }
		exit 0
	}
	"smoke"   {
		# Script errors don't fail an assertion by themselves; surface them.
		# Hard 8-minute limit: when a script fails to compile, the test's own
		# watchdog never starts and a headless run would idle forever.
		$outFile = [IO.Path]::GetTempFileName()
		$errFile = [IO.Path]::GetTempFileName()
		$p = Start-Process -FilePath $godot -ArgumentList "--headless", "--path", "`"$proj`"", "res://tests/smoke_test.tscn" `
			-NoNewWindow -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile
		$handle = $p.Handle  # keeps ExitCode readable after exit
		$timedOut = -not $p.WaitForExit(480000)
		if ($timedOut) {
			Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
			Write-Output "== smoke timed out after 8 min (compile error before the watchdog?) =="
		}
		$log = @(Get-Content $outFile) + @(Get-Content $errFile)
		$code = if ($timedOut -or $null -eq $p.ExitCode) { 3 } else { $p.ExitCode }
		Remove-Item $outFile, $errFile -ErrorAction SilentlyContinue
		$log | ForEach-Object { Write-Output $_ }
		$scriptErrors = @($log | Where-Object { $_ -match "SCRIPT ERROR|Parse Error" })
		if ($scriptErrors.Count -gt 0) {
			Write-Output "== $($scriptErrors.Count) script error line(s) in output =="
			if ($code -eq 0) { $code = 1 }
		}
		exit $code
	}
	"play"    { & $godot --path $proj }
	"capture" { & $godot --path $proj @cap --resolution 1600x900 res://scenes/combat_lab.tscn -- --capture }
	"worldcapture" { & $godot --path $proj @cap --resolution 1600x900 res://scenes/hub.tscn -- --worldcapture }
	"shots"   {
		# Optional 3rd arg "legacy": same shots with the pre-M06 look (before/after pairs).
		$list = "res://tests/shots/$Name.json"
		$zone = Get-ListZone "$proj\tests\shots\$Name.json"
		$extra = @()
		if ($Label -eq "legacy") { $extra += "--legacy-look" }
		& $godot --path $proj @cap --resolution 1600x900 $zone -- "--shots=$list" @extra
	}
	"perf"    {
		$scenario = "res://tests/perf/$Name.json"
		$zone = Get-ListZone "$proj\tests\perf\$Name.json"
		& $godot --path $proj @cap --resolution 1600x900 $zone -- "--perf=$scenario" "--label=$Label"
	}
	"stress"  { & $godot --path $proj @cap --resolution 1600x900 res://tests/stress_test.tscn -- --stress }
	default   { Write-Error "unknown mode $Mode"; exit 1 }
}
exit $LASTEXITCODE
