"""把趋光菌兽的图集素材转成运行图集（256/格，4 列 × 2 行 = 8 帧）。

素材为 Idle / Move / Attack 三个目录、每目录一张 4×2 的 spritesheet。
与喷孢菌同款：逐格裁剪后全帧统一缩放、居中入格，保留动画本身的位移。
"""
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path('/workspace')
SOURCE = ROOT / 'assets/image/敌人素材/趋光菌兽'
OUTPUT = ROOT / 'assets/image/runtime'

SPECS = {
    'lightseeker_idle': 'Idle',
    'lightseeker_move': 'Move',
    'lightseeker_attack': 'Attack',
}

COLS, ROWS = 4, 2
CELL = 256
MARGIN = 2
ALPHA_TH = 8


def frame_cells(path):
    im = Image.open(path).convert('RGBA')
    cw, ch = im.width // COLS, im.height // ROWS
    return [im.crop((c * cw, r * ch, (c + 1) * cw, (r + 1) * ch))
            for r in range(ROWS) for c in range(COLS)]


def tight(im):
    ys, xs = np.where(np.asarray(im)[:, :, 3] > ALPHA_TH)
    return im.crop((int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1))


# 三套共用缩放，保证各动画间体型一致
all_frames = {k: [tight(f) for f in frame_cells(SOURCE / v / 'spritesheet.png')]
              for k, v in SPECS.items()}
limit = CELL - MARGIN * 2
scale = min(limit / max(f.width for fs in all_frames.values() for f in fs),
            limit / max(f.height for fs in all_frames.values() for f in fs))

for key, frames in all_frames.items():
    atlas = Image.new('RGBA', (CELL * COLS, CELL * ROWS))
    cells = []
    for i, f in enumerate(frames):
        w, h = max(1, round(f.width * scale)), max(1, round(f.height * scale))
        resized = f.resize((w, h), Image.Resampling.LANCZOS)
        cx, cy = (i % COLS) * CELL, (i // COLS) * CELL
        ox = cx + (CELL - w) // 2
        oy = cy + (CELL - h) // 2
        atlas.alpha_composite(resized, (ox, oy))
        cells.append([ox - cx, oy - cy, ox - cx + w, oy - cy + h])
    atlas.save(OUTPUT / f'enemy_{key}.png')
    union = [min(c[0] for c in cells), min(c[1] for c in cells),
             max(c[2] for c in cells), max(c[3] for c in cells)]
    print(f"enemy_{key}: 图集 {atlas.size}  {len(frames)} 帧  bounds={{ {union[0]}, {union[1]}, {union[2]}, {union[3]} }}")

print(f"共用缩放 = {scale:.4f}")
