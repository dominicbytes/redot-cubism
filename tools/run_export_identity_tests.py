#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Check actual exported native identity, including a deliberately wrong variant."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def hashes(directory):
    return {p.relative_to(directory).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in directory.rglob('*') if p.is_file()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bridge-report', type=Path, required=True)
    parser.add_argument('--wrong-library', type=Path, required=True,
                        help='Same source/dependencies, opposite debug/release native build')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    previous = json.loads(args.bridge_report.read_text())
    if previous['status'] != 'PASS':
        parser.error('Requires a passing legacy bridge export fixture')
    source_run = Path(previous['run'])
    previous_manifest = json.loads((source_run / 'export/cubism-export.json').read_text())
    mode = previous_manifest['mode']
    source = source_run / 'project 模型'
    args.output.mkdir(parents=True, exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix='export-identity-', dir=args.output.resolve()))
    project = run / 'project 模型'
    for path in source.rglob('*'):
        if path.is_file():
            destination = project / path.relative_to(source)
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(path.read_bytes())
    helpers = project / 'addons/gd_cubism/editor'
    for path in (ROOT / 'demo/addons/gd_cubism/editor').glob('*'):
        if path.suffix in {'.gd', '.py'} or path.name == '.gdignore':
            (helpers / path.name).write_bytes(path.read_bytes())
    output = run / 'export'
    checks = []

    def invoke(name):
        report = run / (name + '.json')
        with (run / (name + '.log')).open('w') as log:
            result = subprocess.run([sys.executable, str(helpers / 'checked_export.py'),
                                     '--project', str(project), '--preset', previous_manifest['preset'],
                                     '--mode', mode, '--output', str(output), '--redot-bin', os.environ['REDOT_BIN'],
                                     '--report', str(report)], stdout=log, stderr=subprocess.STDOUT,
                                    env=dict(os.environ, PYTHONDONTWRITEBYTECODE='1'), timeout=600)
        return result.returncode, json.loads(report.read_text())

    ok = False
    try:
        code, status = invoke('correct-variant')
        assert code == 0 and status['status'] == 'PASS', status
        manifest = json.loads((output / 'cubism-export.json').read_text())
        assert manifest['build']['target'] == 'template_' + mode
        assert manifest['native_libraries'] == previous_manifest['native_libraries']
        assert all(hashes(output)[name] == digest for name, digest in manifest['files'].items())
        assert not list(output.glob('.cubism-identity-editor*')), 'Probe editor leaked into the package'
        checks.append({'test': 'correct-variant-and-artifact-hashes', 'status': 'PASS'})
        preserved = hashes(output)
        descriptor = project / 'addons/gd_cubism/gd_cubism.gdextension'
        platform = manifest['build']['platform']
        lines = descriptor.read_text().splitlines()
        keys = {platform + '.' + mode + '.x86_64', platform + '.x86_64'}
        selected = [line.split('=', 1)[0].strip() for line in lines if line.split('=', 1)[0].strip() in keys]
        assert len(selected) == 1, 'Expected one matching native descriptor entry'
        # The binary header and dependency versions still match. Only the
        # native build target is wrong, so architecture checks cannot catch it.
        (project / 'addons/gd_cubism/bin' / args.wrong_library.name).write_bytes(args.wrong_library.read_bytes())
        descriptor.write_text('\n'.join(selected[0] + '=' + json.dumps('res://addons/gd_cubism/bin/' + args.wrong_library.name)
                                        if line.split('=', 1)[0].strip() == selected[0] else line for line in lines) + '\n')
        code, status = invoke('wrong-variant')
        assert code == 1 and status['status'] == 'FAIL', status
        assert 'native build target' in status['error'], status
        work = Path(status['work'])
        identity = json.loads((work / 'native-identity.json').read_text())
        assert identity['target'] != 'template_' + mode, identity
        assert not (work / 'smoke.log').exists(), 'Incompatible template must not be launched'
        assert not list((work / 'build').glob('.cubism-identity-editor*')), 'Failed probe was not cleaned up'
        assert hashes(output) == preserved, 'Wrong native variant replaced the previous build'
        checks.append({'test': 'wrong-variant-rejected-previous-preserved', 'status': 'PASS'})
        ok = True
    except (AssertionError, OSError, KeyError, subprocess.TimeoutExpired) as error:
        checks.append({'test': 'identity-assertions', 'status': 'FAIL', 'error': str(error)})
    report = {'status': 'PASS' if ok else 'FAIL', 'mode': mode, 'run': str(run), 'checks': checks}
    (args.output / 'export-identity-report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2), flush=True)
    return 0 if ok else 1


if __name__ == '__main__':
    raise SystemExit(main())
