#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Capture imported models at private SDK reference states and compare RGB/alpha."""
import argparse
import json
import math
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tempfile

from build_inputs import sha256
from run_sdk_motion_tests import compare_states

ROOT = Path(__file__).resolve().parents[1]
METRICS = ('rgb_rms', 'alpha_rms', 'rgb_max', 'alpha_max')


def measure_pixels(reference, actual):
    if not reference or len(reference) != len(actual) or len(reference) % 4:
        raise ValueError('RGBA buffers must have equal nonzero dimensions')
    rgb_square = alpha_square = foreground = rgb_max = alpha_max = rgb_outliers = alpha_outliers = 0
    for i in range(0, len(reference), 4):
        if reference[i + 3] == 0 and actual[i + 3] == 0:
            continue
        foreground += 1
        differences = [abs(reference[i + c] - actual[i + c]) for c in range(4)]
        rgb_square += sum(v * v for v in differences[:3])
        alpha_square += differences[3] ** 2
        rgb_max = max(rgb_max, *differences[:3])
        alpha_max = max(alpha_max, differences[3])
        rgb_outliers += max(differences[:3]) > 3
        alpha_outliers += differences[3] > 3
    if not foreground:
        raise ValueError('Empty reference and candidate cannot qualify rendering')
    return {'foreground_pixels': foreground, 'rgb_rms': math.sqrt(rgb_square / (foreground * 3)),
            'alpha_rms': math.sqrt(alpha_square / foreground), 'rgb_max': rgb_max, 'alpha_max': alpha_max,
            'rgb_pixels_above_3': rgb_outliers, 'alpha_pixels_above_3': alpha_outliers}


def load_fixtures(path, pins):
    data = json.loads(path.read_text(encoding='utf-8'))
    reference = data['reference']
    for key in ('framework_sha256', 'core_sha256', 'executable_sha256'):
        if not isinstance(reference.get(key), str) or not re.fullmatch('[0-9a-f]{64}', reference[key]):
            raise ValueError('Reference requires SHA-256 identity: ' + key)
    if reference['framework_sha256'] != pins['cubism_framework']['source_sha256']:
        raise ValueError('Reference Framework differs from the pinned SDK')
    if reference['core_sha256'] not in pins['cubism_sdk']['core_library_sha256'].values():
        raise ValueError('Reference Core differs from the pinned SDK')
    if not isinstance(reference.get('description'), str) or not reference['description'].strip():
        raise ValueError('Describe how the independent SDK reference was captured')
    cases = data['cases']
    if not isinstance(cases, list) or not cases:
        raise ValueError('A nonempty reference case list is required')
    ids = set()
    for case in cases:
        if not isinstance(case.get('id'), str) or not re.fullmatch('[A-Za-z0-9_-]+', case['id']) or case['id'] in ids:
            raise ValueError('Case IDs must be unique path-safe names')
        ids.add(case['id'])
        if not isinstance(case.get('size'), list) or len(case['size']) != 2 or any(type(v) is not int or not 16 <= v <= 4096 for v in case['size']):
            raise ValueError('Capture size must be two integers in 16..4096')
        image = (path.parent / case['image']).resolve()
        if sha256(image) != case['image_sha256']:
            raise ValueError('Reference image hash mismatch: ' + case['id'])
        case['image'] = str(image)
        if not isinstance(case.get('models'), list) or not case['models']:
            raise ValueError('Each case requires model states in drawing order')
        for model in case['models']:
            resource = model.get('resource')
            if not isinstance(resource, str) or not resource.startswith('res://') or '..' in resource.split('/'):
                raise ValueError('Model resources must be project-local')
            if not isinstance(model.get('texture_sha256'), list) or not model['texture_sha256']:
                raise ValueError('Source texture hashes must be a nonempty list')
            for value in [model['manifest_sha256'], model['moc_sha256'], *model['texture_sha256']]:
                if not isinstance(value, str) or not re.fullmatch('[0-9a-f]{64}', value):
                    raise ValueError('Model/texture hashes must be SHA-256 values')
            if not model['texture_sha256'] or type(model['premultiplied_alpha']) is not bool:
                raise ValueError('Texture identities and encoding are required')
            if type(model['mask_quality']) is not int or model['mask_quality'] not in (0, 1, 2):
                raise ValueError('Select low/medium/high mask quality explicitly')
            mvp = model['mvp']
            if not isinstance(mvp, list) or len(mvp) != 16 or any(type(v) not in (int, float) or not math.isfinite(v) for v in mvp):
                raise ValueError('MVP must contain 16 finite numbers')
            if any(mvp[i] != 0 for i in (2, 3, 6, 7, 8, 9, 11, 14)) or mvp[10] != 1 or mvp[15] != 1:
                raise ValueError('Only a 2D affine MVP is supported')
            compare_states(model, model)
    return data


