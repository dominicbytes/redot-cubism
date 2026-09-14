#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Compare native motion and selected expression/physics/pose/breath states with the pinned SDK."""
import argparse
import json
import math
import os
from pathlib import Path
import platform
import re
import shlex
import shutil
import subprocess
import tempfile

from build_inputs import core_library, sdk_roots, sha256

ROOT = Path(__file__).resolve().parents[1]
TOLERANCE = 1e-5
CASE_KEYS = ('resource', 'group', 'index', 'steps', 'fps', 'expression', 'physics', 'pose', 'breath')


def compare_states(expected, actual):
    differences = []
    for group in ('parameters', 'parts'):
        left, right = expected[group], actual[group]
        if not isinstance(left, dict) or not isinstance(right, dict) or left.keys() != right.keys():
            raise ValueError('Parameter/part IDs differ from SDK reference')
        if group == 'parameters' and not left:
            raise ValueError('SDK reference has no parameters')
        for key, value in left.items():
            found = right[key]
            if any(type(v) not in (int, float) or not math.isfinite(v) for v in (value, found)):
                raise ValueError('Non-finite or nonnumeric state')
            if abs(found - value) > TOLERANCE:
                differences.append({'group': group, 'id': key, 'expected': value, 'actual': found})
    return differences


def load_fixtures(path):
    fixtures = json.loads(path.read_text(encoding='utf-8'))
    if not isinstance(fixtures, list) or not fixtures:
        raise ValueError('Fixtures must be a nonempty array')
    for fixture in fixtures:
        if not isinstance(fixture, dict) or not isinstance(fixture.get('model'), str):
            raise ValueError('Each fixture needs a model path')
        resource = fixture.get('resource')
        if not isinstance(resource, str) or not resource.startswith('res://') or '..' in resource.split('/'):
            raise ValueError('Each fixture needs a project-local imported resource')
        motions = fixture.get('motions')
        if not isinstance(motions, list) or not motions:
            raise ValueError('Each fixture needs a nonempty motions array')
        for motion in motions:
            if (not isinstance(motion, dict) or not isinstance(motion.get('group'), str) or not motion['group'] or
                    type(motion.get('index')) is not int or motion['index'] < 0):
                raise ValueError('Motions require a group and nonnegative integer index')
            motion.setdefault('expression', '')
            for key in ('physics', 'pose', 'breath'): motion.setdefault(key, False)
            if not isinstance(motion['expression'], str) or any(type(motion[key]) is not bool for key in ('physics', 'pose', 'breath')):
                raise ValueError('Expression must be a string and physics/pose/breath must be booleans')
        fixture['model'] = str((path.parent / fixture['model']).resolve())
    return fixtures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('project', 'library', 'fixtures', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--sdk-root', type=Path, default=os.environ.get('CUBISM_SDK_ROOT'))
    parser.add_argument('--steps', type=int, nargs='+', default=[1, 30, 90, 180])
    parser.add_argument('--fps', type=int, default=60)
    parser.add_argument('--uncapped-manual-step', action='store_true', help='Explicitly enable uncapped manual test steps, including rates below 10 Hz')
    args = parser.parse_args()
    if platform.system() not in ('Linux', 'Windows') or platform.machine().lower() not in ('x86_64', 'amd64'):
        parser.error('Use a native Linux/Windows x86_64 runner')
    minimum_fps = 1 if args.uncapped_manual_step else 10
    if not args.sdk_root or not args.steps or any(n < 1 or n > 36000 for n in args.steps) or not minimum_fps <= args.fps <= 240:
        parser.error('Supply SDK root, steps in1..36000 and fps in10..240; use --uncapped-manual-step for1..9Hz')
    source = args.project.resolve()
    output = args.output.resolve()
    if output == source or source in output.parents:
        parser.error('Output must be outside the prepared project')
    if not (source / 'project.godot').is_file() or not args.library.is_file():
        parser.error('Prepared project or addon library missing')
    pins = json.loads((ROOT / 'DEPENDENCIES.json').read_text())
    engine = Path(os.environ['REDOT_BIN']).resolve()
    version = subprocess.check_output([str(engine), '--version'], text=True, timeout=10).strip()
    if version != pins['redot']['version']: parser.error('Editor differs from pinned Redot')
    try:
        core, framework = sdk_roots({'CUBISM_SDK_ROOT': str(args.sdk_root)}, pins)
        fixtures = load_fixtures(args.fixtures.resolve())
        core_path = core / ('lib/windows/x86_64/143/Live2DCubismCore_MD.lib' if os.name == 'nt' else 'lib/linux/x86_64/libLive2DCubismCore.a')
        core_library(core_path, core, pins)
    except (OSError, ValueError) as error: parser.error(str(error))
    output.mkdir(parents=True, exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix='sdk-motion-', dir=output))
    build = run / 'build'
    build.mkdir()
    reference = build / ('reference.exe' if os.name == 'nt' else 'reference')
    reference_source = ROOT / 'tests/native/sdk_motion_reference.cpp'
    driver = ROOT / 'tests/native/project/sdk_motion_checks.gd'
    sdk_sources = sorted((framework / 'src').glob('*.cpp'))
    for folder in ('Effect', 'Id', 'Math', 'Model', 'Motion', 'Physics', 'Rendering', 'Type', 'Utils'):
        sdk_sources += sorted((framework / 'src' / folder).glob('*.cpp'))
    report = {'status': 'RUNNING', 'run': str(run), 'scope': 'Native non-looping motion and selected expression/physics/pose/breath parameter and part states',
              'release_qualified': False, 'platform': platform.system(), 'engine_version': version,
              'engine_sha256': sha256(engine), 'library_sha256': sha256(args.library),
              'framework_sha256': pins['cubism_framework']['source_sha256'], 'core_sha256': sha256(core_path),
              'source_hashes': {str(p.relative_to(ROOT)): sha256(p) for p in (reference_source, driver, Path(__file__).resolve())},
              'tolerance': TOLERANCE, 'steps': args.steps, 'fps': args.fps,
              'uncapped_manual_step': args.uncapped_manual_step, 'checks': [], 'cases': []}

    def save(): (output / 'sdk-motion-report.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')

    env = dict(os.environ, PYTHONUTF8='1', PYTHONIOENCODING='utf-8')
    env.pop('CUBISM_TEST_UNCAPPED_MANUAL_STEP', None)
    if args.uncapped_manual_step: env['CUBISM_TEST_UNCAPPED_MANUAL_STEP'] = '1'
    for key in ('CONFIG', 'CACHE', 'DATA'): env['XDG_' + key + '_HOME'] = str(run / key.lower())

    def execute(name, command, marker=None):
        log = run / (name + '.log')
        with log.open('w', encoding='utf-8') as stream:
            try: code = subprocess.run(command, cwd=build, env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=300).returncode
            except subprocess.TimeoutExpired: code = 124
        text = log.read_text(encoding='utf-8', errors='replace')
        passed = code == 0 and not re.search(r'ERROR:|WARNING:|SCRIPT ERROR|runtime error:|crashed', text)
        if marker: passed = passed and marker in text
        report['checks'].append({'test': name, 'command': command, 'log': str(log), 'exit_code': code, 'status': 'PASS' if passed else 'FAIL'})
        save()
        if not passed: raise ValueError('Failed command: ' + name)
        return text

    save()
    print('SDK motion report: ' + str(output / 'sdk-motion-report.json'), flush=True)
    try:
        compiler = shlex.split(os.environ.get('CXX', 'cl' if os.name == 'nt' else 'g++'))
        if os.name == 'nt':
            compiler_version = execute('compiler', compiler)
            if not re.search(r'Version 19\.3\d\.', compiler_version):
                raise ValueError('Use VS2022 MSVC14.3 x64 Native Tools environment')
            flags = ['/nologo', '/std:c++17', '/EHsc', '/O2', '/MD', '/utf-8', '/I' + str(framework / 'src'), '/I' + str(core / 'include')]
            end = ['/Fe:' + str(reference)]
        else:
            report['compiler'] = execute('compiler', compiler + ['--version']).splitlines()[0]
            # Define the SDK csmString signed hash arithmetic without modifying SDK source.
            flags = ['-std=c++17', '-O2', '-fwrapv', '-I' + str(framework / 'src'), '-I' + str(core / 'include')]
            end = ['-o', str(reference)]
        execute('build-reference', compiler + flags + [str(reference_source), *map(str, sdk_sources), str(core_path)] + end)
        report['reference_sha256'] = sha256(reference)
        cases = []
        for fixture in fixtures:
            manifest_path = Path(fixture['model'])
            manifest = json.loads(manifest_path.read_text(encoding='utf-8-sig'))['FileReferences']
            for motion in fixture['motions']:
                motion_path = manifest_path.parent / manifest['Motions'][motion['group']][motion['index']]['File']
                effect_hashes = {}
                if motion['expression']:
                    matches = [item['File'] for item in manifest.get('Expressions', []) if item['Name'] == motion['expression']]
                    if len(matches) != 1: raise ValueError('Select exactly one manifest expression')
                    effect_hashes['expression_sha256'] = sha256(manifest_path.parent / matches[0])
                for key in ('physics', 'pose'):
                    if motion[key]: effect_hashes[key + '_sha256'] = sha256(manifest_path.parent / manifest[key.title()])
                for steps in args.steps:
                    name = 'reference-' + str(len(cases))
                    state_path = run / (name + '.json')
                    execute(name, [str(reference), str(manifest_path), motion['group'], str(motion['index']), str(steps), str(args.fps), str(state_path),
                                   motion['expression'], str(int(motion['physics'])), str(int(motion['pose'])), str(int(motion['breath']))])
                    state = json.loads(state_path.read_text(encoding='utf-8'))
                    compare_states(state, state)
                    if state['steps'] != steps or state['fps'] != args.fps: raise ValueError('Reference time mismatch')
                    if any(state[key] != motion[key] for key in ('expression', 'physics', 'pose', 'breath')): raise ValueError('Reference effects mismatch')
                    cases.append(dict(state, resource=fixture['resource'], group=motion['group'], index=motion['index'],
                                      manifest_sha256=sha256(manifest_path), moc_sha256=sha256(manifest_path.parent / manifest['Moc']), motion_sha256=sha256(motion_path), **effect_hashes))
        (run / 'reference.json').write_text(json.dumps({'cases': cases}, indent=2) + '\n', encoding='utf-8')
        project = run / 'project'
        shutil.copytree(source, project, copy_function=shutil.copyfile, ignore=shutil.ignore_patterns('shader_cache'))
        addon = project / 'addons/gd_cubism'
        (addon / 'bin' / args.library.name).write_bytes(args.library.read_bytes())
        target = 'windows' if os.name == 'nt' else 'linux'
        (addon / 'gd_cubism.gdextension').write_text('[configuration]\nentry_symbol="gd_cubism_library_init"\ncompatibility_minimum="26.2"\ndisable_godot_checks=true\nreloadable=false\n[libraries]\n' + target + '.x86_64="res://addons/gd_cubism/bin/' + args.library.name + '"\n', encoding='utf-8')
        (project / 'sdk_motion_checks.gd').write_bytes(driver.read_bytes())
        execute('redot', [str(engine), '--headless', '--audio-driver', 'Dummy', '--path', str(project), '--script', 'res://sdk_motion_checks.gd',
                          '--quit-after', '10000', '--', str(run / 'reference.json'), str(run / 'actual.json')], 'CUBISM_SDK_MOTION_PASS')
        actual = json.loads((run / 'actual.json').read_text())
        if actual['status'] != 'PASS' or len(actual['cases']) != len(cases): raise ValueError('Incomplete native results')
        for expected, found in zip(cases, actual['cases']):
            if found['status'] != 'PASS' or any(found[k] != expected[k] for k in CASE_KEYS):
                raise ValueError('Native case identity mismatch')
            differences = compare_states(expected, found)
            report['cases'].append({k: found[k] for k in CASE_KEYS} |
                                   {'status': 'FAIL' if differences else 'PASS', 'differences': differences})
        report['status'] = 'PASS' if all(c['status'] == 'PASS' for c in report['cases']) else 'FAIL'
    except (OSError, ValueError, KeyError, IndexError, TypeError) as error:
        report.update(status='FAIL', error=str(error))
    save()
    print(report['status'], len(report['cases']), 'motion cases', flush=True)
    return int(report['status'] != 'PASS')


if __name__ == '__main__':
    raise SystemExit(main())
