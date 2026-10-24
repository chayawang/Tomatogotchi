#!/usr/bin/env python3
"""Render the real PetStage offscreen. Does not drive windows or user settings.

The temporary Theme copy only redirects Bundle.module to the packaged resources
and exposes its initial blink and synthetic Reduce Motion values. Timing and real OS settings remain separate QA.
"""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
QA = Path(tempfile.mkdtemp(prefix="qa-pet-render-", dir=ROOT / ".build"))
env = {**os.environ, "CLANG_MODULE_CACHE_PATH": str(ROOT / ".build/module-cache"),
       "SWIFT_MODULECACHE_PATH": str(ROOT / ".build/module-cache")}
binary_dir = Path(subprocess.check_output(
    ["swift", "build", "--configuration", "release", "--show-bin-path", "--disable-sandbox"],
    cwd=ROOT, env=env, text=True).strip())
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--theme-source", type=Path, default=ROOT / "Sources/Tomatogotchi/Theme.swift",
                    help="Optional previous Theme source for regression reproduction")
theme = parser.parse_args().theme_source.read_text()
assert theme.count("return Bundle.module") == 1
assert theme.count("@State private var blinking = false") == 1
theme = theme.replace("return Bundle.module", 'return Bundle(path: ProcessInfo.processInfo.environment["QA_RESOURCE_BUNDLE"]!)!')
theme = theme.replace("@State private var blinking = false", "@State var blinking = false")
reduce_field = r"@Environment(\.accessibilityReduceMotion) private var reduceMotion"
assert theme.count(reduce_field) == 1
# Apple's preference environment key is read-only; do not change the user's OS setting.
theme = theme.replace(reduce_field, "var reduceMotion = false")
(QA / "Theme.swift").write_text(theme)
command = ["swiftc", "-parse-as-library", "-I", str(binary_dir), "-I", str(binary_dir / "Modules"),
           *map(str, sorted((binary_dir / "PetCore.build").glob("*.o"))),
           str(QA / "Theme.swift"), str(ROOT / "scripts/PetRenderChecks.swift"),
           "-o", str(QA / "render-checks")]
subprocess.run(command, cwd=ROOT, env=env, check=True)
env["QA_RESOURCE_BUNDLE"] = str(ROOT / "build/Tomatogotchi.app/Contents/Resources/Tomatogotchi_Tomatogotchi.bundle")
subprocess.run([str(QA / "render-checks"), str(QA)], env=env, check=True)
print(f"Offscreen renders: {QA}")
