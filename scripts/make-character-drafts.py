#!/usr/bin/env python3
"""Original 24×24 pixel studies; source shapes, no imported reference artwork."""
from pathlib import Path
import struct, zlib
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'design' / 'characters'
PALETTE = {'.': (0,0,0,0), '#': (41,45,43,255), 'o': (241,241,239,255)}

def rect(g, x, y, w, h, value='#'):
    for yy in range(y,y+h):
        for xx in range(x,x+w): g[yy][xx] = value

def poly(g, pts):
    for y in range(24):
        for x in range(24):
            inside = False
            px,py = x+.5,y+.5
            for (ax,ay),(bx,by) in zip(pts,pts[1:]+pts[:1]):
                if (ay>py)!=(by>py) and px < (bx-ax)*(py-ay)/(by-ay)+ax:
                    inside = not inside
            if inside: g[y][x] = '#'

def cat(blink=False):
    g=[list('.'*24) for _ in range(24)]
    poly(g,[(6,3),(9,3),(12,7),(15,7),(18,3),(20,3),(20,14),(18,16),(18,21),(15,21),(15,20),(11,20),(11,21),(8,21),(8,19),(5,19),(3,17),(3,13),(5,13),(5,16),(8,17),(8,15),(6,13)])
    rect(g,7,5,1,2,'o');rect(g,18,5,1,2,'o')
    rect(g,9,11 if blink else 10,2 if blink else 1,1 if blink else 2,'o');rect(g,16,11 if blink else 10,2 if blink else 1,1 if blink else 2,'o')
    rect(g,12,13,2,1,'o');rect(g,12,17,2,2,'o')
    return g

def dinosaur(blink=False):
    g=[list('.'*24) for _ in range(24)]
    poly(g,[(13,3),(19,3),(19,5),(22,5),(22,11),(19,11),(19,12),(16,12),(16,13),(20,13),(20,15),(17,15),(17,19),(19,19),(19,21),(15,21),(14,19),(12,19),(12,21),(8,21),(8,19),(5,18),(2,15),(2,12),(4,12),(4,15),(8,16),(10,14),(10,10),(12,8),(12,4)])
    rect(g,17,7 if blink else 6,2 if blink else 1,1 if blink else 2,'o');rect(g,20,9,2,1,'o')
    rect(g,13,13,2,5,'o');rect(g,12,15,1,3,'o')
    return g

def png(path, pixels):
    height,width=len(pixels),len(pixels[0])
    def chunk(kind,data):
        return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
    data=b''.join(b'\0'+bytes(sum((list(p) for p in row),[])) for row in pixels)
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',width,height,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(data))+chunk(b'IEND',b''))

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    all_grids=[]
    for name, maker in [('cat',cat),('dinosaur',dinosaur)]:
        for blink in [False,True]:
            grid=maker(blink);state='blink' if blink else 'idle'
            all_grids.append(grid)
            rects=[]
            for y,row in enumerate(grid):
                x=0
                while x<24:
                    value=row[x];end=x+1
                    while end<24 and row[end]==value: end+=1
                    if value!='.':
                        color='#292D2B' if value=='#' else '#F1F1EF'
                        rects.append(f'<rect x="{x}" y="{y}" width="{end-x}" height="1" fill="{color}"/>')
                    x=end
            (OUT/f'{name}-{state}.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" shape-rendering="crispEdges">'+''.join(rects)+'</svg>\n')
            png(OUT/f'{name}-{state}.png',[[PALETTE[v] for v in row] for row in grid])
    # Left to right: cat idle, cat blink, dinosaur idle, dinosaur blink.
    canvas=[[(241,241,239,255)]*640 for _ in range(200)]
    for index,grid in enumerate(all_grids):
        for y,row in enumerate(grid):
            for x,value in enumerate(row):
                if value=='.': continue
                for yy in range(6):
                    for xx in range(6): canvas[28+y*6+yy][8+index*160+x*6+xx]=PALETTE[value]
    (ROOT/'outputs').mkdir(exist_ok=True)
    png(ROOT/'outputs'/'character-studies.png',canvas)
    print('Generated four original 24×24 source studies and preview; not yet approved or connected to hatch.')

if __name__ == "__main__": main()
