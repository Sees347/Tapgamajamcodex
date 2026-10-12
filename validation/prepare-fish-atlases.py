"""把上传的鱼待机素材（4 列 × 2 行，每列上下两半叠成一帧）转换为运行图集 + 图标。

源图约定：4096×1024，横向 4 列、纵向 2 行；第 r 行第 c 格与第 r+1 行第 c 格
上下拼接后是该角色朝左的完整一帧，共 4 帧（与运行时图集帧数一致）。
原始素材保留在 image/FishAnim，不参与运行包。
"""
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path('/workspace')
SOURCE = ROOT / 'assets/image/FishAnim/FishAnim'
OUTPUT = ROOT / 'assets/image/runtime'

# fishKey -> 源图相对路径
SPECS = {
    'swordfish': '剑鱼/剑鱼待机.png',
    'barnacle': '藤壶/藤壶待机.png',
    'frog': '青蛙/青蛙待机.png',
}

FRAMES = 4
CELL = 256          # 运行图集单格尺寸
ICON_SIZE = 128     # 图标画布
ICON_MARGIN = 10    # 图标留边
ALPHA_TH = 8        # 判定“可见像素”的 alpha 阈值


def stacked_frames(path):
    """源图 4×2 格 → 每列上下叠合为一帧，输出 4 张 1024×1024。"""
    im = Image.open(path).convert('RGBA')
    cw, ch = im.width // 4, im.height // 2
    cells = [im.crop((c * cw, r * ch, (c + 1) * cw, (r + 1) * ch))
             for r in range(2) for c in range(4)]
    frames = []
    for c in range(4):
        canvas = Image.new('RGBA', (cw, ch * 2))
        canvas.alpha_composite(cells[c], (0, 0))
        canvas.alpha_composite(cells[c + 4], (0, ch))
        frames.append(canvas.resize((CELL, CELL), Image.Resampling.LANCZOS))
    return frames


def union_bounds(frames, th=ALPHA_TH):
    """各帧可见像素的并集包围盒，供 drawFish 定标与定位。"""
    x0 = y0 = 10 ** 9
    x1 = y1 = -1
    for f in frames:
        ys, xs = np.where(np.asarray(f)[:, :, 3] > th)
        x0, y0 = min(x0, int(xs.min())), min(y0, int(ys.min()))
        x1, y1 = max(x1, int(xs.max()) + 1), max(y1, int(ys.max()) + 1)
    return [x0, y0, x1, y1]


def make_icon(frame):
    """取首帧紧致裁剪，等比缩放到图标留边内并居中。"""
    ys, xs = np.where(np.asarray(frame)[:, :, 3] > ALPHA_TH)
    crop = frame.crop((int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1))
    limit = ICON_SIZE - ICON_MARGIN * 2
    scale = min(limit / crop.width, limit / crop.height)
    crop = crop.resize((max(1, round(crop.width * scale)), max(1, round(crop.height * scale))),
                       Image.Resampling.LANCZOS)
    icon = Image.new('RGBA', (ICON_SIZE, ICON_SIZE))
    icon.alpha_composite(crop, ((ICON_SIZE - crop.width) // 2, (ICON_SIZE - crop.height) // 2))
    return icon


for key, rel in SPECS.items():
    frames = stacked_frames(SOURCE / rel)
    atlas = Image.new('RGBA', (CELL * FRAMES, CELL))
    for i, f in enumerate(frames):
        atlas.alpha_composite(f, (i * CELL, 0))
    atlas.save(OUTPUT / f'fish_{key}.png')
    make_icon(frames[0]).save(OUTPUT / f'fish_{key}_icon.png')
    b = union_bounds(frames)
    print(f"fish_{key}: 图集 {atlas.size}  图标 {ICON_SIZE}×{ICON_SIZE}  "
          f"bounds = {{ {b[0]}, {b[1]}, {b[2]}, {b[3]} }}")
