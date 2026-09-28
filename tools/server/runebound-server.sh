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
		# The server follows RUNEBOUND_BRANCH (release; user 2026-09-28: only a
		# new release commit restarts it, main keeps moving). Read fresh from
		# the file, so a changed branch takes effect on this very start.
		want="$(sed -n 's/^RUNEBOUND_BRANCH=//p' "$here/server.env" | tail -n 1)"
		current="$(git branch --show-current)"
		if [[ -n "$want" && "$want" != "$current" ]]; then
			if git rev-parse --quiet --verify "origin/$want" > /dev/null; then
				git checkout --quiet -B "$want" "origin/$want"
				git branch --quiet --set-upstream-to="origin/$want"
				echo "RUNEBOUND: switched to branch $want ($(git log --oneline -1))"
			else
				echo "RUNEBOUND: branch $want is not on origin - staying on $current" >&2
			fi
		fi
		upstream="$(git rev-parse '@{u}')" || fail "branch $(git branch --show-current) has no upstream"
		held="$(cat "${RUNEBOUND_DEPLOY_HOLD:-/nonexistent}" 2>/dev/null || true)"
		if [[ -n "$held" && "$upstream" == "$held" ]]; then
			# runebound-deploy rolled this commit back (it did not start): stay put.
			echo "RUNEBOUND: ${upstream:0:7} is held after a failed deploy - staying at $(git log --oneline -1)"
		elif [[ "$(git rev-parse HEAD)" != "$upstream" ]]; then
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
