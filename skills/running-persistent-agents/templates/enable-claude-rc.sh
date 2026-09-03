#!/usr/bin/env bash
# Host script: persistent Claude Remote Control supervisors (one per repo).
# Drop into $SERVER_CONFIG_DIR/host/scripts.d/ — apply.sh runs it. Idempotent.
#
# The claude-rc@.service template itself is dotfile-layer state (chezmoi).
# What is NOT dotfile state, and so lives here, is the linger flag and the
# list of repos that should have a supervisor. See the
# running-persistent-agents skill.
#
# A supervisor refuses to start in a directory whose workspace trust has not
# been accepted, and that dialog needs a TTY. So on a rebuilt machine this
# script enables the unit only for repos already trusted, and tells you what
# to run for the rest instead of leaving a crashlooping unit behind.
set -euo pipefail

# The manifest: directory names under ~/repos. Edit this list; it is the
# record of which repos are meant to have a supervisor.
REPOS=(
    # my-project
)

UNIT_TEMPLATE="$HOME/.config/systemd/user/claude-rc@.service"
CLAUDE_JSON="$HOME/.claude.json"

if [ ! -f "$UNIT_TEMPLATE" ]; then
    echo "==> claude-rc@.service not present yet (run chezmoi apply first); skipping"
    exit 0
fi

# Units must outlive logout and survive reboot.
if [ "$(loginctl show-user "$USER" -p Linger --value 2>/dev/null)" != "yes" ]; then
    echo "==> Enabling linger for $USER"
    loginctl enable-linger "$USER"
fi

trusted() {
    python3 - "$CLAUDE_JSON" "$HOME/repos/$1" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
except (OSError, ValueError):
    sys.exit(1)
sys.exit(0 if d.get("projects", {}).get(sys.argv[2], {}).get("hasTrustDialogAccepted") else 1)
PY
}

for repo in "${REPOS[@]}"; do
    if [ ! -d "$HOME/repos/$repo" ]; then
        echo "==> ~/repos/$repo missing; skipping claude-rc@$repo"
        continue
    fi
    if ! trusted "$repo"; then
        echo "==> claude-rc@$repo: workspace not trusted yet."
        echo "    Run once in a terminal, then rerun this script:"
        echo "      cd ~/repos/$repo && claude   # accept the trust dialog, then quit"
        continue
    fi
    if systemctl --user is-active --quiet "claude-rc@$repo"; then
        continue
    fi
    echo "==> Enabling claude-rc@$repo"
    systemctl --user enable --now "claude-rc@$repo"
done
