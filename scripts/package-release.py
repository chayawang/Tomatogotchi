#!/usr/bin/env python3
"""Build and package a clean committed development revision, with its user guide."""
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def run(*args, **kwargs):
    return subprocess.run(args, cwd=ROOT, check=True, **kwargs)


dirty = subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True)
if dirty.strip():
    raise SystemExit("Commit or resolve source changes before packaging; the source archive must match the built revision.")
revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
run("bash", "scripts/build-app.sh")
output = ROOT / "outputs"
output.mkdir(exist_ok=True)
app = ROOT / "build/Tomatogotchi.app"
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
if re.search(rb"/(?:Users|home)/[^/\x00\s]+/", (app / "Contents/MacOS/Tomatogotchi").read_bytes()):
    raise SystemExit("Public package must be built in a neutral temporary checkout, without a developer home path in the executable.")
architecture = subprocess.check_output(["lipo", "-archs", str(app / "Contents/MacOS/Tomatogotchi")], text=True).strip()
if architecture != "arm64":
    raise SystemExit(f"This development delivery currently supports arm64 only, got {architecture}.")
metadata = {"version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"],
            "gitCommit": revision, "architecture": architecture, "minimumMacOS": info["LSMinimumSystemVersion"],
            "signing": "ad-hoc", "notarized": False, "releaseChannel": "prerelease", "publicDistributionVerified": False}
with tempfile.TemporaryDirectory(prefix="package-", dir=ROOT / ".build") as temporary:
    staging = Path(temporary) / "contents"
    staging.mkdir()
    run("ditto", str(app), str(staging / "Tomatogotchi.app"))
    (staging / "使用說明.md").write_bytes((ROOT / "docs/user-guide.md").read_bytes())
    (staging / "驗證結果與限制.md").write_bytes((ROOT / "docs/releases" / ("v" + metadata["version"] + ".md")).read_bytes())
    for name in ["LICENSE", "SECURITY.md", "DISCLAIMER.zh-TW.md", "THIRD_PARTY_NOTICES.md"]:
        (staging / name).write_bytes((ROOT / name).read_bytes())
    licenses = staging / "THIRD_PARTY_LICENSES"
    licenses.mkdir()
    (licenses / "OFL.txt").write_bytes((ROOT / "Sources/Tomatogotchi/Resources/OFL.txt").read_bytes())
    (staging / "release-metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
    run("codesign", "--verify", "--deep", "--strict", str(staging / "Tomatogotchi.app"))
    package = Path(temporary) / "Tomatogotchi-macOS-arm64-dev.zip"
    run("ditto", "-c", "-k", "--norsrc", "--noextattr", str(staging), str(package))
    package.replace(output / package.name)
run("git", "archive", "--format=zip", "--prefix=Tomatogotchi/",
    "--output=" + str(output / "Tomatogotchi-source.zip"), revision)
(output / "release-metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
versioned_app = f"Tomatogotchi-v{metadata['version']}-macOS-arm64-dev.zip"
versioned_source = f"Tomatogotchi-v{metadata['version']}-source.zip"
shutil.copyfile(output / "Tomatogotchi-macOS-arm64-dev.zip", output / versioned_app)
shutil.copyfile(output / "Tomatogotchi-source.zip", output / versioned_source)
names = [versioned_app, versioned_source, "release-metadata.json"]
(output / "SHA256SUMS.txt").write_text("".join(
    f"{hashlib.sha256((output / name).read_bytes()).hexdigest()}  {name}\n" for name in names))
print(f"Packaged {metadata['version']} build {metadata['build']} from {revision}; development package only.")
