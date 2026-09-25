#!/usr/bin/env bash
# RUNEBOUND dedicated server start (systemd: runebound-server.service).
# Pulls the latest commit (fast-forward only), re-imports if something came
# in, then replaces itself with a headless Godot running RUNEBOUND_SCENE.
set -euo pipefail

here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
godot="${GODOT:-$HOME/godot/godot}"

# Values already in the environment (systemd EnvironmentFile) win.
if [[ -z "${RUNEBOUND_SCENE:-}" || -z "${RUNEBOUND_PORT:-}" ]]; then
	set -a
	# shellcheck source=server.env
	source "$here/server.env"
	set +a
fi

fail() {
	echo "!!! RUNEBOUND SERVER: $* - not starting." >&2
	exit 1
}

cd "$repo"
git fetch --quiet origin || fail "git fetch failed (network? GitHub auth?)"
upstream="$(git rev-parse '@{u}')" || fail "branch $(git branch --show-current) has no upstream"
if [[ "$(git rev-parse HEAD)" != "$upstream" ]]; then
	# The committed .godot/ comes from Windows; a Linux import rewrites it.
	# That churn is regenerated below and would otherwise block the pull.
	git checkout -- .godot
	git pull --ff-only || fail "git pull --ff-only failed (local changes or diverged history?)"
	echo "RUNEBOUND: updated to $(git log --oneline -1)"
	GODOT="$godot" "$here/run_godot.sh" import || fail "import after update failed"
else
	echo "RUNEBOUND: up to date at $(git log --oneline -1)"
fi

export RUNEBOUND_PORT
echo "RUNEBOUND: starting $RUNEBOUND_SCENE (port $RUNEBOUND_PORT/udp)"
exec "$godot" --headless --path "$repo" "$RUNEBOUND_SCENE"
