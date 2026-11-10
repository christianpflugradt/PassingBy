"""Offline archive provenance and rejection tests; native validation runs separately."""
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location("artifacts", Path(__file__).with_name("release-artifacts.py"))
artifacts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(artifacts)


class ArtifactTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        env = dict(RELEASE_VERSION="1.2.3", GITHUB_SHA="a" * 40, GITHUB_RUN_ID="123", GITHUB_RUN_ATTEMPT="2")
        self.environment = patch.dict(os.environ, env)
        self.environment.start()
        self.addCleanup(self.environment.stop)
        checkout = patch.object(artifacts.subprocess, "check_output", return_value="a" * 40)
        checkout.start()
        self.addCleanup(checkout.stop)
        self.archive()

    def archive(self, extra=None, executable=True, version="1.2.3"):
        with zipfile.ZipFile(self.directory / "Passing-By-1.2.3.zip", "w") as archive:
            binary = zipfile.ZipInfo(artifacts.BINARY)
            binary.external_attr = (0o100755 if executable else 0o100644) << 16
            archive.writestr(binary, b"synthetic executable")
            archive.writestr(f"{artifacts.APP}/Contents/Info.plist", plistlib.dumps(dict(
                CFBundleIdentifier="local.passingby.app", CFBundleShortVersionString=version, CFBundleVersion=version)))
            if extra:
                archive.writestr(extra, b"unexpected")
        artifacts.record(self.directory)

    def test_valid_archive_reaches_native_verifier(self):
        with patch.object(artifacts.subprocess, "run") as verifier:
            artifacts.verify(self.directory)
        verifier.assert_called_once()
        self.assertTrue(verifier.call_args.kwargs["check"])
        self.assertTrue(verifier.call_args.args[0][0].endswith("Scripts/check-app-bundle.sh"))

    def test_source_version_and_workflow_attempt_are_bound(self):
        for key in ("source_sha", "version", "run_id", "run_attempt", "platform"):
            with self.subTest(key=key):
                artifacts.record(self.directory)
                path = self.directory / "metadata.json"
                data = json.loads(path.read_text())
                data[key] = "wrong"
                path.write_text(json.dumps(data))
                with self.assertRaisesRegex(ValueError, "mismatch"):
                    artifacts.verify(self.directory)

    def test_corrupt_archive_and_checksum_are_rejected(self):
        archive = self.directory / "Passing-By-1.2.3.zip"
        archive.write_bytes(archive.read_bytes() + b"corruption")
        with self.assertRaisesRegex(ValueError, "digest mismatch"):
            artifacts.verify(self.directory)
        self.archive()
        (self.directory / "SHA256SUMS").write_text("wrong")
        with self.assertRaisesRegex(ValueError, "checksum mismatch"):
            artifacts.verify(self.directory)

    def test_unsafe_members_nonexecutable_and_wrong_bundle_version_are_rejected(self):
        for extra in ("../escape", "/absolute", f"{artifacts.APP}/../escape", "other-app/file"):
            with self.subTest(extra=extra):
                self.archive(extra=extra)
                with self.assertRaisesRegex(ValueError, "Unsafe"):
                    artifacts.verify(self.directory)
        self.archive(executable=False)
        with self.assertRaisesRegex(ValueError, "nonexecutable"):
            artifacts.verify(self.directory)
        self.archive(version="9.9.9")
        with self.assertRaisesRegex(ValueError, "App identity or version mismatch"):
            artifacts.verify(self.directory)

    def test_binary_hash_and_complete_artifact_set_are_required(self):
        path = self.directory / "metadata.json"
        data = json.loads(path.read_text())
        data["binary_sha256"] = "0" * 64
        path.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, "Unverified"):
            artifacts.verify(self.directory)
        (self.directory / "extra.zip").write_bytes(b"unexpected")
        with self.assertRaisesRegex(ValueError, "exactly one"):
            artifacts.verify(self.directory)

    def test_native_verification_failure_is_not_ignored(self):
        with patch.object(artifacts.subprocess, "run", side_effect=artifacts.subprocess.CalledProcessError(1, "verifier")):
            with self.assertRaises(artifacts.subprocess.CalledProcessError):
                artifacts.verify(self.directory)
