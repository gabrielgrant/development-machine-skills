# Claude Remote Control lifecycle

How `claude remote-control` sessions persist, resume, and get lost.
None of this is in upstream docs; it was verified against the Claude
Code 2.1.237 binary (built 2026-08-19). Internals like these can change
between versions — re-verify the specifics before leaning hard on them.

## "Environment" is two unrelated things

| | Remote Control environment | Cloud environment |
|---|---|---|
| ID prefix | `env_…` | `ccpool_…` |
| Created by | `claude remote-control` registering itself | Anthropic-side (or self-hosted pool), used via `--environment` |
| Code runs on | **your machine, always** | Anthropic sandbox |

The RC environment is a server-side routing record — machine name,
directory, branch, repo URL, max sessions. The supervisor long-polls it
for work; each work item is a session it spawns locally. Nothing about
it is compute.

## The bridge pointer

`--continue` works through a local pointer file:

- Path: `~/.claude/projects/<encoded-project-dir>/bridge-pointer.json`
- Shape: `{sessionId, environmentId, source: "standalone"|"repl", pid, procStart}`
- Written on startup, refreshed hourly while running, considered fresh
  for **4 hours** (`BRIDGE_POINTER_TTL_MS`) — the "roughly the last
  4 hours" in `--continue`'s help text.

On startup the supervisor reads it. Pointer's pid dead + `source:
"standalone"` → it requests reuse of that environment when registering.
Same `env_…` id back → existing claude.ai threads reconnect. Server
declines → it warns ("Existing claude.ai/code sessions from the
previous run will not reconnect"), **clears the pointer**, and runs
under a fresh environment.

A cleared or missing pointer is the usual cause of the
duplicate-thread-on-every-restart symptom: with nothing to reuse, each
restart registers fresh. Spawn mode is not lost with it — that persists
separately (`remoteControlSpawnMode` under the project's entry in
`~/.claude.json`).

If the pointer's pid is still alive, a second instance in the same
directory refuses to start ("Exiting to avoid a split-brain conflict").

## Shutdown: preserve vs deregister

Two exits:

- **Preserving** (normal SIGTERM path): skips archive + deregister,
  prints "Environment preserved. Restart `claude remote-control` to
  reconnect existing sessions."
- **Final**: archives every session, then deletes the environment.

SIGKILL takes neither — the process just dies, the server eventually
notices, and sessions that end while the machine is offline are cleaned
up server-side ("…the environment was cleaned up on the server and
can't be resumed"). Worktrees are deliberately kept ("Your work is safe
— worktrees kept: …").

Shutdown allows stuck sessions a 30s grace before force-kill; give any
supervisor a stop timeout above that.

## Reviving a single session

`claude remote-control --session-id cse_…` looks the session up
server-side, reads its recorded environment id, re-registers against
*that* environment, and re-queues the session — unarchiving it first if
needed. The original claude.ai thread reattaches instead of a duplicate
appearing. It cannot be combined with `--continue` or spawn flags, and
fails plainly when the session or its environment is gone ("may have
been archived or expired").

## What survives everything

Local transcripts (`~/.claude/projects/<slug>/<session-uuid>.jsonl`)
and worktrees are independent of all server-side state — deleting an
environment, archiving a session, or wiping the pointer touches none of
it. Recovery recipes built on that floor: [recovery.md](recovery.md).

## Why the supervision wrapper splits on elapsed time

`--continue` exits nonzero both when there is nothing to resume and
when a resumed session dies much later (network, crash). A supervisor
that treats those the same falls through to a fresh environment after
every late failure — silently abandoning the thread. An immediate exit
(<10s) means the pointer lookup itself failed; only that case should
start fresh. Late failures re-exit so the restart loop lands back in
`--continue` while the pointer is still warm.
