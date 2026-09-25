#!/bin/sh
# RUNEBOUND (M09b): the server user may not open connections to other
# services on this laptop - anything listening on localhost (web UIs, CUPS,
# tailscaled's helpers). Answers to the connections tailscaled opens to the
# game stay allowed (they are not NEW), and the resolver stays reachable for
# the update's git fetch. The game unit itself allows 127.0.0.1/::1 only
# (IPAddressAllow), so it cannot use the resolver either.
# Installed as root-owned /usr/local/sbin/runebound-egress by setup-service.sh
# (never run from the server's own clone); runebound-egress.service calls it.
#   runebound-egress start | stop | status
set -eu

rules() {
	op="$1"
	# iptables -I puts each rule on top: the REJECT goes in first, the DNS
	# exceptions end up above it.
	iptables -w "$op" OUTPUT -o lo -m owner --uid-owner runebound -m conntrack --ctstate NEW -j REJECT
	for proto in udp tcp; do
		iptables -w "$op" OUTPUT -o lo -d 127.0.0.53,127.0.0.54 -p "$proto" --dport 53 \
			-m owner --uid-owner runebound -j ACCEPT
	done
	ip6tables -w "$op" OUTPUT -o lo -m owner --uid-owner runebound -m conntrack --ctstate NEW -j REJECT
}

case "${1:-status}" in
	start)
		rules -D 2>/dev/null || true  # never twice
		rules -I
		;;
	stop)
		rules -D 2>/dev/null || true
		;;
	status)
		iptables -S OUTPUT | grep -- "--uid-owner" || echo "no runebound rules (IPv4)"
		ip6tables -S OUTPUT | grep -- "--uid-owner" || echo "no runebound rules (IPv6)"
		;;
	*)
		echo "usage: $0 start | stop | status" >&2
		exit 1
		;;
esac
