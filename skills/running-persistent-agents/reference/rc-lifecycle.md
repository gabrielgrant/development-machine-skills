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

Vocabulary: the **environment** is the container — what claude.ai/code
groups sessions under in the sidebar, one per `claude remote-control`
registration. Each thread inside it is a **session** (`cse_…` /
`session_…`), and the local process serving the environment is the
**supervisor**. When an environment is deleted server-side, its
sessions drop into the sidebar's "Other" section with
`environment_deleted` — a recoverable state (recovery.md), despite the
error text.

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

## Why not --continue

Resuming and plain-starting are different code paths, and the resume
flags (`--continue`, `--session-id`) do two things a supervisor does not
want. Spawn mode is chosen as:

    if (resuming)          spawnMode = "single-session"   // reason: "resume"
    else if (--spawn given) spawnMode = flag              // reason: "flag"
    else if (saved)        spawnMode = remoteControlSpawnMode
    else                   spawnMode = "same-dir"

so a resumed supervisor is always single-session — it serves one thread
and exits when that thread completes, regardless of
`remoteControlSpawnMode` in `~/.claude.json`. Observed: a supervisor
started as `Capacity: 1/32 - New sessions will be created in an isolated
worktree` came back after a `--continue` restart as `Resuming session
... - Single session - exits when complete`.

Second, pointer-based environment reuse is gated on *not* resuming
(`if (!resuming && ...) { read pointer; reuseEnvironmentId = ... }`).

A plain `claude remote-control --spawn=worktree` gets both: it reads the
pointer, re-registers the same `env_...` so existing threads reconnect,
and keeps worktree spawning. That is why the unit takes no resume flag
and needs no wrapper — restart is just the same command again.

(`--continue` remains the right tool for a one-off manual reattach to a
single session, which is what its help describes.)

## Pointer ownership: one owner per directory

The pointer is written by the instance that *owns* it, and ownership is
decided once at startup:

- If a prior pointer exists whose recorded pid is still alive, the new
  instance logs "pointer writer pid N still running; registering a
  fresh env, deferring pointer write" and never writes one — for its
  whole lifetime, even after that other process exits.
- Otherwise it writes the pointer after creating its initial in-directory
  session, and refreshes it hourly. `--no-create-session-in-dir`
  therefore also leaves no pointer.

A manual session that runs `/rc` counts as a pointer writer (`source:
"repl"`), and only `source: "standalone"` pointers are eligible for
reuse. So `/rc` in a directory that a supervisor also serves is enough
to leave the supervisor permanently pointerless — and a pointerless
supervisor can never reuse its environment, so every restart strands
the previous threads.

This is not hypothetical: the `git-prov` supervisor (running since
2026-08-20) has no pointer file, having started while a manual `/rc`
session was live in the same directory.

## Shutdown: preserve vs deregister

Two exits:

- **Preserving** (normal SIGTERM path): skips archive + deregister and
  prints "Environment preserved. Restart `claude remote-control` to
  reconnect existing sessions." — on stdout, which the unit sends to
  null, so it never reaches the journal. There, the surviving pointer
  file is the signal.
- **Final**: archives every session, then deletes the environment.

SIGKILL takes neither — the process just dies, the server eventually
notices, and sessions that end while the machine is offline are cleaned
up server-side ("…the environment was cleaned up on the server and
can't be resumed"). Worktree fate differs by path: crashes and
disconnects keep them ("Your work is safe — worktrees kept: …"), while
a *graceful* shutdown removes the worktrees and branches of the
sessions it is actively serving ("removed worktree <path>", observed
2026-08-31). Transcripts are unaffected either way; recovery.md covers
restoring a removed worktree.

Shutdown allows stuck sessions a 30s grace before force-kill; give any
supervisor a stop timeout above that.

## Reviving a single session

`claude remote-control --session-id cse_…` looks the session up
server-side, reads its recorded environment id, re-registers against
*that* environment, and re-queues the session — unarchiving it first if
needed. The original claude.ai thread reattaches instead of a duplicate
appearing. It cannot be combined with `--continue` or spawn flags.
"Session … not found" is the one fatal case. A *deleted environment* is
not fatal: the code carries a fallback ("Could not resume session — its
environment has expired. Creating a fresh session instead."), but in
practice the backend honored `reuseEnvironmentId` for an environment
that had shown `environment_deleted` for days — the id was resurrected,
the original thread reattached, and the session's `last_init_error`
cleared (verified 2026-08-31 on 2.1.252). The server's error text
("its state cannot be recovered") describes the environment's serving
state, not the recoverability of its id or sessions.

## What survives everything

Local transcripts (`~/.claude/projects/<slug>/<session-uuid>.jsonl`)
and worktrees are independent of all server-side state — deleting an
environment, archiving a session, or wiping the pointer touches none of
it. Recovery recipes built on that floor: [recovery.md](recovery.md).
