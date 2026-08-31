#!/usr/bin/env bash
# Read-only drift audit for a managed dev machine.
# Exit code 0 always (it's a report, not a gate); findings go to stdout.
set -uo pipefail

SERVER_CONFIG_DIR="${SERVER_CONFIG_DIR:-$HOME/server-config}"
# Non-login shells (ssh cmd, cron) may lack user bin dirs.
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH="$HOME/.local/bin:$PATH" ;; esac
section() { printf '\n=== %s ===\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

section "CHEZMOI DIFF"
if have chezmoi; then
    if out=$(chezmoi diff 2>&1) && [ -z "$out" ]; then
        echo "clean"
    else
        printf '%s\n' "$out" | head -n 100
    fi
else
    echo "chezmoi not installed"
fi

section "LOADER INTEGRITY"
for f in "$HOME/.bashrc" "$HOME/.profile"; do
    [ -f "$f" ] || continue
    n=$(grep -cF '# >>> managed shell loader >>>' "$f" || true)
    case "$n" in
        1) echo "$f: loader block OK" ;;
        0) echo "$f: NO loader block" ;;
        *) echo "$f: DUPLICATE loader blocks ($n)" ;;
    esac
    # Heuristic: installer-ish lines outside the managed pattern.
    grep -nE '(^export PATH=|^\. |^source |nvm\.sh|\.cargo/env|/bin:\$PATH)' "$f" |
        grep -vE 'managed shell loader|/.config/shell/' |
        grep -vE 'PATH="\$HOME/(bin|\.local/bin):\$PATH"' |
        sed "s|^|$f: suspicious: |" || true
done

section "APT DRIFT (manual packages in neither manifest nor baseline)"
MANIFEST="$SERVER_CONFIG_DIR/host/apt-packages.txt"
BASELINE="$SERVER_CONFIG_DIR/host/apt-baseline.txt"
if [ -f "$MANIFEST" ]; then
    drift=$(comm -23 <(apt-mark showmanual | sort -u) \
        <(grep -hvE '^[[:space:]]*(#|$)' "$MANIFEST" "$BASELINE" 2>/dev/null | sort -u))
    if [ -n "$drift" ]; then
        printf 'unrecorded: %s\n' $drift | head -n 60
    else
        echo "clean"
    fi
else
    echo "no manifest at $MANIFEST — run setting-up-dev-machine apply.sh"
fi

section "ETCKEEPER"
if have etckeeper && sudo -n test -d /etc/.git 2>/dev/null; then
    st=$(sudo git -C /etc status --porcelain 2>/dev/null | head -n 40)
    [ -z "$st" ] && echo "clean" || printf '%s\n' "$st"
else
    echo "etckeeper not initialized (or no passwordless sudo for check)"
fi

section "UNMANAGED USER BINARIES"
# An entry is recorded if cargo installed it under ~/.local (listed in
# ~/.local/.crates.toml) or its name appears in the code of a server-config
# install script (comments and messages don't count — they name neighbours).
# Anything else has no owner: installing-dev-tools ladder, or remove.
bin_records=$(ls "$SERVER_CONFIG_DIR"/host/apply.sh "$SERVER_CONFIG_DIR"/host/scripts.d/*.sh \
    "$SERVER_CONFIG_DIR"/dotfiles/run_* "$SERVER_CONFIG_DIR"/packages/*/* 2>/dev/null)
bin_drift=0
while IFS= read -r bin; do
    [ -n "$bin" ] || continue
    name=$(basename "$bin")
    owner=""
    if grep -qE "^\"[^\"]+\" = \[.*\"$name\"" "$HOME/.local/.crates.toml" 2>/dev/null; then
        owner="cargo install --root ~/.local"
    else
        for rec in $bin_records; do
            if grep -vE '^[[:space:]]*(#|echo|printf|log)([[:space:]]|$)' "$rec" 2>/dev/null |
                    grep -qwF -- "$name"; then
                owner="${rec#"$SERVER_CONFIG_DIR"/}"
                break
            fi
        done
    fi
    link=""
    [ -L "$bin" ] && link=" -> $(readlink "$bin")"
    if [ -n "$owner" ]; then
        echo "ok: $bin$link ($owner)"
    else
        echo "drift: $bin$link (no recorded install)"
        bin_drift=1
    fi
done < <(find "$HOME/.local/bin" "$HOME/bin" -maxdepth 1 \( -type f -o -type l \) 2>/dev/null | sort)
[ "$bin_drift" -eq 0 ] && echo "clean"

section "FAILED UNITS"
systemctl --failed --no-legend 2>/dev/null || true
systemctl --user --failed --no-legend 2>/dev/null || true

section "PROJECT ENVS"
if [ -d "$HOME/repos" ]; then
    for envrc in "$HOME"/repos/*/.envrc; do
        [ -f "$envrc" ] || continue
        repo_dir=$(dirname "$envrc")
        key=$(grep -oE 'use_personal_devbox +[^ ]+' "$envrc" | awk '{print $2}')
        if [ -n "${key:-}" ] && [ ! -f "$SERVER_CONFIG_DIR/environments/$key/devbox.json" ]; then
            echo "$repo_dir: .envrc references missing overlay $key"
        fi
    done
fi
echo "(done)"

section "DEVBOX GLOBAL (live config vs tracked copy)"
DBG_LIVE="$HOME/.local/share/devbox/global/default"
DBG_TRACKED="$SERVER_CONFIG_DIR/devbox-global"
if ! have devbox; then
    echo "devbox not installed"
elif [ ! -f "$DBG_TRACKED/devbox.json" ]; then
    echo "untracked: no $DBG_TRACKED/devbox.json — copy the live config in and commit"
else
    dbg_drift=0
    for f in devbox.json devbox.lock; do
        if ! diff -q "$DBG_LIVE/$f" "$DBG_TRACKED/$f" >/dev/null 2>&1; then
            echo "drift: $f differs from tracked copy"
            diff -u "$DBG_TRACKED/$f" "$DBG_LIVE/$f" 2>&1 | head -n 20
            dbg_drift=1
        fi
    done
    [ "$dbg_drift" -eq 0 ] && echo "clean"
fi

section "SERVER-CONFIG REPO"
if [ -d "$SERVER_CONFIG_DIR/.git" ]; then
    git -C "$SERVER_CONFIG_DIR" status --short --branch | head -n 30
else
    echo "MISSING: $SERVER_CONFIG_DIR is not a git repo — run setting-up-dev-machine"
fi
