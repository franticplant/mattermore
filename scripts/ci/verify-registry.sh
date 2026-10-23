#!/usr/bin/env bash
# Fresh-runner verification: OCI native metadata, signed provenance, signed SPDX,
# exact source identity, tag/digest equality, and a digest-pulled runtime test.
set -euo pipefail
variant="${1:?variant}"
record="out/$variant.candidate.json"
image="$(jq -r .image "$record")"
digest="$(jq -r .digest "$record")"
candidate="$(jq -r .candidate "$record")"
test "$image" = "ghcr.io/$GITHUB_REPOSITORY"
test "$(jq -r .source_commit "$record")" = "$GITHUB_SHA"
test "sha256:$(skopeo inspect --raw "docker://$image:$candidate" | sha256sum | cut -d' ' -f1)" = "$digest"
skopeo inspect --raw "docker://$image@$digest" > "out/$variant.index.json"
jq -e '[.manifests[].platform | select(.os != "unknown") | .os+"/"+.architecture] | sort == ["linux/amd64"]' "out/$variant.index.json"
# BuildKit attestations must actually be present in the index, not only enabled
# in YAML. Their bytes are bound by the signed index digest.
jq -e '[.manifests[] | select(.annotations["vnd.docker.reference.type"] == "attestation-manifest")] | length > 0' "out/$variant.index.json"
source upstream.env
docker buildx imagetools inspect "$image@$digest" --format '{{json .Provenance}}' > "out/$variant.buildkit-provenance.json"
jq -e --arg server "$SERVER_COMMIT" --arg calls "$CALLS_COMMIT" --arg sha "$GITHUB_SHA" \
    '[.. | strings] | index($server) != null and index($calls) != null and index($sha) != null' \
    "out/$variant.buildkit-provenance.json"
policy=(--repo "$GITHUB_REPOSITORY" --source-digest "$GITHUB_SHA"
    --signer-workflow "$GITHUB_REPOSITORY/.github/workflows/release.yml"
    --deny-self-hosted-runners)
for storage in api oci; do
    extra=()
    if [ "$storage" = oci ]; then extra+=(--bundle-from-oci); fi
    gh attestation verify "oci://$image@$digest" "${policy[@]}" "${extra[@]}" \
        --format json > "out/$variant.provenance-$storage.json"
    gh attestation verify "oci://$image@$digest" "${policy[@]}" "${extra[@]}" \
        --predicate-type https://spdx.dev/Document --format json > "out/$variant.sbom-$storage.json"
done
# Compare the attested predicate to the downloadable SBOM, not just its type.
jq -S . "out/$variant.spdx.json" > "out/$variant.expected-spdx.json"
jq -S '.[0].verificationResult.statement.predicate' "out/$variant.sbom-api.json" > "out/$variant.attested-spdx.json"
cmp "out/$variant.expected-spdx.json" "out/$variant.attested-spdx.json"
docker pull "$image@$digest"
labels="$(docker image inspect "$image@$digest" --format '{{json .Config.Labels}}')"
jq -e --arg sha "$GITHUB_SHA" --arg version "$GITHUB_REF_NAME" \
    '."org.opencontainers.image.revision" == $sha and
     ."org.opencontainers.image.source" == "https://github.com/franticplant/mattermore" and
     ."org.opencontainers.image.version" == $version and
     (."org.opencontainers.image.created" | length > 0) and
     ."org.opencontainers.image.licenses" == "AGPL-3.0-only"' <<< "$labels"
scripts/e2e.sh "$image@$digest"
# Registry compressed layer sizes are measured from the actual platform manifest.
platform_digest="$(jq -r '.manifests[] | select(.platform.os == "linux") | .digest' "out/$variant.index.json")"
size="$(skopeo inspect --raw "docker://$image@$platform_digest" | jq '[.layers[].size] | add')"
jq --argjson size "$size" '. + {verification:"passed",compressed_layer_bytes:$size,
    provenance:"GitHub SLSA v1 (API and OCI) plus BuildKit index predicate",
    sbom_attestation:"GitHub SPDX (API and OCI)"}' "$record" > "out/$variant.verified.json"
echo "Verified $variant: $image@$digest; compressed layers $size bytes; provenance/SPDX (API + OCI), source, metadata and digest-pulled e2e passed." >> "$GITHUB_STEP_SUMMARY"
