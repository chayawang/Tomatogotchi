#!/usr/bin/env python3
"""Exercise isolated adoption state transitions and render the real device form."""
from pathlib import Path
import os,plistlib,shutil,subprocess,tempfile
root=Path(__file__).resolve().parents[1]
qa=Path(tempfile.mkdtemp(prefix='qa-adoption-',dir=root/'.build'))
env={**os.environ,'CLANG_MODULE_CACHE_PATH':str(root/'.build/module-cache'),'SWIFT_MODULECACHE_PATH':str(root/'.build/module-cache')}
binary=Path(subprocess.check_output(['swift','build','--configuration','release','--show-bin-path','--disable-sandbox'],cwd=root,env=env,text=True).strip())
theme=(root/'Sources/Tomatogotchi/Theme.swift').read_text().replace('return Bundle.module','return Bundle(path: ProcessInfo.processInfo.environment["QA_RESOURCE_BUNDLE"]!)!')
(qa/'Theme.swift').write_text(theme)
objects=[str(p) for target in ['PetCore','CareCore','AdoptionFlow','CareFlow','DesktopCore'] for p in (binary/(target+'.build')).glob('*.o')]
sources=[str(root/'Sources/Tomatogotchi'/n) for n in ['DesktopController.swift','PetDeviceView.swift','ContentView.swift']]
subprocess.run(['swiftc','-parse-as-library','-I',str(binary),'-I',str(binary/'Modules'),*objects,str(qa/'Theme.swift'),*sources,str(root/'scripts/AdoptionPresentationChecks.swift'),'-o',str(qa/'adoption-checks')],cwd=root,env=env,check=True)
app=qa/'AdoptionQA.app';(app/'Contents/MacOS').mkdir(parents=True)
shutil.copy2(qa/'adoption-checks',app/'Contents/MacOS/adoption-checks')
(app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'work.shiroi.adoption-checks.'+qa.name,'CFBundleExecutable':'adoption-checks','CFBundleName':'Adoption QA','CFBundlePackageType':'APPL','NSPrincipalClass':'NSApplication'}))
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
env.update(QA_ADOPTION_DIRECTORY=str(qa/'data'),QA_RESOURCE_BUNDLE=str(root/'build/Tomatogotchi.app/Contents/Resources/Tomatogotchi_Tomatogotchi.bundle'))
result=subprocess.run([str(app/'Contents/MacOS/adoption-checks')],cwd=root,env=env,text=True,capture_output=True,timeout=25)
print(result.stdout,end='');print(result.stderr,end='')
assert result.returncode==0 and 'PASS AdoptionPresentationChecks:' in result.stdout,'Adoption presentation failed'
print('Adoption QA files:',qa)
