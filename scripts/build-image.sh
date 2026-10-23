#!/usr/bin/env bash
# Shared source build, supported by rootless Podman and Docker Buildx.
# Usage: build-image.sh [tag] [minimal|alpine|ubi|ubi-micro|debug]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
tag="${1:-mattermore:dev}"
variant="${2:-minimal}"
case "$variant" in minimal|alpine|ubi|ubi-micro|debug) ;; *) exit 2;; esac
engine="${CONTAINER_ENGINE:-$(command -v podman || command -v docker)}"
# Only tracked files enter the build, regardless of local ignored files.
context="$(mktemp -d)"
trap 'rm -rf "$context"' EXIT
git archive HEAD | tar -x -C "$context"
# shellcheck source=upstream.env
source "$context/upstream.env"
"$engine" build --target "$variant" --build-arg "RUNTIME=$variant" \
    --build-arg "SOURCE_REVISION=$(git rev-parse HEAD)" \
    --build-arg "SOURCE_DATE_EPOCH=$(git show -s --format=%ct HEAD)" \
    --build-arg "CREATED=$(git show -s --format=%cI HEAD)" \
    --build-arg "SERVER_COMMIT=$SERVER_COMMIT" --build-arg "CALLS_COMMIT=$CALLS_COMMIT" \
    -t "$tag" -f "$context/Containerfile" "$context"
