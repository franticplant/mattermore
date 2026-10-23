#!/usr/bin/env bash
# No registry credentials. Reuse the application cache for all runtime targets.
set -euo pipefail
source upstream.env
mkdir -p out context
git archive HEAD | tar -x -C context
args=(--file context/Containerfile --platform linux/amd64
    --build-arg "SOURCE_REVISION=$GITHUB_SHA"
    --build-arg "SOURCE_DATE_EPOCH=$(git show -s --format=%ct HEAD)"
    --build-arg "CREATED=$(git show -s --format=%cI HEAD)"
    --build-arg "VERSION=${VERSION:-ci}"
    --build-arg "SERVER_COMMIT=$SERVER_COMMIT" --build-arg "CALLS_COMMIT=$CALLS_COMMIT")
for variant in minimal alpine ubi ubi-micro debug; do
    docker buildx build "${args[@]}" --build-arg "RUNTIME=$variant" --target "$variant" \
        --provenance=mode=max \
        --sbom=generator=docker/buildkit-syft-scanner@sha256:ae4f3b554449e7e25548e7d8ccc029d17357348e30c6e3df01b92bc93654d6a9 \
        --metadata-file "out/$variant.build.json" \
        --output "type=oci,dest=out/$variant.tar,rewrite-timestamp=true" context
    skopeo copy "oci-archive:out/$variant.tar" "docker-daemon:mattermore:$variant"
    # Every variant proves the existing >250-user and Calls functionality.
    scripts/e2e.sh "mattermore:$variant"
    scripts/ci/scan-image.sh "$variant"
    docker image inspect "mattermore:$variant" > "out/$variant.inspect.json"
    docker image rm "mattermore:$variant"
done
# Export the already-built binary and compare in a fresh job with no cache.
docker buildx build "${args[@]}" --target binary --output type=local,dest=out/binary context
sha256sum out/binary/mattermore-server | cut -d' ' -f1 > out/server.sha256
rm -r out/binary
cp upstream.env out/
python3 scripts/ci/release-manifest.py inventory out
(cd out && find . -maxdepth 1 -type f -print0 | sort -z | xargs -0 sha256sum) > family-checksums
mv family-checksums out/SHA256SUMS
tar -cf family.tar out
echo "family-sha=$(sha256sum family.tar | cut -d' ' -f1)" >> "$GITHUB_OUTPUT"
echo "server-sha=$(cat out/server.sha256)" >> "$GITHUB_OUTPUT"
