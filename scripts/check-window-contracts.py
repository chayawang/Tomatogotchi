#!/usr/bin/env python3
"""Compile the real DesktopController into an offscreen native contract check.

Only its test NSWindow is created; it is never shown or activated. This is not
native UI automation and cannot replace mouse/keyboard or actual OS-event QA.
"""
import os
from pathlib import Path
import subprocess
import tempfile
ROOT = Path(__file__).resolve().parent.parent
QA = Path(tempfile.mkdtemp(prefix='qa-window-contracts-', dir=ROOT / '.build'))
env = {**os.environ, 'CLANG_MODULE_CACHE_PATH': str(ROOT / '.build/module-cache'),
       'SWIFT_MODULECACHE_PATH': str(ROOT / '.build/module-cache')}
binary_dir = Path(subprocess.check_output(['swift', 'build', '--configuration', 'release', '--show-bin-path', '--disable-sandbox'], cwd=ROOT, env=env, text=True).strip())
theme = (ROOT / 'Sources/Tomatogotchi/Theme.swift').read_text()
assert theme.count('return Bundle.module') == 1
theme = theme.replace('return Bundle.module', 'return Bundle(path: ProcessInfo.processInfo.environment["QA_RESOURCE_BUNDLE"]!)!')
(QA / 'Theme.swift').write_text(theme)
objects = [str(p) for target in ['PetCore', 'CareCore', 'AdoptionFlow', 'CareFlow', 'DesktopCore'] for p in sorted((binary_dir / (target+'.build')).glob('*.o'))]
command = ['swiftc', '-parse-as-library', '-I', str(binary_dir), '-I', str(binary_dir/'Modules'), *objects,
           str(QA/'Theme.swift'), *[str(ROOT/'Sources/Tomatogotchi'/name) for name in ['ContentView.swift', 'DesktopController.swift', 'PetDeviceView.swift']],
           str(ROOT/'scripts/WindowContractChecks.swift'), '-o', str(QA/'window-checks')]
subprocess.run(command, cwd=ROOT, env=env, check=True)
env['QA_RESOURCE_BUNDLE'] = str(ROOT/'build/Tomatogotchi.app/Contents/Resources/Tomatogotchi_Tomatogotchi.bundle')
subprocess.run([str(QA/'window-checks'), str(QA/'data')], cwd=ROOT, env=env, check=True)
print(f'Offscreen window contract files: {QA}')
