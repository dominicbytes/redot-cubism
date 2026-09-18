#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Run the licensed desktop functional sequence for one native build variant."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import signal
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def sha256(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def check_report(path, library_hash, engine_version):
    report = json.loads(path.read_text())
    if not isinstance(report, dict) or report.get('status') != 'PASS':
        raise ValueError('Child suite did not pass')
    if report.get('library_sha256', library_hash) != library_hash:
        raise ValueError('Child suite tested a different library')
    if report.get('engine_version', engine_version) != engine_version:
        raise ValueError('Child suite tested a different engine')
    checks = report.get('checks', [])
    if not isinstance(checks, list) or any(not isinstance(check, dict) or check.get('status') != 'PASS' for check in checks):
        raise ValueError('Child suite contains an incomplete or failed check')
    return report


def export_stages(library, template, mode, imported, bridge, other_library):
    common = ['--library', str(library)]
    template = ['--template', str(template)]
    return [
        ('selection', 'run_export_selection_tests.py', template + ['--importer-report', str(imported), '--export-mode', mode, '--preflight'], 'selection-report.json'),
        ('checked-export', 'run_checked_export_tests.py', ['--importer-report', str(imported), '--mode', mode, '--ui'], 'checked-export-report.json'),
        ('legacy-export', 'run_legacy_export_tests.py', common + ['--importer-report', str(imported)], 'legacy-export-report.json'),
        ('legacy-bridge', 'run_legacy_bridge_tests.py', common + template + ['--importer-report', str(imported), '--mode', mode, '--graphics'], 'legacy-bridge-report.json'),
        ('export-identity', 'run_export_identity_tests.py', ['--bridge-report', str(bridge), '--wrong-library', str(other_library)], 'export-identity-report.json'),
    ]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('model', 'library', 'other-library', 'template', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--expression', required=True, help='Known non-neutral model expression')
    parser.add_argument('--mode', choices=['debug', 'release'], required=True)
    args = parser.parse_args()
    if sys.platform not in {'linux', 'win32'}:
        parser.error('Run on a native Linux or Windows host')
    for name in ('model', 'library', 'other_library', 'template'):
        path = getattr(args, name).resolve()
        if not path.is_file(): parser.error('Missing input: ' + str(path))
        setattr(args, name, path)
    engine = Path(os.environ['REDOT_BIN']).resolve()
    version = subprocess.check_output([str(engine), '--version'], text=True, timeout=10).strip()
    pins = json.loads((ROOT / 'DEPENDENCIES.json').read_text())
    if version != pins['redot']['version']: parser.error('Editor version differs from pinned Redot')
    if subprocess.check_output([str(args.template), '--version'], text=True, timeout=10).strip() != version:
        parser.error('Template version differs from editor')
    args.output.mkdir(parents=True, exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix='desktop-' + args.mode + '-', dir=args.output.resolve()))
    native = run / 'native/native-report.json'
    imported = run / 'importer/importer-report.json'
    bridge = run / 'legacy-bridge/legacy-bridge-report.json'
    common = ['--library', str(args.library)]
    model = ['--model', str(args.model)]
    template = ['--template', str(args.template)]
    stages = [
        ('paths', 'run_path_tests.py', common, 'physical-path-report.json'),
        ('native', 'run_native_tests.py', common + model + template + ['--expression', args.expression, '--export-mode', args.mode, '--graphics', 'gl_compatibility'], 'native-report.json'),
        ('editor', 'run_editor_tests.py', common + ['--native-report', str(native)], 'editor-report.json'),
        ('importer', 'run_importer_tests.py', common + model + template + ['--export-mode', args.mode, '--dependencies', '--graphics', 'gl_compatibility'], 'importer-report.json'),
        ('model2d', 'run_model2d_tests.py', common + template + ['--importer-report', str(imported), '--mode', args.mode, '--graphics', '--motion', '--examples', '--audio-timing'], 'model2d-report.json'),
    ] + export_stages(args.library, args.template, args.mode, imported, bridge, args.other_library)
    report = {'status': 'RUNNING', 'suite': 'desktop-functional', 'platform': platform.system(),
              'architecture': platform.machine(), 'mode': args.mode, 'run': str(run),
              'runner_sha256': sha256(__file__),
              'engine_version': version, 'engine_sha256': sha256(engine),
              'library_sha256': sha256(args.library), 'other_library_sha256': sha256(args.other_library),
              'template_sha256': sha256(args.template), 'model_manifest_sha256': sha256(args.model),
              'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
              'source_dirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT)),
              'release_qualified': False,
              'separate_gates': ['Other desktop platform and build variant', 'SDK visual parity and fixture matrix',
                                 'ASan/UBSan lifecycle', 'Dedicated benchmark thresholds',
                                 'Remaining manual editor checks', 'Release audit and publication'],
              'stages': [{'name': name, 'status': 'NOT_RUN'} for name, *_ in stages]}
    destination = run / 'desktop-report.json'

    def save():
        destination.write_text(json.dumps(report, indent=2) + '\n')

    env = dict(os.environ, REDOT_BIN=str(engine), PYTHONUNBUFFERED='1', PYTHONDONTWRITEBYTECODE='1',
               PYTHONUTF8='1', PYTHONIOENCODING='utf-8')
    save()
    print('Desktop report: ' + str(destination), flush=True)
    for stage, (name, tool, switches, filename) in zip(report['stages'], stages):
        output = run / name
        output.mkdir()
        command = [sys.executable, str(ROOT / 'tools' / tool), *switches, '--output', str(output)]
        stage.update(status='RUNNING', command=command, runner_sha256=sha256(ROOT / 'tools' / tool),
                     log=str(output / 'runner.log'), report=str(output / filename))
        save()
        print(name + ': RUNNING', flush=True)
        start = time.monotonic()
        try:
            with (output / 'runner.log').open('w') as log:
                process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT,
                                           start_new_session=os.name != 'nt')
                stage['pid'] = process.pid
                save()
                try:
                    code = process.wait(timeout=1800)
                except subprocess.TimeoutExpired:
                    if os.name == 'nt':
                        subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'], capture_output=True, timeout=30)
                    else:
                        os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=30)
                    code = 124
            stage['exit_code'] = code
            if code: raise ValueError('Child process exited ' + str(code))
            check_report(output / filename, report['library_sha256'], version)
            stage['status'] = 'PASS'
        except (OSError, ValueError, subprocess.TimeoutExpired) as error:
            stage.update(status='FAIL', error=str(error))
        stage['elapsed_seconds'] = round(time.monotonic() - start, 3)
        if stage['status'] != 'PASS': report['status'] = 'FAIL'
        save()
        print(name + ': ' + stage['status'], flush=True)
        if report['status'] == 'FAIL': return 1
    report['status'] = 'PASS'
    save()
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
