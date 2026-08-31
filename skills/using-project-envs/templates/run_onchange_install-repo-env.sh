#!/bin/sh
# Install the repo-env CLI (tools/repo-env in development-machine-skills)
# into ~/.local/bin. Level-5 wrapped installer per installing-dev-tools:
# `cargo install` is the installer, pinned to a commit. `--root ~/.local`
# puts the binary in the machine's user-bin dir (~/.local/bin is on PATH
# for every login shell, including the claude-rc@ unit's `bash -lc`, with
# no dependency on ~/.cargo/env) and records it in ~/.local/.crates.toml,
# which machine-audit.sh reads as the install record.
#
# Upgrade: bump REV, commit, `chezmoi apply` (run_onchange reruns on edit).
# Needs cargo: rustup is installed on first need via installing-dev-tools
# (rustup-init --no-modify-path). Until it exists this script fails, so
# chezmoi retries on the next apply instead of recording a silent no-op.
set -eu

REPO_URL=https://github.com/gabrielgrant/development-machine-skills
REV=37db5eec7bb6aeb559b10c2b2b3e404feb8f5d6a
ROOT="$HOME/.local"

# Already installed at exactly this rev: skip. cargo reaches the same
# conclusion on its own, but only after fetching the repo.
if grep -F '"repo-env ' "$ROOT/.crates.toml" 2>/dev/null | grep -qF "?rev=$REV#"; then
    exit 0
fi

[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
if ! command -v cargo >/dev/null 2>&1; then
    echo "install-repo-env: cargo not found — install rustup first (installing-dev-tools), then rerun chezmoi apply" >&2
    exit 1
fi

# --force also adopts a pre-existing ~/.local/bin/repo-env that cargo has no
# record of (a hand-copied build), which cargo otherwise refuses to replace.
cargo install --git "$REPO_URL" --rev "$REV" --root "$ROOT" --locked --force repo-env
