#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Build and qualify both variants on one provisioned native desktop runner."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import signal
import subprocess
import sys
import tempfile
import time

from run_benchmarks import SCENARIOS
from run_desktop_tests import check_report, sha256
from run_visual_tests import load_fixtures, validate_limits

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = (
    'REDOT_BIN', 'REDOT_CPP_ROOT', 'CUBISM_SDK_ROOT', 'CUBISM_MODEL', 'CUBISM_EXPRESSION',
    'CUBISM_TEMPLATE_DEBUG', 'CUBISM_TEMPLATE_RELEASE', 'CUBISM_MOTION_PROJECT',
    'CUBISM_MOTION_FIXTURES', 'CUBISM_VISUAL_MATRIX', 'CUBISM_BENCHMARK_PROJECT', 'CUBISM_BENCHMARK_RESOURCE',
    'CUBISM_BENCHMARK_MASK_RESOURCE', 'CUBISM_BENCHMARK_MOTION', 'CUBISM_BENCHMARK_EXPRESSION',
    'CUBISM_BENCHMARK_RUNNER_ID', 'CUBISM_BENCHMARK_BASELINE', 'CUBISM_BENCHMARK_RELATIVE_THRESHOLD',
)
DESKTOP_STAGES = {'paths', 'native', 'editor', 'importer', 'model2d', 'selection',
                  'checked-export', 'legacy-export', 'legacy-bridge', 'export-identity'}
VISUAL_CASES = {
    'transforms': {'Haru-nonuniform', 'Haru-mirrored', 'Haru-minified', 'Haru-clipped',
                   'Mao-nonuniform', 'Mao-mirrored', 'Mao-minified', 'Mao-clipped'},
    'effects': {'Haru-neutral', 'Haru-motion', 'Haru-expression', 'Haru-physics', 'Haru-transform',
                'Mao-neutral', 'Mao-motion', 'Mao-expression', 'Mao-physics', 'Mao-transform'},
    'pair': {'neutral-forward', 'neutral-reverse', 'motion-forward', 'motion-reverse'},
    'additive': {'additive-forward'},
}
VISUAL_MODEL_COUNTS = {'transforms': 1, 'effects': 1, 'pair': 2, 'additive': 1}
VISUAL_FAMILIES = tuple(f'{family}-{encoding}' for family in VISUAL_CASES
                        for encoding in ('straight', 'premultiplied'))


def load_visual_matrix(path, pins):
    path = Path(path).resolve()
    try:
        matrix_bytes = path.read_bytes()
        data = json.loads(matrix_bytes.decode('utf-8'))
    except (OSError, UnicodeError, ValueError) as error:
        raise ValueError('Cannot read the private visual matrix: ' + str(error)) from error
    if not isinstance(data, dict) or set(data) != {'schema_version', 'families'} or data['schema_version'] != 1:
        raise ValueError('Visual matrix must use schema_version 1 with only a families list')
    if not isinstance(data['families'], list):
        raise ValueError('Visual matrix families must be a list')
    entries = {}
    fixture_hashes = set()
    limits_hashes = set()
    for raw in data['families']:
        if not isinstance(raw, dict) or set(raw) != {'id', 'project', 'fixtures', 'limits'}:
            raise ValueError('Each visual family needs exactly id, project, fixtures and limits')
        family_id = raw['id']
        if not isinstance(family_id, str) or family_id not in VISUAL_FAMILIES or family_id in entries:
            raise ValueError('Visual family IDs must be unique members of the required eight-family set')
        family, encoding = family_id.rsplit('-', 1)

        def resolve(name):
            value = raw[name]
            if not isinstance(value, str) or not value.strip():
                raise ValueError('Visual matrix paths must be nonempty strings: ' + family_id + '/' + name)
            candidate = Path(value).expanduser()
            return (candidate if candidate.is_absolute() else path.parent / candidate).resolve()

        project, fixtures, limits = resolve('project'), resolve('fixtures'), resolve('limits')
        if not project.is_dir() or not (project / 'project.godot').is_file():
            raise ValueError('Visual family needs a prepared project.godot: ' + family_id)
        if not fixtures.is_file() or not limits.is_file():
            raise ValueError('Visual family fixture and limits files must exist: ' + family_id)
        fixture_hash, limits_hash = sha256(fixtures), sha256(limits)
        if fixture_hash in fixture_hashes or limits_hash in limits_hashes:
            raise ValueError('Visual families may not reuse fixture or limits content: ' + family_id)
        try:
            fixture_data = load_fixtures(fixtures, pins)
            case_ids = [case['id'] for case in fixture_data['cases']]
            limits_data = json.loads(limits.read_text(encoding='utf-8'))
            validate_limits(limits_data, fixture_hash, case_ids)
        except (KeyError, OSError, TypeError, ValueError) as error:
            raise ValueError('Invalid visual family ' + family_id + ': ' + str(error)) from error
        if len(case_ids) != len(VISUAL_CASES[family]) or set(case_ids) != VISUAL_CASES[family]:
            raise ValueError('Visual family has missing, extra or relabelled cases: ' + family_id)
        expected_encoding = encoding == 'premultiplied'
        expected_models = VISUAL_MODEL_COUNTS[family]
        if any(len(case['models']) != expected_models for case in fixture_data['cases']):
            raise ValueError('Visual family has the wrong model count per case: ' + family_id)
        if any(model['premultiplied_alpha'] is not expected_encoding
               for case in fixture_data['cases'] for model in case['models']):
            raise ValueError('Visual family texture encoding does not match its required ID: ' + family_id)
        if sha256(fixtures) != fixture_hash or sha256(limits) != limits_hash:
            raise ValueError('Visual family inputs changed while the matrix was being validated: ' + family_id)
        fixture_hashes.add(fixture_hash)
        limits_hashes.add(limits_hash)
        entries[family_id] = {
            'id': family_id,
            'project': project,
            'fixtures': fixtures,
            'limits': limits,
            'fixtures_sha256': fixture_hash,
            'limits_sha256': limits_hash,
            'case_ids': tuple(case_ids),
            'limits_snapshot': limits_data,
        }
    if set(entries) != set(VISUAL_FAMILIES):
        raise ValueError('Visual matrix must contain exactly all eight required family/encoding IDs')
    return hashlib.sha256(matrix_bytes).hexdigest(), [entries[family_id] for family_id in VISUAL_FAMILIES]


