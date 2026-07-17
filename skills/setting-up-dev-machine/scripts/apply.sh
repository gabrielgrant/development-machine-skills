#!/usr/bin/env bash
# Converge the host + user layers of a managed dev machine.
# Bootstraps a fresh box AND is the ongoing apply tool: package installs are
# driven by $SERVER_CONFIG_DIR/host/apt-packages.txt, so rerunning after a
# manifest edit converges the machine. Idempotent: a clean second run is the
# reproducibility test.
set -euo pipefail

SERVER_CONFIG_DIR="${SERVER_CONFIG_DIR:-$HOME/server-config}"
HOST_DIR="$SERVER_CONFIG_DIR/host"
MANIFEST="$HOST_DIR/apt-packages.txt"
BASELINE="$HOST_DIR/apt-baseline.txt"
SHELL_DIR="$HOME/.config/shell"
DIRENV_LIB="$HOME/.config/direnv/lib"
BIN_DIR="$HOME/.local/bin"

log() { printf '==> %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
CHANGED=0

# --- 1. etckeeper first, so /etc history covers everything that follows ---
if ! have etckeeper || ! have git; then
    log "Installing git + etckeeper"
    sudo apt-get update -q
    sudo apt-get install -qy git etckeeper
    CHANGED=1
fi
if ! sudo test -d /etc/.git; then
    log "Initializing etckeeper"
    sudo etckeeper init
    sudo etckeeper commit "Initial /etc baseline" || true
    CHANGED=1
fi

# --- 2. server-config skeleton + manifests ---
mkdir -p "$HOST_DIR/scripts.d" \
    "$SERVER_CONFIG_DIR"/{dotfiles,devbox-global,environments,packages,inventories}
if [ ! -d "$SERVER_CONFIG_DIR/.git" ]; then
    log "Initializing $SERVER_CONFIG_DIR git repo"
    git -C "$SERVER_CONFIG_DIR" init -b main
    printf '%s\n' '*.secret' > "$SERVER_CONFIG_DIR/.gitignore"
    CHANGED=1
fi

# Baseline: what the image had marked manual before we chose anything.
# Drift later = showmanual - baseline - manifest.
if [ ! -f "$BASELINE" ]; then
    log "Snapshotting apt baseline (image-provided manual packages)"
    apt-mark showmanual | sort -u > "$BASELINE"
    CHANGED=1
fi

if [ ! -f "$MANIFEST" ]; then
    log "Seeding $MANIFEST"
    cat > "$MANIFEST" <<'EOF'
# Host-layer packages: things the MACHINE needs, one per line.
# Not language runtimes, not per-project deps (see installing-dev-tools).
# Apply with: host/apply.sh
git
etckeeper
direnv
curl
ca-certificates
tmux
build-essential
pkg-config
libssl-dev
EOF
    CHANGED=1
fi

# --- 3. host scripts (apt repos/keyrings/binaries too fiddly for the manifest) ---
# Run BEFORE manifest convergence so a script can add an apt repo whose
# packages the manifest then declares (e.g. install-docker.sh + docker-ce).
# Each must be idempotent.
for script in "$HOST_DIR"/scripts.d/*.sh; do
    [ -e "$script" ] || continue
    log "Running host script: $script"
    bash "$script"
done

# --- 4. converge packages from the manifest ---
mapfile -t wanted < <(grep -vE '^[[:space:]]*(#|$)' "$MANIFEST" | sort -u)
missing=()
for pkg in "${wanted[@]}"; do
    dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
done
if ((${#missing[@]})); then
    log "Installing from manifest: ${missing[*]}"
    sudo apt-get update -q
    sudo apt-get install -qy "${missing[@]}"
    CHANGED=1
else
    log "Manifest packages all present"
fi

# --- 5. chezmoi + devbox binaries ---
mkdir -p "$BIN_DIR"
if ! have chezmoi && [ ! -x "$BIN_DIR/chezmoi" ]; then
    log "Installing chezmoi to $BIN_DIR"
    sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$BIN_DIR"
    CHANGED=1
fi
if ! have devbox && [ ! -x "$BIN_DIR/devbox" ]; then
    log "Installing devbox"
    curl -fsSL https://get.jetify.com/devbox | FORCE=1 bash
    CHANGED=1
fi

CHEZMOI_CFG="$HOME/.config/chezmoi/chezmoi.toml"
if [ ! -f "$CHEZMOI_CFG" ]; then
    mkdir -p "$(dirname "$CHEZMOI_CFG")"
    printf 'sourceDir = "%s"\n' "$SERVER_CONFIG_DIR/dotfiles" > "$CHEZMOI_CFG"
    CHANGED=1
fi

# --- 6. shell loader blocks + snippet dirs ---
mkdir -p "$SHELL_DIR/bashrc.d" "$SHELL_DIR/profile.d" "$DIRENV_LIB"

install_loader() {
    local file="$1" subdir="$2"
    local begin="# >>> managed shell loader >>>"
    local end="# <<< managed shell loader <<<"
    if ! grep -qF "$begin" "$file" 2>/dev/null; then
        log "Adding loader block to $file"
        cat >> "$file" <<EOF

$begin
for __f in "\$HOME"/.config/shell/$subdir/*.sh; do
    [ -r "\$__f" ] && . "\$__f"
done
unset __f
$end
EOF
        CHANGED=1
    fi
}
install_loader "$HOME/.bashrc" "bashrc.d"
install_loader "$HOME/.profile" "profile.d"

write_if_absent() {
    local path="$1"
    if [ ! -f "$path" ]; then
        log "Writing $path"
        cat > "$path"
        CHANGED=1
    else
        cat > /dev/null
    fi
}

write_if_absent "$SHELL_DIR/profile.d/10-local-bin.sh" <<'EOF'
# Ensure ~/.local/bin is on PATH even for shells that skip the distro block.
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) PATH="$HOME/.local/bin:$PATH"; export PATH ;;
esac
EOF

write_if_absent "$SHELL_DIR/bashrc.d/40-devbox-global.sh" <<'EOF'
# Devbox Global: expose globally-managed CLI tools in every shell.
# Plain shellenv (no --init-hook): hook scripts don't exist until a global
# profile is created, and global profiles rarely need init hooks anyway.
if command -v devbox >/dev/null 2>&1; then
    eval "$(devbox global shellenv 2>/dev/null)"
fi
EOF

# direnv hook must run late (after prompt-manipulating extensions).
write_if_absent "$SHELL_DIR/bashrc.d/90-direnv.sh" <<'EOF'
if command -v direnv >/dev/null 2>&1; then
    eval "$(direnv hook bash)"
fi
EOF

write_if_absent "$DIRENV_LIB/use_personal_devbox.sh" <<'EOF'
# direnv helper: activate a personal Devbox overlay kept outside the repo.
# Usage in .envrc:  use_personal_devbox github.com/owner/repo
use_personal_devbox() {
    local project="$1"
    local config="${SERVER_CONFIG_DIR:-$HOME/server-config}/environments/$project"
    if [ ! -f "$config/devbox.json" ]; then
        echo "Missing personal Devbox config: $config/devbox.json" >&2
        return 1
    fi
    eval "$(devbox generate direnv --print-envrc --config "$config")"
}
EOF

# --- 7. install this script as the machine's converge tool ---
SELF="$(readlink -f "$0")"
TARGET="$HOST_DIR/apply.sh"
if [ "$SELF" != "$TARGET" ] && ! cmp -s "$SELF" "$TARGET" 2>/dev/null; then
    cp "$SELF" "$TARGET" && chmod +x "$TARGET"
    log "Installed self as $TARGET (run that copy from now on)"
    CHANGED=1
fi

# --- report ---
echo
if [ "$CHANGED" -eq 1 ]; then
    log "Changes made. Commit them: git -C $SERVER_CONFIG_DIR add -A && git -C $SERVER_CONFIG_DIR commit"
    log "Then open a NEW login shell and rerun — a clean run is the reproducibility test."
else
    log "No changes: machine matches the manifest."
fi
unrecorded=$(comm -23 <(apt-mark showmanual | sort -u) <(sort -u "$MANIFEST" "$BASELINE") || true)
if [ -n "$unrecorded" ]; then
    log "Drift — manually installed but in neither manifest nor baseline:"
    printf '    %s\n' $unrecorded
fi
