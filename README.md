# development-machine-skills

Agent skills that codify how to manage a development machine (an Ubuntu dev
server/VM used for coding agents and project work) as a set of versioned,
reproducible layers instead of an opaque "pet" server.

The division of labor: **you** start sessions and make judgment calls;
**agents** (following these skills) do the machine chores — setup,
migration, tool installs, drift cleanup. The human surface area is
deliberately small.

## Install

Skills (compatible with [vercel-labs/skills](https://github.com/vercel-labs/skills)):

```bash
npx skills add gabrielgrant/development-machine-skills
```

The `repo-env` CLI, on the dev machine:

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
one marker-guarded block sourcing numbered snippets from
`~/.config/shell/{bashrc.d,profile.d}/` — installers never own lines in the
core files.

## What you do yourself

### Start work on a project

```bash
cd ~/repos
git clone git@github.com:someorg/proj.git proj   # existing project
mkdir proj                                       # or brand-new — no GitHub repo needed
cd proj
repo-env setup     # once per checkout (offers git init for fresh dirs)
```

For **your own projects** (no origin remote yet), setup defaults to a
committable `devbox.json` + `.envrc` in the repo — it travels with the
project and works on any machine. For **third-party repos** it defaults to
a personal overlay outside the repo so upstream stays untouched
(`--in-repo`/`--overlay` override either way).

From then on, `cd`-ing into the repo activates its environment
automatically, and **anything you launch from that shell — including
agents — inherits it**. Ask the agent to populate the environment as needs
surface, or do it yourself (`devbox add <pkg>`, plus
`--config "$(repo-env path)"` in overlay mode).

### Launch a persistent agent session

On the dev machine:

- **Claude:** the
  [running-persistent-agents](skills/running-persistent-agents/SKILL.md)
  skill — one systemd-supervised `claude remote-control` per repo.
  Threads opened in [claude.ai/code](https://claude.ai/code) or the
  mobile app each get their own worktree session on the machine and
  survive crashes and reboots. For a session you also want to sit in
  locally, run `claude --remote-control` in the repo, in tmux
  ([docs](https://code.claude.com/docs/en/remote-control)).
- **Codex:** run `codex remote-control start` then `codex remote-control
  pair` once on the dev machine — a daemon that pairs with the ChatGPT
  mobile/desktop app and surfaces the machine's codex sessions there,
  independent of your laptop. (The desktop app's *Settings → Connections →
  SSH* feature is different: your laptop SSHes to the dev machine and
  proxies it, so it stops working when the laptop sleeps.) Lowest-tech
  fallback: `codex` inside tmux, reattach over SSH from any device.
- **Containerized agents:** the
  [opencode-docker-glibc](https://github.com/gabrielgrant/opencode-docker-glibc)
  `*-project` scripts still work as before; container envs come from the
  image, not the host overlay.

systemd is what keeps an agent alive and reconnecting; the
remote-control layer is what lets you steer it from anywhere; tmux
earns a place only in sessions you also sit in locally.

`repo-env exec <cmd>` exists for launches that *don't* pass through an
interactive shell in the repo — systemd units, the agent portal, editor
tasks, cron — which mostly means it appears inside automation, not your
typing.

### Delegate everything else

Machine chores are agent work — point an agent with these skills at the
box (running on it, or from any machine with SSH access to it, which is
also how you bootstrap a machine that has no agent yet):

- "Set up this fresh server as my dev machine" → [setting-up-dev-machine](skills/setting-up-dev-machine/SKILL.md)
- "Migrate my old dev box onto this new server" → [migrating-dev-machine](skills/migrating-dev-machine/SKILL.md)
- "Install X on this machine" → [installing-dev-tools](skills/installing-dev-tools/SKILL.md) (picks the right layer, keeps it recorded)
- "Something added junk to my .bashrc, clean it up" → [normalizing-dotfiles](skills/normalizing-dotfiles/SKILL.md)
- "Is everything on this machine tracked?" → [auditing-dev-machine](skills/auditing-dev-machine/SKILL.md)

### What needs no procedure at all

Logins/re-auth (`claude /login`, `gh auth login`) and self-updates of
already-installed tools (`claude update`, `rustup update`, `devbox global
update`) touch only tool-owned state — nothing to record or commit.
server-config records how a tool is *installed*, not which build it's on.
If an updater ever oversteps into a dotfile, `chezmoi diff` and the audit
catch it; you don't need to check proactively. The things that do need
recording: new installs, `apt install` (see above), and installing skill
packs — add the repo to `~/server-config/agent-skills.txt` alongside
`npx skills add` so a rebuild restores them (hand-edited global agent
config like `~/.claude/CLAUDE.md` is chezmoi territory, like any dotfile).

### The three commands worth memorizing

```bash
repo-env setup                         # new checkout → managed environment
~/server-config/host/apply.sh          # converge machine to config (always safe)
~/server-config/host/machine-audit.sh  # is anything untracked?
```

## The skills (agent-facing)

- [managing-dev-machine](skills/managing-dev-machine/SKILL.md) — router: layer model, conventions, which skill when
- [setting-up-dev-machine](skills/setting-up-dev-machine/SKILL.md) — bootstrap a fresh machine
- [migrating-dev-machine](skills/migrating-dev-machine/SKILL.md) — in-place adoption or old→new server migration
- [installing-dev-tools](skills/installing-dev-tools/SKILL.md) — where a tool belongs + reproducible install
- [normalizing-dotfiles](skills/normalizing-dotfiles/SKILL.md) — triage installer-written dotfile changes
- [using-project-envs](skills/using-project-envs/SKILL.md) — per-repo environments, activation, agent launches
- [running-persistent-agents](skills/running-persistent-agents/SKILL.md) — always-on remote-controlled agents: systemd supervision, resume, recovery
- [auditing-dev-machine](skills/auditing-dev-machine/SKILL.md) — drift detection
- [backing-up-dev-machine](skills/backing-up-dev-machine/SKILL.md) — back up vs rebuild

## Tools

- [tools/repo-env](tools/repo-env/) — Rust CLI mapping a checkout's git
  identity (origin remote, or `local/<dirname>` before one exists) to its
  environment overlay: `setup`, `exec`, `path`, `key`, `init`, `doctor`.
- Bash scripts bundled inside the skills that use them:
  [apply.sh](skills/setting-up-dev-machine/scripts/apply.sh) (host converge),
  [machine-audit.sh](skills/auditing-dev-machine/scripts/machine-audit.sh) (drift),
  [machine-inventory.sh](skills/migrating-dev-machine/scripts/machine-inventory.sh) (full capture),
  [home-conflicts.sh](skills/migrating-dev-machine/scripts/home-conflicts.sh) (migration comparison).
