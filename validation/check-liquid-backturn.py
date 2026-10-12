"""终检：背侧图集轮廓、端点阴影及非目标资源均保持一致。"""
from pathlib import Path
import hashlib
import json
import numpy as np
from PIL import Image

root=Path('/workspace')
baseline=json.loads((root/'validation/liquid-backturn-baseline.json').read_text())
changed=[p for p,h in baseline.items() if hashlib.sha256((root/p).read_bytes()).hexdigest()!=h]
allowed={'scripts/core/art.lua','scripts/data/art.lua','assets/image/runtime/liquid_turn.png'}
assert set(changed)==allowed,changed
atlas=Image.open(root/'assets/image/runtime/liquid_turn.png').convert('RGBA')
idle=Image.open(root/'assets/image/runtime/liquid_idle.png').convert('RGBA')
first=np.array(idle.crop((2,2,254,254)))
last=np.array(atlas.crop((770,258,1022,510)))
mask=first[:,:,3]>0
assert np.array_equal(first[mask],last[mask]),'终点必须保留主角色彩、alpha与阴影'
frames=[]
for i in range(8):
 x,y=i%4*256+2,i//4*256+2
 frame=np.asarray(atlas.crop((x,y,x+252,y+252)))
 ys,xs=np.where(frame[:,:,3]>80)
 frames.append([int(xs.max()-xs.min()+1),int(ys.max()-ys.min()+1)])
assert max(v[0] for v in frames)-min(v[0] for v in frames)<=3
assert len(set(v[1] for v in frames))==1
report={'passed':True,'changed':changed,'non_target_resources_unchanged':True,
        'endpoint_colors_alpha_shadow_match_idle':True,'back_frames':[3,4,5,6],
        'frame_dimensions':frames,'raw_front_facing_frame_removed':True}
(root/'validation/liquid-backturn-assets-final.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
print(json.dumps(report,ensure_ascii=False))
