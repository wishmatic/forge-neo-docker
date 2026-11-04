#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

CONTAINER="${CONTAINER:-sdwui-forge-neo}"
IMAGE="${IMAGE:-forge-neo:latest}"

MODE=container
STATIC=0
RECREATE=0

ALLOWED_TO_FLOAT=""

usage() {
    cat <<EOF
usage: $(basename "$0") [options]

Runs every check that has to pass before an image is worth deploying.

  --container NAME   container to check (default: $CONTAINER)
  --image IMAGE      check a freshly built image with no running container and no
                     GPU; runs only the checks that need neither (used by CI)
  --static           skip the GPU checks
  --recreate         remove and re-create the container with ./run.sh first, and
                     assert the image id is unchanged afterwards
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --container) CONTAINER="$2"; shift 2 ;;
        --image) MODE=image; IMAGE="$2"; shift 2 ;;
        --static) STATIC=1; shift ;;
        --recreate) RECREATE=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; usage; exit 2 ;;
    esac
done

if [ "$MODE" = image ]; then
    STATIC=1
fi

if [ "$MODE" = image ] && [ "$RECREATE" = 1 ]; then
    echo "--recreate needs a container, not --image" >&2
    exit 2
fi

if [ "$MODE" = container ]; then
    if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
        echo "no container named $CONTAINER; create it with ./run.sh" >&2
        exit 2
    fi
    if [ "$(docker inspect --format '{{.State.Running}}' "$CONTAINER")" != true ]; then
        echo "$CONTAINER is not running; start it with ./run.sh --recreate" >&2
        exit 2
    fi
fi

step() { printf '\n%s\n' "$*"; }
pass() { printf '  ok    %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*" >&2; exit 1; }

runtime() {
    local stage=$1
    if [ "$MODE" = image ]; then
        docker run --rm -i -e "VERIFY_ALLOW_FLOAT=$ALLOWED_TO_FLOAT" \
            --entrypoint python "$IMAGE" - "$stage" < "$SCRIPT_DIR/scripts/verify_runtime.py"
    else
        docker exec -i -e "VERIFY_ALLOW_FLOAT=$ALLOWED_TO_FLOAT" \
            "$CONTAINER" python - "$stage" < "$SCRIPT_DIR/scripts/verify_runtime.py"
    fi
}

recreate() {
    local before after
    before=$(docker inspect --format '{{.Image}}' "$CONTAINER")
    "$SCRIPT_DIR/run.sh" --recreate >/dev/null
    after=$(docker inspect --format '{{.Image}}' "$CONTAINER")
    echo "     image id before: $before"
    echo "     image id after:  $after"
    [ "$before" = "$after" ] || fail "the image changed across a container recreate"
}

step "torch is built for sm_120"
runtime static || fail "torch cannot run on this GPU"
pass "sm_120 present in the arch list"

step "installed packages match requirements.lock"
runtime pins || fail "the venv drifted from the lock"
pass "no drift"

if [ "$STATIC" = 0 ]; then
    if [ "$RECREATE" = 1 ]; then
        step "re-create the container"
        recreate
        pass "same image id across a recreate"
    fi

    step "cuda runs"
    runtime gpu || fail "a CUDA op failed"
    pass "matmul and xformers attention ran"
fi

printf '\nall checks passed\n'
