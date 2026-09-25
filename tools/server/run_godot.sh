#!/usr/bin/env bash
# Linux counterpart of tools/run_godot.ps1 for the headless server laptop.
# Usage:
#   tools/server/run_godot.sh import   # import assets headless
#   tools/server/run_godot.sh smoke    # headless smoke test (fails on SCRIPT ERROR too)
#   tools/server/run_godot.sh serve    # run RUNEBOUND_SCENE from server.env headless
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

case "$mode" in
	import)
		exec "$godot" --headless --path "$proj" --import
		;;
	smoke)
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
	serve)
		# Values already in the environment (systemd EnvironmentFile) win.
		if [[ -z "${RUNEBOUND_SCENE:-}" ]]; then
			set -a
			# shellcheck source=server.env
			source "$here/server.env"
			set +a
		fi
		export RUNEBOUND_PORT
		exec "$godot" --headless --path "$proj" "$RUNEBOUND_SCENE"
		;;
	*)
		echo "unknown mode $mode (import | smoke | serve)" >&2
		exit 1
		;;
esac
