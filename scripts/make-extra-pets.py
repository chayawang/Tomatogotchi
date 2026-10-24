#!/usr/bin/env python3
"""Original pixel pets built from this repository's native vector/grid system."""
from pathlib import Path
import argparse,json,runpy
ROOT=Path(__file__).resolve().parents[1]
base=runpy.run_path(str(ROOT/'scripts/make-character-drafts.py'))
rect,poly,png=base['rect'],base['poly'],base['png']
PALETTE=base['PALETTE']
ACTIONS=['idle','walk','sleep','play','eat']
EXPRESSIONS=['neutral','happy','angry','joyful']
SUPPORTED=['dog','daruma','goblin']

def shape(species):
    g=[list('.'*24) for _ in range(24)]
    if species=='dog':
        poly(g,[(7,4),(17,4),(19,6),(21,6),(21,15),(18,15),(18,19),(17,21),(14,21),(14,19),(10,19),(10,21),(7,21),(6,19),(6,16),(3,16),(2,13),(3,11),(5,11),(5,14),(6,14),(6,7)])
        rect(g,3,5,4,8);rect(g,17,5,4,8)
        rect(g,4,7,1,4,'o');rect(g,19,7,1,4,'o')
        rect(g,7,6,10,7,'o');rect(g,10,15,5,3,'o')
    elif species=='daruma':
        poly(g,[(8,4),(16,4),(19,6),(21,10),(21,17),(18,21),(6,21),(3,17),(3,10),(5,6)])
        rect(g,7,7,10,7,'o')
        rect(g,8,16,1,3,'o');rect(g,9,17,1,1,'o');rect(g,11,16,5,1,'o');rect(g,11,18,5,1,'o');rect(g,11,17,1,1,'o');rect(g,13,17,1,1,'o');rect(g,15,17,1,1,'o')
    elif species=='goblin':
        poly(g,[(8,5),(16,5),(18,8),(18,12),(15,14),(9,14),(6,12),(6,8)])
        poly(g,[(2,5),(8,7),(7,11),(4,10)]);poly(g,[(16,7),(22,5),(21,10),(17,11)])
        rect(g,9,3,6,2);rect(g,7,14,11,5);rect(g,4,14,3,4);rect(g,18,14,3,4)
        rect(g,7,19,4,2);rect(g,14,19,4,2)
        rect(g,10,14,4,4,'o');rect(g,12,14,1,4);rect(g,11,18,2,1,'o')
    return g

def goblin_sprite(action,expression,frame):
    g=shape('goblin')
    if action=='sleep':
        g=[list('.'*24)for _ in range(24)]
        poly(g,[(6,13),(17,13),(20,16),(20,19),(17,21),(6,21),(3,18)])
        poly(g,[(1,13),(7,15),(6,18),(3,17)]);poly(g,[(17,15),(23,13),(21,18),(18,18)])
        rect(g,8,16,3,1,'o');rect(g,14,16,2,1,'o');rect(g,10,19,4,1 if frame else 2,'o')
        rect(g,2 if frame else 3,3 if frame else 4,3,1);rect(g,3 if frame else 4,4 if frame else 5,1,1);rect(g,2 if frame else 3,5 if frame else 6,3,1)
        return g
    for x in [8,14]:
        if action=='idle'and frame:rect(g,x,9,2,1,'o')
        elif expression=='neutral':rect(g,x,8,1,2,'o')
        elif expression=='happy':rect(g,x,9,2,1,'o');rect(g,x+1,8,1,1,'o')
        elif expression=='angry':rect(g,x,7,1,1,'o');rect(g,x+1,8,1,2,'o')
        else:rect(g,x,8,2,2,'o')
    rect(g,10,11,4,2 if expression=='joyful'else 1,'o')
    if expression=='happy':rect(g,10,10,1,1,'o');rect(g,13,10,1,1,'o')
    if expression=='angry':rect(g,11,12,2,1,'o')
    if action=='walk':
        rect(g,6,19,13,2,'.');rect(g,6 if frame else 8,19,3,2);rect(g,15 if frame else 14,19,3,1 if frame else 2)
        rect(g,4,14,3,4,'.');rect(g,4,13 if frame else 15,3,2)
    elif action=='play':
        rect(g,18,13,4,5,'.');rect(g,18,11 if frame else 14,3,2)
        rect(g,2 if frame else 4,19 if frame else 18,3,2);rect(g,3 if frame else 5,18 if frame else 17,1,1)
    elif action=='eat':
        rect(g,17,18,7,1);rect(g,18,19,1,1);rect(g,23,19,1,1);rect(g,19,20,4,1)
        rect(g,10,11,4,2 if frame else 1,'o');rect(g,18 if frame else 16,16,2,1,'o')
    return g

