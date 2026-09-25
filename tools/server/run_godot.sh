#!/usr/bin/env bash
# Linux counterpart of tools/run_godot.ps1 for the headless server laptop.
# Usage:
#   tools/server/run_godot.sh import   # import assets headless
#   tools/server/run_godot.sh ensure-import  # import only if project files changed since the last one
#   tools/server/run_godot.sh smoke    # headless smoke test (fails on SCRIPT ERROR too)
#   tools/server/run_godot.sh serve    # run RUNEBOUND_SCENE from server.env headless
#   tools/server/run_godot.sh serverperf [heroes]  # M09: Highlands tick cost with bot heroes
#   tools/server/run_godot.sh net [scenario]       # M09: multi-process co-op tests
# Godot comes from $GODOT (default ~/godot/godot).
set -euo pipefail

mode="${1:-smoke}"
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
proj="$(cd "$here/../.." && pwd)"
godot="${GODOT:-$HOME/godot/godot}"

if [[ ! -x "$godot" ]]; then
	echo "Godot not found: $godot" >&2
	exit 1
fi

# A new class_name script, scene or asset is unknown to a headless run until
# an import has rescanned the project. The stamp marks the last import; any
# project file newer than it (git pull, by hand or by the service) triggers
# one before the run.
stamp="$proj/.godot/runebound_import.stamp"

do_import() {
	local code=0
	"$godot" --headless --path "$proj" --import || code=$?  # set -e: keep going to write the stamp
	mkdir -p "$proj/.godot" && touch "$stamp"
	return $code
}

ensure_import() {
	if [[ -f "$stamp" ]] && [[ -z "$(find "$proj/assets" "$proj/scenes" "$proj/scripts" "$proj/resources" \
			"$proj/shaders" "$proj/tests" "$proj/project.godot" -newer "$stamp" -type f -print -quit 2>/dev/null)" ]]; then
		return 0
	fi
	echo "RUNEBOUND: project files changed since the last import: importing first"
	do_import > /dev/null 2>&1
}

case "$mode" in
	import)
		do_import
		exit $?
		;;
	ensure-import)
		ensure_import
		exit $?
		;;
	smoke)
		ensure_import
		# Script errors don't fail an assertion by themselves; surface them.
		# Hard 8-minute limit: when a script fails to compile, the test's own
		# 300 s watchdog never starts and a headless run would idle forever.
		log="$(mktemp)"
		trap 'rm -f "$log"' EXIT
		set +e
		timeout --kill-after=10 480 "$godot" --headless --path "$proj" res://tests/smoke_test.tscn >"$log" 2>&1
		code=$?
		set -e
		cat "$log"
		if [[ $code -eq 124 || $code -eq 137 ]]; then
			echo "== smoke timed out after 8 min (compile error before the watchdog?) =="
			exit 3
		fi
		if grep -q "smoke watchdog" "$log"; then
			echo "== smoke watchdog fired (run exceeded 300 s) =="
			exit 2
		fi
		errors="$(grep -c -E "SCRIPT ERROR|Parse Error" "$log" || true)"
		if [[ $errors -gt 0 ]]; then
			echo "== $errors script error line(s) in output =="
			if [[ $code -eq 0 ]]; then code=1; fi
		fi
		exit "$code"
		;;
	net)
		ensure_import
		# M09: a dedicated server and headless test clients per scenario.
		timeout --kill-after=10 1200 "$godot" --headless --path "$proj" res://tests/net_test.tscn \
			-- "--scenario=${2:-all}"
		;;
	serverperf)
		ensure_import
		# M09 Spike A: every frame is exactly one physics tick (--fixed-fps),
		# so the wall time per frame is the tick cost on this machine.
		exec "$godot" --headless --fixed-fps 60 --path "$proj" --quit-after 20000 \
			res://tests/server_perf.tscn -- "--heroes=${2:-5}"
		;;
	serve)
		# Values already in the environment (systemd EnvironmentFile) win.
		if [[ -z "${RUNEBOUND_SCENE:-}" ]]; then
			set -a
			# shellcheck source=server.env
			source "$here/server.env"
			set +a
		fi
		export RUNEBOUND_PORT
		ensure_import
		exec "$godot" --headless --path "$proj" "$RUNEBOUND_SCENE"
		;;
	*)
		echo "unknown mode $mode (import | ensure-import | smoke | net | serverperf | serve)" >&2
		exit 1
		;;
esac
