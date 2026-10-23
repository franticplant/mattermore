#!/usr/bin/env bash
# Fail closed on authentication/network errors. Only an explicit absent manifest
# permits a write. GHCR does not provide a compare-and-swap/immutable-tag API.
set -euo pipefail
reference="${1:?registry reference}"
err="$(mktemp)"
trap 'rm -f "$err"' EXIT
if skopeo inspect "docker://$reference" >/dev/null 2>"$err"; then
    echo "Refusing to overwrite $reference" >&2
    exit 1
fi
if ! grep -Eiq 'manifest unknown|name unknown|MANIFEST_UNKNOWN|NAME_UNKNOWN' "$err"; then
    cat "$err" >&2
    exit 1
fi
