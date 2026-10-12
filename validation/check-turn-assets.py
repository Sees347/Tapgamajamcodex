import json
import hashlib
from pathlib import Path
import numpy as np
from PIL import Image
from scipy.ndimage import label

ROOT = Path('/workspace')
baseline = json.loads((ROOT / 'validation/turn-original-hashes.json').read_text())
changed = []
for name, sha in baseline.items():
    path = ROOT / name
    if hashlib.sha256(path.read_bytes()).hexdigest() != sha:
        changed.append(name)
print('changed:', changed)
assert set(changed) == {'scripts/core/art.lua', 'scripts/data/art.lua', 'assets/image/runtime/liquid_turn.png'}
report = {}
for form in ('liquid', 'solid', 'gas'):
    for key in ('idle', 'turn'):
        image = Image.open(ROOT / f'assets/image/runtime/{form}_{key}.png').convert('RGBA')
        count = 4 if key == 'idle' and form == 'gas' or key == 'turn' and form == 'solid' else 8 if key == 'idle' else 5
        boxes = []
        for i in range(count):
            x, y = i % 4 * 256 + 2, i // 4 * 256 + 2
            a = np.asarray(image.crop((x, y, x + 252, y + 252)))
            ids, _ = label(a[:, :, 3] > 80)
            sizes = np.bincount(ids.ravel())
            sizes[0] = 0
            ys, xs = np.where(ids == sizes.argmax())
            boxes.append([int(xs.min()), int(ys.min()), int(xs.max()+1), int(ys.max()+1)])
        report[f'{form}_{key}'] = boxes
        print(form, key, boxes)
(ROOT / 'validation/turn-size-audit.json').write_text(json.dumps(report,indent=2))
(ROOT / 'validation/turn-hash-check.json').write_text(json.dumps({'changed':changed,'non_target_unchanged':True},indent=2))
