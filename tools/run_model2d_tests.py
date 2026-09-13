#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Exercise the preferred native node, then load its scene from a checked export."""
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
    parser.add_argument('--graphics', action='store_true')
    parser.add_argument('--motion', action='store_true', help='Prepare and exercise deterministic native motion fixtures')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    previous = json.loads(args.importer_report.read_text())
    if previous['status'] != 'PASS': parser.error('Requires a passing imported-resource fixture')
    engine = os.environ['REDOT_BIN']
    version = subprocess.check_output([engine, '--version'], text=True, timeout=10).strip()
    if version != previous['engine_version']: parser.error('Pinned editor version mismatch')
    args.output.mkdir(parents=True, exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix='model2d-', dir=args.output.resolve()))
    source = Path(previous['run']) / 'source-not-available'
    project = run / 'project 模型'
    for p in source.rglob('*'):
        if p.is_file():
            q = project / p.relative_to(source)
            q.parent.mkdir(parents=True, exist_ok=True)
            q.write_bytes(p.read_bytes())
    addon = project / 'addons/gd_cubism'
    (addon / 'bin' / args.library.name).write_bytes(args.library.read_bytes())
    platform = 'windows' if os.name == 'nt' else 'linux'
    (addon / 'gd_cubism.gdextension').write_text('[configuration]\nentry_symbol="gd_cubism_library_init"\ncompatibility_minimum="26.2"\ndisable_godot_checks=true\nreloadable=false\n[libraries]\n' + platform + '.x86_64="res://addons/gd_cubism/bin/' + args.library.name + '"\n')
    for p in (ROOT / 'demo/addons/gd_cubism/editor').glob('*'):
        if p.suffix in {'.gd', '.py'} or p.name == '.gdignore': (addon / 'editor' / p.name).write_bytes(p.read_bytes())
    (project / 'model2d_checks.gd').write_bytes((ROOT / 'tests/native/project/model2d_checks.gd').read_bytes())
    (project / 'model2d_render_checks.gd').write_bytes((ROOT / 'tests/native/project/model2d_render_checks.gd').read_bytes())
    if args.motion:
        (project / 'motion_api_checks.gd').write_bytes((ROOT / 'tests/native/project/motion_api_checks.gd').read_bytes())
        (project / 'expression_api_checks.gd').write_bytes((ROOT / 'tests/native/project/expression_api_checks.gd').read_bytes())
        driver = project / 'addons/motion_test'
        driver.mkdir(exist_ok=True)
        (driver / 'checks.gd').write_bytes((ROOT / 'tests/editor/preferred_motion_prepare.gd').read_bytes())
        (driver / 'plugin.cfg').write_text('[plugin]\nname="Motion fixtures"\ndescription="Private test"\nauthor="Tests"\nversion="1"\nscript="checks.gd"\n')
        config = (project / 'project.godot').read_text()
        config = re.sub(r'\[editor_plugins\][\s\S]*?(?=\n\[|\Z)', '', config)
        (project / 'project.godot').write_text(config + '\n[editor_plugins]\nenabled=PackedStringArray("res://addons/motion_test/plugin.cfg")\n')
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1')
    for kind in ('CONFIG', 'DATA', 'CACHE'):
        directory = run / kind.lower(); directory.mkdir()
        env['XDG_' + kind + '_HOME'] = str(directory)
    (run / 'cache/fontconfig').mkdir()
    checks = []

    def execute(name, command, marker=None, cwd=project):
        with (run / (name + '.log')).open('w') as log:
            result = subprocess.run(command, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=600)
        log = (run / (name + '.log')).read_text()
        ok = result.returncode == 0 and not re.search(r'ERROR:|WARNING:|SCRIPT ERROR|crashed', log) and (marker is None or marker in log)
        checks.append({'test': name, 'status': 'PASS' if ok else 'FAIL', 'exit_code': result.returncode})
        print(name, checks[-1]['status'], flush=True)
        if not ok: raise ValueError(log[-5000:])

    ok = False
    try:
        if args.motion:
            execute('prepare-motion', [engine, '--headless', '--editor', '--path', str(project), '--quit-after', '10000'], 'CUBISM_PREFERRED_MOTION_PREPARED')
            config = (project / 'project.godot').read_text()
            (project / 'project.godot').write_text(re.sub(r'\[editor_plugins\][\s\S]*?(?=\n\[|\Z)', '', config))
            execute('native-motion', [engine, '--headless', '--path', str(project), '--script', 'res://motion_api_checks.gd', '--quit-after', '10000'], 'CUBISM_MOTION_API_PASS')
            execute('native-expression', [engine, '--headless', '--path', str(project), '--script', 'res://expression_api_checks.gd', '--quit-after', '10000'], 'CUBISM_EXPRESSION_API_PASS')
        execute('native-node', [engine, '--headless', '--path', str(project), '--script', 'res://model2d_checks.gd', '--quit-after', '10000', '--', '--prepare-scene'], 'CUBISM_MODEL2D_PASS')
        template = json.dumps(str(args.template.resolve()))
        (project / 'export_presets.cfg').write_text('[preset.0]\nname="Model2D"\nplatform="' + ('Windows Desktop' if os.name == 'nt' else 'Linux') + '"\nrunnable=true\nexport_path=""\nexport_filter="resources"\nexport_files=PackedStringArray("res://model2d.tscn", "res://model2d_checks.gd", "res://model2d_render_checks.gd")\ninclude_filter=""\nexclude_filter=""\nscript_export_mode=2\n[preset.0.options]\ncustom_template/debug=' + template + '\ncustom_template/release=' + template + '\nbinary_format/architecture="x86_64"\nbinary_format/embed_pck=false\n')
        output = run / 'export'
        if args.motion:
            presets = (project / 'export_presets.cfg').read_text()
            (project / 'export_presets.cfg').write_text(presets.replace('"res://model2d.tscn",', '"res://expression_api_checks.gd", "res://motion_api_checks.gd", "res://model2d.tscn",'))
        execute('checked-export', [sys.executable, str(ROOT / 'tools/checked_export.py'), '--project', str(project), '--preset', 'Model2D', '--output', str(output), '--redot-bin', engine, '--mode', args.mode, '--report', str(run / 'checked.json')])
        project.rename(run / 'source-not-available')
        try:
            execute('exported-node', [str(output / ('game.exe' if os.name == 'nt' else 'game')), '--headless', '--script', 'res://model2d_checks.gd', '--quit-after', '10000'], 'CUBISM_MODEL2D_PASS', output)
            if args.motion:
                execute('exported-motion', [str(output / ('game.exe' if os.name == 'nt' else 'game')), '--headless', '--script', 'res://motion_api_checks.gd', '--quit-after', '10000'], 'CUBISM_MOTION_API_PASS', output)
                execute('exported-expression', [str(output / ('game.exe' if os.name == 'nt' else 'game')), '--headless', '--script', 'res://expression_api_checks.gd', '--quit-after', '10000'], 'CUBISM_EXPRESSION_API_PASS', output)
            if args.graphics:
                captures = run / 'captures'; captures.mkdir()
                command = [str(output / ('game.exe' if os.name == 'nt' else 'game')), '--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy', '--script', 'res://model2d_render_checks.gd', '--quit-after', '1000']
                if os.name != 'nt': command += ['--display-driver', 'x11']
                execute('exported-render', [*command, '--', str(captures), *(['--motion'] if args.motion else [])], 'CUBISM_MODEL2D_RENDER_PASS', output)
        finally:
            (run / 'source-not-available').rename(project)
        ok = True
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        checks.append({'test': 'node-assertions', 'status': 'FAIL', 'error': str(error)})
    report = {'status': 'PASS' if ok else 'FAIL', 'engine_version': version, 'run': str(run), 'mode': args.mode,
              'library_sha256': hashlib.sha256(args.library.read_bytes()).hexdigest(), 'checks': checks}
    (args.output / 'model2d-report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
    return 0 if ok else 1


if __name__ == '__main__':
    raise SystemExit(main())
