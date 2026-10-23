# Mattermore container supply chain

See [the baseline audit](container-audit.md) and [validation evidence](container-validation.md).
**A workflow definition is not a successful release.** Do not treat a family as
released until its GitHub release and `release-manifest.json` exist and verify.

## Build and trust boundaries

PRs and main use `build.yml` → `containers.yml`: lint, clean tracked-file
context, pinned upstream clones, existing patch/brand scripts, static Go server
and mmctl, upstream npm builds, upstream Calls make, five runtime images.
Application layers are shared on one BuildKit builder; variants do not compile
five separate application copies. All five images run the existing 255-user /
patched Calls test, PostgreSQL migrations, `/api/v4/system/ping`, notices and
asset checks under non-root, no capabilities, no-new-privileges and read-only
root. No OIDC provider or production credentials are needed. Existing external
authentication-specific `scripts/release-test` tooling is not replaced.

CI has contents-read only, no registry login, no OIDC or attestation write, no
release secrets. There is no pull_request_target or PR publishing. A fresh
second job rebuilds and compares the server binary SHA256 and **gates** both CI
and releases. OCI archives, SPDX inventories, scans, BuildKit metadata and
checksums are retained as `validated-family` for seven days. Failures retain
available JSON reports. Main does not publish development or production tags.

The release workflow accepts only stable `vMAJOR.MINOR.PATCH` tags (no leading
zeros). The commit must be on main and have a successful main push build for
that exact SHA. It rebuilds/checks the family, verifies archive checksums across
jobs, then requires approval in the `release` environment. Only publication
jobs have packages-write. Only signing jobs have OIDC/attestations-write.
Checkout credentials are not persisted; actions and base images are SHA/digest
pinned; runner OS is ubuntu-24.04 (host patch image is maintained by GitHub).

Each image is first pushed under a unique `candidate-RUN-ATTEMPT-VARIANT` tag,
with the exact OCI index preserved, not rebuilt. Both GitHub provenance and
SPDX attestations bind **that variant's index digest**. Fresh verification jobs
check the registry index/platforms, native attestation presence, signed
attestations via both GitHub API and OCI, attested/downloaded SPDX equality,
source commit, labels and candidate tag equality, then pull by digest and rerun
the restrictive e2e test. All must pass before version-tag promotion.

Public tags are `1.2.3` (minimal), `1.2.3-alpine`, `1.2.3-ubi`,
`1.2.3-ubi-micro`, `1.2.3-debug`. No rolling tags are currently written. Never
use `latest` as the canonical reference. Global release concurrency does not
cancel running releases. Existing version tags/releases are refused, including
on reruns. GHCR has no immutable-tag compare-and-swap: this is workflow-enforced
immutability, not protection against an administrator or another writer.
Restrict package writers and never push these version tags manually.

Five registry tag writes cannot be atomic. A failed promotion can leave some
version tags, but no complete GitHub release is created. Never overwrite them;
investigate and cut a new version. Candidate tags may remain after failure;
they are not official releases. No deletion/cleanup of existing assets is
performed. A published release manifest is the completeness marker.

## Runtime family and platforms

| Variant | Base / intent | Platforms |
|---|---|---|
| minimal | distroless Debian base, glibc and CA roots, no shell/package manager | AMD64 |
| alpine | Alpine; static Mattermore server and matching static mmctl | AMD64 |
| ubi | UBI 9 Minimal, RPM inventory/package manager inherited | AMD64 |
| ubi-micro | UBI 9 Micro, no package manager | AMD64 |
| debug | Alpine with curl, DNS/network/process tools and strace | AMD64 |

Every target has the same application tree, inherited plugins/assets/notices,
configuration overrides, patched Calls bundle, and trust bundle. Old server and
webapp layers are **not** retained. The glibc base is deliberate rather than
claiming scratch compatibility for every inherited third-party component.
Alpine's suitability is gated by the plugin activation test, not assumed.
Debug is for diagnosis, not the default production recommendation; strace still
obeys the host seccomp/capability policy (no automatic SYS_PTRACE).

ARM64 is not advertised: pinned upstream Team Edition provides only AMD64,
including its original dynamically-linked mmctl and other bundled plugins.
Calls Go builds do support ARM64, but that alone does not establish image-family
support. Static mmctl is now built from matching server source for Alpine;
ARM64 still needs a tested replacement for the complete inherited image payload.
No QEMU relabeling or AMD64 image is used under an ARM platform descriptor.

