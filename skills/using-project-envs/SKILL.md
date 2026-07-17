---
name: using-project-envs
description: Sets up and uses per-repo development environments on a managed dev machine — personal Devbox overlays for third-party repos, direnv auto-activation, and direnv exec for coding agents and non-interactive launches. Use when starting work in a checkout, cloning a repo, launching an agent (claude/codex) inside a project, when tools are missing in a repo, or when a repo lacks devbox/devcontainer config that shouldn't be committed upstream.
---

# Using project environments

Third-party repos get a **personal overlay**: env config stored centrally
in `$SERVER_CONFIG_DIR/environments/<host>/<owner>/<repo>/`, activated by a
repo-local `.envrc` that is excluded via `.git/info/exclude` (never
committed, never in `.gitignore` — that file is upstream's). Repos you
control declare their environment in-repo instead.

The `repo-env` tool (Rust, in this repo under `tools/repo-env/`) automates
the mapping; install once with
`cargo install --git https://github.com/gabrielgrant/development-machine-skills repo-env`.

## Entering a repo for the first time

```bash
cd ~/repos/some-project
repo-env setup        # derives key from `git remote get-url origin`,
                      # creates the overlay dir (+ empty devbox.json) if
                      # missing, writes ignored .envrc, runs direnv allow
devbox add <pkgs> --config "$(repo-env path)"   # add what the project needs
git -C "$SERVER_CONFIG_DIR" add -A && git -C "$SERVER_CONFIG_DIR" commit -m "env: some-project"
```

After that, `cd` into the repo auto-activates (direnv hook). Without
repo-env, the manual equivalent is an `.envrc` containing
`use_personal_devbox <host>/<owner>/<repo>` (helper installed by
setting-up-dev-machine).

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

direnv's hook only fires around interactive prompts. Anything launched by
systemd, an editor, a portal, or another agent must go through:

```bash
repo-env exec claude          # = direnv exec <git-root> claude
repo-env exec npm test
```

Never assume an agent inherited the environment just because it runs in
the repo directory.

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
