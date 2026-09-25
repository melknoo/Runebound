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
#   .\tools\run_godot.ps1 serverperf [heroes]    # M09: headless Highlands tick cost with bot heroes
#   .\tools\run_godot.ps1 net [scenario]        # M09: multi-process co-op tests (server + headless clients)
#   .\tools\run_godot.ps1 server [port]         # M09: local dedicated server (join 127.0.0.1 from the title)
#   .\tools\run_godot.ps1 coop [bots]           # M09: solo co-op playtest: local server + companion bots + this window
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

# A new class_name script, scene or asset is unknown to a game or headless run
# until an import has rescanned the project (the editor does it by itself).
# Import first whenever a project file is newer than the last import: after a
# git pull, after edits, on a fresh clone. The stamp lives in .godot/.
$importStamp = Join-Path $proj ".godot\runebound_import.stamp"
function Invoke-Import {
	& $godot --headless --path $proj --import 2>&1 | Out-Null
	$code = $LASTEXITCODE
	New-Item -ItemType Directory -Force (Split-Path $importStamp) | Out-Null
	Set-Content -Path $importStamp -Value (Get-Date -Format o) -Encoding ascii
	return $code
}
function Update-Import {
	$since = if (Test-Path $importStamp) { (Get-Item $importStamp).LastWriteTime } else { [datetime]::MinValue }
	$dirs = @("assets", "scenes", "scripts", "resources", "shaders", "tests") |
		ForEach-Object { Join-Path $proj $_ } | Where-Object { Test-Path $_ }
	$changed = @(Get-ChildItem -Path $dirs -Recurse -File -ErrorAction SilentlyContinue |
		Where-Object { $_.LastWriteTime -gt $since } | Select-Object -First 1)
	if ((Get-Item (Join-Path $proj "project.godot")).LastWriteTime -gt $since) { $changed += @(Get-Item (Join-Path $proj "project.godot")) }
	if ($changed.Count -gt 0) {
		Write-Output ("Project files changed since the last import ({0}): importing first ..." -f $changed[0].Name)
		Invoke-Import | Out-Null
	}
}
if ($Mode -notin @("import", "reset")) { Update-Import }

if ($Mode -notin @("import", "smoke", "net", "server", "serverperf")) { Show-OtherGodot }  # headless modes share no GPU

# Automated windowed runs get a hard frame cap (about 8 min at 60 FPS): a
# script that fails to compile never attaches its runner, and the game would
# otherwise idle forever.
$cap = @("--quit-after", "30000")

switch ($Mode) {
	"import"  { exit (Invoke-Import) }
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
	"net"     {
		# M09 multi-process co-op tests: a dedicated server and headless test
		# clients per scenario (tests/net_test.gd). Optional scenario name.
		$scenario = if ($Name) { $Name } else { "all" }
		$p = Start-Process -FilePath $godot -ArgumentList "--headless", "--path", "`"$proj`"", "res://tests/net_test.tscn", "--", "--scenario=$scenario" `
			-NoNewWindow -PassThru
		$handle = $p.Handle
		if (-not $p.WaitForExit(1200000)) {
			Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
			Write-Output "== net test timed out after 20 min =="
			exit 3
		}
		exit $p.ExitCode
	}
	"coop"    {
		# M09 solo co-op playtest: a local dedicated server, N companion bots
		# (headless; they follow you, fight with you and travel with you) and
		# this game window, joined automatically. Closing the window ends all.
		$bots = if ($Name) { [int]$Name } else { 2 }
		$port = 7780
		$srv = Start-Process -FilePath $godot -PassThru -WindowStyle Hidden -ArgumentList "--headless", "--path", "`"$proj`"",
			"res://scenes/dedicated_server.tscn", "--", "--port=$port", "--save=user://local_server.json"
		Start-Sleep -Seconds 4
		$names = @("Sigmund", "Brynja", "Halvard", "Yrsa")
		$procs = @($srv)
		for ($i = 0; $i -lt [Math]::Min($bots, 4); $i++) {
			$procs += Start-Process -FilePath $godot -PassThru -WindowStyle Hidden -ArgumentList "--headless", "--path", "`"$proj`"",
				"res://tests/net_client.tscn", "--", "--connect=127.0.0.1:$port", "--net-test=companion", "--role=bot$i",
				"--name=$($names[$i])", "--duration=14400", "--save=user://companion_$i.json", "--result=user://companion_$i.result"
		}
		& $godot --path $proj -- "--connect=127.0.0.1:$port"
		foreach ($p in $procs) { if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } }
		exit 0
	}
	"server"  {
		# M09: a local dedicated server on port 7777 (or the given port) for
		# joining from the title screen ("Join co-op" -> 127.0.0.1).
		$port = if ($Name) { $Name } else { "7777" }
		& $godot --headless --path $proj res://scenes/dedicated_server.tscn -- "--port=$port" "--save=user://local_server.json"
	}
	"serverperf" {
		# M09 Spike A: headless tick cost of the Highlands with N bot heroes
		# (default 5). --fixed-fps 60 makes every frame exactly one tick.
		$heroes = if ($Name) { $Name } else { "5" }
		& $godot --headless --fixed-fps 60 --path $proj --quit-after 20000 res://tests/server_perf.tscn -- "--heroes=$heroes"
	}
	default   { Write-Error "unknown mode $Mode"; exit 1 }
}
exit $LASTEXITCODE