UID:GID is 2000:2000. Read-only root requires writable volumes at:
`/mattermost/config`, `/mattermost/data`, `/mattermost/logs`,
`/mattermost/plugins`, `/mattermost/client/plugins`; tmpfs at `/tmp` and
`/var/tmp` (local-mode socket). Plugin storage must allow execution. Named
volumes initialize defaults from the image. For bind mounts, seed the config
and set ownership in the rootless user's namespace, e.g.
`podman unshare chown -R 2000:2000 <directory>`, and use `:Z` on SELinux hosts
(`:z` only for deliberately shared paths). Ensure the user's subordinate
UID/GID range covers 2000; do not chown host directories to a guessed host UID.
No engine socket, privileged mode or root init is required. Externally poll
`/api/v4/system/ping`; minimal does not install curl merely for HEALTHCHECK.
The precise restrictions tested are in `scripts/e2e.sh`; rootless Podman and
SELinux host testing are separately recorded, not implied by Docker CI.

## Upstream inputs and reproduction

`upstream.env` pairs human-readable tags with exact commits. Scripts clone the
tag and abort if its peeled HEAD changes. Update both together, rebase patches
only when necessary, and review upstream licensing/security changes. The
transcriber is not part of this image. Go 1.26.8, Node 22.22.2, base images,
BuildKit, scanner and action identities are pinned in source. To update a base:

```sh
skopeo inspect --format '{{.Digest}}' docker://docker.io/library/alpine:3.23
git ls-remote https://github.com/mattermost/mattermost.git 'refs/tags/v12.0.1*'
```

Review manifests/platforms and licenses, update the digest in a PR and require
all tests/scans. Do not automatically refresh mutable tags in a release.
Go uses CGO_ENABLED=0, trimpath, no VCS stamping and an empty build ID. Plugin
repacking sorts paths, fixes ownership/mtime, and removes gzip timestamps.
SOURCE_DATE_EPOCH/created use the fork commit time; OCI export rewrites mtimes.

```sh
git checkout <reviewed-commit>
mkdir -p "$HOME/mattermore-tmp"  # use disk, not RAM-backed /tmp
TMPDIR="$HOME/mattermore-tmp" CONTAINER_ENGINE=podman \
  scripts/build-image.sh mattermore:local minimal
CONTAINER_ENGINE=podman scripts/e2e.sh mattermore:local
```

build-image uses **committed tracked files**, not uncommitted edits. Docker
requires Buildx for the CI OCI/provenance exports. Reproduction is intentionally
limited to the server binary, not byte-identical OCI indexes, native provenance,
webpack assets or Calls output. Attestations contain run-specific identities;
webpack and upstream make may introduce other nondeterminism. Debian build-stage
apt and debug apk repositories are still live; dependency indexes and scanner
databases are not hermetically snapshotted. Those package versions appear in
build/native SBOMs or final image inventories. Do not claim fully hermetic builds
or a SLSA assurance level from max provenance alone.

## SBOM, provenance and security policy

BuildKit emits OCI-native max build provenance and an SPDX SBOM for each index
member. The max predicate records build args (including exact source/upstream
revisions), base digest materials, target and build steps. Source fetched by a
RUN git clone is **not** automatically a native resolved dependency: the pinned
commit is checked by scripts and recorded as an argument and in the shipped
`build-inputs/upstream.env`. The local tracked context's revision is asserted by
the workflow, labels and signed GitHub provenance, not discovered from .git.

GitHub additionally signs SLSA v1 provenance identifying repository, commit,
workflow and run, and signs the Syft **final delivered OCI archive** SPDX against
each pushed index digest. These signed index subjects also bind the embedded
BuildKit predicates. BuildKit attachment alone is not a separate Sigstore
identity signature. GitHub actions run with the selected source; a compromised
approved workflow can make false claims. These are integrity/origin checks,
not proof that software is safe or all dependencies are identified.

Syft catalogs OS packages and Go modules discoverable in binaries. Shipped npm
lockfiles in `/mattermost/build-inputs` supplement bundled JS discovery but may
include build/dev dependencies which are not runtime code. Compressed plugin
archives and minified JS may not be fully resolved by any scanner. The patched
Calls binary and version are exercised at runtime. Do not claim complete JS,
all plugins, or third-party dependency coverage without reviewing the SBOM.

Trivy scans final images for vulnerabilities, secrets (redacted in reports), and
full license findings. Scanner errors block. All CRITICAL findings block by
default, not only those with known fixes; all secret findings block. HIGH and
lower are reported for review; exploitability and build-only attribution require
human triage. No blanket ignore or continue-on-error is used. Exact package/CVE
exceptions in `security/exceptions.json` require owner, reason, review date,
expiry within 90 days; invalid/expired entries block. Changes require review.
Licenses are inventoried, not automatically declared legally compliant.
AGPL source/distribution duties, upstream notices and third-party licenses must
be reviewed before approval. Preserve LICENSE, source patches, bundled plugin
licenses and webapp license files. No code license is changed here.

