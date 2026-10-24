#!/usr/bin/env python3
"""Verify complete shipped sprite matrices and independent PNG/SVG/source equivalence."""
from pathlib import Path
import json,struct,zlib,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]
PALETTE={'.':(0,0,0,0),'#':(41,45,43,255),'o':(241,241,239,255)}
colors={'#292D2B':PALETTE['#'],'#F1F1EF':PALETTE['o']}
count=0
for manifest in sorted((ROOT/'design/characters/animation').glob('*-manifest.json')):
    rows=json.loads(manifest.read_text());species=manifest.name.removesuffix('-manifest.json')
    expected={(a,e,f) for a in ['idle','walk','sleep','play','eat'] for e in ['neutral','happy','angry','joyful'] for f in [0,1]}
    assert len(rows)==40 and {(r['action'],r['expression'],r['frame'])for r in rows}==expected
    by={(r['action'],r['expression'],r['frame']):r for r in rows}
    assert len({tuple(by[('idle',e,0)]['grid'])for e in ['neutral','happy','angry','joyful']})==4,'Expressions must be visibly distinct'
    for a,e,_ in expected:assert by[(a,e,0)]['grid']!=by[(a,e,1)]['grid'],'Every action needs two distinct frames'
    for row in rows:
        assert row['species']==species and row['key']==f"{species}-{row['action']}-{row['expression']}-{row['frame']}"
        g=row['grid'];assert len(g)==24 and all(len(r)==24 for r in g)
        pixels=[PALETTE[c]for line in g for c in line]
        occupied=[(x,y)for y,line in enumerate(g)for x,c in enumerate(line)if c!='.']
        assert len(occupied)>40 and all(3<=y<21 for x,y in occupied),'Must fit the real short LCD without cropping'
        data=(ROOT/'Sources/Tomatogotchi/Resources'/(row['key']+'.png')).read_bytes()
        assert data[:8]==b'\x89PNG\r\n\x1a\n'
        offset=8;compressed=b''
        while offset<len(data):
            length=struct.unpack('>I',data[offset:offset+4])[0];kind=data[offset+4:offset+8];chunk=data[offset+8:offset+8+length]
            if kind==b'IHDR':assert struct.unpack('>IIBBBBB',chunk)==(24,24,8,6,0,0,0)
            if kind==b'IDAT':compressed+=chunk
            offset+=length+12
        decoded=zlib.decompress(compressed)
        expectedBytes=b''.join(b'\0'+bytes(v for p in pixels[y*24:(y+1)*24]for v in p)for y in range(24))
        assert decoded==expectedBytes,'Shipped PNG differs from source grid'
        vector=[PALETTE['.']]*576
        svg=ET.fromstring((ROOT/'design/characters/animation'/(row['key']+'.svg')).read_text())
        for rect in svg:
            x,y,w,h=(int(rect.attrib[k])for k in ['x','y','width','height'])
            for yy in range(y,y+h):
                for xx in range(x,x+w):vector[yy*24+xx]=colors[rect.attrib['fill']]
        assert vector==pixels,'Editable SVG differs from app PNG/source grid'
        count+=1
print(f'PASS ExtraPets: {count} complete original PNG/SVG/grid frames, distinct expressions/action pairs, short-LCD bounds')
