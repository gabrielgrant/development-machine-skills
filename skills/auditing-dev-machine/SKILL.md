---
name: auditing-dev-machine
description: Detects drift on a managed dev machine — state that exists but isn't captured in the server-config layers. Use for periodic machine health/drift checks, before a migration or backup, after a burst of ad-hoc work, or when asked "what's changed on this machine", "is everything tracked", or why config differs between machines.
---

# Auditing a dev machine

Drift = state whose owner is "nobody" (see managing-dev-machine for the
layer table). The audit finds it; remediation is: promote into a managed
layer (installing-dev-tools / normalizing-dotfiles), or remove.

## Run

```bash
scripts/machine-audit.sh          # read-only; prints a sectioned report
```

Sections and what to do per finding:

| Section | Finding means | Remediation |
|---|---|---|
| chezmoi diff | live dotfiles differ from desired state | normalizing-dotfiles |
| loader integrity | duplicate/missing marker blocks, installer lines outside them | normalizing-dotfiles |
| apt drift | manually-installed packages in neither `host/apt-packages.txt` nor the adoption baseline | add to manifest or `apt-mark auto`/remove |
| etckeeper | uncommitted `/etc` changes | review, `sudo etckeeper commit` |
| unmanaged binaries | files in `~/.local/bin` etc. with no recorded install | installing-dev-tools ladder |
| failed units / timers | broken services | fix or remove the unit |
| stale .envrc | repos with `.envrc` but missing overlay (or vice versa) | `repo-env setup` / delete |
| devbox global | live global config differs from (or missing in) `devbox-global/` tracked copy | copy `devbox.json` + `devbox.lock` into the repo and commit, or `devbox global rm` the ad-hoc addition |

For deeper point-in-time capture (e.g. pre-migration), use
migrating-dev-machine's `machine-inventory.sh` instead — the audit is a
quick delta check, the inventory is a full snapshot.

`$SERVER_CONFIG_DIR/host/apply.sh` also prints package drift at the end of
every run, so applying and auditing agree by construction.

## Cadence

After any session that touched machine state; before migrations and
backups; otherwise monthly. A clean audit is the definition of "everything
is tracked".
