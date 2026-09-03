---
name: using-project-envs
description: Sets up and uses per-repo development environments on a managed dev machine — personal Devbox overlays for third-party repos, direnv auto-activation, and direnv exec for coding agents and non-interactive launches. Use when starting work in a checkout, cloning a repo, launching an agent (claude/codex) inside a project, when tools are missing in a repo, or when a repo lacks devbox/devcontainer config that shouldn't be committed upstream.
---

# Using project environments

Two modes, chosen by ownership:

- **In-repo** (repos you control, and the default for new projects with no
  origin remote): committable `devbox.json` + `.envrc` in the repo itself.
  Works out of the box on any machine, nothing to migrate later.
- **Overlay** (third-party repos, the default when an origin exists): env
  config stored centrally in
  `$SERVER_CONFIG_DIR/environments/<host>/<owner>/<repo>/`, activated by a
  repo-local `.envrc` excluded via `.git/info/exclude` (never committed,
  never in `.gitignore` — that file is upstream's).

`repo-env setup` picks the default from the remote; override with
`--in-repo` / `--overlay`. For a repo you control that already has an
origin, prefer `--in-repo`.

The `repo-env` tool (Rust, in this repo under `tools/repo-env/`) automates
the mapping. It is a machine-level install and is recorded like one
(installing-dev-tools level 5 — `cargo install` is the installer):

```bash
SKILL=~/.agents/skills/using-project-envs        # this skill's own dir
cp "$SKILL"/templates/run_onchange_install-repo-env.sh "$SERVER_CONFIG_DIR/dotfiles/"
chezmoi apply    # runs: cargo install --git … --rev <pinned> --root ~/.local repo-env
```

`--root ~/.local` lands the binary in `~/.local/bin` — the user-bin dir
the setup keeps on PATH for every login shell, so systemd units
(`bash -lc`) find it without `~/.cargo/env` — and records it in
`~/.local/.crates.toml`, which the audit reads as the install record.
Needs cargo (rustup, via installing-dev-tools) first; the script fails
loudly until then and chezmoi retries on the next apply. Upgrade = bump
the pinned rev in the script and commit; chezmoi reruns it on change.
Persistent-agent units (running-persistent-agents) exec `repo-env`, so
this comes before enabling any of them. On an unmanaged machine the
same `cargo install` line, with those flags, is the ad hoc equivalent.

## Entering a repo for the first time

`new-project` (scripts/new-project.sh, installed to `~/.local/bin` and
`chezmoi add`ed) is the whole path in one command, and needs no agent:

```bash
new-project my-thing            # ~/repos/my-thing, created if absent
new-project --serve my-thing    # ...and give it a persistent agent
new-project --in-repo ~/repos/a-clone   # a repo you own that has an origin
```

It creates the directory if needed, runs `repo-env setup --git-init`,
and makes the initial commit if HEAD is unborn — that last step matters
because an unborn HEAD passes every check here and then breaks
worktree-spawning agents (running-persistent-agents). It commits only
the environment files: it also runs on directories that already have
content, where a blind `git add -A` on a repo with no `.gitignore` is
how build output and secrets get committed. Anything else is reported,
not staged. With `--serve` it appends the repo to the `REPOS` list in
`host/scripts.d/enable-claude-rc.sh` and runs it, so enabling lives in
one place.

The four entry shapes — empty directory, directory with files but no
git, a repo with history, a clone — differ on only two axes: whether
there is a commit, and whether there is an origin. (A bare repo is not
one of them; clone it first.) The steps by hand:

```bash
cd ~/repos/some-project
repo-env setup        # offers git init if needed (--git-init to skip the
                      # prompt); then in-repo or overlay per the rules above
# in-repo:  devbox add <pkgs>            then commit devbox.json/.lock + .envrc
# overlay:  devbox add <pkgs> --config "$(repo-env path)"
#           then commit $SERVER_CONFIG_DIR
```

After that, `cd` into the repo auto-activates (direnv hook). `repo-env
doctor` verifies a checkout, including a stale overlay key after a remote
change. If the repo should also host a persistent remote agent:
`systemctl --user enable --now claude-rc@<repo>`
(running-persistent-agents). Without repo-env, the manual overlay equivalent is an `.envrc`
containing `use_personal_devbox <host>/<owner>/<repo>` (helper installed
by setting-up-dev-machine).

## Runtime version authority

One authority per runtime — never two declarations:

| Project has | Authority |
|---|---|
| `.nvmrc` | nvm (the `.envrc` runs `nvm use` after devbox) |
| `rust-toolchain.toml` | rustup (devbox may supply rustup itself) |
| `devbox.json` pinning a runtime | devbox |
| `packageManager` field | corepack |
| nothing | pin in your overlay's devbox.json |

## Launching agents / non-interactive commands

An interactive shell that has `cd`-ed into the repo has the environment,
and **every child process inherits it** — launching `claude` or `codex`
from a repo shell (e.g. inside tmux, with `claude --remote-control` for
remote steering) needs nothing special.

direnv's hook only fires around interactive prompts, so anything that
*bypasses* an interactive repo shell — systemd units, an agent portal,
editor tasks, cron, or a command run from outside the repo — must go
through:

```bash
repo-env exec claude          # = direnv exec <git-root> claude
repo-env exec npm test
```

The test is "did this process's ancestry pass through an interactive
shell prompt inside the repo?" — if unsure, `repo-env exec` is always
correct (direnv makes it a no-op when the env is already loaded).

## Devbox overlay vs Dev Container

Default to the Devbox overlay. Reach for a Dev Container when you need OS
isolation, a specific distro/libc, compose-based services, or separated
agent credentials/home. Keep external devcontainer configs in the same
overlay dir (`.devcontainer/devcontainer.json`) and run
`devcontainer up --workspace-folder <repo> --config <overlay>/.devcontainer/devcontainer.json`.

## Upstreaming an overlay

Overlays are stored upstream-shaped, so proposing them is a copy:
`cp "$(repo-env path)"/devbox.json . && cp "$(repo-env path)"/devbox.lock .`
on a clean branch, review, PR. Don't use a long-lived personal branch in
the upstream repo as your environment store — it entangles env commits
with work branches and syncs poorly across machines.
