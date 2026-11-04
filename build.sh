#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR"

FORGE_REF="${FORGE_REF:-$(sed -n 's/^ARG FORGE_REF=\([0-9a-f]\{40\}\)$/\1/p' Dockerfile)}"
if [ -z "$FORGE_REF" ]; then
    echo "cannot read a full FORGE_REF from the Dockerfile" >&2
    exit 1
fi

IMAGE="${IMAGE:-forge-neo}"
SHORT="${FORGE_REF:0:12}"
FORGE_TAG="${IMAGE}:forge-${SHORT}"

docker build --build-arg "FORGE_REF=$FORGE_REF" --tag "$FORGE_TAG" .

ID=$(docker image inspect --format '{{.Id}}' "$FORGE_TAG")
ID=${ID#sha256:}
ID=${ID:0:12}

docker tag "$FORGE_TAG" "${IMAGE}:digest-${ID}"
docker tag "$FORGE_TAG" "${IMAGE}:latest"

printf '\n%s\n%s\n%s\n' "$FORGE_TAG" "${IMAGE}:digest-${ID}" "${IMAGE}:latest"
