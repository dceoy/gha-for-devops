"""Local, offline regression tests for OSV auto-remediation."""

import contextlib
import json
import os
import runpy
import subprocess
import tempfile
import unittest
from pathlib import Path

HELPER = Path(__file__).resolve().parents[1] / "scripts" / "osv-remediate.py"
FUNCTIONS = runpy.run_path(str(HELPER))


class RemediationTests(unittest.TestCase):
    def test_pnpm_lock_versions_and_major_guard(self):
        with tempfile.TemporaryDirectory() as directory:
            lock = Path(directory) / "pnpm-lock.yaml"
            lock.write_text("packages:\n\n  '@example/foo@1.2.3':\n  'bar@3.4.5':\n")
            self.assertEqual(FUNCTIONS["versions"](lock)["@example/foo"], {(1, 2, 3)})
            self.assertTrue(
                FUNCTIONS["safe_upgrade"]({"foo": {(1, 2, 3)}}, {"foo": {(1, 2, 4)}})
            )
            self.assertFalse(
                FUNCTIONS["safe_upgrade"]({"foo": {(1, 2, 3)}}, {"foo": {(2, 0, 0)}})
            )

    def test_uv_update_and_major_rollback(self):
        for update, expected in (("1.2.4", "1.2.4"), ("2.0.0", "1.2.3")):
            with self.subTest(update=update), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                subprocess.run(["git", "init", "-q"], cwd=root, check=True)
                lock = root / "uv.lock"
                original = 'version = 1\n[[package]]\nname = "foo"\nversion = "1.2.3"\n'
                lock.write_text(original)
                subprocess.run(["git", "add", "uv.lock"], cwd=root, check=True)
                subprocess.run(
                    ["git", "-c", "user.name=Test", "-c", "user.email=test@example.com",
                     "commit", "-qm", "initial"],
                    cwd=root,
                    check=True,
                )
                bin_dir = root / "bin"
                bin_dir.mkdir()
                fake_uv = bin_dir / "uv"
                fake_uv.write_text(
                    "#!/bin/sh\ncat > uv.lock <<'EOF'\n"
                    f'version = 1\n[[package]]\nname = "foo"\nversion = "{update}"\n'
                    "EOF\n"
                )
                fake_uv.chmod(0o755)
                report = root / "scan.json"
                report.write_text(json.dumps({
                    "results": [{
                        "source": {"path": str(lock)},
                        "packages": [{
                            "package": {"name": "foo", "ecosystem": "PyPI"},
                            "vulnerabilities": [{"id": "GHSA-test"}],
                        }],
                    }],
                }))
                old_path = os.environ["PATH"]
                try:
                    os.environ["PATH"] = str(bin_dir) + os.pathsep + old_path
                    with contextlib.chdir(root):
                        FUNCTIONS["main"](report)
                finally:
                    os.environ["PATH"] = old_path
                self.assertIn(f'version = "{expected}"', lock.read_text())


if __name__ == "__main__":
    unittest.main()
