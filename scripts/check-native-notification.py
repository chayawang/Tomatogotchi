#!/usr/bin/env python3
"""Inspect real macOS notification delivery using an isolated app data folder.
Does not request/change authorization, click notifications, or control desktop UI.
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

root = Path(__file__).resolve().parent.parent
qa = Path(tempfile.mkdtemp(prefix="qa-native-notification-", dir=root / ".build"))
app = root / "build/Tomatogotchi.app/Contents/MacOS/Tomatogotchi"
env = {**os.environ, "TOMATOGOTCHI_DATA_DIR": str(qa), "TOMATOGOTCHI_NOTIFICATION_PROBE": "1"}
with (qa / "process.log").open("wb") as log:
    process = subprocess.Popen([str(app)], env=env, stdout=log, stderr=log)
    try:
        report_file = qa / "notification-probe.json"
        deadline = time.monotonic() + 25
        while not report_file.exists():
            assert process.poll() is None, "Probe App exited before reporting"
            assert time.monotonic() < deadline, "Native notification probe timed out"
            time.sleep(0.05)
        report = json.loads(report_file.read_text())
        print(json.dumps(report, ensure_ascii=False, indent=2))
        print(f"Isolated report: {report_file}")
        if report["outcome"] == "delivered":
            print("OBSERVED: real macOS notification center recorded this probe as delivered.")
        elif report["outcome"] == "blocked-existing-permission":
            print("BLOCKED: existing notification authorization does not allow delivery; no permission prompt was requested.")
        else:
            raise RuntimeError(f"Native delivery not verified: {report['outcome']}")
        print("Banner visibility, click routing and actual sleep/lock events remain unverified.")
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
