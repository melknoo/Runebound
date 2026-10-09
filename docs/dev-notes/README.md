# Dev notes

Know-how for whoever works on RUNEBOUND (human or Claude) that the architecture docs do not carry: how the toolchain behaves, what bit us, how the server is operated. Written 2026-10-09 from Claude's local memory so that a second machine starts with the same knowledge.

| Note | Read before |
| --- | --- |
| [workflow.md](workflow.md) | setting up a machine, running tests or perf A/B, using MCP servers, editing files from a shell, committing |
| [gotchas.md](gotchas.md) | writing GDScript, scenes, UI, net code or tests |
| [server-ops.md](server-ops.md) | touching the server, releases, deploys, the net suite |

Rules for these notes:
- This repo is public: no secrets, IPs or address prefixes. (The laptop's host name is already in `resources/net/servers.json` by the user's decision, do not spread it further.)
- Facts carry a date where they can age. Verify an old one before relying on it.
- Claude's local memory is not synced between machines. A durable lesson (a gotcha, a workflow rule, a user decision) is written here or into CLAUDE.md in the same piece of work, not only into memory.
- Architecture belongs in TECHNICAL_ARCHITECTURE, milestone status in PROJECT_STATE, open problems in KNOWN_ISSUES. These notes only link to them.
- `laptop_prompt` in the repo root is a historical one-shot prompt (2026-09-24) for the first server laptop setup. Ignore it.
