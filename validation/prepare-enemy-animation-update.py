"""Pack uploaded fly/crab frames without changing the source artwork.

Runtime samples 256px cells at +2px, so clip pivots/bounds are reported in
the sampled 252px coordinate system. Crab body scale is shared across clips.
"""
from pathlib import Path
import json
import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/image/敌人素材'
OUTPUT = ROOT / 'assets/image/runtime'
CELL, MARGIN = 256, 2


def cells(path, cols, rows):
    im = Image.open(path).convert('RGBA')
    xs = [round(i * im.width / cols) for i in range(cols + 1)]
    ys = [round(i * im.height / rows) for i in range(rows + 1)]
    return [im.crop((xs[c], ys[r], xs[c+1], ys[r+1]))
            for r in range(rows) for c in range(cols)]


def box(im):
    ys, xs = np.where(np.asarray(im)[:, :, 3] > 10)
    return (int(xs.min()), int(ys.min()), int(xs.max())+1, int(ys.max())+1)


def eyes(im):
    arr = np.asarray(im)
    white = (arr[:, :, :3].min(axis=2) > 235) & (arr[:, :, 3] > 10)
    labels, n = ndimage.label(white)
    blobs = []
    for i, sl in enumerate(ndimage.find_objects(labels), 1):
        if sl is None:
            continue
        ys, xs = np.where(labels[sl] == i)
        if 400 <= len(xs) <= 4000:
            blobs.append((xs.mean()+sl[1].start, ys.mean()+sl[0].start, len(xs)))
    pairs = [(min(a[2], b[2]), (a[0]+b[0])/2, abs(a[0]-b[0]))
             for i,a in enumerate(blobs) for b in blobs[i+1:]
             if abs(a[1]-b[1]) < 26 and 40 < abs(a[0]-b[0]) < 150]
    if not pairs:
        raise ValueError('Cannot identify crab eyes')
    _, x, spacing = max(pairs)
    return x, spacing


def save(key, frames):
    atlas = Image.new('RGBA', (CELL*4, CELL*((len(frames)+3)//4)))
    bounds = []
    for i,f in enumerate(frames):
        atlas.alpha_composite(f, ((i%4)*CELL, (i//4)*CELL))
        b = box(f)
        assert min(b[:2]) >= 2 and max(b[2:]) <= 254, (key,i,b)
        bounds.append([v-MARGIN for v in b])
    atlas.save(OUTPUT / (key+'.png'))
    union = [min(b[0] for b in bounds), min(b[1] for b in bounds),
             max(b[2] for b in bounds), max(b[3] for b in bounds)]
    return {'bounds':union, 'frameBounds':bounds, 'count':len(frames)}


specs = [('enemy_crab_move','移动',2), ('enemy_crab_melee','近战攻击',4),
         ('enemy_crab_ranged','远程攻击',2)]
raw, info = {}, {}
for key,sub,rows in specs:
    paths = list((SOURCE/'裂钳蟹'/sub).glob('*.png'))
    assert len(paths)==1, f'{sub}: expected exactly one sheet'
    fs = cells(paths[0],4,rows)
    centers = [eyes(f)[0] for f in fs]
    base = 52 / float(np.median([eyes(f)[1] for f in fs]))
    raw[key] = (fs,centers,base)

# One fit factor keeps the crab's body identical in move/melee/ranged clips.
fit = 1.0
for fs,centers,base in raw.values():
    for f,ex in zip(fs,centers):
        x0,y0,x1,y1=box(f)
        fit=min(fit,126/(max(ex-x0,x1-ex)*base),252/((y1-y0)*base))

reference = None
for key,_,_ in specs:
    fs,centers,base=raw[key]
    scale=base*fit
    packed=[]
    for f,ex in zip(fs,centers):
        x0,y0,x1,y1=box(f)
        tight=f.crop((x0,y0,x1,y1))
        w,h=max(1,round(tight.width*scale)),max(1,round(tight.height*scale))
        resized=tight.resize((w,h),Image.Resampling.LANCZOS)
        frame=Image.new('RGBA',(CELL,CELL))
        # Eye midpoint anchors x; actual opaque bottom anchors the floor.
        ox=round(128-(ex-x0)*scale)
        frame.alpha_composite(resized,(ox,254-h))
        packed.append(frame)
    meta=save(key,packed)
    if reference is None:
        reference=float(np.median([b[3]-b[1] for b in meta['frameBounds']]))
    meta.update(pivotX=126,pivotY=252,sourceHeight=reference)
    info[key]=meta

# Keep the fly's source positions and a common scale through wing flaps.
fs=cells(SOURCE/'变异飞蝇/spritesheet.png',4,2)
bs=[box(f) for f in fs]
u=(min(b[0] for b in bs),min(b[1] for b in bs),max(b[2] for b in bs),max(b[3] for b in bs))
scale=min(250/(u[2]-u[0]),250/(u[3]-u[1]))
packed=[]
for f in fs:
    tight=f.crop(u)
    w,h=round(tight.width*scale),round(tight.height*scale)
    frame=Image.new('RGBA',(CELL,CELL))
    frame.alpha_composite(tight.resize((w,h),Image.Resampling.LANCZOS),((CELL-w)//2,(CELL-h)//2))
    packed.append(frame)
info['enemy_fly']=save('enemy_fly',packed)
(ROOT/'validation/enemy-animation-metadata.json').write_text(json.dumps(info,indent=2),encoding='utf-8')
for key,meta in info.items():
    print(key, {k:v for k,v in meta.items() if k!='frameBounds'})
