#!/usr/bin/env bash

set -euo pipefail

IMAGE="${IMAGE:-forge-neo:latest}"
CONTAINER="${CONTAINER:-sdwui-forge-neo}"
PORT="${PORT:-7860}"
APPDATA="${APPDATA:-/mnt/user/appdata/forge-neo}"

RECREATE=0
if [ "${1:-}" = "--recreate" ]; then
    RECREATE=1
elif [ $# -gt 0 ]; then
    echo "usage: $(basename "$0") [--recreate]" >&2
    exit 2
fi

if docker inspect "$CONTAINER" >/dev/null 2>&1; then
    if [ "$RECREATE" = 0 ]; then
        echo "$CONTAINER already exists; pass --recreate to replace it" >&2
        exit 1
    fi
    docker rm --force "$CONTAINER" >/dev/null
fi

mkdir -p "$APPDATA"/models "$APPDATA"/output "$APPDATA"/extensions \
         "$APPDATA"/embeddings "$APPDATA"/config "$APPDATA"/cache

# nobody:users. Root-owned dirs here would be unwritable to the container.

if [ "$(id -u)" = 0 ]; then
    chown -R 99:100 "$APPDATA"
fi

extra=()
if [ -n "${COMMANDLINE_ARGS:-}" ]; then
    extra=(-e "COMMANDLINE_ARGS=$COMMANDLINE_ARGS")
fi

docker run --detach \
    --name "$CONTAINER" \
    --init \
    --gpus all \
    --restart unless-stopped \
    --user 99:100 \
    --publish "$PORT:7860" \
    --volume "$APPDATA/models:/home/forge/sd-webui/models" \
    --volume "$APPDATA/embeddings:/home/forge/sd-webui/models/embeddings" \
    --volume "$APPDATA/output:/home/forge/sd-webui/output" \
    --volume "$APPDATA/extensions:/home/forge/sd-webui/extensions" \
    --volume "$APPDATA/config:/home/forge/sd-webui/config" \
    --volume "$APPDATA/cache:/home/forge/sd-webui/cache" \
    "${extra[@]}" \
    "$IMAGE"
