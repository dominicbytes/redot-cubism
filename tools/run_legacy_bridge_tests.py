#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Qualify the imported legacy path bridge and source-free selective export."""
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--importer-report', type=Path, required=True)
    parser.add_argument('--library', type=Path, required=True)
    parser.add_argument('--template', type=Path, required=True)
    parser.add_argument('--mode', choices=['debug', 'release'], default='debug')
    parser.add_argument('--graphics', action='store_true', help='Also render the source-free legacy scenes with OpenGL and save captures')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    previous = json.loads(args.importer_report.read_text())
    if previous['status'] != 'PASS':
        parser.error('Requires a passing importer fixture')
    engine = os.environ['REDOT_BIN']
    version = subprocess.check_output([engine, '--version'], text=True, timeout=10).strip()
    if version != previous['engine_version'] or subprocess.check_output([str(args.template), '--version'], text=True, timeout=10).strip() != version:
        parser.error('Editor/template version mismatch')
    args.output.mkdir(parents=True, exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix='legacy-bridge-', dir=args.output.resolve()))
    project = run / 'project 模型'
    source = Path(previous['run']) / 'source-not-available'
    for path in source.rglob('*'):
        if path.is_file():
            destination = project / path.relative_to(source)
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(path.read_bytes())
    for path in (ROOT / 'demo/addons/gd_cubism/editor').glob('*'):
        if path.suffix in {'.gd', '.py'} or path.name == '.gdignore':
            (project / 'addons/gd_cubism/editor' / path.name).write_bytes(path.read_bytes())
    assert (project / 'addons/gd_cubism/bin' / args.library.name).exists(), 'Use the same build variant as the importer fixture'
    (project / 'addons/gd_cubism/bin' / args.library.name).write_bytes(args.library.read_bytes())
    original = source / json.loads((source / 'fixture.json').read_text())['model'].removeprefix('res://')
    sources = []
    for index, directory in enumerate(['legacy-a', 'legacy-b']):
        for path in original.parent.rglob('*'):
            if path.is_file() and path.suffix not in {'.import', '.uid'} and not path.name.endswith('.model3.json'):
                target = project / directory / path.relative_to(original.parent)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(path.read_bytes())
        manifest = json.loads(original.read_text())
        manifest.setdefault('Layout', {})['x'] = index * 0.5
        name = directory + '/模型.model3.json'
        # Materialize the source from the editor test after startup scanning, so
        # preparation is measured independently of discovery/cache behavior.
        (project / (name + '.fixture')).write_text(json.dumps(manifest, ensure_ascii=False))
        sources.append('res://' + name)
    (project / 'bridge-fixture.json').write_text(json.dumps({'sources': sources}))
    driver = project / 'addons/bridge_test'
    driver.mkdir()
    (driver / 'checks.gd').write_bytes((ROOT / 'tests/editor/legacy_bridge_prepare.gd').read_bytes())
    (driver / 'plugin.cfg').write_text('[plugin]\nname="Legacy bridge checks"\ndescription="Private test"\nauthor="Tests"\nversion="1"\nscript="checks.gd"\n')
    (project / 'legacy_bridge_checks.gd').write_bytes((ROOT / 'tests/native/project/legacy_bridge_checks.gd').read_bytes())
    config = 'config_version=5\n[application]\nconfig/name="Legacy bridge checks"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n'
    (project / 'project.godot').write_text(config + '[editor_plugins]\nenabled=PackedStringArray("res://addons/bridge_test/plugin.cfg")\n')
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1')
    for key in ('CONFIG', 'DATA', 'CACHE'):
        directory = run / key.lower()
        directory.mkdir()
        env['XDG_' + key + '_HOME'] = str(directory)
    (run / 'cache/fontconfig').mkdir()
    checks = []

    def execute(name, command, marker=None, cwd=run, timeout=180, expected_code=0):
        with (run / (name + '.log')).open('w') as log:
            result = subprocess.run(command, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=timeout)
        text = (run / (name + '.log')).read_text()
        ok = result.returncode == expected_code and not re.search(r'ERROR:|WARNING:|SCRIPT ERROR|crashed', text) and (marker is None or marker in text)
        checks.append({'test': name, 'status': 'PASS' if ok else 'FAIL', 'exit_code': result.returncode})
        print(name, checks[-1]['status'], flush=True)
        assert ok, text[-6000:]

    ok = False
    try:
        execute('prepare', [engine, '--headless', '--editor', '--path', str(project), '--quit-after', '10000'], 'CUBISM_LEGACY_BRIDGE_PREPARED')
        expected = json.loads((project / 'bridge-expected.json').read_text())
        assert len(expected['checks']) == 10
        (run / 'preparation.json').write_text(json.dumps(expected, indent=2) + '\n')
        (project / 'project.godot').write_text(config)
        execute('restart-runtime', [engine, '--headless', '--path', str(project), '--script', 'res://legacy_bridge_checks.gd', '--quit-after', '2'], 'CUBISM_LEGACY_BRIDGE_PASS')
        platform = 'Windows Desktop' if os.name == 'nt' else 'Linux'
        template = json.dumps(str(args.template.resolve()))
        files = [*expected['scenes'], 'res://legacy_bridge_checks.gd']
        (project / 'export_presets.cfg').write_text(
            f'[preset.0]\nname="Legacy"\nplatform="{platform}"\nrunnable=true\nexport_path=""\nexport_filter="resources"\n'
            'export_files=PackedStringArray(' + ','.join(json.dumps(path) for path in files) + ')\n'
            'include_filter="bridge-expected.json"\nexclude_filter="addons/bridge_test/*,addons/import_test/*"\nscript_export_mode=2\n'
            f'[preset.0.options]\ncustom_template/debug={template}\ncustom_template/release={template}\n'
            'binary_format/architecture="x86_64"\nbinary_format/embed_pck=false\n')
        output = run / 'export'
        status_path = run / 'checked.json'
        execute('checked-export', [sys.executable, str(ROOT / 'tools/checked_export.py'), '--project', str(project),
                                  '--preset', 'Legacy', '--output', str(output), '--redot-bin', engine,
                                  '--mode', args.mode, '--report', str(status_path)], timeout=600)
        status = json.loads(status_path.read_text())
        preflight = json.loads((Path(status['work']) / 'preflight.json').read_text())
        assert preflight['models'] == 2 and all(path in preflight['validated_files'] for path in sources), preflight
        # No broad raw-file filter. Both source directories must be injected from
        # the saved bridge edges, then load with the developer project absent.
        project.rename(run / 'source-not-available')
        try:
            game = output / ('game.exe' if os.name == 'nt' else 'game')
            execute('exported-legacy-runtime', [str(game), '--headless', '--script', 'res://legacy_bridge_checks.gd', '--quit-after', '2'], 'CUBISM_LEGACY_BRIDGE_PASS', output)
            execute('exported-wrong-source-rejected', [str(game), '--headless', '--script', 'res://legacy_bridge_checks.gd', '--quit-after', '2', '--', '--wrong-source'], 'CUBISM_LEGACY_BRIDGE_FAIL', output, expected_code=1)
            if args.graphics:
                captures = run / 'captures'
                captures.mkdir()
                command = [str(game), '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--script', 'res://legacy_bridge_checks.gd', '--quit-after', '1000']
                if os.name != 'nt':
                    command += ['--display-driver', 'x11']
                execute('exported-legacy-graphics', [*command, '--', '--capture-dir=' + str(captures)], 'CUBISM_LEGACY_BRIDGE_PASS', output)
                assert len(list(captures.glob('*.png'))) == 4
        finally:
            (run / 'source-not-available').rename(project)
        ok = True
    except (AssertionError, OSError, KeyError, subprocess.TimeoutExpired) as error:
        checks.append({'test': 'bridge-assertions', 'status': 'FAIL', 'error': str(error)})
        print(str(error), flush=True)
    report = {'status': 'PASS' if ok else 'FAIL', 'engine_version': version, 'run': str(run),
              'library_sha256': hashlib.sha256(args.library.read_bytes()).hexdigest(), 'checks': checks}
    (args.output / 'legacy-bridge-report.json').write_text(json.dumps(report, indent=2) + '\n')
    return 0 if ok else 1


if __name__ == '__main__':
    raise SystemExit(main())
