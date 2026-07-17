#!/usr/bin/env bash
# Compare a staged copy of an old home directory against the live home.
# Usage: home-conflicts.sh STAGED_OLD_HOME [LIVE_HOME] [OUT_DIR]
# Produces: old-only.txt (safe to copy), shared-differences.txt (needs
# review/merge), new-only.txt (new-machine/provider files). Read-only.
set -euo pipefail

OLD_HOME="${1:?usage: home-conflicts.sh STAGED_OLD_HOME [LIVE_HOME] [OUT_DIR]}"
LIVE_HOME="${2:-$HOME}"
OUT="${3:-$(pwd)/home-conflict-reports}"

[ -d "$OLD_HOME" ] || { echo "not a directory: $OLD_HOME" >&2; exit 1; }
mkdir -p "$OUT"

# Exclude the staging area itself if it lives inside the live home.
EXCLUDES=()
case "$OLD_HOME"/ in
    "$LIVE_HOME"/*) EXCLUDES+=(--exclude "/$(realpath --relative-to="$LIVE_HOME" "$OLD_HOME" | cut -d/ -f1)/") ;;
esac

rsync -ani --ignore-existing "${EXCLUDES[@]}" --out-format='%i %n%L' \
    "$OLD_HOME/" "$LIVE_HOME/" > "$OUT/old-only.txt"

rsync -ani --checksum --existing "${EXCLUDES[@]}" --out-format='%i %n%L' \
    "$OLD_HOME/" "$LIVE_HOME/" > "$OUT/shared-differences.txt"

rsync -ani --ignore-existing "${EXCLUDES[@]}" --out-format='%i %n%L' \
    "$LIVE_HOME/" "$OLD_HOME/" > "$OUT/new-only.txt"

echo "Reports in $OUT:"
for f in old-only shared-differences new-only; do
    printf '  %-22s %s lines\n' "$f.txt" "$(wc -l < "$OUT/$f.txt")"
done
echo
echo "shared-differences.txt is the review/merge list. Directory-metadata"
echo "lines (starting .d) are usually noise; focus on >f lines."
