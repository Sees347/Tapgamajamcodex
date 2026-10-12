from PIL import Image
import numpy as np,json
from pathlib import Path
black=np.array(Image.open('/workspace/screenshots/map-fill-matrix-black.png').convert('RGB'))
white=np.array(Image.open('/workspace/screenshots/map-fill-matrix-white.png').convert('RGB'))
assert black.shape==white.shape==(720,1280,3)
delta=np.abs(black.astype('int16')-white.astype('int16')).max(2)
rows=[]
for ri,v in enumerate([8,16,26,4,80]):
 for oi,off in enumerate([0,.25,.5,.75]):
  for subject in [1,2]:
   x=(oi*2+subject-1)*160;y=ri*144;cx=int(80+off);cy=int(72+off)
   mask=np.zeros((144,160),bool)
   if subject==1: mask[cy-5:cy+6,cx-5:cx+6]=True
   else:
    mask[12:132,cx-2:cx+3]=True
    mask[cy-2:cy+3,12:148]=True
   # 仅采真实墙面内部：viewH80时8米测试墙面仅72px宽，不能把墙外空白当漏底。
   ppu=720/v
   xx,yy=np.meshgrid(np.arange(160)+.5,np.arange(144)+.5)
   seam=1 if subject==1 else 4
   wx=seam+(xx-(80+off))/ppu
   wy=-4-((yy-(72+off))/ppu)
   mask &= (wx>.5)&(wx<7.5)&(wy>-7.5)&(wy<-.5)
   values=delta[y:y+144,x:x+160][mask]
   guard=black[y+1,x+1].tolist()==[0,0,0] and white[y+1,x+1].tolist()==[255,255,255] and delta[y+3,x+3]>100
   rows.append({'viewH':v,'offset':off,'subject':'边界格内外共边' if subject==1 else '4格宏块共边','sampled':int(len(values)),'maxRGBDelta':int(values.max()),'nonzero':int(np.count_nonzero(values)),'guard':bool(guard)})
r={'cases':rows,'combinations':len(rows),'sampledPixels':sum(a['sampled'] for a in rows),'maxRGBDelta':max(a['maxRGBDelta'] for a in rows),'nonzeroPixels':sum(a['nonzero'] for a in rows),'allGuards':all(a['guard'] for a in rows)}
Path('/workspace/validation/map-fill-matrix-result.json').write_text(json.dumps(r,ensure_ascii=False,indent=2))
print({k:v for k,v in r.items() if k!='cases'})
for a in rows:
 if a['nonzero']:print(a)
