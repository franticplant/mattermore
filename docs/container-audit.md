# Container pipeline audit (2026-10-23)

Baseline: fork main, before `ci/verified-container-family` changes.

* `upstream.env` selected Mattermost v12.0.1 and Calls v1.12.6 by mutable
  tags only. Transcriber master is separate and not included in this image.
* Scripts clone tags, apply the numbered server/Calls patches, apply branding,
  create upstream Go workspaces, and invoke upstream Go/npm/make builds.
* Server compilation did not disable CGO, strip paths or fix build IDs. Webapp
  uses npm ci and upstream webpack. Calls uses upstream `make dist`, then
  changes the manifest version to 1000.12.6 and repacks it. Its standalone
  dependencies were installed by mutable `npm install` through make.
* Containerfile inherited the official Team Edition image, merged patched web
  assets and configuration, replaced the server, added Calls, and retained
  upstream mmctl, notices, runtime libraries and other bundled plugins.
  All base tags were mutable; the source label named a different repository.
* build-image.sh already selects Podman or Docker, with an explicit engine
  override. Inputs were built in a host directory and copied into the context.
* Calls upstream Makefile supports linux/amd64 and linux/arm64 (also BSD), but
  Team Edition 12.0.1 index contains ONLY linux/amd64 plus an attestation.
  Its AMD64 manifest is b0fdecf049bbb5d224d719bade7f438261b27e7061205f904bcc9e4f2f36eb70.
  Inherited mmctl and other bundled plugins cannot be relabeled ARM64. All five
  runtime variants are therefore AMD64-only pending a separately tested ARM
  build of the complete inherited payload. This is not a Calls Go blocker.
* Old PR CI checked patches, compiled server/Calls separately, then repeated
  both builds for e2e. e2e creates 255 users and checks patched Calls activation.
* Old release accepted v* and arbitrary dispatch, pushed a moving tag and
  latest without smoke tests, digest checks, scans, SBOM or attestations. It
  granted contents/packages write workflow-wide and used mutable action tags.
* Fork Actions API: enabled, allowed_actions=all, SHA pinning not enforced;
  default token read, PR approval disabled. No environments or rulesets were
  returned at initial audit. Subsequently, at the owner's explicit request,
  active all-branch required-signatures ruleset 25726914 was created with no
  bypass actors. No existing security setting was weakened.

## Actual references inspected

* franticplant/tailmesh-android release.yml: SHA-pinned actions, protected
  environment, signed provenance/SPDX, checksums, verified artifact handoff,
  separate reproduction, and refusal to modify published releases. Reproduction
  is advisory in that repository; APK signing is not applicable here.
* franticplant/wg-gateway release.yml: Buildx runtime target matrix, dual-arch
  OCI indexes, metadata, max BuildKit provenance, native SBOM and GitHub digest
  attestation. Its workflow uses mutable action tags and broad permissions;
  those are not copied.
* crazy-taksi/grande-taksi build.yml, cd.yml, service-delivery.yml: branch
  checks, explicit dry-run/write separation, serialized delivery, registry
  digest resolution before GitOps updates, distinction between desired state
  and runtime health. Deployment machinery is not needed here.
* grande-taksi-website build-release.yaml/deploy.yaml: archive release and
  Pages separation, but mutable actions and no comparable image attestation.
* crazy-taksi/grande-taksi-deploy workflow listing: HTTP 404 with current
  credentials. Its contents were not inferred from the calling repository.

Principal gaps: immutable inputs, precise permissions, all-runtime testing,
honest architecture support, verified per-image attestations, final-image
inventory/scans, release integrity, reproduction evidence, and owner-enforced
tag/environment/package safeguards.
