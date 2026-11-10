"""Bind the macOS release ZIP to its verified source and workflow attempt."""
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import stat
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
APP = "Passing By.app"
BINARY = f"{APP}/Contents/MacOS/PassingBy"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def identity():
    version = os.environ.get("RELEASE_VERSION", "")
    if not re.fullmatch(r"[1-9][0-9]*\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", version):
        raise ValueError("RELEASE_VERSION must be an exact stable version")
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    if os.environ.get("GITHUB_SHA", head) != head:
        raise ValueError("Checkout does not match the dispatched source")
    return dict(schema_version=1, version=version, source_sha=head,
                run_id=os.environ.get("GITHUB_RUN_ID", "local"),
                run_attempt=os.environ.get("GITHUB_RUN_ATTEMPT", "local"), platform="macos")


def record(directory):
    expected = identity()
    name = f"Passing-By-{expected['version']}.zip"
    archive = directory / name
    data = archive.read_bytes()
    with zipfile.ZipFile(archive) as zipped:
        binary_hash = digest(zipped.read(BINARY))
    expected.update(archive=name, sha256=digest(data), binary_sha256=binary_hash)
    (directory / "metadata.json").write_text(json.dumps(expected, indent=2) + "\n")
    (directory / "SHA256SUMS").write_text(f"{digest(data)}  {name}\n")


def verify(directory):
    expected = identity()
    name = f"Passing-By-{expected['version']}.zip"
    if directory.is_symlink() or not directory.is_dir():
        raise ValueError("Missing or unsafe dist directory")
    if {p.name for p in directory.iterdir()} != {name, "metadata.json", "SHA256SUMS"}:
        raise ValueError("Expected exactly one archive, metadata and checksum file")
    if any(not p.is_file() or p.is_symlink() for p in directory.iterdir()):
        raise ValueError("Release artifacts must be regular files")
    metadata = json.loads((directory / "metadata.json").read_text())
    if not isinstance(metadata, dict) or set(metadata) != set(expected) | {"archive", "sha256", "binary_sha256"}:
        raise ValueError("Invalid release metadata")
    if any(metadata.get(key) != value for key, value in expected.items()):
        raise ValueError("Release source, version, platform or workflow attempt mismatch")
    data = (directory / name).read_bytes()
    if metadata["archive"] != name or metadata["sha256"] != digest(data):
        raise ValueError("Archive digest mismatch")
    if (directory / "SHA256SUMS").read_text() != f"{digest(data)}  {name}\n":
        raise ValueError("Archive checksum mismatch")
    with zipfile.ZipFile(directory / name) as zipped, tempfile.TemporaryDirectory() as temporary:
        entries = zipped.infolist()
        if len(entries) != len({item.filename for item in entries}):
            raise ValueError("Duplicate archive members")
        if sum(item.file_size for item in entries) > 512 * 1024 * 1024:
            raise ValueError("Archive exceeds the app size limit")
        for item in entries:
            path = PurePosixPath(item.filename)
            if (path.is_absolute() or ".." in path.parts or not path.parts or path.parts[0] != APP
                    or "\\" in item.filename or stat.S_ISLNK(item.external_attr >> 16)):
                raise ValueError("Unsafe archive member")
        if zipped.testzip() is not None:
            raise ValueError("Corrupt archive member")
        binary = zipped.getinfo(BINARY)
        if not binary.external_attr >> 16 & 0o111 or digest(zipped.read(BINARY)) != metadata["binary_sha256"]:
            raise ValueError("Unverified or nonexecutable app binary")
        plist = plistlib.loads(zipped.read(f"{APP}/Contents/Info.plist"))
        if (plist.get("CFBundleIdentifier") != "local.passingby.app"
                or plist.get("CFBundleShortVersionString") != expected["version"]
                or plist.get("CFBundleVersion") != expected["version"]):
            raise ValueError("App identity or version mismatch")
        zipped.extractall(temporary)
        for item in entries:
            if not item.is_dir():
                (Path(temporary) / item.filename).chmod(stat.S_IMODE(item.external_attr >> 16) & 0o777)
        subprocess.run([str(ROOT / "Scripts/check-app-bundle.sh"), str(Path(temporary) / APP)], check=True)
    print(f"Verified {name}: source, workflow attempt, checksums and signed app bundle")


if __name__ == "__main__":
    try:
        if sys.argv[1:] == ["record"]:
            record(ROOT / "dist")
        elif sys.argv[1:] == ["verify"]:
            verify(ROOT / "dist")
        else:
            raise ValueError("Usage: release-artifacts.py record|verify")
    except (OSError, ValueError, KeyError, zipfile.BadZipFile, subprocess.SubprocessError) as error:
        sys.exit(f"Release artifact verification failed: {error}")
