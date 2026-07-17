---
name: installing-dev-tools
description: Decides where a new tool belongs on a managed dev machine (host manifest, Devbox Global, project overlay, nix flake, pinned binary, or wrapped curl|bash installer) and installs it reproducibly. Use when installing any CLI, runtime, language toolchain, or package on the dev machine, when a tool ships only a curl|bash installer, or when apt/npm -g/cargo install/pipx is about to be run ad hoc.
---

# Installing dev tools

Two decisions, in order: **which layer**, then **which install method**.
Every install ends with a commit to `$SERVER_CONFIG_DIR` recording what and
why — an install that isn't recorded is drift.

## 1. Which layer

| Requirement | Layer |
|---|---|
| Needed to administer/bootstrap the machine (docker, ssh, tmux) | host manifest (`$SERVER_CONFIG_DIR/host/apt-packages.txt` + apply.sh) |
| Useful in nearly every shell (rg, jq, gh, just) | Devbox Global |
| Needed only for one checkout | Project overlay (see using-project-envs) |
| Project already declares it (`.nvmrc`, `rust-toolchain.toml`, `devbox.json`, `.devcontainer/`) | Use the project's mechanism |
| Requires OS/container isolation | Dev Container |
| One-time experiment | Temporary — don't persist; promote if it recurs |

One authority per runtime, no duplicates: if a project has `.nvmrc`, nvm
owns Node there — don't also pin Node in devbox. rustup and devbox are
complementary: devbox can supply rustup; rustup honors
`rust-toolchain.toml`. Share `~/.rustup`/`~/.cargo` caches across projects
rather than per-project toolchains.

## 2. Which install method (escalation ladder)

Try each level; stop at the first that works.

1. **Nixpkgs**: `devbox search <tool>` → `devbox add <tool>@<version>`
   (or `devbox global add`).
2. **Upstream flake**: package entry `github:vendor/tool/v1.2.3`.
3. **Own local flake** in `$SERVER_CONFIG_DIR/packages/<tool>/` for tools
   shipping static binaries — pinned, checksummed, cleanly removable.
4. **Host-script-managed binary**: an idempotent script in
   `$SERVER_CONFIG_DIR/host/scripts.d/` — pinned URL, checksum verify,
   skip-if-present, symlink into `~/.local/bin`. For host-level tools.
5. **Wrapped official installer** — when the installer does real work
   (auth, platform detection, self-update). Codify, don't just run it:
   - download and skim the script; pin a version; never pipe blindly
   - disable profile modification where supported
     (`rustup-init --no-modify-path`, nvm `PROFILE=/dev/null` or
     `PROFILE=~/.config/shell/bashrc.d/20-<tool>.sh`)
   - if it may still edit dotfiles: snapshot `.bashrc`/`.profile` first,
     diff after, then run the normalizing-dotfiles skill on the diff
   - record the exact invocation in `$SERVER_CONFIG_DIR` (chezmoi
     `run_onchange_` script for user tools; `host/scripts.d/` for host tools)
6. **Temporary unmanaged**: evaluation only. Note it somewhere visible;
   promote or remove before it becomes load-bearing.

Never install tools from a devbox `init_hook` (runs every shell entry).

## After any install

1. Fresh login shell: `command -v <tool>` works.
2. `chezmoi diff` clean (or triaged via normalizing-dotfiles).
3. Rerun of the install step is a no-op.
4. Commit with provenance: method, version, reason.
