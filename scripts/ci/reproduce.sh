#!/usr/bin/env bash
set -euo pipefail
source upstream.env
mkdir context
git archive HEAD | tar -x -C context
docker buildx build --no-cache --file context/Containerfile --platform linux/amd64 \
    --build-arg "SOURCE_REVISION=$GITHUB_SHA" \
    --build-arg "SOURCE_DATE_EPOCH=$(git show -s --format=%ct HEAD)" \
    --build-arg "SERVER_COMMIT=$SERVER_COMMIT" --build-arg "CALLS_COMMIT=$CALLS_COMMIT" \
    --target binary --output type=local,dest=binary context
actual="$(sha256sum binary/mattermore-server | cut -d' ' -f1)"
test "$actual" = "$EXPECTED_SERVER_SHA"
echo "Independent server binary reproduction: $actual" >> "$GITHUB_STEP_SUMMARY"
