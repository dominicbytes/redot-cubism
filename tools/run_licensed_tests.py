#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Build and qualify both variants on one provisioned native desktop runner."""
import argparse
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

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = (
    'REDOT_BIN', 'REDOT_CPP_ROOT', 'CUBISM_SDK_ROOT', 'CUBISM_MODEL', 'CUBISM_EXPRESSION',
    'CUBISM_TEMPLATE_DEBUG', 'CUBISM_TEMPLATE_RELEASE', 'CUBISM_MOTION_PROJECT',
    'CUBISM_MOTION_FIXTURES', 'CUBISM_VISUAL_PROJECT', 'CUBISM_VISUAL_FIXTURES',
    'CUBISM_VISUAL_LIMITS', 'CUBISM_BENCHMARK_PROJECT', 'CUBISM_BENCHMARK_RESOURCE',
    'CUBISM_BENCHMARK_MASK_RESOURCE', 'CUBISM_BENCHMARK_MOTION', 'CUBISM_BENCHMARK_EXPRESSION',
    'CUBISM_BENCHMARK_RUNNER_ID', 'CUBISM_BENCHMARK_BASELINE', 'CUBISM_BENCHMARK_RELATIVE_THRESHOLD',
)
DESKTOP_STAGES = {'paths', 'native', 'editor', 'importer', 'model2d', 'selection',
                  'checked-export', 'legacy-export', 'legacy-bridge', 'export-identity'}


def configuration(env, target):
    required = REQUIRED + (('CUBISM_SANITIZER_RUNTIME',) if target == 'linux' else ())
    for key in required:
        if not env.get(key):
            raise ValueError('Missing private runner environment variable: ' + key)
    threshold = float(env['CUBISM_BENCHMARK_RELATIVE_THRESHOLD'])
    if not math.isfinite(threshold) or threshold < 0:
        raise ValueError('Supply a finite, nonnegative reviewed benchmark threshold')
    for key in ('REDOT_BIN', 'CUBISM_MODEL', 'CUBISM_TEMPLATE_DEBUG', 'CUBISM_TEMPLATE_RELEASE',
                'CUBISM_MOTION_FIXTURES', 'CUBISM_VISUAL_FIXTURES', 'CUBISM_VISUAL_LIMITS',
                'CUBISM_BENCHMARK_BASELINE') + (('CUBISM_SANITIZER_RUNTIME',) if target == 'linux' else ()):
        if not Path(env[key]).is_file():
            raise ValueError('Missing private input file: ' + key)
    for key in ('REDOT_CPP_ROOT', 'CUBISM_SDK_ROOT', 'CUBISM_MOTION_PROJECT',
                'CUBISM_VISUAL_PROJECT', 'CUBISM_BENCHMARK_PROJECT'):
        if not Path(env[key]).is_dir():
            raise ValueError('Missing private input directory: ' + key)
    import SCons
    from PIL import __version__ as pillow_version
    pins = json.loads((ROOT / 'DEPENDENCIES.json').read_text())
    if SCons.__version__ != pins['toolchain']['scons']:
        raise ValueError('Install the pinned SCons version on the private runner')
    if pillow_version != (ROOT / 'tools/requirements-visual.txt').read_text().strip().split('==')[1]:
        raise ValueError('Install tools/requirements-visual.txt on the private runner')
    return threshold, pins


def validate_result(path, kind, library_hash, version):
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
    if kind in ('motion', 'visual'):
        cases = report.get('cases')
        if not isinstance(cases, list) or not cases or any(c.get('status') != 'PASS' for c in cases):
            raise ValueError('Missing, failed or measurement-only comparison cases')
    if kind == 'visual' and not report.get('limits'):
        raise ValueError('Visual comparison requires reviewed limits')
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
        threshold, pins = configuration(env, target)
    except (ImportError, OSError, ValueError) as error:
        report.update(status='FAIL', error=str(error), configuration_error=True)
        save()
        print(str(error), file=sys.stderr)
        return 2
    version = pins['redot']['version']
    report.update(engine_version=version,
                  source_commit=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                  source_dirty=bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT)))

    def execute(name, command, *, timeout=1800, build_env=None, filename=None, kind=None, library=None):
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
                validate_result(candidates[0], kind, sha256(library) if library else None, version)
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
            execute('visual-' + mode, tool('run_visual_tests') + ['--project', env['CUBISM_VISUAL_PROJECT'],
                    '--library', str(library), '--fixtures', env['CUBISM_VISUAL_FIXTURES'], '--limits', env['CUBISM_VISUAL_LIMITS']],
                    filename='visual-report.json', kind='visual', library=library)
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
