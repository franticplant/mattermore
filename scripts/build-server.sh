#!/usr/bin/env bash
#
# Builds the Mattermore server binary.
#
# Usage: ./scripts/build-server.sh [output-path]
# Requires: git, go, node, npm.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$(realpath -m "${1:-$ROOT/dist/mattermore-server}")"
WORK="$ROOT/build/server"

# shellcheck source=upstream.env
source "$ROOT/upstream.env"

echo "==> upstream $SERVER_TAG"
rm -rf "$WORK"; mkdir -p "$(dirname "$WORK")" "$(dirname "$OUT")"
git clone --quiet --depth 1 --branch "$SERVER_TAG" \
    https://github.com/mattermost/mattermost.git "$WORK"
test "$(git -C "$WORK" rev-parse HEAD)" = "$SERVER_COMMIT"

for patch in "$ROOT"/patches/server/*.patch; do
    echo "    $(basename "$patch")"
    git -C "$WORK" apply "$patch"
done

# The marks are images, not code, so they are copied rather than patched. They
# are committed already rendered, so this needs no image tooling.
"$ROOT/scripts/brand-assets.sh" apply "$WORK"

# Upstream's own build does this and gitignores the result: the server module
# depends on server/public, and without a workspace Go resolves it to the
# published version, which lags the tree and fails to compile.
( cd "$WORK/server" && go work init . ./public )

( cd "$WORK/server" && CGO_ENABLED=0 go build -trimpath -buildvcs=false \
    -ldflags='-buildid=' -o "$OUT" ./cmd/mattermost )

# Two patches change only the web app, and the official image ships a prebuilt
# one. Without this step those patches are inert: the guest administration
# screens stay hidden and the licence badges stay put. Roughly four minutes.
if [ "${SKIP_WEBAPP:-}" != "1" ]; then
    echo "==> building the web app"
    "$ROOT/scripts/build-webapp.sh" "$WORK" "$(dirname "$OUT")"
    echo "==> $(dirname "$OUT")/client"
fi

echo "==> $OUT"
