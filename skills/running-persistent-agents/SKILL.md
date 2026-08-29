---
name: running-persistent-agents
description: Runs persistent, remotely-accessible coding agents on the dev machine — one systemd-supervised claude remote-control per repo, surviving crashes and reboots and reconnecting to the same claude.ai threads. Day-to-day nothing is run on the machine — open claude.ai/code or the mobile app and work in the repo's environment; each thread gets its own worktree session there. Enabling an already-set-up machine for another repo is one command, systemctl --user enable --now claude-rc@<repo>. Use for first-time install on a machine, or to recover when something breaks — a thread died or duplicated in claude.ai/code, a worktree was orphaned, an old session needs reviving.
---

# Running persistent agents

One systemd unit instance per repo runs `claude remote-control` as a
supervisor. Every thread opened in claude.ai/code or the mobile app
becomes its own session in its own git worktree on this machine; all
execution is local. After install, day-to-day use involves no commands
here — steer entirely from the app.

## Install

Once per machine — both files are dotfile-layer state, so record them:

```bash
cp templates/claude-rc-supervise ~/.local/bin/        # from this skill
cp templates/claude-rc@.service ~/.config/systemd/user/
chezmoi add ~/.local/bin/claude-rc-supervise \
            ~/.config/systemd/user/claude-rc@.service
loginctl enable-linger "$USER"    # units outlive logout and reboot
```

Commit in `$SERVER_CONFIG_DIR` like any deliberate machine change.

Once per repo, lazily — whenever a repo should first host a persistent
agent (its environment should already be set up per using-project-envs,
since the unit launches through `repo-env exec`):

```bash
systemctl --user enable --now claude-rc@<repo>   # %i = dir under ~/repos
```

## Day-to-day

Nothing to run on the machine. If you must stop or restart a
supervisor, only via `systemctl --user stop|restart claude-rc@<repo>`:
SIGTERM lets it hand its threads back for reconnection, `kill -9`
forfeits them.

The one thing systemd can't host is a session you also *sit in*
locally (there's no TTY to attach). For that, run `claude` in the repo
— `/rc` makes it remotely steerable too — inside tmux if it should
survive SSH disconnects. That's tmux's only remaining role here.

## When something breaks

Dead or duplicated threads, orphaned worktrees, reviving old sessions:
[reference/recovery.md](reference/recovery.md). What resume does under
the covers — the pointer file, environment reuse, what each failure
message means: [reference/rc-lifecycle.md](reference/rc-lifecycle.md).
