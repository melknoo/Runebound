# Server operations

How the dedicated server is run and what went wrong before. Setup, units and invite codes: [SERVER_SETUP.md](../SERVER_SETUP.md) (German). Protocol, transports and access: TECHNICAL_ARCHITECTURE "Co-op (M09)".

## Topology
- The server is a Linux laptop at the owner's home on Starlink (CGNAT for IPv4, inbound IPv6 blocked). It runs headless, as the sandboxed system user `runebound`, from the **`release`** branch (`RUNEBOUND_BRANCH` in `tools/server/server.env`).
- Friends reach it without Tailscale through Tailscale Funnel (public HTTPS name, TCP only) over a WebSocket transport, with a personal invite code each. The owner reaches it through the tailnet. The Funnel name is in `resources/net/servers.json` on purpose (the title screen shows aliases only, user decision 2026-10-01). Address prefixes and IPs stay out of the public docs.
- Authority is hybrid: the server owns enemies, camps, bosses, flags, chests, rewards and zone travel; every client owns its hero, its hit detection and its HP. Personal loot, shared travel with a 5-second countdown, enemy HP +70 % per extra player (user rules 2026-09-25).

## Reading and deploying
- **Access:** `ssh` to the laptop (Tailscale SSH). The default target is in `tools/run_godot.ps1`, `RUNEBOUND_SERVER_SSH` overrides it. Tailscale SSH sometimes needs a browser check: the ssh output prints a `login.tailscale.com` URL the user must open. Outside the tailnet (Tailscale off, laptop off) ssh just times out (it did from the main PC on 2026-10-09).
- **Journal, read-only:** `journalctl -u runebound-server -u runebound-deploy` works for the login user; `/var/lib/runebound` is not readable.
- **Deploy:** `runebound-deploy.timer` checks every 5 minutes (and 5 minutes after boot). A new commit on the server branch restarts the server; with players online it waits for their 5-minute countdown. A new build that writes no status file within 3 minutes is rolled back and held (`/var/lib/runebound/deploy_hold`); the next newer commit lifts the hold.
- **Ship:** `tools\run_godot.cmd release` pushes `main` to `release` (fast-forward only; refuses if main is dirty, unpushed or not the current branch) and deploys now. `tools\run_godot.cmd deploy` only triggers the deploy. Ship only on the user's request.
- **Protocol lesson (2026-09-30):** the server runs `release`, the user plays from `main`. When `main` bumps `Net.PROTOCOL` and `release` stays behind, the user is refused although the game is current (release sat at protocol 8 while main was 12). `Net.version_reason` now names the side that is behind ("this server runs an older RUNEBOUND" = ship a release; "your game is older" = `git pull`). After every bump remind the user. Friends play from `release`.
- Godot versions must match in major.minor (`Net.godot_minor`).

## Measurements (dated, M09, 2026-09-25..28)
- Dedicated server, 1 hero: p50 2.0 ms per tick; 5 full bots p50 7.6 / p95 17.9 ms; 4 bots on the laptop p95 8-11 ms.
- From the owner's main PC: Funnel path RTT p50 62 / p95 90 ms; the tailnet path of that PC only ran over a DERP relay (40-208 ms, p95 669 ms, stalls up to 14.6 s).

## Funnel and DNS
- A freshly enabled Funnel takes about 10 minutes to appear in public DNS.
- On a tailnet Windows PC `Resolve-DnsName -Server 1.1.1.1` still returns the tailnet IP (NRPT): resolve over DNS-over-HTTPS (`dns.google/resolve`). `run_godot wsspike <host>` does it.

## Quirks
- `pkill -f` inside an ssh command matches the ssh shell's own command line: split into separate ssh calls.
- The laptop login user's PATH lacks `/usr/sbin` (iptables, runuser).
- `systemd-analyze security --offline=true x.service` scores a unit without installing it; `systemd-run --user -p SystemCallFilter=... -p MemoryDenyWriteExecute=yes` tests seccomp and W^X without root (Godot 4.6.3 runs fine under both).
- The net suite is a multi-process test: see workflow.md "Tests and measurements" for RAM, logs and the rule not to edit scripts while it runs.
- Local server for tests and joining from the title: `tools\run_godot.cmd server [port]` (join `127.0.0.1`), or `coop [bots]` for server + companion bots + the window.
