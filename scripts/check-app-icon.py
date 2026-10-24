#!/usr/bin/env python3
"""Verify actual bundle icon declaration, chunk sizes and every decoded rendition."""
from pathlib import Path
import plistlib
import struct
import subprocess
import tempfile
root=Path(__file__).resolve().parents[1]
app=root/'build/Tomatogotchi.app'
info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert info['CFBundleIconFile']=='AppIcon.icns'
data=(app/'Contents/Resources/AppIcon.icns').read_bytes()
assert data==(root/'Sources/Tomatogotchi/Resources/AppIcon.icns').read_bytes()
assert data[:4]==b'icns' and struct.unpack('>I',data[4:8])[0]==len(data)
with tempfile.TemporaryDirectory(dir=root/'.build',prefix='qa-icon-') as temp:
    out=Path(temp)/'AppIcon.iconset'
    subprocess.run(['iconutil','-c','iconset',str(app/'Contents/Resources/AppIcon.icns'),'-o',str(out)],check=True)
    dimensions=set()
    for p in out.glob('*.png'):
        png=p.read_bytes()
        assert png[:8]==b'\x89PNG\r\n\x1a\n'
        w,h=struct.unpack('>II',png[16:24]);assert w==h
        dimensions.add(w)
    assert {16,32,64,128,256,512,1024}<=dimensions,dimensions
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
print('PASS AppIcon: bundle declaration, exact resource, decoded 16–1024px renditions, strict signature; Dock/Finder remains native QA')
