# Repository identity and release safety

Before creating ANY commit or tag, inspect `git var GIT_AUTHOR_IDENT`,
`git var GIT_COMMITTER_IDENT`, and the effective signing configuration.

* Author/committer for this owner's work: `franticplant
  <100934153+franticplant@users.noreply.github.com>`.
* Sign every commit and annotated tag with the owner's registered SSH signing
  key. Expected public key: `.github/signing/allowed_signers`; fingerprint:
  `SHA256:LX88N4eVrt68HbjW1CGuMPQRUdFrwU56sIJQgrQ8hTM`.
* Set repository-local `user.name`, `user.email`, `gpg.format=ssh`,
  `user.signingkey` (the available owner key), `commit.gpgsign=true`, and
  `tag.gpgsign=true`. A loaded authorized agent key or signing device is needed.
* Never fall back to a machine account, unsigned commit, generated substitute
  key, or `--no-gpg-sign`. If the authorized key is unavailable, stop before
  committing and tell the owner. Never read, copy or upload private keys.
* Verify each signature before push:
  `git -c gpg.ssh.allowedSignersFile=.github/signing/allowed_signers verify-commit HEAD`.
  Verify tags with the equivalent `verify-tag`. Confirm GitHub reports verified
  after push. Do not claim signing merely because Git configuration enables it.
* Do not rewrite someone else's commits. Correcting this agent's own published
  commits requires owner authorization and `--force-with-lease`, never `--force`.
* Do not merge, create release tags, or publish candidate/production images
  without explicit owner authorization. Opening a draft PR is not a release.
* Do not weaken tests, permissions, signature rules or release safeguards to
  obtain a green run. Record actual evidence in docs/container-validation.md.

Keep build data on disk, not RAM-backed `/tmp`, on this owner's workstation.
