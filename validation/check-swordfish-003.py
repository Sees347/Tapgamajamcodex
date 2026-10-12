from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import json
import os
import subprocess

ROOT = Path('/workspace/validation')
base = (ROOT / 'swordfish-visual.lua').read_text()
samples = [(stage, progress, 1) for stage in (1, 2, 3) for progress in (0.05, 0.35, 0.85, 1.05)]
samples += [(stage, 0.35, -1) for stage in (1, 2, 3)] + [(5, 0.35, -1)]
env = dict(os.environ, LIBGL_ALWAYS_SOFTWARE='1', GALLIUM_DRIVER='llvmpipe', EGL_PLATFORM='surfaceless',
           HTTP_PROXY='http://127.0.0.1:1080', HTTPS_PROXY='http://127.0.0.1:1080',
           http_proxy='http://127.0.0.1:1080', https_proxy='http://127.0.0.1:1080')


def run(sample):
    stage, progress, facing = sample
    name = f'swordfish-003-stage{stage}-p{round(progress * 100):03}-f{facing}'
    test = ROOT / (name + '.lua')
    if test.exists():
        raise RuntimeError(f'验收文件已存在，不覆盖: {test}')
    test.write_text(base.replace('local SAMPLE = 1', f'local SAMPLE = {stage}')
                   .replace('local PROGRESS = 0.35', f'local PROGRESS = {progress}')
                   .replace('local FACING = 1', f'local FACING = {facing}'))
    command = ['/workspace/.cli/UrhoXRuntime', 'main.lua', '-tapcode_dir=/workspace', '-tool_mode',
               '-graphicssurfaceless', '-nosound', '-validate', '-validate-frames=165',
               '-validate-timeout=95', '-validate-spike-threshold=1500', f'-validate-test={test}',
               f'-validate-output={ROOT / (name + ".json")}', f'-screenshot={ROOT / (name + ".png")}',
               '-screenshot-frame=160', '-x', '1280', '-y', '720']
    with (ROOT / (name + '.log')).open('w') as log:
        process = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=115)
    report = ROOT / (name + '.json')
    if not report.exists():
        return {'name': name, 'exit': process.returncode, 'report': False}
    result = json.loads(report.read_text())
    errors = [error for phase in result['phases'].values() for error in phase.get('errors', [])]
    summary = {'name': name, 'exit': process.returncode, 'result': result['result'],
               'test': result.get('test_result'), 'assertions': result.get('test_assertions'),
               'lua_errors': result['summary']['lua_errors'], 'missing': result['missing_resources'],
               'screenshot': (ROOT / (name + '.png')).is_file(),
               'engine_messages': sorted(set(error['message'].split('ERROR: ', 1)[-1] for error in errors))}
    print(name, 'test=', summary['test'], 'lua=', summary['lua_errors'],
          'missing=', summary['missing'], 'png=', summary['screenshot'], flush=True)
    return summary


with ThreadPoolExecutor(max_workers=2) as pool:
    results = list(pool.map(run, samples))
(ROOT / 'swordfish-003-visual-summary.json').write_text(json.dumps(results, ensure_ascii=False, indent=2))
print('已完成', len(results), '组确定性刀光采样', flush=True)
