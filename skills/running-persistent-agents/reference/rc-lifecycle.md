# Claude Remote Control lifecycle

How `claude remote-control` sessions persist, resume, and get lost.
None of this is in upstream docs; it was read out of the Claude Code
2.1.237 binary and the behavioural claims re-checked live on 2.1.252.
Internals like these can change between versions — re-verify before
leaning hard on them.

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
- Usually written on startup, refreshed hourly while running,
  considered fresh for **4 hours** (`BRIDGE_POINTER_TTL_MS`) — the "roughly the last
  4 hours" in `--continue`'s help text.

On startup the supervisor reads it. Pointer's pid dead + `source:
"standalone"` → it requests reuse of that environment when registering.
Same `env_…` id back → existing claude.ai threads reconnect. Server
declines → it warns ("Existing claude.ai/code sessions from the
previous run will not reconnect"), **clears the pointer**, and runs
under a fresh environment.

A cleared or missing pointer is the usual cause of the
duplicate-thread-on-every-restart symptom: with nothing to reuse, each
restart registers fresh. Long-running supervisors have been observed
with no pointer at all, so check the file exists before counting on
`--continue`.

## Restart loses worktree mode

`--continue` reattaches *the single session recorded in the pointer*,
not the environment as a whole, and it refuses `--spawn` outright
("--session-id and --continue cannot be used with --spawn, --capacity,
or --create-session-in-dir"). So a supervisor that started as

    Capacity: 1/32 - New sessions will be created in an isolated worktree

comes back after `systemctl --user restart` as

    Resuming session session_... - Single session - exits when complete

even though `remoteControlSpawnMode` is still `worktree` under the
project's entry in `~/.claude.json` (observed on 2.1.237 and 2.1.252).
The environment id *is* reused, so existing threads reconnect; new
threads just stop getting their own worktree. The runtime toggle for
spawn mode (`w`) is TTY-only, so a unit can't correct it.

To force worktree mode back, stop the unit, delete the project's
`bridge-pointer.json`, and start it — at the cost of the old threads no
longer reattaching as a group.

If the pointer's pid is still alive, a second instance in the same
directory refuses to start ("Exiting to avoid a split-brain conflict").

## Shutdown: preserve vs deregister

Two exits:

- **Preserving** (normal SIGTERM path): skips archive + deregister.
  The binary carries an "Environment preserved…" status string for
  this, but it was not observed in the journal on a clean
  `systemctl --user stop` — treat the surviving pointer file, not that
  message, as the signal that the environment was kept.
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
