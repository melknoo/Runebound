#!/usr/bin/env bash
# RUNEBOUND invite codes (M09b): one personal code per friend. The server
# reads the list every 2 s, so changes apply at once: a removed or rotated
# code ends that friend's session.
#   tools/server/invites.sh add NAME      # a new code for NAME (printed once here)
#   tools/server/invites.sh show NAME     # NAME's code again
#   tools/server/invites.sh rotate NAME   # a new code for NAME, the old one stops working
#   tools/server/invites.sh remove NAME   # revoke (NAME is kicked if online)
#   tools/server/invites.sh list          # names and dates (no codes)
# The list is RUNEBOUND_INVITES (server.env; /etc/runebound/invites on the
# laptop): it belongs to you, the server may only read it. Never commit it.
# Format (scripts/net/net_auth.gd): name<TAB>code<TAB>added, "#" comments.
set -euo pipefail

here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
if [[ -z "${RUNEBOUND_INVITES:-}" ]]; then
	RUNEBOUND_INVITES="$(sed -n 's/^RUNEBOUND_INVITES=//p' "$here/server.env" | tail -n 1)"
fi
file="${RUNEBOUND_INVITES:-/etc/runebound/invites}"

die() {
	echo "invites: $*" >&2
	exit 1
}

valid_name() {
	[[ "$1" =~ ^[A-Za-z0-9_.-]{1,24}$ ]]
}

# 10 random bytes = 80 bits = 16 base32 characters (A-Z, 2-7).
new_code() {
	local raw
	raw="$(head -c 10 /dev/urandom | base32 | tr -d '=\n')"
	echo "${raw:0:4}-${raw:4:4}-${raw:8:4}-${raw:12:4}"
}

ensure_file() {
	if [[ ! -f "$file" ]]; then
		[[ -w "$(dirname "$file")" ]] || die "cannot create $file (run tools/server/setup-service.sh first)"
		printf '# RUNEBOUND invites (tools/server/invites.sh). One friend per line:\n# name<TAB>code<TAB>added\n' > "$file"
		chmod 640 "$file"
	fi
	[[ -w "$file" ]] || die "cannot write $file (it should belong to you)"
}

has_name() {
	awk -v n="$1" '$1 == n { found = 1 } END { exit !found }' "$file"
}

# The list without NAME, plus an optional new line, swapped in atomically:
# the server never reads half a file.
rewrite() {
	local name="$1" line="${2:-}" tmp
	tmp="$(mktemp "$(dirname "$file")/.invites.XXXXXX")"
	awk -v n="$name" '$1 != n' "$file" > "$tmp"
	if [[ -n "$line" ]]; then
		printf '%s\n' "$line" >> "$tmp"
	fi
	chmod 640 "$tmp"
	chgrp --reference="$file" "$tmp" 2>/dev/null || true
	mv -f "$tmp" "$file"
}

cmd="${1:-list}"
name="${2:-}"
case "$cmd" in
	add | rotate)
		valid_name "$name" || die "a name is letters, digits and _ . - (at most 24), like: $0 $cmd anna"
		ensure_file
		if [[ "$cmd" == add ]] && has_name "$name"; then
			die "$name already has a code ($0 show $name, or $0 rotate $name for a new one)"
		fi
		if [[ "$cmd" == rotate ]] && ! has_name "$name"; then
			die "there is no invite named $name"
		fi
		code="$(new_code)"
		rewrite "$name" "$(printf '%s\t%s\t%s' "$name" "$code" "$(date +%F)")"
		echo "Invite code for $name: $code"
		echo "The server knows it within 2 s. Send $name the code and the server address."
		;;
	show)
		[[ -r "$file" ]] || die "no invite list at $file"
		awk -v n="$name" '$1 == n { print $2; found = 1 } END { exit !found }' "$file" \
			|| die "there is no invite named $name"
		;;
	remove)
		ensure_file
		has_name "$name" || die "there is no invite named $name"
		rewrite "$name"
		echo "Removed $name's invite. If $name is playing, the server ends the session within 2 s."
		;;
	list)
		if [[ ! -r "$file" ]]; then
			echo "no invite list yet ($file)"
			exit 0
		fi
		awk '!/^#/ && NF >= 2 { printf "%-24s added %s\n", $1, ($3 == "" ? "?" : $3); n++ }
			END { if (!n) print "no invites yet" }' "$file"
		;;
	*)
		die "usage: $0 add|show|rotate|remove NAME, or $0 list"
		;;
esac
