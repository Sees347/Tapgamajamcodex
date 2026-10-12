#!/usr/bin/env python3
"""Quantify independent black/white seam coverage; never edit production trees."""
import argparse
import hashlib
import json
import re
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path('/workspace')
PREFIX = 'tile-seam-matrix-independent'


def tagged(log, tag):
    matches = re.findall(re.escape('[' + tag + ']') + r'\s+(\{[^\n]*\})', log)
    if not matches:
        raise ValueError(f'missing runtime tag {tag}')
    return json.loads(matches[-1])


def stats(a, b, mask):
    delta = np.abs(a.astype(np.int16) - b.astype(np.int16))
    values = delta[mask]
    if not len(values):
        raise ValueError('empty seam sample')
    per_pixel = values.max(axis=-1)
    return {
        'sampled_pixels': int(len(values)),
        'strict_nonzero_pixels': int(np.count_nonzero(per_pixel)),
        'pixels_over_rounding_tolerance_2': int(np.count_nonzero(per_pixel > 2)),
        'max_rgb_delta': int(values.max()),
        'mean_absolute_channel_delta': float(values.mean()),
        'delta_histogram': {str(i): int(n) for i, n in zip(*np.unique(per_pixel, return_counts=True))},
    }


def report_errors(report, log):
    noise, real = [], []
    for phase, detail in report.get('phases', {}).items():
        for error in detail.get('errors', []):
            item = dict(error, phase=phase)
            message = error['message']
            if 'texture3DLod' in message and 'compilation terminated' in message:
                item['noise_type'] = 'Mesa/GLES LUT shader texture3DLod overload compilation'
                noise.append(item)
            elif 'Frame time spike' in message:
                item['noise_type'] = 'software-render/initialization frame spike; not performance certification'
                noise.append(item)
            elif '[ShaderError]' in message or 'Could not initialize audio output' in message:
                item['noise_type'] = 'known headless environment noise'
                noise.append(item)
            else:
                real.append(item)
    unresolved = sorted(set(re.findall(r"DownloadManager: cannot resolve '([^']+)'", log)))
    targeted = [p for p in unresolved if p.startswith('image/地图/')]
    ready = sorted(set(re.findall(r'已读取真实图集：([^，\n]+)', log)))
    ready += sorted(set(re.findall(r'首载真实整图：([^，\n]+)', log)))
    targeted_unready = [p for p in targeted if p not in ready]
    return {
        'raw_result': report['result'],
        'frames_completed': report['frames_completed'],
        'summary': report['summary'],
        'test_result': report.get('test_result'),
        'test_assertions': report.get('test_assertions'),
        'missing_resources': report.get('missing_resources', []),
        'missing_engine_resources': report.get('missing_engine_resources', []),
        'known_environment_noise_count': len(noise),
        'noise_types': sorted(set(e['noise_type'] for e in noise)),
        'noise_records': noise,
        'unclassified_errors': real,
        'log_unresolved_resource_warning_paths': unresolved,
        'targeted_terrain_resource_warnings': targeted,
        'targeted_terrain_resources_not_finally_ready': targeted_unready,
        'final_ready_image_paths': ready,
        'max_frame_time_ms': report.get('max_frame_time_ms'),
        'script_resource_checks_pass': not real and not targeted_unready
            and report['summary']['lua_errors'] == 0 and report['summary']['resource_errors'] == 0
            and not report.get('missing_resources') and report['result'] != 'TIMEOUT'
            and report.get('test_result') == 'PASSED' and report['frames_completed'] >= 125,
    }


