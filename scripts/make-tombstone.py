#!/usr/bin/env python3
"""Original 24px tombstone, shared editable SVG and transparent PNG."""
from pathlib import Path
import runpy
root=Path(__file__).resolve().parents[1]
png=runpy.run_path(str(root/'scripts/make-app-icon.py'))['png']
g=[['.']*24 for _ in range(24)]
def rect(x,y,w,h,c):
    for yy in range(y,y+h):
        for xx in range(x,x+w):g[yy][xx]=c
rect(9,3,6,1,'#');rect(7,4,10,2,'#');rect(6,6,12,14,'#')
rect(9,4,6,1,'o');rect(8,5,8,2,'o');rect(7,7,10,12,'o')
rect(4,20,16,2,'#');rect(6,19,12,1,'#');rect(5,21,14,1,'#')
# A small engraved cross and two memorial lines, readable at 3× and 4×.
rect(11,7,2,6,'#');rect(9,9,6,2,'#');rect(9,15,6,1,'#');rect(10,17,4,1,'#')
palette={'.':(0,0,0,0),'#':(41,45,43,255),'o':(241,241,239,255)}
rects=[]
for y,row in enumerate(g):
    for x,c in enumerate(row):
        if c!='.':rects.append(f'<rect x="{x}" y="{y}" width="1" height="1" fill="{"#292D2B" if c=="#" else "#F1F1EF"}"/>')
out=root/'design/characters';out.mkdir(exist_ok=True)
(out/'tombstone.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" shape-rendering="crispEdges">'+''.join(rects)+'</svg>\n')
png(root/'Sources/Tomatogotchi/Resources/tombstone.png',[[palette[c] for c in row]for row in g])
print('Generated original 24×24 tombstone SVG and PNG')
