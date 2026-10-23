#!/usr/bin/env bash
set -euo pipefail
variant="${1:?variant}"
syft=docker.io/anchore/syft:v1.42.3@sha256:5999d209a342e55e9edf70bf8930fb5b86d8f2a783fa401178372c50e21b1d36
trivy=docker.io/aquasec/trivy:0.69.3@sha256:bcc376de8d77cfe086a917230e818dc9f8528e3c852f7b1aff648949b6258d1c
mkdir -p out/scanner-cache
# Archive access, never the engine socket. Syft's image scan includes binary
# modules and OS packages; shipped lockfiles supplement bundled JS visibility.
docker run --rm -v "$PWD/out:/scan:rw" "$syft" "oci-archive:/scan/$variant.tar" \
    -o "spdx-json=/scan/$variant.spdx.json"
docker run --rm -v "$PWD/out:/scan:rw" "$trivy" image --input "/scan/$variant.tar" \
    --cache-dir /scan/scanner-cache --scanners vuln,secret,license --license-full --redact 100 \
    --format json --output "/scan/$variant.scan.json" --exit-code 0
# Scanner errors above fail closed. Severity/exception policy is evaluated from
# the complete machine-readable report, never by ignoring scanner exit errors.
python3 scripts/ci/security-gate.py "out/$variant.scan.json" security/exceptions.json
rm -r out/scanner-cache
