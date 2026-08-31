# Recovering Remote Control sessions

Under the systemd pattern these states are rare — they mostly date from
pre-systemd manual runs, a SIGKILL, or the machine being offline long
enough for the server to clean up. Model background:
[rc-lifecycle.md](rc-lifecycle.md).

Ground truth first: local transcripts
(`~/.claude/projects/<encoded-dir>/<session-uuid>.jsonl`) and the
spawned worktrees are independent of every server-side state. No
failure below loses conversation history.

| Symptom | Recovery |
|---|---|
| Supervisor stopped or died within the last ~4h | `systemctl --user restart claude-rc@<repo>` — the wrapper's `--continue` reconnects the environment and its threads. |
| Threads duplicate in claude.ai/code on every restart | The local pointer was cleared, so the supervisor registers a fresh environment each start (lifecycle doc, pointer section). The old threads aren't reattachable as a group; revive the ones that matter individually (next row) and let new work accumulate under the fresh environment. |
| One specific thread to revive (archived, or its environment dead) | Stop the unit first — a running supervisor in the same directory wins the split-brain guard. Then `cd <its worktree>` and `claude remote-control --session-id cse_…`: reattaches the *original* claude.ai thread, unarchiving if needed, and fails plainly if the environment is gone. Restart the unit afterwards. |
| Environment gone for good ("cleaned up on the server and can't be resumed") | `cd <worktree> && claude --resume <session-uuid>` continues the conversation locally; `/rc` inside it restores remote steering — as a new claude.ai thread, the old one being unrecoverable. |
| Which worktree belongs to which session? | Worktree names embed the server session id (`bridge-cse_…`); each transcript dir under `~/.claude/projects/` is keyed by the worktree path and records branch, title, and last prompt. |

## Adopting a repo that already has a hand-started supervisor

A `claude remote-control` started by hand can't be adopted in place:
the unit won't start while another instance holds the same directory,
and every claude.ai thread that supervisor hosts is one of its child
processes and dies with it — including, quite possibly, the session
you are reading this in. Check with `ps -o ppid= -p $$` and walk the
ancestry before starting.

Do the switch from somewhere that supervisor doesn't own — another
repo's session, a local `claude` in tmux, or plain SSH:

```bash
kill -TERM <old-pid>          # never -9; SIGTERM is what preserves the environment
systemctl --user enable --now claude-rc@<repo>
```

Threads reconnect only if `~/.claude/projects/<encoded-dir>/bridge-pointer.json`
exists and is under 4h old. Check for it *first*: a supervisor that
started while another instance held the directory never writes one
(rc-lifecycle.md, "Pointer ownership"), and then the new unit registers
a fresh environment and the old threads must be revived individually
(table above). Make sure nothing else — including a manual session that
ran `/rc` — is left holding the directory, or the new unit inherits the
same problem.

## Two habits prevent most of this

- Stop supervisors only with SIGTERM (`systemctl --user stop`), never
  `kill -9` — clean shutdown is what preserves the environment for
  reconnection.
- `claude --resume` restores the conversation, never the cwd. Always
  `cd` into the session's own directory first, or it resumes stranded
  outside its files.
