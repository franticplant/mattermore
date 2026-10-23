import datetime as dt
import json
from pathlib import Path
import subprocess
import tempfile
import unittest


class Gate(unittest.TestCase):
    def check_gate(self, report, exceptions):
        with tempfile.TemporaryDirectory() as tmp:
            report_path = Path(tmp) / "report.json"
            exception_path = Path(tmp) / "exceptions.json"
            report_path.write_text(json.dumps(report))
            exception_path.write_text(json.dumps(exceptions))
            return subprocess.run(["python3", "scripts/ci/security-gate.py", str(report_path),
                                   str(exception_path)], capture_output=True).returncode

    def test_clean(self):
        self.assertEqual(0, self.check_gate({"Results": []}, []))

    def test_critical(self):
        self.assertNotEqual(0, self.check_gate({"Results": [{"Vulnerabilities": [
            {"Severity": "CRITICAL", "VulnerabilityID": "CVE-test", "PkgName": "test"}]}]}, []))

    def test_secret(self):
        self.assertNotEqual(0, self.check_gate({"Results": [{"Target": "file", "Secrets": [
            {"RuleID": "test"}]}]}, []))

    def test_reviewed_exception(self):
        today = dt.date.today()
        report = {"Results": [{"Vulnerabilities": [
            {"Severity": "CRITICAL", "VulnerabilityID": "CVE-test", "PkgName": "test"}]}]}
        exception = {"id": "CVE-test", "package": "test", "reviewed": today.isoformat(),
                     "expires": (today + dt.timedelta(days=14)).isoformat(),
                     "owner": "security-team", "reason": "test fixture"}
        self.assertEqual(0, self.check_gate(report, [exception]))
        exception["expires"] = (today - dt.timedelta(days=1)).isoformat()
        self.assertNotEqual(0, self.check_gate(report, [exception]))


if __name__ == "__main__":
    unittest.main()
