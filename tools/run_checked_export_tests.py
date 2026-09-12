#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Exercise real checked exports and verify failures preserve the previous build."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def tree_hashes(directory):
    return {p.relative_to(directory).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in directory.rglob('*') if p.is_file()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--importer-report', type=Path, required=True)
    parser.add_argument('--mode', choices=['debug', 'release'], default='debug')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--ui', action='store_true', help='Also invoke the real editor menu and capture its dialog using OpenGL')
    args = parser.parse_args()
    previous = json.loads(args.importer_report.read_text())
    if previous['status'] != 'PASS':
        parser.error('Requires a passing importer fixture')
    args.output.mkdir(parents=True, exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix='checked-export-', dir=args.output.resolve()))
    project = run / 'project 模型'
    for path in (Path(previous['run']) / 'source-not-available').rglob('*'):
        if path.is_file():
            destination = project / path.relative_to(Path(previous['run']) / 'source-not-available')
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(path.read_bytes())
    for path in (ROOT / 'demo/addons/gd_cubism/editor').glob('*'):
        if path.suffix in {'.gd', '.py'} or path.name == '.gdignore':
            (project / 'addons/gd_cubism/editor' / path.name).write_bytes(path.read_bytes())
    libraries = project / 'addons/gd_cubism/bin'
    assert any(hashlib.sha256(p.read_bytes()).hexdigest() == previous['library_sha256'] for p in libraries.iterdir())
    output = run / 'exported 游戏'
    checks = []

    def invoke(name, should_pass):
        report = run / (name + '.json')
        command = [sys.executable, str(project / 'addons/gd_cubism/editor/checked_export.py'),
                   '--project', str(project), '--preset', 'Textures', '--output', str(output),
                   '--name', '模型 game', '--mode', args.mode, '--redot-bin', os.environ['REDOT_BIN'], '--report', str(report)]
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=600,
                                env=dict(os.environ, PYTHONDONTWRITEBYTECODE='1'))
        (run / (name + '.log')).write_text(result.stdout)
        status = json.loads(report.read_text())
        ok = (result.returncode == 0 and status['status'] == 'PASS') if should_pass else (result.returncode != 0 and status['status'] == 'FAIL')
        checks.append({'test': name, 'status': 'PASS' if ok else 'FAIL', 'exit_code': result.returncode, 'result': status})
        print(name, checks[-1]['status'], flush=True)
        assert ok, status
        return status

    ok = False
    try:
        first = invoke('valid-unicode', True)
        smoke = json.loads((Path(first['work']) / 'smoke.json').read_text())
        assert smoke['models'] > 0 and smoke['motions'] > 0 and smoke['expressions'] > 0 and smoke['parameters_changed']
        (output / 'obsolete-library.txt').write_text('previous only')
        second = invoke('replace-complete-build', True)
        assert not (output / 'obsolete-library.txt').exists()
        assert (Path(second['work']) / 'previous/obsolete-library.txt').read_text() == 'previous only'
        preserved = tree_hashes(output)
        preflight = json.loads((Path(second['work']) / 'preflight.json').read_text())
        moc = project / next(p for p in preflight['raw_hashes'] if p.endswith('.moc3')).removeprefix('res://')
        original = moc.read_bytes()
        moc.unlink()
        try:
            failed = invoke('missing-moc', False)
            assert not (Path(failed['work']) / 'export.log').exists()
            assert tree_hashes(output) == preserved
        finally:
            moc.write_bytes(original)
        preset = project / 'export_presets.cfg'
        original_preset = preset.read_text()
        lines = original_preset.splitlines()
        preset.write_text('\n'.join('custom_template/' + args.mode + '="/missing/cubism-template"' if line.startswith('custom_template/' + args.mode + '=') else line for line in lines) + '\n')
        try:
            failed = invoke('packaging-failure', False)
            assert (Path(failed['work']) / 'export.log').exists()
            assert tree_hashes(output) == preserved
        finally:
            preset.write_text(original_preset)
        script = project / 'addons/gd_cubism/editor/export_smoke.gd'
        original_script = script.read_bytes()
        script.write_text('extends SceneTree\nfunc _initialize():\n\tprinterr("Injected smoke failure")\n\tquit(1)\n')
        try:
            failed = invoke('smoke-failure', False)
            assert (Path(failed['work']) / 'archive.json').exists()
            assert tree_hashes(output) == preserved
        finally:
            script.write_bytes(original_script)
        if args.ui:
            driver = project / 'addons/checked_export_test'
            driver.mkdir()
            (driver / 'checks.gd').write_bytes((ROOT / 'tests/editor/checked_export_ui_checks.gd').read_bytes())
            (driver / 'plugin.cfg').write_text('[plugin]\nname="Checked export UI test"\ndescription="Private integration test"\nauthor="Tests"\nversion="1"\nscript="checks.gd"\n')
            config = project / 'project.godot'
            config.write_text(config.read_text() + '\n[editor_plugins]\nenabled=PackedStringArray("res://addons/checked_export_test/plugin.cfg")\n')
            env = dict(os.environ, CUBISM_PYTHON_BIN=sys.executable, CUBISM_UI_MODE=args.mode,
                       CUBISM_UI_BEFORE=str(run / 'dialog-before.png'), CUBISM_UI_AFTER=str(run / 'dialog-after.png'),
                       CUBISM_UI_OUTPUT=str(run / 'ui-export'), PYTHONDONTWRITEBYTECODE='1')
            for kind in ['CONFIG','DATA','CACHE']:
                path = run / ('ui-' + kind.lower())
                path.mkdir()
                env['XDG_' + kind + '_HOME'] = str(path)
            (run / 'ui-cache/fontconfig').mkdir()
            command = [os.environ['REDOT_BIN'], '--editor', '--path', str(project), '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--quit-after', '10000']
            if os.name != 'nt':
                command += ['--display-driver', 'x11']
            with (run / 'editor-ui.log').open('w') as log:
                result = subprocess.run([*command, '--', '--checked-export-ui-test'], env=env, stdout=log, stderr=subprocess.STDOUT, text=True, timeout=300)
            ui_log = (run / 'editor-ui.log').read_text()
            passed = result.returncode == 0 and 'CUBISM_CHECKED_EXPORT_UI_PASS' in ui_log and not re.search(r'ERROR:|WARNING:|SCRIPT ERROR|crashed', ui_log)
            checks.append({'test': 'editor-ui', 'status': 'PASS' if passed else 'FAIL', 'exit_code': result.returncode})
            print('editor-ui', checks[-1]['status'], flush=True)
            assert passed, ui_log[-5000:]
        ok = True
    except (AssertionError, KeyError, OSError, subprocess.TimeoutExpired) as error:
        checks.append({'test': 'pipeline-assertions', 'status': 'FAIL', 'error': str(error)})
        print(str(error), flush=True)
    report = {'status': 'PASS' if ok else 'FAIL', 'run': str(run), 'library_sha256': previous['library_sha256'], 'checks': checks}
    (args.output / 'checked-export-report.json').write_text(json.dumps(report, indent=2) + '\n')
    return 0 if ok else 1


if __name__ == '__main__':
    raise SystemExit(main())
