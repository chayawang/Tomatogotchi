#!/usr/bin/env python3
"""Exercise the real SwiftUI Window/contentSize scene with isolated fake data.

The window is hidden once its view is ready. Programmatic frame changes and
resize-event counts reproduce layout feedback; no mouse events are injected.
A PASS marker is required as well as a successful exit.
"""
import os
from pathlib import Path
import subprocess
import tempfile
import plistlib
import shutil
ROOT = Path(__file__).resolve().parent.parent
QA = Path(tempfile.mkdtemp(prefix='qa-window-motion-', dir=ROOT / '.build'))
env = {**os.environ, 'CLANG_MODULE_CACHE_PATH': str(ROOT / '.build/module-cache'),
       'SWIFT_MODULECACHE_PATH': str(ROOT / '.build/module-cache')}
binary_dir = Path(subprocess.check_output(['swift', 'build', '--configuration', 'release', '--show-bin-path', '--disable-sandbox'], cwd=ROOT, env=env, text=True).strip())
theme = (ROOT / 'Sources/Tomatogotchi/Theme.swift').read_text()
assert theme.count('return Bundle.module') == 1
theme = theme.replace('return Bundle.module', 'return Bundle(path: ProcessInfo.processInfo.environment["QA_RESOURCE_BUNDLE"]!)!')
(QA / 'Theme.swift').write_text(theme)
# accessibilityReduceMotion is read-only in the system EnvironmentValues.
# Build a QA-only copy with a writable QA EnvironmentKey, preserving the production Environment semantics.
# The source app and system preference stay unchanged; all other root/adapter code is exact.
desktop_source = (ROOT / 'Sources/Tomatogotchi/DesktopController.swift').read_text()
reduce_motion_input = r'@Environment(\.accessibilityReduceMotion) private var reduceMotion'
assert desktop_source.count(reduce_motion_input) == 1
(QA / 'DesktopController.swift').write_text(desktop_source.replace(reduce_motion_input, r'@Environment(\.qaReduceMotion) private var reduceMotion'))
objects = [str(p) for target in ['PetCore', 'CareCore', 'AdoptionFlow', 'CareFlow', 'DesktopCore'] for p in sorted((binary_dir / (target+'.build')).glob('*.o'))]
command = ['swiftc', '-parse-as-library', '-I', str(binary_dir), '-I', str(binary_dir/'Modules'), *objects,
           str(QA/'Theme.swift'), str(QA/'DesktopController.swift'), *[str(ROOT/'Sources/Tomatogotchi'/name) for name in ['ContentView.swift', 'PetDeviceView.swift']],
           str(ROOT/'scripts/WindowMotionChecks.swift'), '-o', str(QA/'motion-checks')]
subprocess.run(command, cwd=ROOT, env=env, check=True)
env['QA_MOTION_DIRECTORY'] = str(QA/'data')
env['QA_RESOURCE_BUNDLE'] = str(ROOT/'build/Tomatogotchi.app/Contents/Resources/Tomatogotchi_Tomatogotchi.bundle')
app = QA/'WindowMotion.app'
(app/'Contents/MacOS').mkdir(parents=True)
shutil.copy2(QA/'motion-checks', app/'Contents/MacOS/motion-checks')
(app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'work.shiroi.window-motion.'+QA.name,
    'CFBundleExecutable': 'motion-checks', 'CFBundleName': 'Window Motion QA', 'CFBundlePackageType': 'APPL',
    'NSPrincipalClass': 'NSApplication', 'NSHighResolutionCapable': True}))
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
result = subprocess.run([str(app/'Contents/MacOS/motion-checks')], cwd=ROOT, env=env, capture_output=True, text=True, timeout=15)
print(result.stdout, end=''); print(result.stderr, end='')
assert result.returncode == 0 and 'PASS WindowMotionChecks:' in result.stdout, 'Motion checks did not complete successfully' 
print(f'SwiftUI window motion files: {QA}')
