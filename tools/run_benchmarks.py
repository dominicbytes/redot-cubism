#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Measure the eight licensed runtime scenarios; optionally compare a fixed-runner baseline."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import shutil
import statistics
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SCENARIOS = ('static', 'vn', 'party', 'crowd', 'masks', 'physics', 'offscreen', 'hidden')
METRICS = ('frame_usec', 'model_update_usec', 'renderer_update_usec', 'vertex_bytes',
           'mask_requests', 'engine_static_bytes', 'render_video_bytes')


def summarize(samples):
    if len(samples) < 100:
        raise ValueError('At least 100 measured frames are required')
    result = {}
    for key in METRICS:
        values = [row[key] for row in samples]
        if any(type(v) not in (int, float) or not math.isfinite(v) or v < 0 for v in values):
            raise ValueError('Invalid measurement: ' + key)
        values.sort()
        result[key] = {'mean': statistics.mean(values), 'median': statistics.median(values),
                       'p95': values[math.ceil(len(values) * .95) - 1],
                       'p99': values[math.ceil(len(values) * .99) - 1]}
    return result


def compare(current, baseline, threshold):
    if not math.isfinite(threshold) or threshold < 0:
        raise ValueError('Relative threshold must be finite and nonnegative')
    if not current['identity']['runner_id'] or current['identity'] != baseline['identity']:
        raise ValueError('Baseline requires the same named runner, engine, fixtures and measurement configuration')
    if baseline['status'] != 'PASS' or set(baseline['scenarios']) != set(SCENARIOS):
        raise ValueError('Baseline must contain all eight passing scenarios')
    regressions = []
    for scenario in SCENARIOS:
        for key in METRICS:
            old = baseline['scenarios'][scenario]['summary'][key]['p95']
            new = current['scenarios'][scenario]['summary'][key]['p95']
            if not math.isfinite(old) or old < 0:
                raise ValueError('Invalid baseline metric')
            if new > old * (1 + threshold):
                regressions.append({'scenario': scenario, 'metric': key, 'baseline_p95': old,
                                    'current_p95': new, 'relative_limit': threshold})
    return regressions


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, required=True, help='Prepared private project containing imported resources')
    parser.add_argument('--library', type=Path, required=True, help='Debug addon library')
    parser.add_argument('--resource', default='res://imported-model.res')
    parser.add_argument('--mask-resource', required=True, help='Imported resource with at least eight mask compositions')
    parser.add_argument('--motion', default='Cue/0')
    parser.add_argument('--expression', default='Add')
    parser.add_argument('--samples', type=int, default=300)
    parser.add_argument('--warmup', type=int, default=60)
    parser.add_argument('--runner-id', default='', help='Stable dedicated machine label, required for comparison')
    parser.add_argument('--baseline', type=Path)
    parser.add_argument('--relative-threshold', type=float)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.samples < 100 or args.warmup < 2: parser.error('Use at least 100 samples and two warmup frames')
    if bool(args.baseline) != (args.relative_threshold is not None): parser.error('Supply baseline and reviewed relative threshold together')
    if args.relative_threshold is not None and (not math.isfinite(args.relative_threshold) or args.relative_threshold < 0): parser.error('Threshold must be finite and nonnegative')
    source = args.project.resolve()
    if not (source / 'project.godot').is_file(): parser.error('Prepared project.godot is missing')
    for resource in (args.resource, args.mask_resource):
        if not resource.startswith('res://') or not (source / resource[6:]).resolve().is_relative_to(source): parser.error('Resources must be project-local res:// paths')
        if not (source / resource[6:]).is_file(): parser.error('Missing imported resource: ' + resource)
    output = args.output.resolve()
    if output.is_relative_to(source): parser.error('Output must be outside the input project')
    engine = Path(os.environ['REDOT_BIN']).resolve()
    version = subprocess.check_output([str(engine), '--version'], text=True, timeout=10).strip()
    pins = json.loads((ROOT / 'DEPENDENCIES.json').read_text())
    if version != pins['redot']['version']: parser.error('Editor differs from pinned Redot')
    output.mkdir(parents=True, exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix='benchmark-', dir=output))
    project = run / 'project'
    shutil.copytree(source, project, copy_function=shutil.copyfile, ignore=shutil.ignore_patterns('shader_cache'))
    script = ROOT / 'tests/benchmark/benchmark.gd'
    (project / 'cubism_benchmark.gd').write_bytes(script.read_bytes())
    addon = project / 'addons/gd_cubism'
    (addon / 'bin' / args.library.name).write_bytes(args.library.read_bytes())
    shaders = ROOT / 'demo/addons/gd_cubism/res/shader'
    shader_hashes = {p.name: sha(p) for p in shaders.glob('*.gdshader')}
    for name in shader_hashes:
        (addon / 'res/shader' / name).write_bytes((shaders / name).read_bytes())
    target = 'windows' if os.name == 'nt' else 'linux'
    (addon / 'gd_cubism.gdextension').write_text('[configuration]\nentry_symbol="gd_cubism_library_init"\ncompatibility_minimum="26.2"\ndisable_godot_checks=true\nreloadable=false\n[libraries]\n' + target + '.x86_64="res://addons/gd_cubism/bin/' + args.library.name + '"\n')
    settings = {key: getattr(args, key) for key in ('resource', 'mask_resource', 'motion', 'expression', 'samples', 'warmup')}
    identity = {'runner_id': args.runner_id, 'platform': platform.platform(), 'machine': platform.machine(),
                'engine_version': version, 'engine_sha256': sha(engine), 'script_sha256': sha(script),
                'runner_script_sha256': sha(Path(__file__)),
                'settings': settings, 'viewport': [1024, 768], 'simulation_step': 1 / 60, 'vsync': False}
    report = {'status': 'RUNNING', 'run': str(run), 'identity': identity,
              'library_sha256': sha(args.library), 'shader_sha256': shader_hashes, 'scenarios': {}}
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(('CUBISM_TEST_', 'CUBISM_COMPARE_', 'CUBISM_REFERENCE_'))}
    for key in ('CONFIG', 'CACHE', 'DATA'): env['XDG_' + key + '_HOME'] = str(run / key.lower())
    flags = ['--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy']
    if os.name != 'nt': flags += ['--display-driver', 'x11']
    try:
        for scenario in SCENARIOS:
            raw = run / (scenario + '.json')
            config = run / 'config.json'
            config.write_text(json.dumps(dict(settings, scenario=scenario, output=str(raw))))
            command = [str(engine), *flags, '--path', str(project), '--script', 'res://cubism_benchmark.gd',
                       '--quit-after', str((args.samples + args.warmup) * 3 + 100), '--', str(config)]
            with (run / (scenario + '.log')).open('w') as log:
                result = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=300)
            text = (run / (scenario + '.log')).read_text()
            if result.returncode or 'CUBISM_BENCHMARK_PASS' not in text or re.search(r'ERROR:|WARNING:|SCRIPT ERROR|crashed', text):
                raise ValueError('Scenario failed: ' + scenario + '\n' + text[-3000:])
            measured = json.loads(raw.read_text())
            if measured['status'] != 'PASS' or len(measured['samples']) != args.samples: raise ValueError('Incomplete scenario: ' + scenario)
            report['scenarios'][scenario] = {'summary': summarize(measured['samples']), 'ownership': measured['ownership'],
                                            'fixture_fingerprint': measured['fixture_fingerprint']}
            current_gpu = [measured['gpu'], measured['driver']]
            if identity.get('graphics', current_gpu) != current_gpu: raise ValueError('Graphics identity changed during run')
            identity['graphics'] = current_gpu
            print(scenario, 'PASS', flush=True)
            (output / 'benchmark-report.json').write_text(json.dumps(report, indent=2) + '\n')
        identity['fixtures'] = {key: report['scenarios'][key]['fixture_fingerprint'] for key in SCENARIOS}
        report['status'] = 'PASS'
        report['qualification'] = 'MEASURED_ONLY'
        if args.baseline:
            report['regressions'] = compare(report, json.loads(args.baseline.read_text()), args.relative_threshold)
            report['qualification'] = 'REGRESSION' if report['regressions'] else 'BASELINE_COMPARISON_PASS'
            if report['regressions']: report['status'] = 'FAIL'
    except (OSError, ValueError, KeyError, subprocess.TimeoutExpired) as error:
        report['status'] = 'FAIL'
        report['error'] = str(error)
        print(str(error), flush=True)
    (output / 'benchmark-report.json').write_text(json.dumps(report, indent=2) + '\n')
    return int(report['status'] != 'PASS')


if __name__ == '__main__':
    raise SystemExit(main())
