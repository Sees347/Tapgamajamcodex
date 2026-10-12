"""裂钳蟹素材转运行图集（256/格，4 列 × 2 行 = 8 帧）。

素材特性：
- 移动/近战/远程 三套，各 4×2=8 帧；近战与远程的 8 帧实为「左螯 4 帧 + 右螯 4 帧」两组。
- 三套机身尺度不同（眼睛间距 87 / 97 / 96）。先按眼睛间距定标使机身一致，
  再用「该套全部帧的并集」做适配，保证抬螯等大动作不溢出格，且各帧以眼睛为锚点稳定。
- 石子是独立 4 帧序列（大石→飞行×2→碎裂），单独出图集。
"""
from pathlib import Path
import glob
import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path('/workspace')
SOURCE = ROOT / 'assets/image/敌人素材/裂钳蟹'
OUTPUT = ROOT / 'assets/image/runtime'

CELL = 256
COLS, ROWS = 4, 2
MARGIN = 2
ALPHA_TH = 10
TARGET_EYE = 52          # 归一化后的眼睛间距（格内像素）


def sheet_cells(path, cols, rows):
    im = Image.open(path).convert('RGBA')
    cw, ch = im.width // cols, im.height // rows
    return [im.crop((c * cw, r * ch, (c + 1) * cw, (r + 1) * ch))
            for r in range(rows) for c in range(cols)]


def content_box(im):
    ys, xs = np.where(np.asarray(im)[:, :, 3] > ALPHA_TH)
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def eye_center(im):
    """两只眼睛（面积相近、近似同高的白色团块）中点；失败退化为内容中心。"""
    arr = np.asarray(im).astype(int)
    r, g, b, a = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2], arr[:, :, 3]
    lab, n = ndimage.label((r > 235) & (g > 235) & (b > 235) & (a > ALPHA_TH))
    blobs = []
    for i in range(1, n + 1):
        ys, xs = np.where(lab == i)
        if 400 <= len(xs) <= 4000:
            blobs.append((int(xs.mean()), int(ys.mean()), len(xs)))
    best = None
    for i in range(len(blobs)):
        for j in range(i + 1, len(blobs)):
            x1, y1, a1 = blobs[i]
            x2, y2, a2 = blobs[j]
            if abs(y1 - y2) < 26 and 40 < abs(x1 - x2) < 150:
                score = min(a1, a2)
                if best is None or score > best[0]:
                    best = (score, (x1 + x2) / 2, (y1 + y2) / 2)
    if best:
        return best[1], best[2]
    bx = content_box(im)
    return (bx[0] + bx[2]) / 2, (bx[1] + bx[3]) / 2


def build_crab(key, sub, eye_sp):
    frames = sheet_cells(sorted(glob.glob(f'{SOURCE}/{sub}/*.png'))[0], COLS, ROWS)
    eyes = [eye_center(f) for f in frames]
    base = TARGET_EYE / eye_sp
    # 眼睛相对坐标下的并集
    minx = miny = 1e9
    maxx = maxy = -1e9
    for f, (ex, ey) in zip(frames, eyes):
        bx0, by0, bx1, by1 = content_box(f)
        minx = min(minx, (bx0 - ex) * base); maxx = max(maxx, (bx1 - ex) * base)
        miny = min(miny, (by0 - ey) * base); maxy = max(maxy, (by1 - ey) * base)
    fit = min(1.0, (CELL - MARGIN * 2) / (maxx - minx), (CELL - MARGIN * 2) / (maxy - miny))
    scale = base * fit
    # 并集中心落到格心 → 眼睛锚点位置
    ucx, ucy = (minx + maxx) / 2 * fit, (miny + maxy) / 2 * fit
    anchor_x, anchor_y = CELL / 2 - ucx, CELL / 2 - ucy

    atlas = Image.new('RGBA', (CELL * COLS, CELL * ROWS))
    cells = []
    for i, (f, (ex, ey)) in enumerate(zip(frames, eyes)):
        w, h = max(1, round(f.width * scale)), max(1, round(f.height * scale))
        resized = f.resize((w, h), Image.Resampling.LANCZOS)
        ox = round(anchor_x - ex * scale)
        oy = round(anchor_y - ey * scale)
        cx, cy = (i % COLS) * CELL, (i // COLS) * CELL
        atlas.alpha_composite(resized, (cx + ox, cy + oy))
        cells.append([ox, oy, ox + w, oy + h])
    atlas.save(OUTPUT / f'enemy_{key}.png')
    union = [min(c[0] for c in cells), min(c[1] for c in cells),
             max(c[2] for c in cells), max(c[3] for c in cells)]
    print(f"enemy_{key}: base={base:.3f} fit={fit:.3f} scale={scale:.3f} "
          f"bounds={{ {union[0]}, {union[1]}, {union[2]}, {union[3]} }}")


for key, sub, eye_sp in [('crab_move', '移动', 87), ('crab_melee', '近战攻击', 97),
                         ('crab_ranged', '远程攻击', 96)]:
    build_crab(key, sub, eye_sp)


def build_stone():
    stones = [f for f in sheet_cells(sorted(glob.glob(f'{SOURCE}/石子/*.png'))[0], 4, 1)]
    tight = []
    for s in stones:
        bx = content_box(s)
        tight.append(s.crop(bx))
    smax = max(max(t.width, t.height) for t in tight)
    scale = (CELL - MARGIN * 2) / smax
    atlas = Image.new('RGBA', (CELL * 4, CELL))
    cells = []
    for i, t in enumerate(tight):
        w, h = max(1, round(t.width * scale)), max(1, round(t.height * scale))
        resized = t.resize((w, h), Image.Resampling.LANCZOS)
        ox = i * CELL + (CELL - w) // 2
        oy = (CELL - h) // 2
        atlas.alpha_composite(resized, (ox, oy))
        cells.append([ox - i * CELL, oy, ox - i * CELL + w, oy + h])
    atlas.save(OUTPUT / 'enemy_crab_stone.png')
    u = [min(c[0] for c in cells), min(c[1] for c in cells), max(c[2] for c in cells), max(c[3] for c in cells)]
    print(f"enemy_crab_stone: scale={scale:.3f} bounds={{ {u[0]}, {u[1]}, {u[2]}, {u[3]} }}")


build_stone()