Reports include observed package counts/vulnerability severities and archive
sizes. After publication compressed **layer** bytes are measured separately
from registry manifests. These metrics are not interchangeable and smallest
does not mean most secure. The per-variant release manifest and downloadable
SPDX/Trivy JSON provide the comparison; do not fabricate measurements before
a successful run.

## Owner setup and release procedure

1. Protect main with required PR review and successful `build` container lint,
   family and reproduce jobs. Require review for workflows, Containerfile,
   scripts, pins, patches and exception policy (CODEOWNERS recommended).
2. Create `release` environment with required reviewers, prevent self-review,
   and allow only protected v* release tags. The guard fails if required
   reviewers are absent. Do not put production application secrets here.
3. Add a v* tag ruleset prohibiting updates/deletion and limiting creation to
   release maintainers. Restrict bypasses. Enable immutable GitHub releases.
4. GHCR package must permit this repository's GITHUB_TOKEN to write. Limit all
   other writers; decide public visibility. Default Actions permissions should
   remain read-only; enable GitHub attestations for the repository/plan.
5. Review critical/license findings, run a controlled candidate release only
   with owner authorization, and verify this pipeline before production use.
6. Once an exact main commit has passed CI, an authorized maintainer may run:

```sh
git fetch origin main
git tag -s v1.2.3 <approved-main-commit> -m 'Mattermore 1.2.3'
git push origin v1.2.3
```

Approve the environment jobs after reviewing the run. A successful release
attaches `release-manifest.json`, all final SPDX and Trivy reports, upstream pins,
LICENSE and SHA256SUMS. Never reuse a tag or overwrite a partial version.
No production tag or candidate is created merely by opening this PR.

## Independent retrieval and verification

Use current gh (tested locally: 2.87.3; must support `--bundle-from-oci`),
Docker/Podman and skopeo. Obtain the **actual** digest and commit from the release
manifest; the variables below intentionally do not invent a published digest.

```sh
gh release download v1.2.3 -R franticplant/mattermore \
  -p release-manifest.json -p minimal.spdx.json -p SHA256SUMS
DIGEST=$(jq -r '.variants[] | select(.variant=="minimal") | .digest' release-manifest.json)
COMMIT=$(jq -r .source_commit release-manifest.json)
IMAGE=ghcr.io/franticplant/mattermore
docker pull "$IMAGE@$DIGEST"
docker buildx imagetools inspect "$IMAGE@$DIGEST"
gh attestation verify "oci://$IMAGE@$DIGEST" -R franticplant/mattermore \
  --signer-workflow franticplant/mattermore/.github/workflows/release.yml \
  --source-digest "$COMMIT" --deny-self-hosted-runners
gh attestation verify "oci://$IMAGE@$DIGEST" -R franticplant/mattermore \
  --signer-workflow franticplant/mattermore/.github/workflows/release.yml \
  --source-digest "$COMMIT" --predicate-type https://spdx.dev/Document \
  --bundle-from-oci --format json > verified-sbom.json
jq -S '.[0].verificationResult.statement.predicate' verified-sbom.json > attested.json
jq -S . minimal.spdx.json > downloaded.json
cmp attested.json downloaded.json
test "$(skopeo inspect --raw docker://$IMAGE:1.2.3 | sha256sum | cut -d' ' -f1)" = "${DIGEST#sha256:}"
```

Repeat for each variant (each has a different subject). Authenticate to GHCR
first if needed; use `gh auth token | docker login ghcr.io -u <user> --password-stdin`
only with a token allowed to read packages. Default gh verification retrieves
bundles from GitHub; `--bundle-from-oci` tests registry storage. Native predicates
can also be inspected with `docker buildx imagetools inspect --format '{{json .Provenance}}'`.
Checksums/release JSON/labels alone are reported metadata; the signed verified
subject and predicate comparison establish cryptographic binding.

Troubleshooting: missing OCI bundles means signing/referrer publication failed,
not permission to skip verification. Check packages-write, id-token-write,
attestations-write and GHCR repository association. Wrong signer/source means
reject the image. Unknown gh flags mean upgrade gh, never drop identity checks.
Scanner database/network errors fail closed; retry with current database.
An existing version tag after a partial promotion requires investigation/new
version, not --clobber. Registry tag absence checks distinguish explicit
manifest-not-found from network/auth errors. Inspect failed-validation-reports
for the precise compile, license, CVE or secret blocker.
