#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Test real export selections on a private copy of a completed importer fixture."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from pck_inspection import inspect_pack

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--importer-report', type=Path, required=True)
    parser.add_argument('--template', type=Path, required=True)
    parser.add_argument('--export-mode', choices=['debug', 'release'], default='debug')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--preflight', action='store_true', help='Check the shared CLI validator against engine export callbacks and rejection cases')
    args = parser.parse_args()
    previous = json.loads(args.importer_report.read_text())
    if previous['status'] != 'PASS' or not any(c['test'] == 'exported-model' and c['status'] == 'PASS' for c in previous['checks']):
        parser.error('Requires a completed full-model importer export check')
    engine = os.environ['REDOT_BIN']
    version = subprocess.check_output([engine, '--version'], text=True, timeout=10).strip()
    if version != previous['engine_version'] or version != json.loads((ROOT/'DEPENDENCIES.json').read_text())['redot']['version']:
        parser.error('Editor version mismatch')
    if subprocess.check_output([str(args.template), '--version'], text=True, timeout=10).strip() != version:
        parser.error('Template version mismatch')
    args.output.mkdir(parents=True, exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix='export-selection-', dir=args.output.resolve()))
    project = run/'project'
    source = Path(previous['run'])/'source-not-available'
    for path in source.rglob('*'):
        if path.is_file():
            destination = project/path.relative_to(source)
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(path.read_bytes())
    libraries = list((project/'addons/gd_cubism/bin').iterdir())
    if not any(hashlib.sha256(p.read_bytes()).hexdigest() == previous['library_sha256'] for p in libraries if p.is_file()):
        parser.error('Fixture library hash mismatch')
    (project/'export_selection_checks.gd').write_bytes((ROOT/'tests/native/project/export_selection_checks.gd').read_bytes())
    if args.preflight:
        for path in (ROOT/'demo/addons/gd_cubism/editor').glob('*.gd'):
            destination = project/'addons/gd_cubism/editor'/path.name
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(path.read_bytes())
    driver = project/'addons/selection_test'
    driver.mkdir()
    (driver/'checks.gd').write_bytes((ROOT/'tests/editor/export_selection_prepare.gd').read_bytes())
    (driver/'plugin.cfg').write_text('[plugin]\nname="Selection checks"\ndescription="Private checks"\nauthor="Tests"\nversion="1"\nscript="checks.gd"\n')
    base_config = 'config_version=5\n[application]\nconfig/name="Cubism export selection checks"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n'
    (project/'project.godot').write_text(base_config+'\n[editor_plugins]\nenabled=PackedStringArray("res://addons/selection_test/plugin.cfg")\n')
    env = dict(os.environ)
    for key in ('CONFIG','DATA','CACHE'):
        directory = run/key.lower()
        directory.mkdir()
        env['XDG_'+key+'_HOME'] = str(directory)
    (run/'cache/fontconfig').mkdir()
    checks = []

    def execute(name, command, marker=None, cwd=None):
        try:
            result = subprocess.run(command, cwd=cwd or run, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=180)
            code, log = result.returncode, result.stdout
        except subprocess.TimeoutExpired as exc:
            code = 124
            log = (exc.stdout or b'').decode('utf-8', errors='replace') if isinstance(exc.stdout, bytes) else (exc.stdout or '')
        (run/(name+'.log')).write_text(log)
        ok = code == 0 and not re.search(r'ERROR:|WARNING:|SCRIPT ERROR|crashed', log) and (marker is None or marker in log)
        checks.append({'test':name,'status':'PASS' if ok else 'FAIL','exit_code':code})
        print(name, checks[-1]['status'], flush=True)
        if not ok:
            print(log)
        return ok

    ok = execute('prepare', [engine,'--headless','--editor','--path',str(project),'--quit-after','10000'], 'CUBISM_EXPORT_SELECTION_PREPARED')
    expected = json.loads((project/'selection-expected.json').read_text()) if ok else {}
    if ok and args.preflight:
        (driver/'checks.gd').write_bytes((ROOT/'tests/editor/export_preflight_checks.gd').read_bytes())
        ok = execute('preflight-cases', [engine,'--headless','--editor','--path',str(project),'--quit-after','10000'], 'CUBISM_EXPORT_PREFLIGHT_CHECKS_PASS')
        (driver/'checks.gd').write_bytes((ROOT/'tests/editor/export_selection_recorder.gd').read_bytes())
    modes = ('resources','scenes','embedded','all','autoload','exclude','customized') if args.preflight else ('resources','scenes','embedded','all')
    for mode in modes:
        if not ok:
            break
        scene = 'matrix-embedded.tscn' if mode == 'embedded' else 'matrix-external.tscn' if mode == 'scenes' else 'texture_export_scene.tscn'
        selection = ['res://'+scene] if mode in ('scenes','embedded') else ['res://imported-model.res','res://export_selection_checks.gd','res://'+scene]
        config = base_config.replace('[application]', '[application]\nrun/main_scene="res://'+scene+'"')
        if args.preflight:
            config += '\n[editor_plugins]\nenabled=PackedStringArray("res://addons/selection_test/plugin.cfg")\n'
        if mode == 'autoload':
            config += '\n[autoload]\nSelectionModel="*res://matrix-external.tscn"\n'
            selection.remove('res://imported-model.res')
        if mode == 'exclude':
            selection = ['res://matrix-unselected.res',expected['unselected']]
        (project/'project.godot').write_text(config)
        platform = 'Windows Desktop' if os.name == 'nt' else 'Linux'
        template = json.dumps(str(args.template.resolve()))
        filter_mode = 'scenes' if mode == 'embedded' else 'all_resources' if mode == 'all' else mode
        if mode == 'autoload':
            filter_mode = 'resources'
        customized = 'customized_files={"res://matrix-unselected.res":"remove",'+json.dumps(expected['unselected'])+':"remove"}\n' if mode == 'customized' else ''
        (project/'export_presets.cfg').write_text(
            f'[preset.0]\nname="Models"\nplatform="{platform}"\nrunnable=true\nexport_filter="{filter_mode}"\n'
            +customized+
            'export_files=PackedStringArray('+','.join(json.dumps(s) for s in selection)+')\n'
            'include_filter="selection-expected.json"\nexclude_filter="addons/selection_test/*,addons/import_test/*"\nexport_path=""\nscript_export_mode=2\n'
            f'[preset.0.options]\ncustom_template/debug={template}\ncustom_template/release={template}\n'
            'binary_format/architecture="x86_64"\nbinary_format/embed_pck=false\n')
        output = run/mode
        output.mkdir()
        game = output/('game.exe' if os.name == 'nt' else 'game')
        if args.preflight:
            preflight_report = run/(mode+'-preflight.json')
            ok = execute(mode+'-preflight', [engine,'--headless','--editor','--path',str(project),'--quit-after','10000','--','--cubism-preflight','Models',str(preflight_report)], 'CUBISM_EXPORT_PREFLIGHT_PASS')
            if not ok:
                break
        ok = execute(mode+'-export', [engine,'--headless','--path',str(project),'--export-'+args.export_mode,'Models',str(game)])
        if not ok:
            break
        try:
            if args.preflight:
                preflight = json.loads(preflight_report.read_text())
                observed = json.loads((project/'selection-observed.json').read_text())
                assert preflight['ok'] and preflight['validated_files'] == observed, {'preflight':preflight['validated_files'],'engine':observed}
                (run/(mode+'-observed.json')).write_text(json.dumps(observed,indent=2)+'\n')
            archive = inspect_pack(output/'game.pck')
            files = archive['files']
            for name, digest in expected['raw'].items():
                assert files[name.removeprefix('res://')]['sha256'] == digest, name
            if args.preflight:
                for name, digest in preflight['raw_hashes'].items():
                    assert files[name.removeprefix('res://')]['sha256'] == digest, name
            assert (expected['unselected'].removeprefix('res://') in files) == (mode == 'all')
            if mode == 'embedded':
                assert 'imported-model.res' not in files
            (run/(mode+'-archive.json')).write_text(json.dumps(archive, indent=2)+'\n')
            checks.append({'test':mode+'-archive','status':'PASS'})
        except (ValueError, OSError, AssertionError, KeyError) as exc:
            checks.append({'test':mode+'-archive','status':'FAIL','error':str(exc)})
            ok = False
            break
        hidden = run/'source-not-available'
        project.rename(hidden)
        switches = ['--'+mode] if mode in ('embedded','all') else []
        try:
            ok = execute(mode+'-runtime', [str(game),'--headless','--script','res://export_selection_checks.gd','--quit-after','2','--',*switches], 'CUBISM_EXPORT_SELECTION_PASS', output)
        finally:
            hidden.rename(project)
    report = {'status':'PASS' if ok else 'FAIL','engine_version':version,'library_sha256':previous['library_sha256'],'run':str(run),'checks':checks}
    (args.output/'selection-report.json').write_text(json.dumps(report,indent=2)+'\n')
    return 0 if ok else 1


if __name__ == '__main__':
    raise SystemExit(main())
