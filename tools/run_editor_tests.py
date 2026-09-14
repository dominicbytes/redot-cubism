#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Exercise the real editor's preferred-model workflow in a private copied fixture."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--native-report', type=Path, required=True, help='Passing run_native_tests.py report with its prepared fixture')
    parser.add_argument('--library', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--headless', action='store_true', help='Diagnostic smoke only; does not qualify real editor graphics')
    args = parser.parse_args()
    previous = json.loads(args.native_report.read_text())
    if previous['status'] != 'PASS' or not previous['real_model_tested']: parser.error('A passing real-model fixture is required')
    engine = os.environ['REDOT_BIN']
    version = subprocess.check_output([engine, '--version'], text=True, timeout=10).strip()
    if version != previous['engine_version']: parser.error('Editor version differs from prepared fixture')
    source = args.native_report.resolve().parent / Path(previous['checks'][0]['log']).parent / 'project'
    if not (source / 'project.godot').is_file(): parser.error('Prepared source project is missing')
    args.output.mkdir(parents=True, exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix='editor-workflow-', dir=args.output.resolve()))
    project = run / 'project'
    shutil.copytree(source, project, copy_function=shutil.copyfile,
                    ignore=lambda directory, names: [name for name in names if name == 'shader_cache' or (Path(directory).name == '.godot' and name == 'editor')])
    addon = project / 'addons/gd_cubism'
    # The native fixture includes example checks; the editor scans their scripts.
    examples = ROOT / 'demo/addons/gd_cubism/examples'
    for source_file in examples.rglob('*'):
        if source_file.is_file():
            target = addon / 'examples' / source_file.relative_to(examples)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(source_file.read_bytes())
    (addon / 'bin' / args.library.name).write_bytes(args.library.read_bytes())
    platform = 'windows' if os.name == 'nt' else 'linux'
    (addon / 'gd_cubism.gdextension').write_text('[configuration]\nentry_symbol="gd_cubism_library_init"\ncompatibility_minimum="26.2"\ndisable_godot_checks=true\nreloadable=false\n[libraries]\n' + platform + '.x86_64="res://addons/gd_cubism/bin/' + args.library.name + '"\n')
    driver = project / 'addons/editor_workflow_test'
    driver.mkdir(exist_ok=True)
    script = ROOT / 'tests/editor/editor_workflow_checks.gd'
    (driver / 'checks.gd').write_bytes(script.read_bytes())
    (driver / 'plugin.cfg').write_text('[plugin]\nname="Cubism editor workflow tests"\ndescription="Private test driver"\nauthor="Tests"\nversion="1"\nscript="checks.gd"\n')
    config = (project / 'project.godot').read_text()
    config = re.sub(r'^run/main_scene=.*\n', '', config, flags=re.MULTILINE)
    config = re.sub(r'\[editor_plugins\][\s\S]*?(?=\n\[|\Z)', '', config)
    (project / 'project.godot').write_text(config + '\n[editor_plugins]\nenabled=PackedStringArray("res://addons/editor_workflow_test/plugin.cfg")\n')
    fixture = json.loads((project / 'fixture.json').read_text())
    inputs = {'resource': 'res://factory-model.res', 'legacy_source': fixture['model'],
              'motion': fixture['motion_group'] + '/0', 'expression': fixture['expression']}
    if not args.headless: inputs['capture'] = str(run / 'editor.png')
    (project / 'editor-workflow-fixture.json').write_text(json.dumps(inputs))
    env = dict(os.environ, UBSAN_OPTIONS='halt_on_error=1:print_stacktrace=1')
    for key in ('CONFIG', 'CACHE', 'DATA'): env['XDG_' + key + '_HOME'] = str(run / key.lower())
    flags = ['--headless'] if args.headless else ['--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy']
    if not args.headless and os.name != 'nt': flags += ['--display-driver', 'x11']
    command = [engine, '--editor', '--path', str(project), *flags, '--quit-after', '10000']
    with (run / 'editor.log').open('w') as log:
        try: code = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=180).returncode
        except subprocess.TimeoutExpired: code = 124
    output = (run / 'editor.log').read_text()
    passed = code == 0 and 'CUBISM_EDITOR_WORKFLOW_PASS' in output and not re.search(r'ERROR:|WARNING:|SCRIPT ERROR|runtime error:|crashed', output)
    if not args.headless: passed = passed and (run / 'editor.png').is_file()
    report = {'status': 'PASS' if passed else 'FAIL', 'engine_version': version, 'run': str(run),
              'exit_code': code, 'command': command, 'graphics': not args.headless,
              'library_sha256': hashlib.sha256(args.library.read_bytes()).hexdigest(),
              'script_sha256': hashlib.sha256(script.read_bytes()).hexdigest(),
              'coverage': 'Preferred model assignment, undo/redo, invalid/clear/recovery, selection, preview, save/reopen, deletion; legacy selection/deletion/close; empty-scene input. Drag/grid input is not exercised.'}
    (args.output / 'editor-report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(output)
    print(json.dumps(report, indent=2))
    return int(not passed)


if __name__ == '__main__':
    raise SystemExit(main())
