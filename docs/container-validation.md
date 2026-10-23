# Validation evidence

This file records executed checks, not intended YAML behavior. It is updated
with actual run links/results during implementation. Production/candidate
publication requires separate owner authorization; none is implied by this PR.

Initial local checks:

* Fork API: Actions enabled, token defaults read-only; no configured environment
  or rulesets returned. No repository settings changed.
* Upstream tag identities resolved with git ls-remote; immutable commits recorded.
* skopeo inspected all selected base/tool/scanner image digests successfully.
* Team Edition manifest confirmed only linux/amd64 (plus unknown/unknown native
  attestation). Original mmctl extracted and identified as dynamically linked
  x86-64 ELF, concretely motivating its matching static source build.
* `python3 -m unittest discover -s tests/ci -v`: 4 tests passed (clean, critical,
  secret, reviewed/expired exception).
* gh 2.87.3 exposes OCI lookup and source/signer enforcement flags. This checks
  CLI capability only; no real image attestation has yet been verified.

Pending actual workflow execution: full compilation/patches, five image
assemblies, restrictive runtime/e2e, image scans/license inventory, independent
server reproduction. Pending authorized release: GHCR upload, digest retrieval,
five provenance/SPDX attestations, fresh digest pull/runtime tests, compressed
size measurements and immutable version promotion. Rootless/SELinux host tests
and complete license/dependency coverage are not established by workflow syntax.