def configuration(env, target):
    required = REQUIRED + (('CUBISM_SANITIZER_RUNTIME',) if target == 'linux' else ())
    for key in required:
        if not env.get(key):
            raise ValueError('Missing private runner environment variable: ' + key)
    threshold = float(env['CUBISM_BENCHMARK_RELATIVE_THRESHOLD'])
    if not math.isfinite(threshold) or threshold < 0:
        raise ValueError('Supply a finite, nonnegative reviewed benchmark threshold')
    for key in ('REDOT_BIN', 'CUBISM_MODEL', 'CUBISM_TEMPLATE_DEBUG', 'CUBISM_TEMPLATE_RELEASE',
                'CUBISM_MOTION_FIXTURES', 'CUBISM_VISUAL_MATRIX',
                'CUBISM_BENCHMARK_BASELINE') + (('CUBISM_SANITIZER_RUNTIME',) if target == 'linux' else ()):
        if not Path(env[key]).is_file():
            raise ValueError('Missing private input file: ' + key)
    for key in ('REDOT_CPP_ROOT', 'CUBISM_SDK_ROOT', 'CUBISM_MOTION_PROJECT',
                'CUBISM_BENCHMARK_PROJECT'):
        if not Path(env[key]).is_dir():
            raise ValueError('Missing private input directory: ' + key)
    import SCons
    from PIL import __version__ as pillow_version
    pins = json.loads((ROOT / 'DEPENDENCIES.json').read_text())
    if SCons.__version__ != pins['toolchain']['scons']:
        raise ValueError('Install the pinned SCons version on the private runner')
    if pillow_version != (ROOT / 'tools/requirements-visual.txt').read_text().strip().split('==')[1]:
        raise ValueError('Install tools/requirements-visual.txt on the private runner')
    matrix_hash, visual_matrix = load_visual_matrix(env['CUBISM_VISUAL_MATRIX'], pins)
    return threshold, pins, matrix_hash, visual_matrix


