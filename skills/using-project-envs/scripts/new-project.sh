#!/usr/bin/env bash
# Stand up a repo as a working project: environment, first commit, and
# optionally a persistent agent. Deterministic — no agent needed to run it.
# Install to ~/.local/bin/new-project and `chezmoi add` it.
#
#   new-project <name>              ~/repos/<name>, created if absent
#   new-project <path>              any existing directory
#   new-project --serve <name>      also enable a claude-rc supervisor
#   new-project --in-repo|--overlay pass through to `repo-env setup`
#
# Covers every entry shape, because they differ on only two axes that this
# script and repo-env split between them:
#
#   has a commit?  no  -> git init (repo-env --git-init) + initial commit here
#   has an origin? yes -> repo-env defaults to overlay, else in-repo
#
# So an empty dir, a dir with files but no git, a git repo with history, and
# a clone all converge here. A bare repo is not an entry shape: the unit sets
# WorkingDirectory to the repo and spawns worktrees, so clone it first.
#
# Ownership is NOT guessed. repo-env picks overlay when an origin exists
# (assumed third-party, config kept out of the repo); for a repo you own that
# already has an origin, pass --in-repo. See using-project-envs.
set -euo pipefail

SERVER_CONFIG_DIR="${SERVER_CONFIG_DIR:-$HOME/server-config}"
ENABLE_SCRIPT="$SERVER_CONFIG_DIR/host/scripts.d/enable-claude-rc.sh"

serve=0
mode=()
target=""
while [ $# -gt 0 ]; do
    case "$1" in
        --serve) serve=1 ;;
        --in-repo|--overlay) mode+=("$1") ;;
        -h|--help) sed -n '2,22p' "$0" | sed 's/^# \?//'; exit 0 ;;
        -*) echo "unknown flag: $1" >&2; exit 2 ;;
        *) [ -n "$target" ] && { echo "one target only" >&2; exit 2; }; target="$1" ;;
    esac
    shift
done
[ -n "$target" ] || { echo "usage: new-project [--serve] [--in-repo|--overlay] <name-or-path>" >&2; exit 2; }

# A bare name means ~/repos/<name>; anything path-shaped is taken as given.
case "$target" in
    */*|.|..) dir="$(cd "$(dirname "$target")" && pwd)/$(basename "$target")" ;;
    *) dir="$HOME/repos/$target" ;;
esac
repo="$(basename "$dir")"

[ -d "$dir" ] || { echo "==> creating $dir"; mkdir -p "$dir"; }
cd "$dir"

# repo-env owns git init, mode selection, .envrc/devbox.json, direnv allow.
echo "==> repo-env setup"
repo-env setup --git-init "${mode[@]+"${mode[@]}"}"

# An unborn HEAD passes every check and then breaks worktree spawning, so
# close it here rather than at the first thread from the app.
#
# Only the environment files go in. Adding everything would be the usual
# `git init` reflex, but this also runs on directories that already had
# content, where a blind `git add -A` on a repo with no .gitignore is how
# build output and secrets get committed. Anything else is reported instead.
if ! git rev-parse --verify -q HEAD >/dev/null; then
    echo "==> no commits yet; committing the environment files"
    for f in .envrc devbox.json devbox.lock; do
        [ -e "$f" ] && git add -- "$f"
    done
    git commit -q -m "Add devbox/direnv project environment

Created by new-project (using-project-envs). A repo needs at least one
commit before it can host worktree-spawning agents."
elif [ -n "$(git status --porcelain -- .envrc devbox.json devbox.lock)" ]; then
    # Pre-existing history: never commit into it unasked, but say so, since
    # repo-env's own advice is to commit these.
    echo "==> environment files are uncommitted (repo already had history):"
    git status --short -- .envrc devbox.json devbox.lock | sed 's/^/    /'
fi

git --no-pager log --oneline -1

if [ -n "$(git status --porcelain)" ]; then
    echo "==> still untracked/modified, left for you:"
    git status --short | sed 's/^/    /'
fi

[ "$serve" -eq 1 ] || exit 0

# --- optional: persistent agent (running-persistent-agents) ---
[ -f "$ENABLE_SCRIPT" ] || {
    echo "$ENABLE_SCRIPT missing — install running-persistent-agents first" >&2
    exit 1
}

# The host script's REPOS list is the record of what should be served, and it
# already owns linger, the trust check and enabling. Add to it, then run it,
# so enabling logic lives in exactly one place.
if ! grep -qE "^[[:space:]]*$repo\$" "$ENABLE_SCRIPT"; then
    echo "==> recording $repo in $ENABLE_SCRIPT"
    python3 - "$ENABLE_SCRIPT" "$repo" <<'PY'
import re, sys
path, repo = sys.argv[1], sys.argv[2]
with open(path) as f:
    s = f.read()
# Insert before the ")" that closes the REPOS array.
new, n = re.subn(r"(REPOS=\((?:[^)]*?))(\n\))", rf"\g<1>\n    {repo}\g<2>", s, count=1)
if n != 1:
    sys.exit("could not find the REPOS=( ... ) block to edit")
with open(path, "w") as f:
    f.write(new)
PY
    echo "    commit $SERVER_CONFIG_DIR when you're happy with it"
fi

bash "$ENABLE_SCRIPT"

if systemctl --user is-active --quiet "claude-rc@$repo"; then
    echo "==> claude-rc@$repo is running"
    systemctl --user is-enabled "claude-rc@$repo" >/dev/null && echo "    enabled at boot"
fi
