# development-machine-skills

Agent skills that codify how to manage a development machine (an Ubuntu dev
server/VM used for coding agents and project work) as a set of versioned,
reproducible layers instead of an opaque "pet" server.

## Install

Compatible with [vercel-labs/skills](https://github.com/vercel-labs/skills):

```bash
npx skills add gabrielgrant/development-machine-skills
# or a single skill:
npx skills add gabrielgrant/development-machine-skills --skill migrating-dev-machine
```

## The model

Machine state is split into layers, each with one owner:

| Layer | Owner | Lives in |
|---|---|---|
| Host packages, services, groups | Ansible + APT | `~/server-config/ansible/` |
| `/etc` change audit | etckeeper | `/etc/.git` (local) |
| Dotfiles (loaders + snippets) | chezmoi | `~/server-config/dotfiles/` |
| Everyday CLI tools | Devbox Global | `~/server-config/devbox-global/` |
| Per-repo environments | Devbox/devcontainer overlays | `~/server-config/environments/` |
| Runtime versions | project's own file (`.nvmrc`, `rust-toolchain.toml`) | project repo |
| Repos, agent state, secrets | backups (not git) | backup target |

Activation is automatic via direnv; agents and non-interactive launches use
`direnv exec` (wrapped by the bundled `repo-env` tool).

## Skills

- **managing-dev-machine** — router: the layer model, conventions, and which skill to use when
- **setting-up-dev-machine** — bootstrap a fresh machine into the pattern
- **migrating-dev-machine** — adopt the pattern in place, or migrate an old server to a new one
- **installing-dev-tools** — decide where a new tool belongs and install it reproducibly
- **normalizing-dotfiles** — triage installer-written dotfile changes (accept / reorganize / reject)
- **using-project-envs** — per-repo environments for repos you don't control
- **auditing-dev-machine** — detect drift between managed config and reality
- **backing-up-dev-machine** — what to back up vs rebuild

## Tools

- `tools/repo-env/` — Rust CLI that maps a checkout's git remote to a personal
  environment overlay and handles `.envrc` setup and `direnv exec` wrapping.
  Install: `cargo install --path tools/repo-env` (or `--git` this repo).
- Bash scripts are bundled inside the skills that use them
  (`skills/*/scripts/`).
