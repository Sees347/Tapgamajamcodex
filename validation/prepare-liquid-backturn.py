"""用当前液态纹理补齐背侧转身，保留原图，所有姿态使用固定主体尺寸。"""
from pathlib import Path
import hashlib
import json
import cv2
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import binary_fill_holes

ROOT = Path('/workspace')
OUT = ROOT / 'validation'
SOURCE = ROOT / 'assets/image/runtime/liquid_idle.png'
source_sha = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
image = Image.open(SOURCE).convert('RGBA')
base = np.array(image.crop((2, 2, 254, 254)))
# 只修补眼睛和嘴，不触碰外沿、鱼鳍、底部折射阴影和透明度。
mask = np.zeros((252, 252), np.uint8)
cv2.ellipse(mask, (86, 88), (7, 11), 0, 0, 360, 255, -1)
cv2.ellipse(mask, (157, 80), (7, 11), -20, 0, 360, 255, -1)
cv2.line(mask, (109, 95), (160, 83), 255, 10)
back = base.copy()
back[:, :, :3] = cv2.inpaint(base[:, :, :3], mask, 6, cv2.INPAINT_TELEA)
# 修补范围用柔边覆盖，水彩纹理不会形成硬方块。
soft = cv2.GaussianBlur(mask.astype(float) / 255, (0, 0), 1.2)
back[:, :, :3] = np.round(base[:, :, :3] * (1-soft[:, :, None]) + back[:, :, :3] * soft[:, :, None]).astype(np.uint8)
left, right = np.fliplr(base).copy(), base
left_back, right_back = np.fliplr(back).copy(), back
# 将镜像角色放回原主角锚点，不能围绕整格画布镜像造成横向偏移。
axis = 95.0
shift = round(2 * axis - 251)
left = cv2.warpAffine(left, np.float32([[1,0,shift],[0,1,0]]), (252,252))
left_back = cv2.warpAffine(left_back, np.float32([[1,0,shift],[0,1,0]]), (252,252))


def spans(arr):
    solid = binary_fill_holes(arr[:, :, 3] > 80)
    bounds = np.zeros((252, 2), dtype=float)
    for y in range(252):
        xs = np.where(solid[y])[0]
        bounds[y] = (xs.min(), xs.max()) if len(xs) else (axis, axis)
    return bounds


lb, rb = spans(left), spans(right)
yy, xx = np.indices((252,252), dtype=np.float32)
frames = []
for i in range(8):
    t = i / 7
    if i == 0:
        arr = left.copy()
    elif i == 7:
        arr = right.copy()
    else:
        # 轮廓两端对齐后连续变换；不像整张交叉淡入那样产生双重描边。
        geometry = lb * (1-t) + rb * t
        width = geometry[:, 1] - geometry[:, 0]
        u = (xx - geometry[:, 0, None]) / np.maximum(1, width[:, None])
        def warp(source, bounds):
            sx = bounds[:, 0, None] + u * (bounds[:,1]-bounds[:,0])[:,None]
            return cv2.remap(source.astype(np.float32), sx.astype(np.float32), yy, cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT)
        a = warp(left_back, lb)
        b = warp(right_back, rb)
        alpha = a[:, :, 3] * (1-t) + b[:, :, 3] * t
        premult = a[:, :, :3] * (a[:, :, 3:4] / 255) * (1-t) + b[:, :, :3] * (b[:, :, 3:4] / 255) * t
        rgb = premult / np.maximum(alpha[:, :, None]/255, 1e-6)
        # 面部只在两端侧面出现，中间四帧完全背向镜头，不出现正面双眼。
        face = max(0, 1-t/0.23) if t < 0.5 else max(0, 1-(1-t)/0.23)
        if face > 0:
            full = warp(left if t<0.5 else right, lb if t<0.5 else rb)
            repair = warp(left_back if t<0.5 else right_back, lb if t<0.5 else rb)
            rgb += (full[:,:,:3]-repair[:,:,:3]) * face
        arr = np.dstack((np.clip(rgb,0,255), alpha)).round().astype(np.uint8)
    arr[arr[:,:,3] == 0, :3] = 0
    frames.append(Image.fromarray(arr))

atlas = Image.new('RGBA', (1024,512))
for i, frame in enumerate(frames):
    atlas.alpha_composite(frame,(i%4*256+2,i//4*256+2))
atlas.save(ROOT/'assets/image/runtime/liquid_turn.png')
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == source_sha
# 为播放器提供原始各帧的视觉尺寸；不是每帧临时扫描图片。
bounds = {}
for key, count in (('liquid_idle',8),('liquid_move',7)):
    im = Image.open(ROOT/f'assets/image/runtime/{key}.png').convert('RGBA')
    values=[]
    for i in range(count):
        a=np.array(im.crop((i%4*256+2,i//4*256+2,i%4*256+254,i//4*256+254)))
        ys,xs=np.where(a[:,:,3]>80)
        values.append([int(xs.min()),int(ys.min()),int(xs.max()+1),int(ys.max()+1)])
    bounds[key]=values
report={'count':8,'fps':32,'reference_sha256':source_sha,'back_frames':[3,4,5,6],
        'base_bounds':bounds['liquid_idle'][0],'frame_bounds':[], 'reference_bounds':bounds}
for im in frames:
    ys,xs=np.where(np.asarray(im)[:,:,3]>80)
    report['frame_bounds'].append([int(xs.min()),int(ys.min()),int(xs.max()+1),int(ys.max()+1)])
(OUT/'liquid-backturn-layout.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
# 深浅背景逐帧检查阴影、透明度和轮廓；验证图仅供内部审核。
sheet=Image.new('RGB',(8*210,460),(20,25,40))
draw=ImageDraw.Draw(sheet)
for row,bg in enumerate(((20,25,40),(212,226,231))):
    draw.rectangle((0,row*230,1680,(row+1)*230),fill=bg)
    for i,frame in enumerate(frames):
        layer=Image.new('RGBA',(252,252),bg+(255,))
        layer.alpha_composite(frame)
        sheet.paste(layer.convert('RGB').resize((210,210)),(i*210,row*230+20))
        draw.text((i*210+5,row*230+4),str(i+1),fill=(150,165,190) if row==0 else (30,50,70))
sheet.save(OUT/'liquid-backturn-sheet.png')
print(json.dumps(report,ensure_ascii=False))
