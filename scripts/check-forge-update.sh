#!/usr/bin/env bash

# Prints upstream commits since the pinned FORGE_REF; exits 1 if there are any. Never edits the
# Dockerfile: bumping is a decision, then build, then verify.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")/.." && pwd)
REPO="${FORGE_REPO:-https://github.com/Haoming02/sd-webui-forge-classic}"
BRANCH="${FORGE_BRANCH:-neo}"

FORGE_REF="${FORGE_REF:-$(sed -n 's/^ARG FORGE_REF=\([0-9a-f]\{40\}\)$/\1/p' "$SCRIPT_DIR/Dockerfile")}"
if [ -z "$FORGE_REF" ]; then
    echo "cannot read a full FORGE_REF from $SCRIPT_DIR/Dockerfile" >&2
    exit 2
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# bare + no blobs: commit history only.
git clone --quiet --bare --filter=blob:none --branch "$BRANCH" "$REPO" "$WORK/forge.git"

AHEAD=$(git -C "$WORK/forge.git" rev-list --count "$FORGE_REF..$BRANCH")
if [ "$AHEAD" = 0 ]; then
    echo "up to date: $BRANCH is at $FORGE_REF"
    exit 0
fi

NEWEST=$(git -C "$WORK/forge.git" rev-parse "$BRANCH")

echo "$AHEAD commit(s) on $BRANCH since $FORGE_REF:"
echo
git -C "$WORK/forge.git" log --oneline --no-decorate "$FORGE_REF..$BRANCH"
echo
echo "to bump: set FORGE_REF to $NEWEST in Dockerfile, run ./build.sh, then ./verify.sh"
exit 1