def validate_result(path, kind, library_hash, version, visual=None):
    report = check_report(path, library_hash, version)
    if kind != 'identity' and report.get('library_sha256') != library_hash:
        raise ValueError('Required native library identity is missing or different')
    observed_version = report.get('identity', {}).get('engine_version') if kind == 'benchmark' else report.get('engine_version')
    if observed_version != version:
        raise ValueError('Required pinned engine identity is missing or different')
    if kind == 'desktop':
        stages = report.get('stages', [])
        if (len(stages) != len(DESKTOP_STAGES) or
            {s.get('name') for s in stages} != DESKTOP_STAGES or any(s.get('status') != 'PASS' for s in stages)):
            raise ValueError('Incomplete desktop functional stages')
    if kind == 'motion':
        cases = report.get('cases')
        if not isinstance(cases, list) or not cases or any(c.get('status') != 'PASS' for c in cases):
            raise ValueError('Missing, failed or measurement-only comparison cases')
    if kind == 'visual':
        if visual is None:
            raise ValueError('Visual comparison requires its selected matrix family')
        cases = report.get('cases')
        if (not isinstance(cases, list) or len(cases) != len(visual['case_ids']) or
            any(not isinstance(case, dict) or case.get('status') != 'PASS' or
                not isinstance(case.get('id'), str) for case in cases)):
            raise ValueError('Visual comparison requires every selected case to pass')
        case_ids = [case['id'] for case in cases]
        if len(set(case_ids)) != len(case_ids) or set(case_ids) != set(visual['case_ids']):
            raise ValueError('Visual comparison case identities differ from the selected family')
        if report.get('fixtures_sha256') != visual['fixtures_sha256']:
            raise ValueError('Visual comparison used a different fixture manifest')
        if report.get('limits') != visual['limits_snapshot']:
            raise ValueError('Visual comparison used different reviewed limits')
        if (sha256(visual['fixtures']) != visual['fixtures_sha256'] or
            sha256(visual['limits']) != visual['limits_sha256']):
            raise ValueError('Visual family inputs changed after matrix preflight')
    if kind == 'benchmark':
        if (report.get('qualification') != 'BASELINE_COMPARISON_PASS' or report.get('regressions') != [] or
            set(report.get('scenarios', {})) != set(SCENARIOS)):
            raise ValueError('All eight benchmark scenarios must pass the reviewed baseline comparison')
    if kind == 'sanitizer':
        sanitizer = report.get('sanitizer', {})
        if (sanitizer.get('tested') is not True or sanitizer.get('addon_sanitizers') != ['address', 'undefined'] or
            sanitizer.get('framework_sanitizers') != ['address', 'undefined'] or sanitizer.get('cycles') != 250):
            raise ValueError('The combined addon/Framework sanitizer lifecycle gate did not pass')
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(argv)
    if sys.platform not in ('linux', 'win32'):
        parser.error('Run on a native Linux or Windows host')
    target = 'windows' if sys.platform == 'win32' else 'linux'
    args.output.mkdir(parents=True, exist_ok=True)
    root = Path(tempfile.mkdtemp(prefix='licensed-' + target + '-', dir=args.output.resolve()))
    destination = root / 'licensed-desktop.json'
    report = {'status': 'RUNNING', 'suite': 'licensed-desktop', 'platform': platform.system(),
              'architecture': platform.machine(), 'run': str(root), 'runner_sha256': sha256(__file__),
              'cubism_model_tests_selected': True, 'release_qualified': False, 'checks': [],
              'separate_gates': ['Other native desktop platform', 'Complete approved fixture matrix',
                                 'Remaining manual editor checks', 'Release audit and publication']}

    def save():
        destination.write_text(json.dumps(report, indent=2) + '\n')

    save()
    print('Licensed desktop report: ' + str(destination), flush=True)
    env = dict(os.environ, PYTHONUTF8='1', PYTHONIOENCODING='utf-8', PYTHONUNBUFFERED='1', PYTHONDONTWRITEBYTECODE='1')
    try:
        threshold, pins, visual_matrix_hash, visual_matrix = configuration(env, target)
    except (ImportError, KeyError, OSError, TypeError, ValueError) as error:
        report.update(status='FAIL', error=str(error), configuration_error=True)
        save()
        print(str(error), file=sys.stderr)
        return 2
    version = pins['redot']['version']
    report.update(engine_version=version,
                  source_commit=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                  source_dirty=bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT)),
                  visual_matrix={
                      'sha256': visual_matrix_hash,
                      'families': [entry['id'] for entry in visual_matrix],
                      'snapshots': [{'id': entry['id'],
                                     'fixtures_sha256': entry['fixtures_sha256'],
                                     'limits_sha256': entry['limits_sha256'],
                                     'case_ids': list(entry['case_ids'])}
                                    for entry in visual_matrix],
                  })

    def execute(name, command, *, timeout=1800, build_env=None, filename=None, kind=None, library=None,
                visual=None):
        output = root / name
        output.mkdir()
        if filename:
            command += ['--output', str(output)]
        stage = {'name': name, 'status': 'RUNNING', 'command': command, 'log': str(output / 'runner.log')}
        report['checks'].append(stage)
        save()
        print(name + ': RUNNING', flush=True)
        started = time.monotonic()
        try:
            with (output / 'runner.log').open('w') as log:
                process = subprocess.Popen(command, cwd=ROOT, env=build_env or env, stdout=log,
                                           stderr=subprocess.STDOUT, start_new_session=os.name != 'nt')
                stage['pid'] = process.pid
                save()
                try:
                    code = process.wait(timeout=timeout)
                except subprocess.TimeoutExpired:
                    if os.name == 'nt':
                        subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'], capture_output=True, timeout=30)
                    else:
                        os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=30)
                    code = 124
            stage['exit_code'] = code
            if code:
                raise ValueError('Child process exited ' + str(code))
            if filename:
                candidates = list(output.glob(filename))
                if len(candidates) != 1:
                    raise ValueError('Expected exactly one fresh child report: ' + filename)
                stage['report'] = str(candidates[0])
                validate_result(candidates[0], kind, sha256(library) if library else None, version, visual)
            stage['status'] = 'PASS'
        except (OSError, ValueError, TypeError, AttributeError, subprocess.TimeoutExpired) as error:
            stage.update(status='FAIL', error=str(error))
            raise
        finally:
            stage['elapsed_seconds'] = round(time.monotonic() - started, 3)
            save()
            print(name + ': ' + stage['status'], flush=True)

    def tool(name):
        return [sys.executable, 'tools/' + name + '.py']

    try:
        execute('identity', tool('verify_dependencies'), filename='host.json', kind='identity')
        api = root / 'identity/extension_api.json'
        common_build = [sys.executable, '-m', 'SCons', 'platform=' + target, 'arch=x86_64',
                        'precision=single', 'custom_api_file=' + str(api), 'build_profile=tools/native_build_profile.json']
        suffix = 'dll' if target == 'windows' else 'so'
        libraries = {}
        for mode in ('debug', 'release'):
            execute('build-' + mode, common_build + ['target=template_' + mode, 'use_static_cpp=yes', '-j2',
                    *(['debug_crt=no'] if target == 'windows' else [])], timeout=3600,
                    build_env=dict(env, CUBISM_BUILD_DIR=str(root / ('build-' + mode))))
            libraries[mode] = ROOT / ('demo/addons/gd_cubism/bin/libgd_cubism.' + target + '.' + mode + '.x86_64.' + suffix)
            report.setdefault('libraries', {})[mode] = {'path': str(libraries[mode]), 'sha256': sha256(libraries[mode])}
        for mode, other in (('debug', 'release'), ('release', 'debug')):
            library = libraries[mode]
            execute('tests-' + mode, tool('run_desktop_tests') + ['--model', env['CUBISM_MODEL'],
                    '--expression', env['CUBISM_EXPRESSION'], '--library', str(library), '--other-library', str(libraries[other]),
                    '--template', env['CUBISM_TEMPLATE_' + mode.upper()], '--mode', mode], timeout=5400,
                    filename='desktop-*/desktop-report.json', kind='desktop', library=library)
            for label, options in (('sdk-motion-', []), ('sdk-motion-manual-',
                                   ['--fps', '2', '--steps', '1', '2', '4', '6', '--uncapped-manual-step'])):
                execute(label + mode, tool('run_sdk_motion_tests') + ['--project', env['CUBISM_MOTION_PROJECT'],
                        '--library', str(library), '--fixtures', env['CUBISM_MOTION_FIXTURES'], *options],
                        filename='sdk-motion-report.json', kind='motion', library=library)
            for entry in visual_matrix:
                execute('visual-' + mode + '-' + entry['id'], tool('run_visual_tests') +
                        ['--project', str(entry['project']), '--library', str(library),
                         '--fixtures', str(entry['fixtures']), '--limits', str(entry['limits'])],
                        filename='visual-report.json', kind='visual', library=library, visual=entry)
        execute('benchmark-debug', tool('run_benchmarks') + ['--project', env['CUBISM_BENCHMARK_PROJECT'],
                '--library', str(libraries['debug']), '--resource', env['CUBISM_BENCHMARK_RESOURCE'],
                '--mask-resource', env['CUBISM_BENCHMARK_MASK_RESOURCE'], '--motion', env['CUBISM_BENCHMARK_MOTION'],
                '--expression', env['CUBISM_BENCHMARK_EXPRESSION'], '--runner-id', env['CUBISM_BENCHMARK_RUNNER_ID'],
                '--baseline', env['CUBISM_BENCHMARK_BASELINE'], '--relative-threshold', str(threshold)], timeout=2500,
                filename='benchmark-report.json', kind='benchmark', library=libraries['debug'])
        if target == 'linux':
            build = root / 'build-asan-ubsan'
            execute('build-asan-ubsan', common_build + ['target=template_debug', 'sanitize=address,undefined', '-j1'],
                    timeout=3600, build_env=dict(env, CUBISM_BUILD_DIR=str(build)))
            execute('sanitizers', tool('run_native_tests') + ['--model', env['CUBISM_MODEL'], '--expression', env['CUBISM_EXPRESSION'],
                    '--library', str(libraries['debug']), '--sanitizer-runtime', env['CUBISM_SANITIZER_RUNTIME'],
                    '--sanitizer-library', str(build / 'bin/libgd_cubism.linux.debug.x86_64.so')],
                    filename='native-report.json', kind='sanitizer', library=libraries['debug'])
        report['status'] = 'PASS'
    except (OSError, ValueError, TypeError, AttributeError, subprocess.SubprocessError) as error:
        report.update(status='FAIL', error=str(error))
    save()
    return int(report['status'] != 'PASS')


if __name__ == '__main__':
    raise SystemExit(main())
