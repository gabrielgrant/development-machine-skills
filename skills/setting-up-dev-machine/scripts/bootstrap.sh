#!/usr/bin/env bash
# Bootstrap a fresh Ubuntu machine into the managed dev-machine pattern.
# Idempotent: safe to rerun; a clean second run is the reproducibility test.
set -euo pipefail

SERVER_CONFIG_DIR="${SERVER_CONFIG_DIR:-$HOME/server-config}"
SHELL_DIR="$HOME/.config/shell"
DIRENV_LIB="$HOME/.config/direnv/lib"
BIN_DIR="$HOME/.local/bin"

log() { printf '==> %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

# --- 1. APT baseline (etckeeper first, so /etc history covers everything) ---
if ! have etckeeper; then
    log "Installing git, etckeeper, direnv, curl"
    sudo apt-get update -q
    sudo apt-get install -qy git etckeeper direnv curl ca-certificates
else
    log "etckeeper already installed"
fi

if ! sudo test -d /etc/.git; then
    log "Initializing etckeeper"
    sudo etckeeper init
    sudo etckeeper commit "Initial /etc baseline" || true
fi

# --- 2. server-config repo ---
log "Ensuring $SERVER_CONFIG_DIR skeleton"
mkdir -p "$SERVER_CONFIG_DIR"/{ansible,dotfiles,devbox-global,environments,packages,inventories}
if [ ! -d "$SERVER_CONFIG_DIR/.git" ]; then
    git -C "$SERVER_CONFIG_DIR" init -b main
    printf '%s\n' '*.secret' '.DS_Store' > "$SERVER_CONFIG_DIR/.gitignore"
fi

# --- 3. chezmoi + devbox binaries ---
mkdir -p "$BIN_DIR"
if ! have chezmoi && [ ! -x "$BIN_DIR/chezmoi" ]; then
    log "Installing chezmoi to $BIN_DIR"
    sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$BIN_DIR"
fi
if ! have devbox && [ ! -x "$BIN_DIR/devbox" ]; then
    log "Installing devbox"
    curl -fsSL https://get.jetify.com/devbox | FORCE=1 bash
fi

# Point chezmoi at the source dir inside server-config.
CHEZMOI_CFG="$HOME/.config/chezmoi/chezmoi.toml"
if [ ! -f "$CHEZMOI_CFG" ]; then
    mkdir -p "$(dirname "$CHEZMOI_CFG")"
    printf 'sourceDir = "%s"\n' "$SERVER_CONFIG_DIR/dotfiles" > "$CHEZMOI_CFG"
fi

# --- 4. shell snippet dirs + loader blocks ---
mkdir -p "$SHELL_DIR/bashrc.d" "$SHELL_DIR/profile.d" "$DIRENV_LIB"

install_loader() {
    # install_loader <file> <snippet-subdir>
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
    fi
}
install_loader "$HOME/.bashrc" "bashrc.d"
install_loader "$HOME/.profile" "profile.d"

# --- 5. standard snippets ---
write_if_absent() {
    local path="$1"
    if [ ! -f "$path" ]; then
        log "Writing $path"
        cat > "$path"
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
if command -v devbox >/dev/null 2>&1; then
    eval "$(devbox global shellenv --init-hook)"
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

log "Done. Open a NEW login shell, then verify:"
log "  command -v devbox direnv chezmoi"
log "  rerun this script — it should change nothing"
log "Next: chezmoi ownership (templates/modify_dot_bashrc), Ansible host packages, devbox global profile."
