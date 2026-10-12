"""把喷孢菌的待机/攻击素材转成运行图集（256/格，4 列 × 2 行 = 8 帧）。

源图约定：1448 宽，横向 4 列、纵向 2 行，共 8 帧（不是上下叠合，逐格即一帧）。
与其它运行图集一致：每格 256，内容四周留 2px，采样时按 +2 内缩取 252。
原始素材保留在 image/敌人素材，不参与运行包。
"""
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path('/workspace')
SOURCE = ROOT / 'assets/image/敌人素材/喷孢菌'
OUTPUT = ROOT / 'assets/image/runtime'

SPECS = {
    'spore_idle': 'Idle/spritesheet-final.png',
    'spore_attack': 'Attack/spritesheet-final.png',
}

COLS, ROWS = 4, 2
CELL = 256
MARGIN = 2          # 每格内缩，采样侧同样按 +2 取 252
ALPHA_TH = 8


def frame_cells(path):
    im = Image.open(path).convert('RGBA')
    cw, ch = im.width // COLS, im.height // ROWS
    return [im.crop((c * cw, r * ch, (c + 1) * cw, (r + 1) * ch))
            for r in range(ROWS) for c in range(COLS)]


def tight(im):
    ys, xs = np.where(np.asarray(im)[:, :, 3] > ALPHA_TH)
    return im.crop((int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1))


def build(key, rel):
    frames = [tight(f) for f in frame_cells(SOURCE / rel)]
    # 全帧统一缩放：按最大边适配到格内，避免各帧尺寸不一导致播放时忽大忽小。
    limit = CELL - MARGIN * 2
    scale = min(limit / max(f.width for f in frames), limit / max(f.height for f in frames))
    atlas = Image.new('RGBA', (CELL * COLS, CELL * ROWS))
    cells = []   # 各帧在“单格局部坐标”(0..256) 下的范围
    for i, f in enumerate(frames):
        w, h = max(1, round(f.width * scale)), max(1, round(f.height * scale))
        resized = f.resize((w, h), Image.Resampling.LANCZOS)
        ox = (i % COLS) * CELL + (CELL - w) // 2
        oy = (i // COLS) * CELL + (CELL - h) // 2
        atlas.alpha_composite(resized, (ox, oy))
        cx, cy = ox - (i % COLS) * CELL, oy - (i // COLS) * CELL
        cells.append([cx, cy, cx + w, cy + h])
    atlas.save(OUTPUT / f'enemy_{key}.png')
    union = [min(c[0] for c in cells), min(c[1] for c in cells),
             max(c[2] for c in cells), max(c[3] for c in cells)]
    print(f"enemy_{key}: 图集 {atlas.size}  {len(frames)} 帧  单格bounds={{ {union[0]}, {union[1]}, {union[2]}, {union[3]} }}")
    return cells, union


for key, rel in SPECS.items():
    build(key, rel)