def analyze(size, same_position=False):
    suffix = '-black' if same_position else ''
    logfile = ROOT / 'validation' / f'{PREFIX}-{size}{suffix}.log'
    reportfile = ROOT / 'validation' / f'{PREFIX}-{size}{suffix}.json'
    shotfile = ROOT / 'screenshots' / f'{PREFIX}-{size}{suffix}.png'
    log = logfile.read_text()
    layout = tagged(log, 'TileSeamMatrixLayout')
    runtime_state = tagged(log, 'TileSeamMatrixFinal')
    report = json.loads(reportfile.read_text())
    image = Image.open(shotfile).convert('RGB')
    assert image.size == (layout['physicalW'], layout['physicalH'])
    assert layout['dpr'] == 1
    pixels = np.array(image)
    second_health = None
    second_shot = None
    if same_position:
        second_shot = ROOT / 'screenshots' / f'{PREFIX}-{size}-white.png'
        second_image = Image.open(second_shot).convert('RGB')
        assert second_image.size == image.size
        second_pixels = np.array(second_image)
        second_log = (ROOT / 'validation' / f'{PREFIX}-{size}-white.log').read_text()
        assert tagged(second_log, 'TileSeamMatrixLayout') == layout, 'same-position captures must have identical layout/geometry/UV'
        second_report = json.loads((ROOT / 'validation' / f'{PREFIX}-{size}-white.json').read_text())
        second_health = report_errors(second_report, second_log)
    measured = []
    crop_tiles = []
    for case in layout['cases']:
        x, y, w, h, shift = [int(case[k]) for k in ['x', 'y', 'w', 'h', 'whiteDeltaY']]
        black = pixels[y:y+h, x:x+w]
        white = second_pixels[y:y+h, x:x+w] if same_position else pixels[y+shift:y+shift+h, x:x+w]
        yy, xx = np.mgrid[:h, :w]
        inset = case['clipInset'] + 2
        visible = (xx >= inset) & (xx < w-inset) & (yy >= inset) & (yy < h-inset)
        if case['kind'] == 'walls':
            cp = layout['tileMetres'] * case['ppu']
            left = case['anchorX'] - 4 * cp
            top = case['anchorY'] - 4 * cp
            # Compare only four-neighbour opaque inner cells (2..7), not outer silhouettes.
            interior = visible & (xx + .5 > left + cp + 1) & (xx + .5 < left + 7*cp - 1) \
                & (yy + .5 > top + cp + 1) & (yy + .5 < top + 7*cp - 1)
            v = np.zeros((h,w), bool)
            hmask = np.zeros((h,w), bool)
            for boundary in range(2, 7):
                v |= np.abs(xx+.5 - (left + boundary*cp)) <= 2.5
                hmask |= np.abs(yy+.5 - (top + boundary*cp)) <= 2.5
            masks = {'vertical_internal_seams': interior & v,
                     'horizontal_internal_seams': interior & hmask}
            mask = interior & (v | hmask)
        else:
            image2, image3 = layout['originalBackgrounds']
            seam_y = layout['backgroundSeamY']
            heights = [bg['width'] * 2106 / 6443 for bg in [image2, image3]]
            upper_world = min(bg['y']+height/2 for bg,height in zip([image2,image3],heights))
            lower_world = max(bg['y']-height/2 for bg,height in zip([image2,image3],heights))
            upper_pixel = case['anchorY'] - (upper_world - seam_y)*case['ppu']
            lower_pixel = case['anchorY'] - (lower_world - seam_y)*case['ppu']
            mask = visible & (np.abs(xx+.5-case['anchorX']) <= 2.5) \
                & (yy+.5 > upper_pixel+2) & (yy+.5 < lower_pixel-2)
            masks = {'background23_center_vertical_seam': mask}
        quant = stats(black, white, mask)
        sample = black[mask]
        # These guards detect unrendered scenes, swapped/empty black-white panels,
        # and a comparator insensitive to actual leaks.
        underlay_black = black[1, 1].tolist()
        underlay_white = white[1, 1].tolist()
        marker_delta = int(np.abs(black[3,3].astype(np.int16)-white[3,3].astype(np.int16)).max())
        guards = {
            'black_gutter_rgb': underlay_black,
            'white_gutter_rgb': underlay_white,
            'half_alpha_marker_max_delta': marker_delta,
            'texture_distinct_rgb_values_on_seams': int(len(np.unique(sample, axis=0))),
            'all_samples_nonblack': bool(np.all(np.any(sample > 0, axis=1))),
            'underlay_and_marker_checks_pass': underlay_black == [0,0,0]
                and underlay_white == [255,255,255] and marker_delta > 100,
        }
        measured.append(dict(case, **quant, guards=guards,
            axis_stats={name: stats(black,white,m) for name,m in masks.items()}))
        if same_position:
            second_black = pixels[y+shift:y+shift+h, x:x+w]
            second_white = second_pixels[y+shift:y+shift+h, x:x+w]
            measured[-1]['same_position_bottom_repeat'] = stats(second_black, second_white, mask)
        # Contact sheet: black render, white render, exaggerated RGB diff.
        # Dark green in the diff shows measured seam pixels with strict zero delta.
        delta = np.abs(black.astype(np.int16)-white.astype(np.int16)).max(axis=2)
        diff = np.repeat(np.clip(delta[:,:,None]*40,0,255),3,axis=2).astype(np.uint8)
        diff[mask & (delta == 0)] = [15,35,15]
        preview = Image.new('RGB', (w*3,h+26), (28,28,36))
        draw = ImageDraw.Draw(preview)
        draw.text((3,3), f"{size} {case['mode']} H{case['viewH']} {case['kind']} off{case['offsetX']} max{quant['max_rgb_delta']}", fill='white')
        for i, arr in enumerate([black,white,diff]):
            preview.paste(Image.fromarray(arr), (i*w,26))
        crop_tiles.append(preview)
    health = report_errors(report, log)
    return {
        'resolution': size, 'screenshot': str(shotfile), 'runtime_report': str(reportfile),
        'runtime_log': str(logfile), 'runtime_state': runtime_state,
        'layout': layout, 'health': health, 'second_capture_health': second_health,
        'second_screenshot': str(second_shot) if second_shot else None,
        'comparison': 'same pixel position across black/white runs' if same_position else 'top/bottom integer translation within one run',
        'cases': measured,
        'strict_nonzero_pixels': sum(c['strict_nonzero_pixels'] for c in measured),
        'pixels_over_rounding_tolerance_2': sum(c['pixels_over_rounding_tolerance_2'] for c in measured),
        'max_rgb_delta': max(c['max_rgb_delta'] for c in measured),
        'sampled_pixels': sum(c['sampled_pixels'] for c in measured),
    }, crop_tiles


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--sizes', nargs='+', default=['1280x720','1920x1080','2560x1440'])
    parser.add_argument('--same-position', action='store_true')
    args=parser.parse_args()
    output_suffix = '-same-position' if args.same_position else ''
    runs=[]
    tiles=[]
    for size in args.sizes:
        result, images=analyze(size, same_position=args.same_position)
        runs.append(result)
        tiles.extend(images)
        print(size, 'samples',result['sampled_pixels'], 'nonzero',result['strict_nonzero_pixels'],
              '>2',result['pixels_over_rounding_tolerance_2'], 'max',result['max_rgb_delta'],
              'health',result['health']['script_resource_checks_pass'])
    # Fixed thumbnail widths preserve nearest-neighbour differences; metrics use
    # original raw pixel dimensions, never this resized contact sheet.
    thumb_w=480
    thumbs=[]
    for tile in tiles:
        ratio=thumb_w/tile.width
        thumbs.append(tile.resize((thumb_w,max(52,round(tile.height*ratio))),Image.Resampling.NEAREST))
    row_h=max(t.height for t in thumbs)
    sheet=Image.new('RGB',(thumb_w*4,row_h*((len(thumbs)+3)//4)),(12,12,16))
    for i,thumb in enumerate(thumbs):
        sheet.paste(thumb,((i%4)*thumb_w,(i//4)*row_h))
    contact=ROOT/'screenshots'/f'{PREFIX}{output_suffix}-contact-sheet.png'
    sheet.save(contact)
    result={
        'version':1, 'method':('two runs with identical geometry/UV and different underlay; same-position RGB absolute difference' if args.same_position else 'same screenshot top/bottom paired underlay; integer translation may perturb nearest UV'),
        'matrix':{'resolutions':args.sizes,'game_viewH':[8,16,26],'editor_viewH':[4,80],
                  'subpixel_offsets_xy':[0,.25,.5,.75],'subjects':['wall_internal_horizontal_vertical','background23_center_vertical'],
                  'ppu_rule':'full logical screen height / viewH; original 1m grid and original image metre dimensions'},
        'rounding_tolerance':2, 'runtime_binary_sha256':hashlib.sha256((ROOT/'.cli/UrhoXRuntime').read_bytes()).hexdigest(),
        'case_count':sum(len(r['cases']) for r in runs), 'sampled_pixels':sum(r['sampled_pixels'] for r in runs),
        'strict_nonzero_pixels':sum(r['strict_nonzero_pixels'] for r in runs),
        'pixels_over_rounding_tolerance_2':sum(r['pixels_over_rounding_tolerance_2'] for r in runs),
        'max_rgb_delta':max(r['max_rgb_delta'] for r in runs),
        'all_cases_strict_zero':all(c['strict_nonzero_pixels']==0 for r in runs for c in r['cases']),
        'all_cases_within_rounding_tolerance':all(c['pixels_over_rounding_tolerance_2']==0 for r in runs for c in r['cases']),
        'all_runtime_script_resource_checks_pass':all(r['health']['script_resource_checks_pass'] and (r['second_capture_health'] is None or r['second_capture_health']['script_resource_checks_pass']) for r in runs),
        'bottom_repeat_sampled_pixels':sum(c.get('same_position_bottom_repeat',{}).get('sampled_pixels',0) for r in runs for c in r['cases']),
        'bottom_repeat_strict_nonzero_pixels':sum(c.get('same_position_bottom_repeat',{}).get('strict_nonzero_pixels',0) for r in runs for c in r['cases']),
        'bottom_repeat_max_rgb_delta':max(c.get('same_position_bottom_repeat',{}).get('max_rgb_delta',0) for r in runs for c in r['cases']),
        'all_comparator_guards_pass':all(c['guards']['underlay_and_marker_checks_pass'] and c['guards']['all_samples_nonblack'] for r in runs for c in r['cases']),
        'contact_sheet':str(contact), 'runs':runs,
        'limitations':['Linux Mesa llvmpipe/GLES offscreen DPR1 only; not Unity or mobile/GPU validation',
                       'Static controlled shared-seam pixels only, not outer silhouettes, gameplay/camera motion, FPS or real-time smoothness',
                       'Editor scenarios call actual shared TS.drawLayer(editor=true) with canvas-style clip, not interactive editor UI',
                       'Strict nonzero and <=2-code rounding tolerance are both reported; tolerance is not silently called zero',
                       'Default filters retained: production tiles nearest, production background default linear'],
    }
    path=ROOT/'validation'/f'{PREFIX}{output_suffix}-quantitative.json'
    path.write_text(json.dumps(result,ensure_ascii=False,indent=2))
    print('saved',path,'and',contact)


if __name__=='__main__':
    main()
