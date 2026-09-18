#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Check legacy scene export validation without instantiating user scene scripts."""
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
    parser.add_argument('--library', type=Path, help='Override the fixture library to test a new build')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    previous = json.loads(args.importer_report.read_text())
    if previous['status'] != 'PASS':
        parser.error('Requires a passing importer fixture')
    engine = os.environ['REDOT_BIN']
    version = subprocess.check_output([engine, '--version'], text=True, timeout=10).strip()
    if version != previous['engine_version']:
        parser.error('Editor version mismatch')
    args.output.mkdir(parents=True, exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix='legacy-export-', dir=args.output.resolve()))
    project = run / 'project'
    source = Path(previous['run']) / 'source-not-available'
    for path in source.rglob('*'):
        if path.is_file():
            destination = project / path.relative_to(source)
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(path.read_bytes())
    if args.library:
        (project / 'addons/gd_cubism/bin' / args.library.name).write_bytes(args.library.read_bytes())
    driver = project / 'addons/legacy_test'
    driver.mkdir()
    (driver / 'checks.gd').write_bytes((ROOT / 'tests/editor/legacy_export_checks.gd').read_bytes())
    (driver / 'plugin.cfg').write_text('[plugin]\nname="Legacy export checks"\ndescription="Private regression test"\nauthor="Tests"\nversion="1"\nscript="checks.gd"\n')
    (project / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="Legacy export checks"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n[editor_plugins]\nenabled=PackedStringArray("res://addons/legacy_test/plugin.cfg")\n')
    env = dict(os.environ)
    for key in ('CONFIG', 'DATA', 'CACHE'):
        directory = run / key.lower()
        directory.mkdir()
        env['XDG_' + key + '_HOME'] = str(directory)
    (run / 'cache/fontconfig').mkdir()
    with (run / 'editor.log').open('w') as log:
        result = subprocess.run([engine, '--headless', '--editor', '--path', str(project), '--quit-after', '10000'],
                                cwd=run, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=180)
    log = (run / 'editor.log').read_text()
    observed = project / 'legacy-export-report.json'
    report = json.loads(observed.read_text()) if observed.exists() else {'checks': []}
    ok = (result.returncode == 0 and 'CUBISM_LEGACY_EXPORT_OBSERVED' in log
          and not re.search(r'ERROR:|WARNING:|SCRIPT ERROR|crashed', log)
          and len(report['checks']) == 7 and all(check['status'] == 'PASS' for check in report['checks']))
    # Exercise the actual checked pipeline: rejection must precede packaging and
    # leave an existing output untouched, not merely fail later on missing data.
    (project / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="Legacy checked export"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
    platform = 'Windows Desktop' if os.name == 'nt' else 'Linux'
    (project / 'export_presets.cfg').write_text(
        f'[preset.0]\nname="Legacy"\nplatform="{platform}"\nrunnable=true\nexport_path=""\nexport_filter="scenes"\n'
        'export_files=PackedStringArray("res://legacy-direct.tscn")\n'
        '[preset.0.options]\nbinary_format/architecture="x86_64"\n')
    output = run / 'previous-output'
    output.mkdir()
    (output / 'cubism-export.json').write_text('{}\n')
    (output / 'preserve.txt').write_text('previous build\n')
    preserved = {p.name: p.read_bytes() for p in output.iterdir()}
    checked_report = run / 'checked.json'
    with (run / 'checked.log').open('w') as log_file:
        checked = subprocess.run([sys.executable, str(ROOT / 'tools/checked_export.py'),
                                  '--project', str(project), '--preset', 'Legacy', '--output', str(output),
                                  '--redot-bin', engine, '--report', str(checked_report)],
                                 cwd=run, env=env, stdout=log_file, stderr=subprocess.STDOUT, timeout=300)
    checked_status = json.loads(checked_report.read_text()) if checked_report.exists() else {}
    work = Path(checked_status['work']) if 'work' in checked_status else None
    preflight = json.loads((work / 'preflight.json').read_text()) if work and (work / 'preflight.json').exists() else {}
    rejected = (checked.returncode != 0 and checked_status.get('status') == 'FAIL'
                and any('Legacy Cubism assets' in item['message'] for item in preflight.get('diagnostics', []))
                and not (work / 'export.log').exists()
                and preserved == {p.name: p.read_bytes() for p in output.iterdir()})
    report['checks'].append({'test': 'checked-preflight-preserves-output', 'status': 'PASS' if rejected else 'FAIL', 'result': checked_status})
    ok = ok and rejected
    report.update(status='PASS' if ok else 'FAIL', run=str(run), engine_version=version,
                  libraries={p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                             for p in (project / 'addons/gd_cubism/bin').iterdir() if p.is_file()})
    (args.output / 'legacy-export-report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2), flush=True)
    return 0 if ok else 1


if __name__ == '__main__':
    raise SystemExit(main())
