#!/usr/bin/env python3
"""Exercise real SwiftUI playback using synthetic inputs and isolated QA only."""
from pathlib import Path
import os, plistlib, shutil, subprocess, tempfile
root=Path(__file__).resolve().parents[1]
qa=Path(tempfile.mkdtemp(prefix='qa-live-presentation-',dir=root/'.build'))
env={**os.environ,'CLANG_MODULE_CACHE_PATH':str(root/'.build/module-cache'),'SWIFT_MODULECACHE_PATH':str(root/'.build/module-cache')}
bin=Path(subprocess.check_output(['swift','build','--configuration','release','--show-bin-path','--disable-sandbox'],cwd=root,env=env,text=True).strip())
s=(root/'Sources/Tomatogotchi/Theme.swift').read_text()
s=s.replace('return Bundle.module','return Bundle(path: ProcessInfo.processInfo.environment["QA_RESOURCE_BUNDLE"]!)!')
s=s.replace(r'@Environment(\.accessibilityReduceMotion) private var reduceMotion','var reduceMotion = false')
(qa/'Theme.swift').write_text(s)
cmd=['swiftc','-parse-as-library','-I',str(bin),'-I',str(bin/'Modules'),*map(str,(bin/'PetCore.build').glob('*.o')),str(qa/'Theme.swift'),str(root/'scripts/LivePresentationChecks.swift'),'-o',str(qa/'live-checks')]
subprocess.run(cmd,cwd=root,env=env,check=True)
app=qa/'LivePresentation.app';(app/'Contents/MacOS').mkdir(parents=True)
shutil.copy2(qa/'live-checks',app/'Contents/MacOS/live-checks')
(app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'work.shiroi.live.'+qa.name,'CFBundleExecutable':'live-checks','CFBundleName':'Live QA','CFBundlePackageType':'APPL','NSPrincipalClass':'NSApplication','NSHighResolutionCapable':True}))
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
env.update(QA_LIVE_OUTPUT=str(qa),QA_APP_PATH=str(root/'build/Tomatogotchi.app'),QA_RESOURCE_BUNDLE=str(root/'build/Tomatogotchi.app/Contents/Resources/Tomatogotchi_Tomatogotchi.bundle'))
r=subprocess.run([str(app/'Contents/MacOS/live-checks')],cwd=root,env=env,capture_output=True,text=True,timeout=25)
print(r.stdout,end='');print(r.stderr,end='')
assert r.returncode==0 and 'PASS LivePresentationChecks:' in r.stdout,'Live task checks did not pass'
print('Live QA output:',qa)
