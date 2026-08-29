---
name: managing-dev-machine
description: Router and conventions for managing a development machine (Ubuntu dev server/VM) as versioned, reproducible layers. Use when the user mentions their dev machine, dev server, VM setup, server-config repo, dotfile management, chezmoi, devbox, direnv, etckeeper, or asks where some tool/config/state should live. Routes to the specific workflow skills.
---

# Managing a dev machine

Machine state is split into layers. Every piece of state has exactly one
owner; anything unowned is drift.

| Layer | Owner | Lives in |
|---|---|---|
| Host packages, Docker, services, groups, firewall | apt manifest + idempotent apply/host scripts | `$SERVER_CONFIG_DIR/host/` |
| Actual `/etc` change history | etckeeper | `/etc/.git` (local only, sensitive) |
| Shell/git/ssh config (dotfiles) | chezmoi | `$SERVER_CONFIG_DIR/dotfiles/` |
| Everyday CLI tools (rg, jq, fzf, gh...) | Devbox Global | `$SERVER_CONFIG_DIR/devbox-global/` |
| Per-repo dev environments | Devbox/devcontainer overlays | `$SERVER_CONFIG_DIR/environments/<host>/<owner>/<repo>/` |
| Runtime versions in a project | the project's own declaration (`.nvmrc` → nvm, `rust-toolchain.toml` → rustup, `devbox.json` pin) | project repo |
| Custom nix packaging for tools | local flakes | `$SERVER_CONFIG_DIR/packages/<tool>/` |
| Migration/baseline inventories | plain files in git | `$SERVER_CONFIG_DIR/inventories/` |
| Repos, agent session state, caches, secrets | backups — never the config repo | backup target |

## Conventions

- `SERVER_CONFIG_DIR` defaults to `~/server-config`: a single private git repo
  holding all of the above except `/etc` history and backups.
- Shell startup: `~/.bashrc` and `~/.profile` keep their distro content and
  gain one chezmoi-managed marker block that sources
  `~/.config/shell/bashrc.d/*.sh` / `~/.config/shell/profile.d/*.sh`.
  Each tool integration is one numbered snippet file (e.g. `20-nvm.sh`).
  Installers never permanently own lines in the core files.
- Project activation is automatic via direnv (`.envrc` excluded through
  `.git/info/exclude`); agents and non-interactive launches go through
  `direnv exec` / the `repo-env` tool.
- Every deliberate machine change becomes a commit in `$SERVER_CONFIG_DIR`
  with provenance ("from rustup installer", "needed by project X").
- The host layer is deliberately plain bash + a package manifest, not
  Ansible; see setting-up-dev-machine for why and when to reintroduce it.

## Which skill

| Task | Skill |
|---|---|
| Fresh machine → this pattern | setting-up-dev-machine |
| Existing machine (in place) or old→new server move | migrating-dev-machine |
| Install a tool; decide which layer it belongs in | installing-dev-tools |
| An installer edited `.bashrc`/`.profile`; `chezmoi diff` is dirty | normalizing-dotfiles |
| Work on / launch agents in a repo (esp. third-party) | using-project-envs |
| Run persistent, remotely-accessible agents; fix their sessions | running-persistent-agents |
| Find unmanaged drift | auditing-dev-machine |
| Back up or restore persistent state | backing-up-dev-machine |