def validate_limits(limits, fixtures_sha256, case_ids):
    if limits.get('fixtures_sha256') != fixtures_sha256 or not isinstance(limits.get('review'), str) or not limits['review'].strip():
        raise ValueError('Limits need a review record and the exact reference fixture hash')
    if limits.get('platform') != platform.system() or not limits.get('adapter') or not limits.get('renderer'):
        raise ValueError('Limits must name the target platform, renderer and adapter')
    if set(limits['cases']) != set(case_ids):
        raise ValueError('Limits must cover exactly the reference cases')
    for case in limits['cases'].values():
        if set(case) != set(METRICS) or any(type(v) not in (int, float) or not math.isfinite(v) or not 0 <= v <= 255 for v in case.values()):
            raise ValueError('RGB/alpha RMS and maximum limits must be finite in 0..255')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('project', 'library', 'fixtures', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--limits', type=Path, help='Explicitly reviewed reference-specific acceptance limits')
    mode.add_argument('--measure-only', action='store_true', help='Collect measurements without returning a visual PASS')
    parser.add_argument('--graphics', choices=('gl_compatibility', 'forward_plus'), default='gl_compatibility')
    args = parser.parse_args()
    try:
        from PIL import Image, ImageChops, __version__ as pillow_version
    except ImportError:
        parser.error('Install tools/requirements-visual.txt in the Python environment used for this command')
    if platform.system() not in ('Linux', 'Windows') or platform.machine().lower() not in ('x86_64', 'amd64'):
        parser.error('Use a native Linux/Windows x86_64 graphics runner')
    source, output = args.project.resolve(), args.output.resolve()
    if output == source or source in output.parents:
        parser.error('Output must be outside the prepared project')
    if not (source / 'project.godot').is_file() or not args.library.is_file():
        parser.error('Prepared project and addon library are required')
    pins = json.loads((ROOT / 'DEPENDENCIES.json').read_text())
    engine = Path(os.environ['REDOT_BIN']).resolve()
    version = subprocess.check_output([str(engine), '--version'], text=True, timeout=10).strip()
    if version != pins['redot']['version']:
        parser.error('Editor differs from pinned Redot')
    try:
        fixtures = load_fixtures(args.fixtures.resolve(), pins)
        limits = json.loads(args.limits.read_text()) if args.limits else None
        if limits is not None:
            validate_limits(limits, sha256(args.fixtures), [case['id'] for case in fixtures['cases']])
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.error(str(error))
    output.mkdir(parents=True, exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix='visual-', dir=output))
    driver = ROOT / 'tests/native/project/sdk_visual_capture.gd'
    report = {'status': 'RUNNING', 'release_qualified': False, 'run': str(run), 'cases': [],
              'scope': 'Rendering transferred SDK states; not native effect evaluation or full release qualification',
              'engine_version': version, 'engine_sha256': sha256(engine), 'library_sha256': sha256(args.library),
              'fixtures_sha256': sha256(args.fixtures), 'reference': fixtures['reference'],
              'limits': limits, 'pillow_version': pillow_version, 'platform': platform.system(),
              'source_hashes': {str(p.relative_to(ROOT)): sha256(p) for p in (Path(__file__).resolve(), driver)}}

    def save():
        (output / 'visual-report.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')

    save()
    try:
        shutil.copyfile(args.fixtures, run / 'fixtures-original.json')
        if limits is not None: shutil.copyfile(args.limits, run / 'limits-original.json')
        project = run / 'project'
        shutil.copytree(source, project, copy_function=shutil.copyfile, ignore=shutil.ignore_patterns('shader_cache'))
        addon = project / 'addons/gd_cubism'
        (addon / 'bin').mkdir(parents=True, exist_ok=True)
        (addon / 'bin' / args.library.name).write_bytes(args.library.read_bytes())
        shader_root = ROOT / 'demo/addons/gd_cubism/res/shader'
        report['shader_sha256'] = {p.name: sha256(p) for p in shader_root.glob('*.gdshader')}
        for name in report['shader_sha256']:
            (addon / 'res/shader' / name).write_bytes((shader_root / name).read_bytes())
        target = 'windows' if os.name == 'nt' else 'linux'
        (addon / 'gd_cubism.gdextension').write_text('[configuration]\nentry_symbol="gd_cubism_library_init"\ncompatibility_minimum="26.2"\ndisable_godot_checks=true\nreloadable=false\n[libraries]\n' + target + '.x86_64="res://addons/gd_cubism/bin/' + args.library.name + '"\n')
        (project / 'sdk_visual_capture.gd').write_bytes(driver.read_bytes())
        env = {k: v for k, v in os.environ.items() if not k.startswith(('CUBISM_TEST_', 'CUBISM_COMPARE_', 'CUBISM_REFERENCE_'))}
        for key in ('CONFIG', 'CACHE', 'DATA'): env['XDG_' + key + '_HOME'] = str(run / key.lower())
        for fixture in fixtures['cases']:
            case = run / fixture['id']
            case.mkdir()
            (case / 'fixture.json').write_text(json.dumps(fixture) + '\n', encoding='utf-8')
            shutil.copyfile(fixture['image'], case / 'reference.png')
            if sha256(case / 'reference.png') != fixture['image_sha256']:
                raise ValueError('Reference image changed after validation: ' + fixture['id'])
            command = [str(engine), '--path', str(project), '--rendering-method', args.graphics, '--audio-driver', 'Dummy',
                       '--script', 'res://sdk_visual_capture.gd', '--quit-after', '1000', '--', str(case / 'fixture.json'), str(case)]
            if os.name != 'nt': command[1:1] = ['--display-driver', 'x11']
            with (case / 'capture.log').open('w', encoding='utf-8') as log:
                code = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=120).returncode
            text = (case / 'capture.log').read_text(encoding='utf-8', errors='replace')
            if code or 'CUBISM_SDK_VISUAL_CAPTURE_PASS' not in text or re.search(r'ERROR:|WARNING:|SCRIPT ERROR|crashed', text):
                raise ValueError('Capture failed: ' + fixture['id'])
            actual = json.loads((case / 'actual.json').read_text())
            if actual['id'] != fixture['id'] or len(actual['models']) != len(fixture['models']) or actual['renderer'] != args.graphics:
                raise ValueError('Incomplete or mismatched capture identity')
            for expected, found in zip(fixture['models'], actual['models']):
                if found['resource'] != expected['resource'] or found['premultiplied_alpha'] != expected['premultiplied_alpha'] or compare_states(expected, found):
                    raise ValueError('Model state differs from SDK reference: ' + fixture['id'])
            left = Image.open(case / 'reference.png')
            right = Image.open(case / 'actual.png')
            if 'A' not in left.getbands() or 'A' not in right.getbands():
                raise ValueError('Reference and candidate must include an explicit alpha channel')
            left, right = left.convert('RGBA'), right.convert('RGBA')
            if left.size != right.size or list(left.size) != fixture['size']:
                raise ValueError('Reference/candidate image dimensions differ')
            metrics = measure_pixels(left.tobytes(), right.tobytes())
            ImageChops.difference(left.convert('RGB'), right.convert('RGB')).save(case / 'rgb-diff.png')
            ImageChops.difference(left.getchannel('A'), right.getchannel('A')).save(case / 'alpha-diff.png')
            failures = []
            if limits is not None:
                if actual['adapter'] != limits['adapter'] or actual['renderer'] != limits['renderer']:
                    raise ValueError('Capture hardware differs from reviewed limits')
                failures = [key for key in METRICS if metrics[key] > limits['cases'][fixture['id']][key]]
            report['cases'].append({'id': fixture['id'], 'status': 'FAIL' if failures else ('PASS' if limits else 'MEASURED'),
                                    'metrics': metrics, 'exceeded_limits': failures, 'command': command,
                                    'renderer': actual['renderer'], 'adapter': actual['adapter'], 'state_matches': True,
                                    'reference_sha256': fixture['image_sha256'], 'actual_sha256': sha256(case / 'actual.png')})
            save()
        report['status'] = 'FAIL' if any(c['status'] == 'FAIL' for c in report['cases']) else ('PASS' if limits else 'MEASURED')
    except (OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired) as error:
        report.update(status='FAIL', error=str(error))
    save()
    print(report['status'], len(report['cases']), 'visual cases:', output / 'visual-report.json')
    return int(report['status'] == 'FAIL')


if __name__ == '__main__':
    raise SystemExit(main())
