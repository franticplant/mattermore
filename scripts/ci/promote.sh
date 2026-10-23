#!/usr/bin/env bash
set -euo pipefail
version="${GITHUB_REF_NAME#v}"
image="ghcr.io/$GITHUB_REPOSITORY"
variants=(minimal alpine ubi ubi-micro debug)
if gh release view "$GITHUB_REF_NAME" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
    echo 'Release already exists; refusing to modify it.' >&2; exit 1
fi
# Preflight the entire family before writing any public version tag.
for variant in "${variants[@]}"; do
    suffix="-$variant"; if [ "$variant" = minimal ]; then suffix=''; fi
    scripts/ci/registry-absent.sh "$image:$version$suffix"
done
for variant in "${variants[@]}"; do
    suffix="-$variant"; if [ "$variant" = minimal ]; then suffix=''; fi
    digest="$(jq -r .digest "out/$variant.verified.json")"
    skopeo copy --all --preserve-digests "docker://$image@$digest" "docker://$image:$version$suffix"
    test "sha256:$(skopeo inspect --raw "docker://$image:$version$suffix" | sha256sum | cut -d' ' -f1)" = "$digest"
done
python3 scripts/ci/release-manifest.py finalize out
mkdir release-assets
cp out/release-manifest.json out/*.spdx.json out/*.scan.json upstream.env LICENSE release-assets/
(cd release-assets && sha256sum ./*) > release-checksums
mv release-checksums release-assets/SHA256SUMS
{
    echo "Mattermore $version, source $GITHUB_SHA. All five AMD64 variants passed digest-pulled verification."
    echo
    echo 'Canonical references (deploy by digest, not by tag):'
    jq -r '.variants[] | "- " + .variant + ": `" + .image + "@" + .digest + "` (" + (.compressed_layer_bytes|tostring) + " compressed layer bytes)"' out/release-manifest.json
    echo
    echo "Upstream revisions and per-variant inventories, scan findings, SBOM/provenance references and verification results: release-manifest.json."
    echo "Verification instructions: https://github.com/$GITHUB_REPOSITORY/blob/$GITHUB_SHA/docs/containers.md"
} > release-notes.md
# GitHub immutable releases: attach everything in one creation, never --clobber.
gh release create "$GITHUB_REF_NAME" release-assets/* --repo "$GITHUB_REPOSITORY" \
    --verify-tag --title "$GITHUB_REF_NAME" --notes-file release-notes.md
