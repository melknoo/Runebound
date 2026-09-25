#!/usr/bin/env bash
# RUNEBOUND (M09b): move the dedicated server to its own locked-down user and
# open it to friends through Tailscale Funnel. Run once on the laptop, with
# sudo, from your own clone (safe to run again, it only fixes what is off):
#   sudo ~/Repositories/Runebound/tools/server/setup-service.sh
# What it does:
#   1. system user "runebound": no password, no login shell, no sudo or docker
#      group; home /var/lib/runebound
#   2. its own clone /var/lib/runebound/Runebound over HTTPS (the repo is
#      public: no key on the server) and Godot in /opt/godot (a copy of yours)
#   3. /etc/runebound/invites: yours to edit (tools/server/invites.sh), the
#      server can only read it
#   4. the units runebound-update (pull + import, may use the network),
#      runebound-server (the game: sandboxed, 127.0.0.1 only) and
#      runebound-egress (the server user opens no connections on this laptop)
#   5. Tailscale Funnel: https://<this laptop>.ts.net -> 127.0.0.1:7780
#   6. moves your world save over (if there is one), drops the old 7777/udp
#      firewall rule and starts the server
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Please run with sudo: sudo $0" >&2; exit 1; }
admin="${SUDO_USER:-melvin}"
admin_home="$(getent passwd "$admin" | cut -d: -f6)"
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
home=/var/lib/runebound
repo="$home/Runebound"
remote=https://github.com/melknoo/Runebound.git
godot_link="$admin_home/godot/godot"
data_rel=.local/share/godot/app_userdata/RUNEBOUND
port=7780

say() { printf '\n== %s\n' "$*"; }
as_server() { runuser -u runebound -- "$@"; }

say "1/6 user runebound"
if ! id runebound >/dev/null 2>&1; then
	useradd --system --user-group --home-dir "$home" --create-home --shell /usr/sbin/nologin runebound
	echo "created"
fi
usermod --shell /usr/sbin/nologin runebound
extra="$(id -nG runebound | tr ' ' '\n' | grep -v -x runebound || true)"
[[ -z "$extra" ]] || { echo "runebound is in extra groups ($extra) - removing them"; usermod -G "" runebound; }
passwd -l runebound >/dev/null 2>&1 || true
install -d -o runebound -g runebound -m 750 "$home"
id runebound

say "2/6 Godot in /opt/godot and the server's own clone"
[[ -e "$godot_link" ]] || { echo "Godot not found at $godot_link" >&2; exit 1; }
godot_bin="$(readlink -f "$godot_link")"
install -d -m 755 /opt/godot
install -m 755 "$godot_bin" "/opt/godot/$(basename "$godot_bin")"
ln -sfn "/opt/godot/$(basename "$godot_bin")" /opt/godot/godot
echo "Godot: $(as_server /opt/godot/godot --headless --version 2>/dev/null | tail -n 1)"
if [[ ! -d "$repo/.git" ]]; then
	as_server git clone --quiet --branch main "$remote" "$repo"
	echo "cloned $remote"
else
	as_server git -C "$repo" remote set-url origin "$remote"
	echo "clone exists: $(as_server git -C "$repo" log --oneline -1)"
fi

say "3/6 invite list /etc/runebound/invites"
install -d -o "$admin" -g runebound -m 2750 /etc/runebound
if [[ ! -f /etc/runebound/invites ]]; then
	printf '# RUNEBOUND invites (tools/server/invites.sh). One friend per line:\n# name<TAB>code<TAB>added\n' \
		> /etc/runebound/invites
	echo "created (empty: nobody can join yet)"
fi
chown "$admin:runebound" /etc/runebound/invites
chmod 640 /etc/runebound/invites
ls -l /etc/runebound/invites

say "4/6 units runebound-egress + runebound-update + runebound-server"
# Root runs only root-owned copies, never scripts from the server's clone.
install -o root -g root -m 755 "$here/runebound-egress.sh" /usr/local/sbin/runebound-egress
install -m 644 "$here/runebound-egress.service" "$here/runebound-update.service" \
	"$here/runebound-server.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable runebound-egress.service runebound-server.service >/dev/null
systemctl restart runebound-egress.service
echo "installed and enabled"
if runuser -u runebound -- bash -c 'exec 3<>/dev/tcp/127.0.0.1/631' 2>/dev/null; then
	echo "!! the server user can still open local connections (check: runebound-egress status)"
else
	echo "ok: the server user cannot open connections to local services"
fi
if runuser -u runebound -- getent hosts github.com >/dev/null; then
	echo "ok: it can still look up github.com for updates"
else
	echo "!! the server user cannot resolve github.com (updates will fail)"
fi

say "5/6 world save and firewall"
old_save="$admin_home/$data_rel/runebound_server.json"
new_dir="$home/$data_rel"
if [[ -f "$old_save" && ! -f "$new_dir/runebound_server.json" ]]; then
	install -d -o runebound -g runebound -m 750 "$new_dir"
	install -o runebound -g runebound -m 640 "$old_save" "$new_dir/runebound_server.json"
	echo "world save moved over from $old_save"
else
	echo "no world save to move"
fi
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "7777/udp"; then
	ufw delete allow in on tailscale0 to any port 7777 proto udp >/dev/null || true
	echo "removed the old 7777/udp rule (the server listens on localhost now)"
fi

say "6/6 update, start, Funnel"
echo "first update and import (a fresh clone takes a few minutes on this laptop) ..."
systemctl start runebound-update.service || { journalctl -u runebound-update -n 30 --no-pager; exit 1; }
systemctl restart runebound-server.service
sleep 8
journalctl -u runebound-server -n 12 --no-pager -o cat || true
if timeout 30 tailscale funnel --bg "$port" >/tmp/runebound-funnel.txt 2>&1; then
	cat /tmp/runebound-funnel.txt
else
	cat /tmp/runebound-funnel.txt
	echo "!! Funnel could not be turned on. In the Tailscale admin console enable HTTPS"
	echo "   certificates (DNS page) and Funnel for this machine, then run this script again."
fi
rm -f /tmp/runebound-funnel.txt

say "sandbox check (lower is safer)"
systemd-analyze security runebound-server.service 2>/dev/null | tail -n 1 || true
systemd-analyze security runebound-update.service 2>/dev/null | tail -n 1 || true

cat <<EOF

Done. Next:
  - codes for you and your friends:  $here/invites.sh add NAME
  - the address for everyone:        $(tailscale status --json 2>/dev/null | sed -n 's/.*"DNSName": "\([^"]*\)\.".*/\1/p' | head -n 1)
  - log:                             journalctl -u runebound-server -f
EOF
