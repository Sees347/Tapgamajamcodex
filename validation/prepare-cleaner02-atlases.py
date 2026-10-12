"""把清洁机器人-002 的逐帧素材转成运行图集（256/格，4 列 × 2 行 = 8 帧）。

素材为 Idle / Attack 两个目录、每目录 8 张独立 PNG（该怪站定射击，无 Move）。
同一套内画布尺寸一致，机身会在画布内摆动——保留该位移，只把内容底边对齐统一
下沿，并让两套共用同一缩放系数。
"""
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path('/workspace')
SOURCE = ROOT / 'assets/image/敌人素材/清洁机器人002'
OUTPUT = ROOT / 'assets/image/runtime'

SPECS = {
    'cleaner02_idle': 'Idle',
    'cleaner02_attack': 'Attack',
}

COLS, ROWS = 4, 2
CELL = 256
MARGIN = 2
BASELINE = CELL - MARGIN - 1
ALPHA_TH = 8


def frames_of(sub):
    return [Image.open(f).convert('RGBA') for f in sorted((SOURCE / sub).glob('*.png'))]


def content_box(im):
    ys, xs = np.where(np.asarray(im)[:, :, 3] > ALPHA_TH)
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


all_frames = {k: frames_of(v) for k, v in SPECS.items()}
max_w = max(f.width for fs in all_frames.values() for f in fs)
limit = CELL - MARGIN * 2
scale = limit / max_w

for key, frames in all_frames.items():
    atlas = Image.new('RGBA', (CELL * COLS, CELL * ROWS))
    cells = []
    for i, f in enumerate(frames):
        w, h = max(1, round(f.width * scale)), max(1, round(f.height * scale))
        resized = f.resize((w, h), Image.Resampling.LANCZOS)
        cx, cy = (i % COLS) * CELL, (i // COLS) * CELL
        bx, by, bx2, by2 = content_box(f)
        ox = cx + (CELL - w) // 2
        oy = cy + BASELINE - round(by2 * scale)
        atlas.alpha_composite(resized, (ox, oy))
        cells.append([ox - cx + round(bx * scale), oy - cy + round(by * scale),
                      ox - cx + round(bx2 * scale), oy - cy + round(by2 * scale)])
    atlas.save(OUTPUT / f'enemy_{key}.png')
    union = [min(c[0] for c in cells), min(c[1] for c in cells),
             max(c[2] for c in cells), max(c[3] for c in cells)]
    print(f"enemy_{key}: 图集 {atlas.size}  {len(frames)} 帧  bounds={{ {union[0]}, {union[1]}, {union[2]}, {union[3]} }}")

print(f"共用缩放 = {scale:.4f}（最宽画布 {max_w}px）")
