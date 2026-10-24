#!/usr/bin/env python3
"""Original pixel animation derived only from this project's original cat/dinosaur."""
from pathlib import Path
import json
import runpy
ROOT=Path(__file__).resolve().parents[1]
base=runpy.run_path(str(ROOT/'scripts/make-character-drafts.py'))
rect,poly,png=base['rect'],base['poly'],base['png']
PALETTE=base['PALETTE']
ACTIONS=['idle','walk','sleep','play','eat']
EXPRESSIONS=['neutral','happy','angry','joyful']


def sprite(species,action,expression,frame):
    g=base[species](blink=action=='idle' and frame==1)
    if action=='sleep':
        g=[list('.'*24)for _ in range(24)]
        if species=='cat':
            poly(g,[(3,14),(5,11),(8,13),(10,12),(17,12),(20,15),(20,19),(18,21),(5,21),(3,19)])
            rect(g,5,15,2,1,'o');rect(g,10,15,2,1,'o');rect(g,15,17,3,2 if frame else 1,'o')
        else:
            poly(g,[(2,17),(7,18),(9,14),(13,13),(16,14),(16,11),(20,11),(20,13),(22,13),(22,18),(19,19),(17,21),(7,21),(4,20)])
            rect(g,18,14,2,1,'o');rect(g,11,17,3,2 if frame else 1,'o')
        rect(g,3 if frame else 2,5 if frame else 6,3,1)
        rect(g,4 if frame else 3,6 if frame else 7,1,1)
        rect(g,3 if frame else 2,7 if frame else 8,3,1)
        return g
    # Erase facial marks only, preserving ear and belly highlights.
    if species=='cat':
        rect(g,9,9,2,4);rect(g,16,9,2,4);rect(g,11,13,4,3)
        eyes=[(9,10),(16,10)];mouth=(12,13)
    else:
        rect(g,16,5,3,4);rect(g,19,8,3,3)
        eyes=[(17,6)];mouth=(20,9)
    for x,y in eyes:
        if expression=='neutral':rect(g,x,y+(1 if action=='idle'and frame else 0),2 if action=='idle'and frame else 1,1 if action=='idle'and frame else 2,'o')
        if expression=='happy':rect(g,x,y+1,2,1,'o');rect(g,x+1,y,1,1,'o')
        if expression=='angry':rect(g,x,y,1,1,'o');rect(g,x+1,y+1,1,1,'o')
        if expression=='joyful':rect(g,x,y,2,2,'o')
    if action=="idle" and frame:
        for x,y in eyes:
            rect(g,x,y,2,2);rect(g,x,y+1,2,1,"o")
    mx,my=mouth
    rect(g,mx,my,2,2 if expression=='joyful' else 1,'o')
    if expression=='happy' and species=='cat':rect(g,mx-1,my-1,1,1,'o');rect(g,mx+2,my-1,1,1,'o')
    if expression=='angry' and species=='cat':rect(g,mx,my+1,2,1,'o')
    if action=='walk':
        # Feet alternate around an invariant baseline; tail articulates separately.
        rect(g,7 if species=='cat' else 8,19,12,3,'.')
        if frame:rect(g,8,19,3,2);rect(g,15,19,2,1);rect(g,16,20,3,1)
        else:rect(g,9,19,2,1);rect(g,7,20,3,1);rect(g,15,19,3,2)
        rect(g,2,11,3,5,'.');rect(g,2,12 if frame else 14,2,3);rect(g,4,15,2,2)
    if action=='play':
        # Lift a forepaw and bat a ball; this is a different silhouette, not a translated idle.
        if species=='cat':
            rect(g,18,12,4,3,'.');rect(g,18,10 if frame else 12,3,2);rect(g,20,9 if frame else 13,2,2)
        else:rect(g,17,12,4,4,'.');rect(g,17,11 if frame else 14,4,2)
        rect(g,2 if frame else 4,19 if frame else 18,3,2);rect(g,3 if frame else 5,18 if frame else 17,1,1)
    if action=='eat':
        # Food bowl and dipping mouth/paw frames share the fixed canvas.
        rect(g,18,18,6,1);rect(g,18,19,1,1);rect(g,23,19,1,1);rect(g,19,20,4,1)
        rect(g,11 if species=='cat' else 19,14 if species=='cat' else 10,2,2 if frame else 1,'o')
        rect(g,12 if frame else 15,19 if frame else 20,2,1,'o')
        if frame:rect(g,10,20,2,1)
    return g


def svg(g):
    parts=[]
    for y,row in enumerate(g):
        x=0
        while x<24:
            c=row[x];end=x+1
            while end<24 and row[end]==c:end+=1
            if c!='.':parts.append(f'<rect x="{x}" y="{y}" width="{end-x}" height="1" fill="{"#292D2B" if c=="#" else "#F1F1EF"}"/>')
            x=end
    return '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" shape-rendering="crispEdges">'+''.join(parts)+'</svg>\n'


def main():
    out=ROOT/'design/characters/animation';out.mkdir(exist_ok=True)
    manifest=[]
    for species in ['cat','dinosaur']:
        for action in ACTIONS:
            for expression in EXPRESSIONS:
                frames=[]
                for f in [0,1]:
                    g=sprite(species,action,expression,f)
                    key=f'{species}-{action}-{expression}-{f}'
                    (out/f'{key}.svg').write_text(svg(g))
                    png(ROOT/f'Sources/Tomatogotchi/Resources/{key}.png',[[PALETTE[c]for c in row]for row in g])
                    manifest.append({'key':key,'species':species,'action':action,'expression':expression,'frame':f,'grid':[''.join(row)for row in g]})
                    frames.append(g)
                assert frames[0]!=frames[1],(species,action,expression)
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print('Generated 80 original 24×24 action/expression PNGs and editable SVGs')

if __name__=='__main__':main()
