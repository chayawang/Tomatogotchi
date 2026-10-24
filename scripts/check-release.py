#!/usr/bin/env python3
"""Verify a packaged development app in disposable, isolated data directories.

Never installs over a user's app, reads real pet data, or changes OS permissions.
Process restarts use SIGTERM; interactive Cmd-Q remains separate native QA.
"""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import time
import uuid
import zipfile

ROOT = Path(__file__).resolve().parent.parent
QA = Path(tempfile.mkdtemp(prefix="qa-release-", dir=ROOT / ".build"))
archive = ROOT / "outputs/Tomatogotchi-macOS-arm64-dev.zip"
expected = plistlib.loads((ROOT / "build/Tomatogotchi.app/Contents/Info.plist").read_bytes())
report = {"appVersion": expected["CFBundleShortVersionString"], "build": expected["CFBundleVersion"],
          "profiles": [], "nativeInteractionVerified": False, "publicDistributionVerified": False}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def snapshot(directory):
    # Desktop position/lease metadata may change. Pet and care data may not.
    # SIGTERM can interrupt an atomic desktop preference write before data is
    # written, leaving a zero-byte Foundation .dat.nosync* staging file. Record
    # those separately; any non-empty staging file still fails preservation.
    files = [p for p in directory.rglob("*") if p.is_file()]
    transient = [p for p in files if p.name.startswith(".dat.nosync") and p.stat().st_size == 0]
    report["emptyAtomicStagingFiles"] = sorted(set(report.get("emptyAtomicStagingFiles", []) + [str(p.relative_to(QA)) for p in transient]))
    return {str(p.relative_to(directory)): p.read_bytes() for p in files
            if p.name not in ("desktop.json", ".session.lock", ".pet.lock") and p not in transient}


def launch_and_stop(app, directory):
    env = {**os.environ, "TOMATOGOTCHI_DATA_DIR": str(directory)}
    # Do not inherit any opt-in probe from a developer's shell.
    env.pop("TOMATOGOTCHI_NOTIFICATION_PROBE", None)
    with (QA / "process.log").open("ab") as log:
        child = subprocess.Popen([str(app / "Contents/MacOS/Tomatogotchi")], env=env, stdout=log, stderr=log)
        try:
            deadline = time.monotonic() + 15
            while True:
                assert child.poll() is None, "Packaged app exited during startup"
                lease = directory / ".session.lock"
                if (directory / "desktop.json").exists() and lease.exists() and lease.read_text().strip() == str(child.pid):
                    break
                assert time.monotonic() < deadline, "Packaged app did not initialize"
                time.sleep(0.05)
            time.sleep(0.5)
            assert child.poll() is None, "Packaged app did not remain running"
        finally:
            if child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()


