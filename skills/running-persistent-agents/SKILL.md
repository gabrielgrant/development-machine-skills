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

Once per machine. Both files are dotfile-layer state, so record them:

```bash
mkdir -p ~/.config/systemd/user
SKILL=~/.agents/skills/running-persistent-agents      # this skill's own dir
cp "$SKILL"/templates/claude-rc@.service ~/.config/systemd/user/
chezmoi add ~/.config/systemd/user/claude-rc@.service
loginctl enable-linger "$USER"    # units outlive logout and reboot
```

Commit in the server-config repo (`~/server-config`) like any
deliberate machine change. `chezmoi add` records the unit only — the
linger flag and which repos are enabled aren't dotfile state, so note
the enabled repos wherever the host layer lives if a rebuild should
restore them.

Once per repo, lazily — whenever a repo should first host a persistent
agent (its environment should already be set up per using-project-envs,
since the unit launches through `repo-env exec`):

```bash
cd ~/repos/<repo> && claude    # once: accept the workspace trust dialog, then quit
systemctl --user enable --now claude-rc@<repo>           # %i = dir under ~/repos
journalctl --user -u claude-rc@<repo> -n 20 --no-pager   # confirm it came up
```

Remote control refuses to start in an untrusted directory, and that
dialog needs a terminal — the unit can't accept it for you. Untrusted,
it crashloops until systemd gives up ("Start request repeated too
quickly"), so read the journal rather than trusting `enable --now`'s
exit code.

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
environment and keeps worktree spawning.

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
