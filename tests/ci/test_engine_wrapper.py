from pathlib import Path
import os
import re
import subprocess
import tempfile
import unittest


class EngineWrapper(unittest.TestCase):
    def test_wrapper_invokes_executable_not_itself(self):
        script = Path("scripts/e2e.sh").read_text()
        wrapper = re.search(r"^docker\(\) \{.*\}$", script, re.MULTILINE).group()
        with tempfile.TemporaryDirectory() as tmp:
            executable = Path(tmp) / "docker"
            executable.write_text('#!/bin/sh\nprintf "external-engine:%s\\n" "$1"\n')
            executable.chmod(0o755)
            environment = dict(os.environ, PATH=tmp + ":" + os.environ["PATH"], FUNCNEST="10")
            result = subprocess.run(["bash", "-c", 'engine=docker; ' + wrapper + '; docker version'],
                                    env=environment, capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "external-engine:version")


if __name__ == "__main__":
    unittest.main()
