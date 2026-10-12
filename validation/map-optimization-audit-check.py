import json,hashlib,tarfile
from pathlib import Path
root=Path('/workspace');base=root/'backups/map-optimization-20261012T095449Z'
m=json.loads((base/'manifest.json').read_text())
changed=[]
with tarfile.open(base/'before.tar.gz') as tar:
 for f in m['files']:
  assert hashlib.sha256(tar.extractfile(f['path']).read()).hexdigest()==f['sha256']
  p=root/f['path']
  if p.exists() and hashlib.sha256(p.read_bytes()).hexdigest()!=f['sha256']:
   changed.append(f['path'])
   if f['path'].startswith('.project/'):
    print(f['path'],'BEFORE:',tar.extractfile(f['path']).read().decode()[:3500],'AFTER:',p.read_text()[:3500])
print('changed',changed)
for name in ['map-camera-verified','map-fill-retry','terrain-groups-complete']:
 p=root/'validation'/f'{name}.json'
 if p.exists():
  r=json.loads(p.read_text());print(name,r['result'],r['summary'],r['test_assertions'],r.get('test_issues'))
else: pass
