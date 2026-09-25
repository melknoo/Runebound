#!/usr/bin/env bash
# RUNEBOUND dedicated server start (systemd: runebound-server.service).
# Pulls the latest commit (fast-forward only), re-imports when project files
# changed since the last import, then replaces itself with a headless Godot
# running RUNEBOUND_SCENE.
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
	# .godot/ is untracked since M09 (.gitignore); older commits tracked it and
	# a Linux import rewrote it, which blocked the pull. Discard that churn if
	# any tracked copy is still around; a no-op (and no error) otherwise.
	if [[ -n "$(git ls-files .godot)" ]]; then
		git checkout -- .godot
	fi
	git pull --ff-only || fail "git pull --ff-only failed (local changes or diverged history?)"
	echo "RUNEBOUND: updated to $(git log --oneline -1)"
else
	echo "RUNEBOUND: up to date at $(git log --oneline -1)"
fi
# Import whenever project files changed since the last import - also after a
# manual `git pull` (2026-09-25: a pull by hand right before the start left the
# class cache stale and the server ran without its co-op scripts).
GODOT="$godot" "$here/run_godot.sh" ensure-import || fail "import failed"

export RUNEBOUND_PORT
echo "RUNEBOUND: starting $RUNEBOUND_SCENE (port $RUNEBOUND_PORT/udp)"
exec "$godot" --headless --path "$repo" "$RUNEBOUND_SCENE"
