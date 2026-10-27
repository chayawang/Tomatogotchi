#!/usr/bin/env python3
"""Verify real root/visible PetStage handshake from hidden first-care actions."""
from pathlib import Path
import os,plistlib,shutil,subprocess,tempfile
root=Path(__file__).resolve().parents[1]
qa=Path(tempfile.mkdtemp(prefix='qa-first-care-',dir=root/'.build'))
env={**os.environ,'CLANG_MODULE_CACHE_PATH':str(root/'.build/module-cache'),'SWIFT_MODULECACHE_PATH':str(root/'.build/module-cache')}
binary=Path(subprocess.check_output(['swift','build','--configuration','release','--show-bin-path','--disable-sandbox'],cwd=root,env=env,text=True).strip())
theme=(root/'Sources/Tomatogotchi/Theme.swift').read_text().replace('return Bundle.module','return Bundle(path: ProcessInfo.processInfo.environment["QA_RESOURCE_BUNDLE"]!)!')
(qa/'Theme.swift').write_text(theme)
objects=[str(p) for target in ['PetCore','CareCore','AdoptionFlow','CareFlow','DesktopCore'] for p in (binary/(target+'.build')).glob('*.o')]
sources=[str(root/'Sources/Tomatogotchi'/n) for n in ['DesktopController.swift','PetDeviceView.swift','ContentView.swift']]
subprocess.run(['swiftc','-parse-as-library','-I',str(binary),'-I',str(binary/'Modules'),*objects,str(qa/'Theme.swift'),*sources,str(root/'scripts/FirstCareHatchingChecks.swift'),'-o',str(qa/'first-care')],cwd=root,env=env,check=True)
app=qa/'FirstCare.app';(app/'Contents/MacOS').mkdir(parents=True)
shutil.copy2(qa/'first-care',app/'Contents/MacOS/first-care')
(app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'work.shiroi.first-care.'+qa.name,'CFBundleExecutable':'first-care','CFBundleName':'First Care QA','CFBundlePackageType':'APPL','NSPrincipalClass':'NSApplication'}))
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
for compact in ['0','1']:
 env.update(QA_HATCH_DIRECTORY=str(qa/('data-'+compact)),QA_HATCH_COMPACT=compact,QA_RESOURCE_BUNDLE=str(root/'build/Tomatogotchi.app/Contents/Resources/Tomatogotchi_Tomatogotchi.bundle'))
 result=subprocess.run([str(app/'Contents/MacOS/first-care')],cwd=root,env=env,text=True,capture_output=True,timeout=20)
 print(result.stdout,end='');print(result.stderr,end='')
 assert result.returncode==0 and 'PASS FirstCareHatchingChecks:' in result.stdout,'First-care presentation failed'
print('First-care QA files:',qa)
