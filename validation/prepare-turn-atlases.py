"""审核三态转身配色并生成运行图集；原始上传素材保持不变。"""
from pathlib import Path
import hashlib
import json
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import label
from skimage.color import rgb2lab, lab2rgb, deltaE_ciede2000

ROOT = Path('/workspace')
SOURCE = ROOT / 'assets/image/PlayerAnim'
OUTPUT = ROOT / 'assets/image/runtime'
AUDIT = ROOT / 'validation'
SPECS = {
    # 液态现改用主角纹理补出的背侧转身，独立由 prepare-liquid-backturn.py 维护。
    # 本脚本只重建固态/气态，不能将液态恢复为正面转身。
    'solid': ('exec-c014650d-15e4-407c-95f2-4f60193a2e3d.png', [3, 2, 1, 0], 193.0),
    'gas': ('exec-558eda89-528c-4c43-9fee-7ecf855b783b.png', [0, 1, 2, 4, 5], 209.0),
}


def frame_cells(image):
    # 1774/4 和 887/2 均为半像素，按完整画布比例四舍五入，不能丢边缘列。
    return [image.crop((round(i % 4 * image.width / 4), round(i // 4 * image.height / 2),
                        round((i % 4 + 1) * image.width / 4), round((i // 4 + 1) * image.height / 2)))
            for i in range(8)]


def pixels(image):
    arr = np.asarray(image.convert('RGBA'))
    rgb = arr[:, :, :3][arr[:, :, 3] > 80].astype(float) / 255
    return rgb2lab(rgb.reshape(-1, 1, 3)).reshape(-1, 3)


def main_body_bounds(image):
    arr = np.asarray(image)
    ids, count = label(arr[:, :, 3] > 80)
    areas = np.bincount(ids.ravel())
    areas[0] = 0
    main = ids == np.argmax(areas)
    ys, xs = np.where(main)
    return (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)


def mapping(source, target):
    # 同一形态的所有帧共用一套 LUT，避免逐帧统计引起闪色。
    quantiles = np.linspace(0, 100, 101)
    old_l = np.percentile(source[:, 0], quantiles)
    new_l = np.percentile(target[:, 0], quantiles)
    levels = np.arange(101, dtype=float)
    unique_l, first = np.unique(old_l, return_index=True)
    mapped_l = np.interp(levels, unique_l, new_l[first])
    # 深色眼线与白色高光保持层次，避免把暗部阴影硬改成白色。
    mapped_l = np.maximum.accumulate(np.clip(mapped_l, levels - 9, levels + 9))
    if float(np.median(target[:, 0]) - np.median(source[:, 0])) < 3:
        # 水/冰原色差很小，用平滑色温修正即可，避免过度直方图匹配弄平材质。
        mapped_l = levels + np.clip(float(target[:, 0].mean() - source[:, 0].mean()), -3, 3)
    chroma = []
    for group, ls in ((source, levels), (target, mapped_l)):
        values = []
        for level_l in ls:
            chosen = group[np.abs(group[:, 0] - level_l) <= 5]
            values.append(np.median(chosen[:, 1:], axis=0) if len(chosen) > 100 else np.median(group[:, 1:], axis=0))
        chroma.append(np.array(values))
    change = np.clip(chroma[1] - chroma[0], -6, 6)
    if abs(float(target[:, 0].mean() - source[:, 0].mean())) < 3:
        change[:] = np.clip(target[:, 1:].mean(0) - source[:, 1:].mean(0), -3, 3)
    return levels, mapped_l, change


def recolor(image, lut, reference, form):
    arr = np.array(image.convert('RGBA'))
    alpha = arr[:, :, 3].copy()
    mask = alpha > 0
    rgb = arr[:, :, :3][mask].astype(float) / 255
    lab = rgb2lab(rgb.reshape(-1, 1, 3)).reshape(-1, 3)
    levels, new_l, delta = lut
    light = lab[:, 0].copy()
    lab[:, 0] = np.interp(light, levels, new_l)
    # 只对阴影/主体/高光作连续色温修正，不破坏青蓝眼睛的饱和度。
    chroma = np.linalg.norm(lab[:, 1:], axis=1)
    strength = np.clip((45 - chroma) / 20, 0, 1)
    for axis in range(2):
        lab[:, axis + 1] += np.interp(light, levels, delta[:, axis]) * strength
    fixed = lab2rgb(lab.reshape(-1, 1, 3)).reshape(-1, 3)
    arr[:, :, :3][mask] = np.clip(np.round(fixed * 255), 0, 255).astype(np.uint8)
    if form in ('liquid', 'solid'):
        # 上传帧主体几乎全不透明；现有水/冰为半透明材质。只统一材质透明度，
        # 不新增/删掉轮廓像素，眼线与高光沿用其对应亮度的参考透明度。
        # 使用平滑的主体/高光透明度曲线，不逐色阶取中位数，避免半透明斑点。
        ref = np.concatenate([np.asarray(image).reshape(-1, 4) for image in reference])
        ref = ref[ref[:, 3] > 80]
        base = float(np.median(ref[:, 3])) / 253
        highlight = np.clip((lab[:, 0] - 90) / 10, 0, 1)
        highlight = highlight * highlight * (3 - 2 * highlight)
        factor = base + (1 - base) * highlight
        arr[:, :, 3][mask] = np.maximum(1, np.round(alpha[mask] * factor)).astype(np.uint8)
    else:
        assert np.array_equal(alpha, arr[:, :, 3]), '气态不改变透明度'
    assert np.array_equal(alpha > 0, arr[:, :, 3] > 0), '不允许改变轮廓覆盖'
    return Image.fromarray(arr)


def summary(samples):
    return {'lab_mean': np.round(samples.mean(0), 3).tolist(),
            'lab_median': np.round(np.median(samples, 0), 3).tolist()}


report = {'source_preserved': True, 'forms': {}}
contact = Image.new('RGB', (8 * 160, 3 * 3 * 190), (20, 25, 40))
draw = ImageDraw.Draw(contact)
for row, (form, (file, indexes, height)) in enumerate(SPECS.items()):
    path = SOURCE / file
    original_hash = hashlib.sha256(path.read_bytes()).hexdigest()
    source = Image.open(path).convert('RGBA')
    cells = frame_cells(source)
    frames = [cells[i] for i in indexes]
    source_samples = np.concatenate([pixels(f) for f in frames])
    idle = Image.open(OUTPUT / f'{form}_idle.png').convert('RGBA')
    move = Image.open(OUTPUT / f'{form}_move.png').convert('RGBA')
    target_samples = np.concatenate([pixels(idle), pixels(move)])
    lut = mapping(source_samples, target_samples)
    corrected = [recolor(f, lut, [idle, move], form) for f in frames]
    corrected_samples = np.concatenate([pixels(f) for f in corrected])
    # 用主体而非游离泡泡确定统一尺寸；同帧表使用统一缩放，保留挤压变化。
    boxes = [main_body_bounds(f) for f in frames]
    max_height = max(b[3] - b[1] for b in boxes)
    scale = height / max_height
    center_x = float(np.median([(b[0] + b[2]) / 2 for b in boxes]))
    bottom_y = float(np.median([b[3] for b in boxes]))
    pivot_x, pivot_y = 126, 126
    atlas = Image.new('RGBA', (1024, ((len(frames) + 3) // 4) * 256))
    packed = []
    for i, frame in enumerate(corrected):
        resized = frame.resize((round(frame.width * scale), round(frame.height * scale)), Image.Resampling.LANCZOS)
        # 固定基线与锚点，各帧不单独拉伸或追着包围盒缩放。
        dx = round(pivot_x - center_x * scale)
        dy = round(pivot_y + height / 2 - bottom_y * scale)
        cell = Image.new('RGBA', (252, 252))
        cell.alpha_composite(resized, (dx, dy))
        atlas.alpha_composite(cell, (i % 4 * 256 + 2, i // 4 * 256 + 2))
        packed.append(cell)
    atlas.save(OUTPUT / f'{form}_turn.png')
    assert hashlib.sha256(path.read_bytes()).hexdigest() == original_hash
    before = float(deltaE_ciede2000(source_samples.mean(0), target_samples.mean(0)))
    after = float(deltaE_ciede2000(corrected_samples.mean(0), target_samples.mean(0)))
    report['forms'][form] = {
        'source': str(path.relative_to(ROOT)), 'source_sha256': original_hash,
        'contour_coverage_preserved_before_resizing': True,
        'opacity_adjusted': form in ('liquid', 'solid'),
        'source_frames': [i + 1 for i in indexes], 'frame_count': len(frames),
        'reference': [f'image/runtime/{form}_idle.png', f'image/runtime/{form}_move.png'],
        'before': summary(source_samples), 'reference_colors': summary(target_samples),
        'after': summary(corrected_samples),
        'mean_color_delta_e_before': round(before, 3), 'mean_color_delta_e_after': round(after, 3),
        'sheet': f'image/runtime/{form}_turn.png', 'sheet_size': list(atlas.size),
        'pivot': [pivot_x, pivot_y], 'source_height': height,
    }
    print(form, 'frames',len(frames),'mean ΔE',round(before,2),'->',round(after,2),'body boxes',boxes)
    # 每组：参考/校色前/校色后，方便审核色温而非仅看平均数字。
    ref = idle.crop((2, 2, 254, 254))
    display_rows = [(f'{form} reference', [ref]), (f'{form} original', frames), (f'{form} matched', packed)]
    for k, (name, images) in enumerate(display_rows):
        y = row * 570 + k * 190
        draw.text((5,y+3), name,fill='white')
        for col, image in enumerate(images):
            image = image.copy()
            image.thumbnail((150,155),Image.Resampling.LANCZOS)
            contact.paste(image,(col*160+5,y+25),image)
contact.save(AUDIT / 'turn-color-comparison.png')
(AUDIT / 'turn-color-audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
