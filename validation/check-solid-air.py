from pathlib import Path
import hashlib
import json
root=Path('/workspace')
baseline=json.loads((root/'validation/solid-air-baseline.json').read_text())
changed=[]
for file,sha in baseline.items():
    p=root/file
    if hashlib.sha256(p.read_bytes()).hexdigest()!=sha:
        changed.append(file)
assert set(changed)=={'scripts/core/art.lua','scripts/data/art.lua'},changed
report={'passed':True,'changed':changed,'all_images_unchanged':True,'other_gameplay_unchanged':True}
(root/'validation/solid-air-assets.json').write_text(json.dumps(report,indent=2))
print(report)
