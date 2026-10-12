"""把清洁机器人-001 的逐帧素材转成运行图集（256/格，4 列 × 2 行 = 8 帧）。

与喷孢菌不同，这套素材是 Idle/Move/Attack 三个目录、每目录 8 张独立 PNG。
同一套内画布尺寸一致，机身会在画布内左右摆动/上下起伏——这正是动画本身，
因此**不做逐帧居中**：三套用同一缩放系数，各帧按原画布位置放入格内，
只把“内容底边”对齐到统一下沿，保留摆动与起伏。
"""
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path('/workspace')
SOURCE = ROOT / 'assets/image/敌人素材/清洁机器人001'
OUTPUT = ROOT / 'assets/image/runtime'

# 未用待机动画（敌人只在移动/攻击间切换），故不生成 Idle 图集。
SPECS = {
    'cleaner01_move': 'Move',
    'cleaner01_attack': 'Attack',
}

COLS, ROWS = 4, 2
CELL = 256
MARGIN = 2
BASELINE = CELL - MARGIN - 1   # 内容底边对齐到该 y（格内坐标）
ALPHA_TH = 8


def frames_of(sub):
    files = sorted((SOURCE / sub).glob('*.png'))
    return [Image.open(f).convert('RGBA') for f in files]


def content_box(im):
    ys, xs = np.where(np.asarray(im)[:, :, 3] > ALPHA_TH)
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


# 三套共用缩放：以最宽画布适配格内，保证机身大小在各动画间一致。
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
        # 水平居中画布（保留机身原位置的摆动），内容底边对齐统一下沿。
        cx = (i % COLS) * CELL
        cy = (i // COLS) * CELL
        bx, by, bx2, by2 = content_box(f)
        ox = cx + (CELL - w) // 2
        oy = cy + BASELINE - round(by2 * scale)
        atlas.alpha_composite(resized, (ox, oy))
        # 该帧内容在“单格局部坐标”下的范围
        cells.append([ox - cx + round(bx * scale), oy - cy + round(by * scale),
                      ox - cx + round(bx2 * scale), oy - cy + round(by2 * scale)])
    atlas.save(OUTPUT / f'enemy_{key}.png')
    union = [min(c[0] for c in cells), min(c[1] for c in cells),
             max(c[2] for c in cells), max(c[3] for c in cells)]
    print(f"enemy_{key}: 图集 {atlas.size}  {len(frames)} 帧  bounds={{ {union[0]}, {union[1]}, {union[2]}, {union[3]} }}")

print(f"共用缩放 = {scale:.4f}（最宽画布 {max_w}px）")
