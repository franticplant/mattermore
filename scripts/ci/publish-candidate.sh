#!/usr/bin/env bash
set -euo pipefail
variant="${1:?variant}"
image="ghcr.io/$GITHUB_REPOSITORY"
candidate="candidate-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT-$variant"
scripts/ci/registry-absent.sh "$image:$candidate"
skopeo copy --all --preserve-digests "oci-archive:out/$variant.tar" "docker://$image:$candidate"
digest="sha256:$(skopeo inspect --raw "docker://$image:$candidate" | sha256sum | cut -d' ' -f1)"
test "$digest" = "$(jq -r '.["containerimage.digest"]' "out/$variant.build.json")"
printf 'digest=%s\ncandidate=%s\n' "$digest" "$candidate" >> "$GITHUB_OUTPUT"
jq -n --arg digest "$digest" --arg candidate "$candidate" --arg image "$image" \
    --arg source_commit "$GITHUB_SHA" \
    '{digest:$digest,candidate:$candidate,image:$image,source_commit:$source_commit}' > "out/$variant.candidate.json"
