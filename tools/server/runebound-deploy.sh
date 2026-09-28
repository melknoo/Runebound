#!/usr/bin/env bash
# RUNEBOUND auto-deploy (M09b, user 2026-09-28: "no more SSH restarts").
# runebound-deploy.timer runs it every 5 minutes; `sudo systemctl start
# runebound-deploy` (allowed without a password for the admin, see
# setup-service.sh) or `tools\run_godot.cmd deploy` runs it now.
#   - nothing new on origin/main: done
#   - players online: the server counts down 5 minutes for them (it reads
#     DEPLOY_AT), then sends them off with a reason; nobody left: at once
#   - restart = runebound-update (pull + import) + runebound-server
#   - the new build must write its status within 3 minutes, else roll back to
#     the old commit and hold the new one (runebound-server.sh update skips a
#     held commit; the next newer commit lifts the hold)
# Installed as root-owned /usr/local/sbin/runebound-deploy; root never runs
# scripts from the server's own clone.
set -euo pipefail

home=/var/lib/runebound
repo="$home/Runebound"
status="$home/.local/share/godot/app_userdata/RUNEBOUND/server_status.json"
deploy_at="$home/deploy_at"
hold="$home/deploy_hold"
countdown="${RUNEBOUND_DEPLOY_COUNTDOWN:-300}"
verify_timeout=180

log() { echo "deploy: $*"; }
as_server() { runuser -u runebound -- "$@"; }
short() { echo "${1:0:7}"; }

# Players on the server now (0 when it is down or its status is stale).
players() {
	[[ -f "$status" ]] || { echo 0; return; }
	local age=$(( $(date +%s) - $(stat -c %Y "$status") ))
	if (( age > 150 )) || ! systemctl is-active -q runebound-server; then
		echo 0
		return
	fi
	local n
	n="$(sed -n 's/.*"players":[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$status")"
	echo "${n:-0}"
}

cd "$repo"
if ! as_server git fetch --quiet origin; then
	log "git fetch failed (network?) - next try in 5 minutes"
	exit 0
fi
old="$(as_server git rev-parse HEAD)"
new="$(as_server git rev-parse '@{u}')"
if [[ "$old" == "$new" ]]; then
	exit 0
fi
if [[ -f "$hold" && "$(cat "$hold")" == "$new" ]]; then
	log "$(short "$new") is held (it failed to start before) - waiting for a newer commit"
	exit 0
fi
if ! as_server git merge-base --is-ancestor "$old" "$new"; then
	log "$(short "$new") is not a fast-forward of $(short "$old") - not deploying, check the clone"
	exit 1
fi
log "new commit $(short "$new"): $(as_server git log --format=%s -1 "$new")"

online="$(players)"
if (( online > 0 )); then
	at=$(( $(date +%s) + countdown ))
	echo "$at" > "$deploy_at"
	chown runebound:runebound "$deploy_at"
	log "$online player(s) online: restart at $(date -d "@$at" +%T), the server counts down"
	while (( $(date +%s) < at )); do
		sleep 5
		if (( $(players) == 0 )); then
			log "everyone left: restarting now"
			break
		fi
	done
fi
rm -f "$deploy_at"

started=$(date +%s)
log "restarting: $(short "$old") -> $(short "$new")"
systemctl restart runebound-server.service || true  # the check below decides
for _ in $(seq 1 $(( verify_timeout / 5 ))); do
	if systemctl is-active -q runebound-server && [[ -f "$status" ]] && (( $(stat -c %Y "$status") >= started )); then
		log "live at $(short "$(as_server git rev-parse HEAD)")"
		rm -f "$hold"
		exit 0
	fi
	sleep 5
done

log "deploy of $(short "$new") failed (no server status within ${verify_timeout} s): rolling back to $(short "$old")"
journalctl -u runebound-update -u runebound-server -n 25 --no-pager -o cat || true
echo "$new" > "$hold"
chown runebound:runebound "$hold"
as_server git reset --hard --quiet "$old"
systemctl restart runebound-server.service || true
exit 1
