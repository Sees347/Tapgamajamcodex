import hashlib
import json
from pathlib import Path

root = Path('/workspace')
validation = root / 'validation'
baseline = json.loads((validation / 'tile-seam-background-fixture-original-hashes.json').read_text())
changed = []
print(f'Checking {len(baseline)} production and save files', flush=True)
for name, previous in baseline.items():
    path = Path(name)
    if not path.exists():
        changed.append({'path': name, 'reason': 'removed'})
        continue
    with path.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    stat = path.stat()
    if digest != previous['sha256'] or stat.st_mtime_ns != previous['mtime_ns']:
        changed.append({'path': name, 'sha256_changed': digest != previous['sha256'], 'mtime_changed': stat.st_mtime_ns != previous['mtime_ns']})
current = {str(path) for directory in ('scripts', 'assets') for path in (root / directory).rglob('*') if path.is_file()}
current.update(str(path) for path in root.glob('*.json'))
added = sorted(current - set(baseline))
old_test = (root / 'scripts/tests/background_validation.lua').read_text()
new_test = (validation / 'background_validation_isolated.lua').read_text()
assert new_test.replace('    assert(ME.loadSource(saved))\n    ME.centerCamera()\n', '', 1) == old_test
report = json.loads((validation / 'tile-seam-background-fixture-isolated.json').read_text())
old_report = json.loads((validation / 'tile-seam-background_validation.json').read_text())
errors = [(phase, error) for phase, section in report['phases'].items() for error in section.get('errors', [])]
log_lines = (validation / 'tile-seam-background-fixture-isolated.log').read_text().splitlines()
result = {
    'baseline_assertions': old_report['test_assertions'],
    'isolated_assertions': report['test_assertions'],
    'runtime_result': report['result'],
    'test_result': report['test_result'],
    'frames_completed': report['frames_completed'],
    'summary': report['summary'],
    'engine_error_breakdown': {
        'texture3DLod_shader_compile': sum('texture3DLod' in error['message'] for _, error in errors),
        'frame_time_spikes': [error['message'] for _, error in errors if 'Frame time spike' in error['message']],
    },
    'missing_resources': report.get('missing_resources', []),
    'missing_engine_resources': report.get('missing_engine_resources', []),
    'cleanup_log': [line for line in log_lines if '[编辑试玩] 已恢复正式游戏进度' in line],
    'actual_save_logs': [line for line in log_lines if '[Save] 已保存' in line or '[Save] 写入' in line or '已保存沙箱注册表' in line],
    'fixture_only_two_line_delta': True,
    'fixture': {
        'shared_default': {'cols': 300, 'rows': 200, 'backgrounds': 4},
        'isolated_initial': {'cols': 30, 'rows': 12, 'tile': 1, 'originX': 0, 'originY': 12, 'spawn': {'x': 15, 'y': 5}, 'camera': {'x': 15, 'y': 6}, 'backgrounds': 0, 'collision_cells': 0, 'ground_rows': 1},
        'delta': ['assert(ME.loadSource(saved))', 'ME.centerCamera()'],
    },
    'assets_unchanged': not any(item['path'].startswith('/workspace/assets/') for item in changed),
    'original_test_unchanged': not any(item['path'] == '/workspace/scripts/tests/background_validation.lua' for item in changed),
    'map_backgrounds_unchanged': not any(item['path'] == '/workspace/scripts/core/map_backgrounds.lua' for item in changed),
    'user_saves_unchanged': not any(item['path'] in ('/workspace/mapedit_world.json', '/workspace/yongquan_save.json') for item in changed),
    'concurrent_change_note': 'terrain_tiles.lua changed outside this validation work at 2026-10-12 16:45:37 +0800, before Runtime launch at 16:47:16; not edited or reverted by this task.',
    'production_integrity': {'files_checked': len(baseline), 'changed': changed, 'added': added, 'unchanged': not changed and not added},
}
(validation / 'tile-seam-background-fixture-audit.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(result, ensure_ascii=False, indent=2), flush=True)
