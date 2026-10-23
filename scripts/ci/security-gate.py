"""Gate critical vulnerabilities and all detected secrets; audit licenses.

Exceptions are exact package/CVE matches with owner/reason/expiry, <=90 days
from review. Expired/invalid exceptions fail even if a scanner no longer finds
the vulnerability. No exception is currently provided.
"""
import datetime as dt
import json
import os
import sys

report = json.load(open(sys.argv[1]))
exceptions = json.load(open(sys.argv[2]))
today = dt.date.today()
allowed = set()
for item in exceptions:
    reviewed = dt.date.fromisoformat(item["reviewed"])
    expires = dt.date.fromisoformat(item["expires"])
    assert reviewed <= today <= expires, "invalid/expired security exception"
    assert 0 < (expires - reviewed).days <= 90, "exception exceeds 90 days"
    assert item["reason"] and item["owner"]
    allowed.add((item["id"], item["package"]))
blocked, counts, licenses = [], {}, set()
for result in report.get("Results", []):
    for vuln in result.get("Vulnerabilities", []):
        severity = vuln["Severity"]
        counts[severity] = counts.get(severity, 0) + 1
        if severity == "CRITICAL" and (vuln["VulnerabilityID"], vuln["PkgName"]) not in allowed:
            blocked.append(f'{vuln["VulnerabilityID"]}: {vuln["PkgName"]}')
    for secret in result.get("Secrets", []):
        # Never print secret match contents to logs or summaries.
        blocked.append(f'secret rule {secret["RuleID"]} in {result["Target"]}')
    for license_item in result.get("Licenses", []):
        licenses.add(license_item.get("Name", "unknown"))
summary = f"### {os.path.basename(sys.argv[1])}\nVulnerabilities: {counts}\n\nLicenses: {sorted(licenses)}\n\nBlocking findings: {blocked}\n"
print(summary)
if os.environ.get("GITHUB_STEP_SUMMARY"):
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as output:
        output.write(summary)
sys.exit(bool(blocked))
