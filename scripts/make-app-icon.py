#!/usr/bin/env python3
"""Reproducible original pixel egg icon. Standard library + macOS iconutil."""
from pathlib import Path
import struct
import subprocess
import zlib

ROOT = Path(__file__).resolve().parents[1]
PALETTE = {'.': (0,0,0,0), 'b':(131,157,242,255), 'B':(189,207,255,255),
           's':(74,87,136,255), '#':(48,56,87,255), 'e':(248,244,222,255),
           'd':(219,213,191,255), 'w':(255,255,250,255)}


def png(path, pixels):
    h,w=len(pixels),len(pixels[0])
    def chunk(kind,data):
        return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
    data=b''.join(b'\0'+bytes(c for p in row for c in p) for row in pixels)
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(data,9))+chunk(b'IEND',b''))


def grid():
    g=[['.']*64 for _ in range(64)]
    def rect(x,y,w,h,c):
        for yy in range(y,y+h):
            for xx in range(x,x+w):g[yy][xx]=c
    for y in range(4,60):
        inset=8 if y<8 or y>=56 else 4
        rect(inset,y,64-2*inset,1,'b')
    rect(8,4,48,2,'B');rect(4,8,2,44,'B')
    widths=[(10,14),(12,20),(16,24),(20,28),(26,32),(42,28),(48,20)]
    # Rows describe an original, stepped egg silhouette, widest near its base.
    for y in range(10,52):
        width=next(w for end,w in [(12,14),(16,20),(20,24),(26,28),(42,32),(48,28),(52,20)] if y<end)
        x=(64-width)//2
        rect(x+2,y+3,width,1,'s');rect(x,y,width,1,'#')
    for y in range(12,50):
        width=next(w for end,w in [(16,10),(20,16),(26,20),(42,26),(46,22),(50,16)] if y<end)
        rect((64-width)//2,y,width,1,'d' if y>=42 else 'e')
    rect(24,20,4,6,'w');rect(22,28,3,10,'w')
    return g


def svg(g):
    paths=[]
    for y,row in enumerate(g):
        x=0
        while x<64:
            c=row[x];end=x+1
            while end<64 and row[end]==c:end+=1
            if c!='.':
                rgb=PALETTE[c];color='#'+''.join(f'{v:02x}' for v in rgb[:3])
                paths.append(f'<rect x="{x}" y="{y}" width="{end-x}" height="1" fill="{color}"/>')
            x=end
    return '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64" shape-rendering="crispEdges">'+''.join(paths)+'</svg>\n'


def main():
    g=grid()
    out=ROOT/'design/app-icon';out.mkdir(exist_ok=True)
    (out/'AppIcon.svg').write_text(svg(g))
    iconset=ROOT/'.build/AppIcon.iconset';iconset.mkdir(parents=True,exist_ok=True)
    for logical in [16,32,128,256,512]:
        for scale in [1,2]:
            n=logical*scale
            pixels=[[PALETTE[g[min(63,y*64//n)][min(63,x*64//n)]] for x in range(n)] for y in range(n)]
            png(iconset/f'icon_{logical}x{logical}{"@2x" if scale==2 else ""}.png',pixels)
    target=ROOT/'Sources/Tomatogotchi/Resources/AppIcon.icns'
    subprocess.run(['iconutil','-c','icns',str(iconset),'-o',str(target)],check=True)
    print(f'Generated editable pixel egg and complete iconset: {target}')

if __name__=='__main__':main()
