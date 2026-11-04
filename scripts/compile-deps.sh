#!/usr/bin/env bash

# Regenerates requirements.lock. Run after bumping FORGE_REF or changing requirements.in or
# extras.txt, then rebuild and verify.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$SCRIPT_DIR"

IMAGE="${IMAGE:-forge-neo:latest}"
FORGE_REF=$(sed -n 's/^ARG FORGE_REF=\([0-9a-f]\{40\}\)$/\1/p' Dockerfile)
TORCH_INDEX=$(sed -n 's/^ARG TORCH_INDEX=\(.*\)$/\1/p' Dockerfile)

if [ -z "$FORGE_REF" ] || [ -z "$TORCH_INDEX" ]; then
    echo "cannot read FORGE_REF or TORCH_INDEX from the Dockerfile" >&2
    exit 1
fi

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "$IMAGE is not built yet; run ./build.sh first" >&2
    exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

git clone --quiet --filter=blob:none --no-checkout https://github.com/Haoming02/sd-webui-forge-classic "$WORK/forge"
git -C "$WORK/forge" checkout --quiet "$FORGE_REF"

docker run --rm \
    --entrypoint uv \
    --volume "$SCRIPT_DIR:/w" \
    --volume "$WORK/forge/requirements.txt:/forge-requirements.txt:ro" \
    --workdir /w \
    --user "$(id -u):$(id -g)" \
    --env HOME=/tmp \
    --env UV_CACHE_DIR=/tmp/uv-cache \
    --env PIP_CONSTRAINT= \
    "$IMAGE" pip compile \
        --generate-hashes \
        --python /usr/bin/python3.12 \
        --index-url https://pypi.org/simple \
        --extra-index-url "https://download.pytorch.org/whl/$TORCH_INDEX" \
        --index-strategy unsafe-best-match \
        requirements.in /forge-requirements.txt extras.txt \
        --output-file requirements.lock
