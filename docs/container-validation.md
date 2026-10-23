# Validation evidence

This file records executed checks, not intended YAML behavior. It is updated
with actual run links/results during implementation. Production/candidate
publication requires separate owner authorization; none is implied by this PR.

Initial local checks:

* Fork API: Actions enabled, token defaults read-only; no configured environment
  or rulesets returned at initial audit. Owner then requested mandatory signing:
  active all-branch required-signatures ruleset 25726914 is now enforced with
  no bypass actors. Global and local Git defaults use franticplant and the
  registered SSH key; commit 490f650 was locally verified and GitHub reports
  `verified: true`, reason `valid`. The original unsigned implementation commit
  was replaced with the owner's authorization; it is not in the PR's history.
* Upstream tag identities resolved with git ls-remote; immutable commits recorded.
* skopeo inspected all selected base/tool/scanner image digests successfully.
* Team Edition manifest confirmed only linux/amd64 (plus unknown/unknown native
  attestation). Original mmctl extracted and identified as dynamically linked
  x86-64 ELF, concretely motivating its matching static source build.
* `python3 -m unittest discover -s tests/ci -v`: 4 tests passed (clean, critical,
  secret, reviewed/expired exception).
* gh 2.87.3 exposes OCI lookup and source/signer enforcement flags. This checks
  CLI capability only; no real image attestation has yet been verified.

## Executed GitHub runs

* [39964736765](https://github.com/franticplant/mattermore/actions/runs/39964736765):
  lint/ShellCheck/policy tests passed; family failed before compilation because
  readlink resolved an output beneath missing /out. Fixed with realpath -m.
* [39965427360](https://github.com/franticplant/mattermore/actions/runs/39965427360):
  lint passed; immutable server revision matched, all 13 patches applied and
  branding applied. Compilation rejected Go 1.26.8 because the pinned upstream
  server/public modules require 1.26.10. Updated toolchain image to 1.26.10 and
  resolved its immutable digest. This is not a compilation pass.
* The inherited attribution-string check was removed at the owner's request;
  signed-commit enforcement is separate and remains active.

Pending actual workflow execution: full compilation, five image
assemblies, restrictive runtime/e2e, image scans/license inventory, independent
server reproduction. Pending authorized release: GHCR upload, digest retrieval,
five provenance/SPDX attestations, fresh digest pull/runtime tests, compressed
size measurements and immutable version promotion. Rootless/SELinux host tests
and complete license/dependency coverage are not established by workflow syntax.
