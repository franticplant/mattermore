#!/usr/bin/env bash
# Same upstream webapp build, separately cacheable from the Go binary.
set -euo pipefail
WORK="$(readlink -f "${1:?patched server checkout}")"
OUT="$(readlink -f "${2:?output directory}")"
( cd "$WORK/webapp" && npm ci --no-audit --no-fund )
( cd "$WORK/webapp" && NODE_OPTIONS=--max-old-space-size=6144 npm run build )
rm -rf "$OUT/client"
cp -r "$WORK/webapp/channels/dist" "$OUT/client"
