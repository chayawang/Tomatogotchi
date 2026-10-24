#!/usr/bin/env python3
"""Process-level QA of the built app. No UI control or production pet data."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "build/Tomatogotchi.app/Contents/MacOS/Tomatogotchi"
QA = Path(tempfile.mkdtemp(prefix="qa-app-session-", dir=ROOT / ".build"))
pet_id = str(uuid.uuid4())
pet = {"saveVersion": 1, "id": pet_id, "name": "QA", "lifeStage": "egg",
       "createdAt": 0, "updatedAt": 0}
care = {"version": 1, "phase": "paused", "remainingWork": 900,
        "workDuration": 1500, "breakDuration": 300, "petID": pet_id}
(QA / "pet.json").write_text(json.dumps(pet))
(QA / "care.json").write_text(json.dumps(care))
original = {name: (QA / name).read_bytes() for name in ("pet.json", "care.json")}
env = {**os.environ, "TOMATOGOTCHI_DATA_DIR": str(QA)}
children = []
try:
    with (QA / "process.log").open("wb") as log:
        first = subprocess.Popen([str(APP)], env=env, stdout=log, stderr=log)
        children.append(first)
        deadline = time.monotonic() + 15
        while not (QA / "desktop.json").exists():
            assert first.poll() is None, "Primary exited before showing its window"
            assert time.monotonic() < deadline, "Primary did not initialize its desktop preferences"
            time.sleep(0.05)
        assert int((QA / ".session.lock").read_text()) == first.pid
        second = subprocess.Popen([str(APP)], env=env, stdout=log, stderr=log)
        children.append(second)
        assert second.wait(timeout=10) == 0, "Secondary did not exit cleanly"
        assert first.poll() is None, "Secondary launch terminated primary"
        assert int((QA / ".session.lock").read_text()) == first.pid, "Secondary replaced ownership"
        for name, data in original.items():
            assert (QA / name).read_bytes() == data, f"Secondary launch changed {name}"
    print("PASS AppSession process QA: built app owner survives duplicate; secondary exits; pet/timer bytes unchanged")
    print(f"Isolated QA files and log: {QA}")
    print("Window visibility, focus, notification delivery and OS lock events are not validated by this check.")
finally:
    for child in children:
        if child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
