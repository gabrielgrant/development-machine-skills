---
name: running-persistent-agents
description: Runs persistent, remotely-accessible coding agents on the dev machine — one systemd-supervised claude remote-control per repo, surviving crashes and reboots and reconnecting to the same claude.ai threads. Day-to-day nothing is run on the machine — open claude.ai/code or the mobile app and work in the repo's environment; each thread gets its own worktree session there. Enabling an already-set-up machine for another repo is two commands, `claude` once in the repo to accept workspace trust, then systemctl --user enable --now claude-rc@<repo>. Use for first-time install on a machine, or to recover when something breaks — a thread died or duplicated in claude.ai/code, a worktree was orphaned, an old session needs reviving.
---

# Running persistent agents

One systemd unit instance per repo runs `claude remote-control` as a
supervisor. Every thread opened in claude.ai/code or the mobile app
becomes its own session in its own git worktree on this machine; all
execution is local. After install, day-to-day use involves no commands
here — steer entirely from the app.

## Install

Once per machine. Prerequisite: `repo-env` installed *and recorded*
(using-project-envs — the `run_onchange_install-repo-env.sh` script in
`$SERVER_CONFIG_DIR/dotfiles/`, applied by `chezmoi apply`). ExecStart
execs it through `bash -lc`, which finds it in `~/.local/bin`; a rebuild
that restores the unit without that script crashloops on a missing
binary. Then the unit itself — both files are dotfile-layer state, so
record them:

```bash
mkdir -p ~/.config/systemd/user
SKILL=~/.agents/skills/running-persistent-agents      # this skill's own dir
cp "$SKILL"/templates/claude-rc@.service ~/.config/systemd/user/
chezmoi add ~/.config/systemd/user/claude-rc@.service
cp "$SKILL"/templates/enable-claude-rc.sh "$SERVER_CONFIG_DIR/host/scripts.d/"
```

Commit in the server-config repo (`~/server-config`) like any
deliberate machine change. `chezmoi add` records the unit template
only. The linger flag and *which repos are enabled* aren't dotfile
state and would otherwise be pure drift — a rebuilt machine gets the
unit template back and no supervisors. Both live in the host script
instead: `enable-claude-rc.sh` sets linger and enables a `REPOS` list
that you edit as the record, and `host/apply.sh` runs it. It enables
only repos whose workspace trust is already recorded and prints the
command for the rest, so a rebuild never leaves a crashlooping unit
behind (see the trust note below).

Once per repo, lazily — whenever a repo should first host a persistent
agent (its environment should already be set up per using-project-envs,
since the unit launches through `repo-env exec`). `new-project --serve
<repo>` (using-project-envs) does all of the below except the trust
dialog, for a new or existing repo; by hand:

```bash
cd ~/repos/<repo> && claude    # once: accept the workspace trust dialog, then quit
systemctl --user enable --now claude-rc@<repo>           # %i = dir under ~/repos
journalctl --user -u claude-rc@<repo> -n 20 --no-pager   # confirm it came up
```

The repo needs at least one commit. `--spawn=worktree` branches per
session, and `git worktree add` cannot branch from an unborn HEAD, so a
freshly-`git init`ed repo passes `repo-env setup` and every check here,
then fails at the first thread from the app. Commit the environment
files (`repo-env setup` writes them) before enabling.

Remote control refuses to start in an untrusted directory, and that
dialog needs a terminal — the unit can't accept it for you. Untrusted,
it crashloops until systemd gives up ("Start request repeated too
quickly"), so read the journal rather than trusting `enable --now`'s
exit code. The journal carries systemd's own lines plus
environment-loading errors (stderr); the supervisor's status output is
dropped — if a start fails without an obvious cause, add a drop-in with
`StandardOutput=journal`, reproduce, then remove it.

There is no headless way to accept trust, and one apparent way is a
trap: `claude -p '…'` in an untrusted directory *runs and exits 0*
while leaving `hasTrustDialogAccepted: false` in `~/.claude.json` — it
bypasses the check rather than recording consent, so the supervisor
still refuses. Nor is hand-editing that flag a shortcut worth taking:
it is a security boundary, the file is rewritten live by every running
session and every other supervisor, and an agent asked to do it should
expect to be blocked. Accept the dialog in a terminal.

**One remote-control owner per directory.** A supervisor that starts
while another instance (including a manual session that ran `/rc`) is
live in the same directory permanently gives up its bridge pointer, and
without one it can never reuse its environment — every restart then
strands the previous threads. A repo already running a hand-started
supervisor needs [reference/recovery.md](reference/recovery.md) first;
adoption isn't in-place.

## Day-to-day

Nothing to run on the machine. If you must stop or restart a
supervisor, only via `systemctl --user stop|restart claude-rc@<repo>`:
SIGTERM lets it hand its threads back for reconnection, `kill -9`
forfeits them. Restart is idempotent — the unit re-registers the same
environment and keeps worktree spawning. A graceful stop also tidies:
worktrees of actively-served sessions are removed if clean with no
extra commits, and kept (with a "kept worktree" message) if they hold
any uncommitted or unmerged work (reference/recovery.md).

Don't add `--continue` to the unit. It looks like the way to resume,
but it forces single-session mode and skips environment reuse
([reference/rc-lifecycle.md](reference/rc-lifecycle.md), "Why not
--continue").

The one thing systemd can't host is a session you also *sit in*
locally (there's no TTY to attach). For that, run `claude` in the repo
— `/rc` makes it remotely steerable too — inside tmux if it should
survive SSH disconnects. That's tmux's only remaining role here.

## When something breaks

Dead or duplicated threads, orphaned worktrees, reviving old sessions,
adopting a hand-started supervisor:
[reference/recovery.md](reference/recovery.md). What resume does under
the covers — the pointer file, environment reuse, what each failure
message means: [reference/rc-lifecycle.md](reference/rc-lifecycle.md).
