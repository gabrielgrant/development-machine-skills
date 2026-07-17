---
name: setting-up-dev-machine
description: Bootstraps a fresh Ubuntu machine into the managed dev-machine pattern (etckeeper, server-config repo, chezmoi dotfile loaders, Devbox Global, direnv). Use when setting up a new dev server/VM from scratch, or when asked to "set up this machine", "bootstrap the dev box", or install the baseline tooling on a clean install. For machines with existing state, use migrating-dev-machine instead.
---

# Setting up a dev machine

Layer model and conventions: see the managing-dev-machine skill.

Order matters: etckeeper must be installed **before** other packages so the
`/etc` baseline and every subsequent package's config changes are recorded.

## Steps

```
Setup progress:
- [ ] 1. Snapshot (if VM) and record baseline
- [ ] 2. Run scripts/bootstrap.sh
- [ ] 3. Wire chezmoi ownership of the loader blocks
- [ ] 4. Host packages via Ansible
- [ ] 5. Devbox Global profile
- [ ] 6. Verify with a fresh login shell
```

**1. Baseline.** Take a provider snapshot if possible. Record
`cat /etc/os-release; id; df -hT` into `$SERVER_CONFIG_DIR/inventories/<host>-baseline/`.

**2. Bootstrap.** Run `scripts/bootstrap.sh`. It is idempotent and:
installs git, etckeeper, direnv, curl via apt; initializes etckeeper;
creates and git-inits `$SERVER_CONFIG_DIR` (default `~/server-config`);
installs chezmoi and devbox to `~/.local/bin`; creates
`~/.config/shell/{bashrc.d,profile.d}/`; inserts the marker-guarded loader
blocks into `.bashrc`/`.profile`; writes the devbox-global and direnv-hook
snippets and the `use_personal_devbox` direnv helper.

**3. Chezmoi ownership.** Copy `templates/modify_dot_bashrc` and
`templates/modify_dot_profile` into the chezmoi source dir
(`$SERVER_CONFIG_DIR/dotfiles/`), then `chezmoi add` every file under
`~/.config/shell/` and `~/.config/direnv/lib/`. From then on the loader
blocks and snippets are chezmoi-managed; installer edits show up in
`chezmoi diff` (handle those with the normalizing-dotfiles skill).

**4. Host packages.** Start from `templates/playbook.yml`; put it in
`$SERVER_CONFIG_DIR/ansible/` and run
`ansible-playbook -K playbook.yml`. Keep the host layer small: Docker,
ssh, tmux, build prerequisites — not language runtimes.

**5. Devbox Global.** `devbox global add ripgrep jq fd fzf bat gh just
shellcheck` (adjust to taste). Symlink or copy the resulting global
`devbox.json` into `$SERVER_CONFIG_DIR/devbox-global/` and commit.

**6. Verify.** Open a **new login shell** and check:
`command -v devbox direnv chezmoi rg` all resolve; `chezmoi diff` is clean;
`sudo etckeeper vcs status` is clean; rerunning `bootstrap.sh` makes no
changes (idempotence is the test that the setup is reproducible).

Commit each step to `$SERVER_CONFIG_DIR` as you go.

## Adding language runtimes

Do not install nvm/rustup here by default. Install them on first need via
the installing-dev-tools skill so the integration snippet and provenance
commit happen together.