try:
    for line in (ROOT / "outputs/SHA256SUMS.txt").read_text().splitlines():
        checksum, name = line.split(maxsplit=1)
        path = (ROOT / "outputs" / name.strip()).resolve()
        assert path.parent == (ROOT / "outputs").resolve(), "Unexpected checksum path"
        assert digest(path) == checksum, f"Checksum mismatch: {path.name}"
    with zipfile.ZipFile(archive) as zipped:
        for name in zipped.namelist():
            assert not Path(name).is_absolute() and ".." not in Path(name).parts, "Unsafe archive path"
    first_location = QA / "解壓縮 測試"
    subprocess.run(["ditto", "-x", "-k", str(archive), str(first_location)], check=True)
    app = first_location / "Tomatogotchi.app"
    assert (first_location / "使用說明.md").read_bytes() == (ROOT / "docs/user-guide.md").read_bytes(), "Missing/stale packaged guide"
    assert (first_location / "驗證結果與限制.md").read_bytes() == (ROOT / "docs/releases" / ("v" + expected["CFBundleShortVersionString"] + ".md")).read_bytes(), "Missing/stale packaged validation notes"
    for name in ["LICENSE", "SECURITY.md", "DISCLAIMER.zh-TW.md", "THIRD_PARTY_NOTICES.md"]:
        assert (first_location / name).read_bytes() == (ROOT / name).read_bytes(), "Missing/stale bundled " + name
    assert (first_location / "THIRD_PARTY_LICENSES/OFL.txt").read_bytes() == (ROOT / "Sources/Tomatogotchi/Resources/OFL.txt").read_bytes()
    assert digest(archive) == digest(ROOT / ("outputs/Tomatogotchi-v" + expected["CFBundleShortVersionString"] + "-macOS-arm64-dev.zip"))
    with zipfile.ZipFile(ROOT / ("outputs/Tomatogotchi-v" + expected["CFBundleShortVersionString"] + "-source.zip")) as source_zip:
        for name in source_zip.namelist():
            assert not Path(name).is_absolute() and ".." not in Path(name).parts
            assert not any(part in [".git", "outputs", ".build", "pet-history"] for part in Path(name).parts)
        assert "Tomatogotchi/LICENSE" in source_zip.namelist()
    metadata = json.loads((first_location / "release-metadata.json").read_text())
    assert metadata["version"] == expected["CFBundleShortVersionString"] and metadata["build"] == expected["CFBundleVersion"]
    assert metadata["releaseChannel"] == "prerelease" and metadata["notarized"] is False and metadata["publicDistributionVerified"] is False
    assert metadata == json.loads((ROOT / "outputs/release-metadata.json").read_text())
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    for key in ("CFBundleIdentifier", "CFBundleVersion", "CFBundleShortVersionString", "LSMinimumSystemVersion"):
        assert info[key] == expected[key], f"Packaged metadata mismatch: {key}"
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    binary = app / "Contents/MacOS/Tomatogotchi"
    assert digest(binary) == digest(ROOT / "build/Tomatogotchi.app/Contents/MacOS/Tomatogotchi")
    assert not re.search(rb"/(?:Users|home)/[^/\x00\s]+/", binary.read_bytes()), "Developer home path in packaged executable"
    architecture = subprocess.check_output(["lipo", "-archs", str(binary)], text=True).strip()
    assert architecture == "arm64", f"Unexpected package architecture: {architecture}"
    resources = app / "Contents/Resources/Tomatogotchi_Tomatogotchi.bundle"
    for original in (ROOT / "Sources/Tomatogotchi/Resources").iterdir():
        if original.is_file():
            assert digest(resources / original.name) == digest(original), f"Missing/changed resource: {original.name}"
    report["architecture"] = architecture
    profiles = []
    for label, suffix, rests in [("v1-egg", "00", None), ("v2-cat-adult", "00", 12), ("v2-dinosaur-hatchling", "01", 3)]:
        directory = QA / "profiles" / label
        directory.mkdir(parents=True)
        pet_id = str(uuid.UUID("00000000-0000-0000-0000-0000000000" + suffix))
        pet = {"saveVersion": 1 if rests is None else 2, "id": pet_id, "name": "保留名字 QA",
               "lifeStage": "egg" if rests is None else "adult" if rests == 12 else "hatchling",
               "createdAt": 0, "updatedAt": 0}
        if rests is not None:
            pet["growth"] = {"species": "cat" if suffix == "00" else "dinosaur",
                             "completedRests": [f"qa-rest-{n}" for n in range(rests)], "neglectedSeconds": 0}
        care = {"version": 1, "phase": "paused", "remainingWork": 240, "workDuration": 300,
                "breakDuration": 300, "petID": pet_id}
        (directory / "pet.json").write_text(json.dumps(pet))
        (directory / "care.json").write_text(json.dumps(care))
        history = directory / "pet-history"
        history.mkdir()
        (history / "previous-pet.json").write_text(json.dumps(pet))
        profiles.append((label, directory, snapshot(directory)))
    # Current-format saves must retain already charged cells and the exact
    # demand receipt, including a departed pet. Startup must not replay losses.
    for label, departed in [("v3-pending-food", False), ("v3-departed-sadness", True)]:
        directory = QA / "profiles" / label
        directory.mkdir(parents=True)
        pet_id = "00000000-0000-0000-0000-000000000002"
        need_id = str(uuid.uuid4()).upper()
        growth = {"species": "cat", "completedRests": [f"qa-rest-{n}" for n in range(3)],
                  "neglectedSeconds": 0, "health": 5 if departed else 3, "mood": 0 if departed else 4,
                  "needs": {need_id: {"steps": 5 if departed else 2, "food": not departed, "responded": False}}}
        if departed:
            growth.update({"departedAt": 1000, "deathReason": "sadness"})
        pet = {"saveVersion": 3, "id": pet_id, "name": "新版生存 QA", "lifeStage": "departed" if departed else "hatchling",
               "createdAt": 0, "updatedAt": 1000, "growth": growth}
        care = {"version": 2, "phase": "paused", "remainingWork": 0, "workDuration": 300,
                "breakDuration": 300, "petID": pet_id, "demand": "walk" if departed else "food",
                "demandID": need_id, "demandElapsed": 900 if departed else 370}
        (directory / "pet.json").write_text(json.dumps(pet))
        (directory / "care.json").write_text(json.dumps(care))
        profiles.append((label, directory, snapshot(directory)))
    fresh = QA / "profiles" / "fresh"
    fresh.mkdir()
    profiles.append(("fresh", fresh, {}))
    for label, directory, before in profiles:
        launch_and_stop(app, directory)
        assert snapshot(directory) == before, f"First startup changed pet/care/history for {label}"
    # Move only the extracted test copy; production/output apps are untouched.
    relocated = QA / "安裝位置 含空格"
    relocated.mkdir()
    app = Path(shutil.move(str(app), str(relocated / "Tomatogotchi.app")))
    for label, directory, before in profiles:
        launch_and_stop(app, directory)
        assert snapshot(directory) == before, f"Relocated restart changed pet/care/history for {label}"
        report["profiles"].append({"name": label, "launch": True, "relocatedRestart": True,
                                   "petCareHistoryUnchanged": True})
    report["outcome"] = "passed"
    print("PASS ReleaseChecks: archive hashes, metadata, arm64, strict signature, all resources; fresh/v1/v2/v3 profiles survive unpacked launch and relocated restart without pet/care/history changes")
    print("Not verified: interactive quit, Finder/Gatekeeper install, actual OS motion setting/window lifecycle, Intel/macOS 13, Developer ID/notarization.")
except Exception as error:
    report["outcome"] = "failed"
    report["error"] = str(error)
    raise
finally:
    (QA / "release-report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2))
    print(f"Isolated release QA: {QA}")
