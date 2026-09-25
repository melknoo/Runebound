#!/usr/bin/env bash
# RUNEBOUND dedicated server (systemd). Two steps, since M09b two units:
#   runebound-server.sh update  # runebound-update.service: fetch, fast-forward
#                               # pull, import when project files changed
#   runebound-server.sh start   # runebound-server.service: replace itself with
#                               # a headless Godot running RUNEBOUND_SCENE
#   runebound-server.sh         # both (the pre-M09b unit)
# The update may use the network (GitHub); the server itself runs sandboxed
# with localhost only (tools/server/setup-service.sh installs both units).
set -euo pipefail

here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
godot="${GODOT:-$HOME/godot/godot}"
step="${1:-all}"

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

update() {
	cd "$repo"
	# No network (Starlink down at boot, GitHub away): start what we have.
	if ! git fetch --quiet origin; then
		echo "RUNEBOUND: git fetch failed (network?) - starting $(git log --oneline -1)" >&2
	else
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
	fi
	# Import whenever project files changed since the last import - also after a
	# manual `git pull` (2026-09-25: a pull by hand right before the start left the
	# class cache stale and the server ran without its co-op scripts).
	GODOT="$godot" "$here/run_godot.sh" ensure-import || fail "import failed"
}

start() {
	export RUNEBOUND_PORT RUNEBOUND_INVITES RUNEBOUND_TRANSPORT
	echo "RUNEBOUND: starting $RUNEBOUND_SCENE (${RUNEBOUND_TRANSPORT:-enet} on port $RUNEBOUND_PORT)"
	exec "$godot" --headless --path "$repo" "$RUNEBOUND_SCENE"
}

case "$step" in
	update)
		update
		;;
	start)
		start
		;;
	all)
		update
		start
		;;
	*)
		echo "usage: $0 [update | start]" >&2
		exit 1
		;;
esac