def daruma_sprite(action,expression,frame):
    g=shape('daruma')
    if action=='sleep':
        g=[list('.'*24)for _ in range(24)]
        poly(g,[(7,12),(17,12),(20,15),(21,18),(18,21),(6,21),(3,18),(4,15)])
        rect(g,7,15,10,4,'o');rect(g,8,16,3,1);rect(g,14,16,2,1)
        rect(g,11,18,2,1);rect(g,10,19,4,1 if frame else 2,'o')
        rect(g,2 if frame else 3,3 if frame else 4,3,1);rect(g,3 if frame else 4,4 if frame else 5,1,1);rect(g,2 if frame else 3,5 if frame else 6,3,1)
        return g
    for x in [8,14]:
        if action=='idle' and frame:rect(g,x,10,2,1)
        elif expression=='neutral':rect(g,x,9,1,2)
        elif expression=='happy':rect(g,x,10,2,1);rect(g,x+1,9,1,1)
        elif expression=='angry':rect(g,x,8,1,1);rect(g,x+1,9,1,2)
        else:rect(g,x,9,2,2)
    rect(g,11,12,2,2 if expression=='joyful' else 1)
    if expression=='happy':rect(g,10,11,1,1);rect(g,13,11,1,1)
    if action in ['walk','play']:
        rocked=[list('.'*24)for _ in range(24)]
        for y,row in enumerate(g):
            shift=(1 if frame else -1) if y<12 else (-1 if frame else 1) if y>=17 else 0
            yy=y-1 if action=='walk'and frame else y
            if yy<0:continue
            for x,c in enumerate(row):
                if c!='.'and 0<=x+shift<24:rocked[yy][x+shift]=c
        g=rocked
        if action=='walk'and frame:rect(g,9,20,6,1)
        if action=='play':
            rect(g,21 if frame else 1,5 if frame else 4,2,1);rect(g,22 if frame else 2,4 if frame else 3,1,3)
    elif action=='eat':
        rect(g,17,18,7,1);rect(g,18,19,1,1);rect(g,23,19,1,1);rect(g,19,20,4,1)
        rect(g,10,12,4,2 if frame else 1);rect(g,18 if frame else 16,16,2,1,'o')
    return g

def sprite(species,action,expression,frame):
    if species=='daruma':return daruma_sprite(action,expression,frame)
    if species=='goblin':return goblin_sprite(action,expression,frame)
    g=shape(species)
    if action=='sleep':
        g=[list('.'*24)for _ in range(24)]
        poly(g,[(3,14),(6,12),(10,13),(14,12),(18,13),(21,16),(21,19),(18,21),(5,21),(3,19)])
        rect(g,5,15,12,4,'o');rect(g,7,16,3,1);rect(g,13,16,3,1)
        rect(g,10,18,3,1 if expression!='joyful' else 2)
        rect(g,18,15,1,2 if frame else 1,'o')
        rect(g,3 if frame else 2,3 if frame else 4,3,1)
        rect(g,4 if frame else 3,4 if frame else 5,1,1)
        rect(g,3 if frame else 2,5 if frame else 6,3,1)
        return g
    # A light muzzle and floppy ears distinguish this dog from the cat silhouette.
    for x in [9,14]:
        if action=='idle' and frame:rect(g,x,9,2,1)
        elif expression=='neutral':rect(g,x,8,1,2)
        elif expression=='happy':rect(g,x,9,2,1);rect(g,x+1,8,1,1)
        elif expression=='angry':rect(g,x,7,1,1);rect(g,x+1,8,1,2)
        else:rect(g,x,8,2,2)
    rect(g,11,10,2,1)
    rect(g,11,12,2,2 if expression=='joyful' else 1)
    if expression=='happy':rect(g,10,11,1,1);rect(g,13,11,1,1)
    if action=='walk':
        rect(g,6,19,12,2,'.')
        rect(g,7 if frame else 8,19,3,2)
        rect(g,14 if frame else 15,19,3,1 if frame else 2)
        rect(g,2,11,3,5,'.');rect(g,2,11 if frame else 13,2,3);rect(g,4,14,2,2)
    elif action=='play':
        rect(g,18,13,4,4,'.');rect(g,18,11 if frame else 14,3,2)
        rect(g,2 if frame else 4,19 if frame else 18,3,2)
        rect(g,3 if frame else 5,18 if frame else 17,1,1)
    elif action=='eat':
        rect(g,17,18,7,1);rect(g,18,19,1,1);rect(g,23,19,1,1);rect(g,19,20,4,1)
        rect(g,11,12,2,2 if frame else 1)
        rect(g,15 if frame else 13,17,2,1,'o')
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
    parser=argparse.ArgumentParser();parser.add_argument('--species',choices=SUPPORTED,required=True);parser.add_argument('--preview',action='store_true');args=parser.parse_args()
    preview=ROOT/'.build';preview.mkdir(exist_ok=True)
    if args.preview:
        g=sprite(args.species,'idle','neutral',0)
        pixels=[[PALETTE[c] if c!='.' else PALETTE['o']for c in row for _ in range(8)]for row in g for _ in range(8)]
        png(preview/(args.species+'-preview.png'),pixels);return
    out=ROOT/'design/characters/animation';out.mkdir(exist_ok=True)
    manifest=[]
    sheet=[[PALETTE['o']]*896 for _ in range(560)]
    for ai,action in enumerate(ACTIONS):
        for ei,expression in enumerate(EXPRESSIONS):
            pair=[]
            for frame in [0,1]:
                g=sprite(args.species,action,expression,frame);pair.append(g);key=f'{args.species}-{action}-{expression}-{frame}'
                (out/(key+'.svg')).write_text(svg(g));png(ROOT/'Sources/Tomatogotchi/Resources'/(key+'.png'),[[PALETTE[c]for c in row]for row in g])
                manifest.append({'key':key,'species':args.species,'action':action,'expression':expression,'frame':frame,'grid':[''.join(row)for row in g]})
                for y,row in enumerate(g):
                    for x,c in enumerate(row):
                        if c=='.':continue
                        for dy in range(4):
                            for dx in range(4):sheet[ai*112+8+y*4+dy][(ei*2+frame)*112+8+x*4+dx]=PALETTE[c]
            assert pair[0]!=pair[1],(action,expression)
    (out/(args.species+'-manifest.json')).write_text(json.dumps(manifest,indent=2)+'\n');png(preview/(args.species+'-sheet.png'),sheet)
    print(f'Generated 40 original {args.species} PNGs, editable SVGs and source manifest')
if __name__=='__main__':main()
