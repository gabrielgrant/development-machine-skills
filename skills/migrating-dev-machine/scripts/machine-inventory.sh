#!/usr/bin/env bash
# Capture a full inventory of this machine's state for migration/audit.
# Writes to ~/machine-inventory-<date>/ (override with $1).
# Sudo-dependent sections are skipped with a warning if sudo is unavailable.
set -uo pipefail
umask 077

INV="${1:-$HOME/machine-inventory-$(date +%F)}"
mkdir -p "$INV"
echo "Writing inventory to $INV"

SUDO="sudo"
if ! sudo -n true 2>/dev/null && ! sudo -v; then
    echo "WARNING: no sudo; system-level sections will be incomplete" >&2
    SUDO=""
fi

# --- system ---
{
    echo "=== TIMESTAMP ==="; date -Is
    echo; echo "=== OS ==="; cat /etc/os-release
    echo; echo "=== KERNEL ==="; uname -a
    echo; echo "=== USER ==="; id
    echo; echo "=== DISK ==="; df -hT; du -sh "$HOME" 2>/dev/null
    echo; echo "=== LISTENING ==="
    ${SUDO:+$SUDO} ss -lntup 2>/dev/null || ss -lntu
} > "$INV/system.txt"

# --- APT state ---
apt-mark showmanual | sort -u > "$INV/apt-manual.txt"
apt-mark showhold   | sort -u > "$INV/apt-holds.txt"
dpkg-query -W -f='${binary:Package}\t${Version}\t${Architecture}\n' | sort > "$INV/dpkg-installed.tsv"
dpkg --print-foreign-architectures > "$INV/dpkg-foreign-architectures.txt"

if [ -n "$SUDO" ]; then
    $SUDO zgrep -hE '^(Start-Date|Commandline|Install|Remove|Purge|End-Date):' \
        /var/log/apt/history.log* > "$INV/apt-history-summary.txt" 2>/dev/null
    $SUDO zgrep -h '^Commandline:' /var/log/apt/history.log* 2>/dev/null |
        sed 's/^Commandline: //' | nl -ba > "$INV/apt-commandlines.txt"

    # Modified package-owned conffiles (vs dpkg's recorded md5sums).
    $SUDO bash -s <<'EOS' > "$INV/dpkg-conffile-changes.tsv"
dpkg-query -W -f='${Conffiles}\n' |
while read -r path expected _; do
    case "$path" in /*) ;; *) continue ;; esac
    if [ ! -e "$path" ]; then printf 'MISSING\t%s\n' "$path"; continue; fi
    actual=$(md5sum -- "$path" | awk '{print $1}')
    [ "$actual" != "$expected" ] && printf 'MODIFIED\t%s\n' "$path"
done
EOS

    # Likely manually-created system files.
    $SUDO find /usr/local /opt /srv /etc/systemd/system /etc/cron.d \
        /etc/profile.d /etc/sysctl.d /etc/ssh/sshd_config.d \
        -xdev -mindepth 1 \
        -printf '%y\t%M\t%u:%g\t%TY-%Tm-%Td %TH:%TM\t%p\n' 2>/dev/null |
        sort > "$INV/custom-system-paths.tsv"

    $SUDO crontab -l > "$INV/root-crontab.txt" 2>&1 || true
    $SUDO ufw status verbose > "$INV/ufw.txt" 2>&1 || true
    $SUDO nft list ruleset > "$INV/nft-ruleset.txt" 2>&1 || true
fi

# --- services / cron ---
systemctl list-unit-files --state=enabled --no-pager > "$INV/system-services-enabled.txt" 2>&1 || true
systemctl list-timers --all --no-pager > "$INV/system-timers.txt" 2>&1 || true
systemctl --user list-unit-files --state=enabled --no-pager > "$INV/user-services-enabled.txt" 2>&1 || true
crontab -l > "$INV/user-crontab.txt" 2>&1 || true

# --- non-APT tooling ---
{
    echo "=== EXECUTABLE LOCATIONS ==="
    for cmd in claude codex opencode node npm pnpm bun deno python3 pip pipx \
               uv cargo rustup rustc go docker gh git jq rg tmux devbox direnv chezmoi; do
        echo; echo "--- $cmd ---"; type -a "$cmd" 2>&1 || true
    done
} > "$INV/tool-locations.txt"

command -v npm    >/dev/null 2>&1 && npm -g ls --depth=0    > "$INV/npm-global.txt" 2>&1
command -v pnpm   >/dev/null 2>&1 && pnpm ls -g --depth=0   > "$INV/pnpm-global.txt" 2>&1
command -v pipx   >/dev/null 2>&1 && pipx list               > "$INV/pipx.txt" 2>&1
command -v cargo  >/dev/null 2>&1 && cargo install --list    > "$INV/cargo-install.txt" 2>&1
command -v rustup >/dev/null 2>&1 && rustup show             > "$INV/rustup.txt" 2>&1
command -v nvm    >/dev/null 2>&1 || [ -s "$HOME/.nvm/nvm.sh" ] && ls "$HOME/.nvm/versions/node" > "$INV/nvm-versions.txt" 2>&1
command -v devbox >/dev/null 2>&1 && devbox global list      > "$INV/devbox-global.txt" 2>&1

find "$HOME/.local/bin" "$HOME/bin" -maxdepth 1 \( -type f -o -type l \) \
    -printf '%M\t%TY-%Tm-%Td %TH:%TM\t%p -> %l\n' 2>/dev/null |
    sort > "$INV/user-bin.txt"

# --- Docker ---
if command -v docker >/dev/null 2>&1; then
    {
        echo "=== VERSION ==="; docker version 2>&1
        echo; echo "=== CONTAINERS ==="
        docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' 2>&1
        echo; echo "=== VOLUMES ==="; docker volume ls 2>&1
        echo; echo "=== COMPOSE ==="; docker compose ls 2>&1
        echo; echo "=== MOUNTS ==="
        for c in $(docker ps -aq 2>/dev/null); do
            echo; echo "--- $(docker inspect --format '{{.Name}}' "$c" | sed 's#^/##') ---"
            docker inspect --format \
                '{{range .Mounts}}{{printf "%s\t%s\t%s\t%s\n" .Type .Name .Source .Destination}}{{end}}' "$c"
        done
        echo; echo "=== DISK ==="; docker system df 2>&1
    } > "$INV/docker-inventory.txt"
fi

echo
echo "=== INVENTORY COMPLETE ==="
du -sh "$INV"
ls -1 "$INV"
