"""Offline tests for the shell formatting rule: verdicts and exit codes in temporary Git repositories."""

from pathlib import Path
import os
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("check.sh")
FORMATTED = "#!/bin/sh\nif true; then\n  echo ok\nfi\n"
UNFORMATTED = "#!/bin/sh\nif true; then\necho ok\n      fi\n"


class FormatShellTests(unittest.TestCase):
    def run_check(self, files, path=None):
        with tempfile.TemporaryDirectory(prefix="format-shell-") as temporary:
            repo = Path(temporary)
            subprocess.run(["git", "init", "--quiet"], cwd=repo, check=True)
            (repo / ".editorconfig").write_text("root = true\n[*]\nindent_style = space\nindent_size = 2\n")
            for name, text in files.items():
                (repo / name).write_text(text)
            subprocess.run(["git", "add", "."], cwd=repo, check=True)
            env = dict(os.environ, PATH=path) if path else None
            return subprocess.run(["sh", str(SCRIPT)], cwd=repo, env=env, capture_output=True, text=True)

    def test_verdicts(self):
        self.assertEqual(self.run_check({}).returncode, 0)
        self.assertEqual(self.run_check({"a.sh": FORMATTED}).returncode, 0)
        self.assertEqual(self.run_check({"a.sh": UNFORMATTED}).returncode, 1)

    def test_zsh_scripts_are_skipped(self):
        self.assertEqual(self.run_check({"z.sh": "#!/bin/zsh\n" + UNFORMATTED[10:]}).returncode, 0)

    def test_syntax_errors_and_missing_tool_are_errors(self):
        self.assertEqual(self.run_check({"a.sh": "#!/bin/sh\nif [\n"}).returncode, 2)
        self.assertEqual(self.run_check({"a.sh": FORMATTED}, path="/usr/bin:/bin").returncode, 2)


if __name__ == "__main__":
    unittest.main()
