from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import json,hashlib,tarfile
root=Path('/workspace');base=root/'backups/map-optimization-20261012T095449Z'
manifest=json.loads((base/'manifest.json').read_text())
old={x['path']:x for x in manifest['files']}
files=['scripts/core/editor_render.lua','scripts/core/render.lua','scripts/core/terrain_tiles.lua','scripts/core/tile_render.lua','scripts/core/tilemap.lua','scripts/core/tilesets.lua','scripts/main.lua','scripts/tests/industrial_tiles_validation.lua']
new=['scripts/core/camera_bounds.lua','scripts/core/grid_regions.lua','scripts/tests/camera_bounds_pure.lua','scripts/tests/map_optimization_validation.lua','scripts/tests/terrain_groups_validation.lua','assets/image/地图/tiles/industrial_wall_fill.png']
media=root/'assets/image/validation';media.mkdir(parents=True,exist_ok=True)
font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',20)
for name,paths in [('map-optimization-comparison',['map-optimization-visual-before.png','map-optimization-visual-after.png']),('map-camera-edge-comparison',['map-optimization-before.png','map-optimization-visual-after.png'])]:
 out=media/(name+'.png');assert not out.exists()
 ims=[Image.open(root/'screenshots'/p).convert('RGB') for p in paths]
 assert all(i.size==(1920,1080) for i in ims)
 sheet=Image.new('RGB',(1920,584),(22,27,36));d=ImageDraw.Draw(sheet)
 d.text((20,12),'BEFORE',font=font,fill='white');d.text((980,12),'AFTER',font=font,fill='white')
 for i,im in enumerate(ims):sheet.paste(im.resize((960,540),Image.Resampling.LANCZOS),(960*i,44))
 sheet.save(out)
source=(root/'assets/image/地图/tiles/industrial_walls.png')
provenance=json.loads((root/'validation/map-fill-provenance.json').read_text())
assert hashlib.sha256(source.read_bytes()).hexdigest()==provenance['source_sha256']
with tarfile.open(base/'before.tar.gz') as tar:
 for f in manifest['files']:assert hashlib.sha256(tar.extractfile(f['path']).read()).hexdigest()==f['sha256']
assert hashlib.sha256((root/'scripts/levels/world_src.lua').read_bytes()).hexdigest()==old['scripts/levels/world_src.lua']['sha256']
assert hashlib.sha256((root/'.project/settings.json').read_bytes()).hexdigest()==old['.project/settings.json']['sha256']
reports={}
for name in ['map-optimization-collision','map-optimization-physics','map-optimization-gameplay','map-optimization-industrial','terrain-groups-complete','map-camera-verified','map-optimization-visual-after','map-fill-retry']:
 r=json.loads((root/'validation'/f'{name}.json').read_text())
 reports[name]={'raw_result':r['result'],'frames':r['frames_completed'],'summary':r['summary'],'assertions':r['test_assertions'],'issues':r.get('test_issues',[])}
audit={'backup':str(base.relative_to(root)),'backup_files_verified':len(manifest['files']),
 'modified_by_this_task':[{'path':p,'before_sha256':old[p]['sha256'],'after_sha256':hashlib.sha256((root/p).read_bytes()).hexdigest()} for p in files],
 'added_by_this_task':[{'path':p,'sha256':hashlib.sha256((root/p).read_bytes()).hexdigest(),'meta_exists':Path(str(root/p)+'.meta').exists()} for p in new],
 'preserved':['shared world_src grid and layout SHA256 unchanged','original industrial_walls PNG SHA256 unchanged','all original resource UUIDs unchanged','settings.json restored byte-for-byte to snapshot'],
 'concurrent_change_not_overwritten':'scripts/core/art.lua liquid_move pivot changed outside this task; preserved, not part of map rollback',
 'metrics':{'solid_cells':9684,'checked_cells':60000,'terrain_rects_before':320,'terrain_rects_after':91,'independent_crates':91,'global_interior_groups':661,'boundary_cells':2221,'visible_cells':216,'visible_fill_submissions':105,'extra_boundary_interior_fill':1,'note':'2882 geometry groups plus one boundary-interior fill if entire map visible; not a measured GPU drawcall or FPS claim'},
 'reports':reports,'seam_matrix':json.loads((root/'validation/map-fill-matrix-result.json').read_text()),
 'material_provenance':provenance,
 'rollback':{'tar':'before.tar.gz','manifest':'manifest.json','map_only_restore':files,'added_files_to_remove_only_if_hash_matches':new,'keep_other_changes':True,'require_official_build_after_restore':True,'not_executed':True},
 'limits':['Linux surfaceless screenshots raw FAIL with known LUT texture3DLod shader errors; retry run also corrupted shader binary/frame spikes; Lua/resources zero, assertions pass','No Unity runtime, physical mobile hardware, native desktop window resize, or FPS certification tested','camera pure mocks cover DPR, not real Retina device']}
(root/'validation/map-optimization-delivery-audit.json').write_text(json.dumps(audit,ensure_ascii=False,indent=2))
print('原图、共享地图、设置文件及130文件快照校验通过；交付对照图已保存；验收记录已生成')
print('assertions',sum(v['assertions']['total'] for v in reports.values()))
