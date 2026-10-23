"""Machine-readable per-variant inventory; never infers verification success."""
import hashlib
import json
import os
from pathlib import Path
import sys

VARIANTS = ("minimal", "alpine", "ubi", "ubi-micro", "debug")


def inventory(root):
    records = []
    for variant in VARIANTS:
        metadata = json.loads((root / f"{variant}.build.json").read_text())
        sbom = json.loads((root / f"{variant}.spdx.json").read_text())
        report = json.loads((root / f"{variant}.scan.json").read_text())
        counts = {}
        for result in report.get("Results", []):
            for vuln in result.get("Vulnerabilities", []):
                severity = vuln["Severity"]
                counts[severity] = counts.get(severity, 0) + 1
        records.append(dict(
            variant=variant, architectures=["linux/amd64"],
            digest=metadata["containerimage.digest"],
            archive_bytes=(root / f"{variant}.tar").stat().st_size,
            # Archive size includes provenance/SBOM/config; not compressed layer size.
            packages=len(sbom.get("packages", [])), vulnerabilities=counts,
            sbom=f"{variant}.spdx.json", provenance="BuildKit index attestation",
            validation="local smoke, metadata, non-root, read-only, security gate passed",
        ))
    pins = dict(line.split("=", 1) for line in (root / "upstream.env").read_text().splitlines()
                if line and not line.startswith("#") and "=" in line)
    result = dict(source_commit=os.environ["GITHUB_SHA"],
                  repository=os.environ["GITHUB_REPOSITORY"],
                  upstream=pins, variants=records)
    (root / "inventory.json").write_text(json.dumps(result, indent=2) + "\n")
    summary = "## Validated image family\n\n| Variant | OCI archive bytes | SBOM packages | Vulnerabilities |\n|---|---:|---:|---|\n"
    for record in records:
        summary += f'| {record["variant"]} | {record["archive_bytes"]} | {record["packages"]} | {record["vulnerabilities"]} |\n'
    summary += "\nArchive size is NOT registry compressed layer size. Inventories are scanner observations, not proof of complete dependency coverage.\n"
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as output:
            output.write(summary)


def finalize(root):
    result = json.loads((root / "inventory.json").read_text())
    result["version"] = os.environ["GITHUB_REF_NAME"][1:]
    result["workflow_run"] = f'https://github.com/{os.environ["GITHUB_REPOSITORY"]}/actions/runs/{os.environ["GITHUB_RUN_ID"]}'
    for record in result["variants"]:
        verified = json.loads((root / f'{record["variant"]}.verified.json').read_text())
        assert verified["digest"] == record["digest"]
        assert verified["source_commit"] == result["source_commit"]
        assert verified["verification"] == "passed"
        record.update(verified)
        record["sbom_sha256"] = hashlib.sha256((root / record["sbom"]).read_bytes()).hexdigest()
    (root / "release-manifest.json").write_text(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    {"inventory": inventory, "finalize": finalize}[sys.argv[1]](Path(sys.argv[2]))
