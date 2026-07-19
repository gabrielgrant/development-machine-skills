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

Also install the bundled CLI on the dev machine itself:

```bash
cargo install --git https://github.com/gabrielgrant/development-machine-skills repo-env
```

## The model

Machine state is split into layers, each with one owner. Anything with no
owner is drift, and the tooling exists to find it and file it.

| Layer | Owner | Lives in |
|---|---|---|
| Host packages, services, groups | apt manifest + idempotent `apply.sh` | `~/server-config/host/` |
| `/etc` change audit | etckeeper | `/etc/.git` (local) |
| Dotfiles (loaders + snippets) | chezmoi | `~/server-config/dotfiles/` |
| Everyday CLI tools | Devbox Global | `~/server-config/devbox-global/` |
| Per-repo environments | Devbox/devcontainer overlays | `~/server-config/environments/` |
| Runtime versions | project's own file (`.nvmrc`, `rust-toolchain.toml`) | project repo |
| Repos, agent state, secrets | backups (not git) | backup target |

`~/server-config` is one private git repo; every deliberate machine change
is a commit there. Shell config stays in `$HOME`: `.bashrc`/`.profile` get
one marker-guarded block that sources numbered snippets from
`~/.config/shell/{bashrc.d,profile.d}/` — installers never own lines in the
core files.

## Day-to-day workflows

These are the things you (or an agent following the skills) actually type.

### Set up a fresh machine

```bash
bash skills/setting-up-dev-machine/scripts/apply.sh   # bootstrap + converge
```

Then follow the rest of the **setting-up-dev-machine** skill (chezmoi
wiring, devbox global profile). From then on the machine's converge tool is
`~/server-config/host/apply.sh`; rerunning it is always safe and a clean
run means "machine matches the config".

### Start working on a project

```bash
git clone git@github.com:someorg/proj.git ~/repos/proj && cd ~/repos/proj
repo-env setup            # creates a personal env overlay keyed to the
                          # git remote, plus a git-ignored .envrc
devbox add nodejs@24 --config "$(repo-env path)"   # whatever it needs
```

After `setup`, just `cd`-ing into the repo activates the environment
(direnv). The overlay lives in `~/server-config/environments/`, so nothing
is committed to the upstream repo — commit the overlay to server-config
instead. If the project declares its own runtime (`.nvmrc`,
`rust-toolchain.toml`, its own `devbox.json`), that declaration wins; don't
duplicate it in the overlay. Details: **using-project-envs**.

### Launch an agent (or anything non-interactive) in a project

```bash
repo-env exec claude      # = direnv exec <git-root> claude
repo-env exec npm test
```

Needed because direnv's automatic activation only fires in interactive
shells — editors, systemd, portals, and agent launchers bypass it.

### Install a tool

Decide the layer first (cheatsheet; full ladder in **installing-dev-tools**):

```bash
# machine infrastructure (docker, tmux):
echo <pkg> >> ~/server-config/host/apt-packages.txt && ~/server-config/host/apply.sh
# everyday CLI tool (rg, jq, gh):
devbox global add <pkg> && devbox global install
# needed by one project:
devbox add <pkg> --config "$(repo-env path)"
```

For `curl | bash`-only tools: point the installer at a snippet
(`PROFILE=~/.config/shell/bashrc.d/20-<tool>.sh`) or diff your dotfiles
after and normalize (**normalizing-dotfiles**). Then commit to
server-config with provenance.

### When an installer scribbled on .bashrc

`chezmoi diff` shows it. Triage each change — accept, move into a numbered
snippet, or delete — per **normalizing-dotfiles**. Goal state: core
dotfiles are distro-default + one loader block, forever.

### Check the machine is fully captured

```bash
~/server-config/host/machine-audit.sh
```

Clean output = everything is owned. Findings map to a remediation skill
(**auditing-dev-machine**). Run after ad-hoc work sessions, before
migrations/backups, or monthly.

### Migrate / rebuild / restore

**migrating-dev-machine** covers both adopting this pattern on an existing
machine and moving old server → new server (inventory → staged copy →
three-way merge → selective reinstall → cutover). **backing-up-dev-machine**
lists what to back up vs rebuild; a restore is "run setup, restore state,
reinstall runtimes".

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

- `tools/repo-env/` — Rust CLI that maps a checkout's git remote to a
  personal environment overlay: `setup` (create overlay + ignored `.envrc`),
  `exec` (run a command inside the env), `path`/`key`/`init`/`doctor`.
- Bash scripts bundled inside the skills that use them (`skills/*/scripts/`):
  `apply.sh` (host converge), `machine-audit.sh` (drift),
  `machine-inventory.sh` (full capture), `home-conflicts.sh` (migration
  comparison).
