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
    parser.add_argument('--audio-timing', action='store_true', help='Measure real 30-second cues at fixed/variable frame rates; requires --motion')
    parser.add_argument('--examples', action='store_true', help='Exercise VN/RPG scenes in native and selected exports; requires --motion')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.audio_timing and not args.motion: parser.error('--audio-timing requires --motion')
    if args.examples and not args.motion: parser.error('--examples requires --motion')
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
    (project / 'mask_quality_checks.gd').write_bytes((ROOT / 'tests/native/project/mask_quality_checks.gd').read_bytes())
    (project / 'fallback_checks.gd').write_bytes((ROOT / 'tests/native/project/fallback_checks.gd').read_bytes())
    (project / 'alpha_checks.gd').write_bytes((ROOT / 'tests/native/project/alpha_checks.gd').read_bytes())
    (project / 'mask_policy_checks.gd').write_bytes((ROOT / 'tests/native/project/mask_policy_checks.gd').read_bytes())
    (project / 'debug_overlay_checks.gd').write_bytes((ROOT / 'tests/native/project/debug_overlay_checks.gd').read_bytes())
    (project / 'renderer_transform_checks.gd').write_bytes((ROOT / 'tests/native/project/renderer_transform_checks.gd').read_bytes())
    if args.examples:
        for p in (ROOT / 'demo/addons/gd_cubism/examples').rglob('*'):
            if p.suffix not in {'.gd', '.tscn'}: continue
            q = addon / 'examples' / p.relative_to(ROOT / 'demo/addons/gd_cubism/examples')
            q.parent.mkdir(parents=True, exist_ok=True)
            q.write_bytes(p.read_bytes())
        (project / 'character_example_checks.gd').write_bytes((ROOT / 'tests/native/project/character_example_checks.gd').read_bytes())
    if args.motion:
        (project / 'motion_api_checks.gd').write_bytes((ROOT / 'tests/native/project/motion_api_checks.gd').read_bytes())
        (project / 'expression_api_checks.gd').write_bytes((ROOT / 'tests/native/project/expression_api_checks.gd').read_bytes())
        (project / 'autoplay_checks.gd').write_bytes((ROOT / 'tests/native/project/autoplay_checks.gd').read_bytes())
        (project / 'procedural_checks.gd').write_bytes((ROOT / 'tests/native/project/procedural_checks.gd').read_bytes())
        (project / 'look_checks.gd').write_bytes((ROOT / 'tests/native/project/look_checks.gd').read_bytes())
        (project / 'hit_checks.gd').write_bytes((ROOT / 'tests/native/project/hit_checks.gd').read_bytes())
        (project / 'lip_sync_checks.gd').write_bytes((ROOT / 'tests/native/project/lip_sync_checks.gd').read_bytes())
        (project / 'controller_checks.gd').write_bytes((ROOT / 'tests/native/project/controller_checks.gd').read_bytes())
        (project / 'controller_utility_checks.gd').write_bytes((ROOT / 'tests/native/project/controller_utility_checks.gd').read_bytes())
        (project / 'controller_audio_timing_checks.gd').write_bytes((ROOT / 'tests/native/project/controller_audio_timing_checks.gd').read_bytes())
        (project / 'controller_state_checks.gd').write_bytes((ROOT / 'tests/native/project/controller_state_checks.gd').read_bytes())
        (project / 'parameter_layer_checks.gd').write_bytes((ROOT / 'tests/native/project/parameter_layer_checks.gd').read_bytes())
        (project / 'custom_effect_checks.gd').write_bytes((ROOT / 'tests/native/project/custom_effect_checks.gd').read_bytes())
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
    hit_flags = ['--rendering-method', 'gl_compatibility', '--audio-driver', 'Dummy'] if args.graphics else ['--headless']
    if args.graphics and os.name != 'nt': hit_flags += ['--display-driver', 'x11']
    hit_args = ['--', '--deformation'] if args.graphics else []

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
            execute('native-autoplay', [engine, '--headless', '--path', str(project), '--script', 'res://autoplay_checks.gd', '--quit-after', '10000', '--', '--prepare-scene'], 'CUBISM_AUTOPLAY_PASS')
            execute('native-procedural', [engine, '--headless', '--path', str(project), '--script', 'res://procedural_checks.gd', '--quit-after', '10000'], 'CUBISM_PROCEDURAL_PASS')
            execute('native-parameter-layers', [engine, '--headless', '--path', str(project), '--script', 'res://parameter_layer_checks.gd', '--quit-after', '10000'], 'CUBISM_PARAMETER_LAYERS_PASS')
            execute('native-custom-effects', [engine, '--headless', '--path', str(project), '--script', 'res://custom_effect_checks.gd', '--quit-after', '10000', '--', '--prepare-scene'], 'CUBISM_CUSTOM_EFFECTS_PASS')
            execute('native-look', [engine, '--headless', '--path', str(project), '--script', 'res://look_checks.gd', '--quit-after', '10000'], 'CUBISM_LOOK_PASS')
            execute('native-hit', [engine, *hit_flags, '--path', str(project), '--script', 'res://hit_checks.gd', '--quit-after', '10000', *hit_args], 'CUBISM_HIT_PASS')
            execute('native-lip', [engine, '--headless', '--audio-driver', 'Dummy', '--path', str(project), '--script', 'res://lip_sync_checks.gd', '--quit-after', '10000', '--', '--prepare-scene'], 'CUBISM_LIP_SYNC_PASS')
            execute('native-controller', [engine, '--headless', '--audio-driver', 'Dummy', '--path', str(project), '--script', 'res://controller_checks.gd', '--quit-after', '10000'], 'CUBISM_CONTROLLER_PASS')
            execute('native-controller-utilities', [engine, '--headless', '--path', str(project), '--script', 'res://controller_utility_checks.gd', '--quit-after', '10000'], 'CUBISM_CONTROLLER_UTILITIES_PASS')
            execute('native-controller-state', [engine, '--headless', '--path', str(project), '--script', 'res://controller_state_checks.gd', '--quit-after', '10000', '--', '--prepare-scene'], 'CUBISM_CONTROLLER_STATE_PASS')
            if args.examples:
                example_args = ['--prepare-scenes']
                if args.graphics:
                    captures = run / 'examples-native'; captures.mkdir()
                    example_args += ['--captures', str(captures)]
                execute('native-character-examples', [engine, *hit_flags, '--audio-driver', 'Dummy', '--path', str(project), '--script', 'res://character_example_checks.gd', '--quit-after', '10000', '--', *example_args], 'CUBISM_CHARACTER_EXAMPLES_PASS')
            if args.audio_timing:
                execute('native-controller-audio-timing', [engine, '--headless', '--audio-driver', 'Dummy', '--path', str(project), '--script', 'res://controller_audio_timing_checks.gd', '--quit-after', '10000'], 'CUBISM_CONTROLLER_AUDIO_TIMING_PASS')
        execute('native-node', [engine, '--headless', '--path', str(project), '--script', 'res://model2d_checks.gd', '--quit-after', '10000', '--', '--prepare-scene'], 'CUBISM_MODEL2D_PASS')
        if args.graphics:
            execute('native-debug-overlay', [engine, *hit_flags, '--path', str(project), '--script', 'res://debug_overlay_checks.gd', '--quit-after', '10000'], 'CUBISM_DEBUG_OVERLAY_PASS')
            execute('native-mask-quality', [engine, *hit_flags, '--path', str(project), '--script', 'res://mask_quality_checks.gd', '--quit-after', '10000'], 'CUBISM_MASK_QUALITY_PASS')
            execute('native-fallback', [engine, *hit_flags, '--path', str(project), '--script', 'res://fallback_checks.gd', '--quit-after', '10000', *(['--', '--motion'] if args.motion else [])], 'CUBISM_FALLBACK_PASS')
            execute('native-alpha', [engine, *hit_flags, '--path', str(project), '--script', 'res://alpha_checks.gd', '--quit-after', '10000'], 'CUBISM_ALPHA_RUNTIME_PASS')
            execute('native-mask-policy', [engine, *hit_flags, '--path', str(project), '--script', 'res://mask_policy_checks.gd', '--quit-after', '10000', *(['--', '--motion'] if args.motion else [])], 'CUBISM_MASK_POLICY_PASS')
        template = json.dumps(str(args.template.resolve()))
        (project / 'export_presets.cfg').write_text('[preset.0]\nname="Model2D"\nplatform="' + ('Windows Desktop' if os.name == 'nt' else 'Linux') + '"\nrunnable=true\nexport_path=""\nexport_filter="resources"\nexport_files=PackedStringArray("res://model2d.tscn", "res://model2d_checks.gd", "res://model2d_render_checks.gd")\ninclude_filter=""\nexclude_filter=""\nscript_export_mode=2\n[preset.0.options]\ncustom_template/debug=' + template + '\ncustom_template/release=' + template + '\nbinary_format/architecture="x86_64"\nbinary_format/embed_pck=false\n')
        output = run / 'export'
        presets = (project / 'export_presets.cfg').read_text()
        (project / 'export_presets.cfg').write_text(presets.replace('"res://model2d.tscn",', '"res://alpha-model.res", "res://alpha_checks.gd", "res://fallback_checks.gd", "res://renderer_transform_checks.gd", "res://mask_quality_checks.gd", "res://mask_policy_checks.gd", "res://debug_overlay_checks.gd", "res://model2d.tscn",'))
        if args.motion:
            presets = (project / 'export_presets.cfg').read_text()
            presets = presets.replace('"res://model2d.tscn",', '"res://controller_checks.gd", "res://model2d.tscn",')
            presets = presets.replace('"res://model2d.tscn",', '"res://controller_utility_checks.gd", "res://model2d.tscn",')
            presets = presets.replace('"res://model2d.tscn",', '"res://controller-state.tscn", "res://controller_state_checks.gd", "res://model2d.tscn",')
            presets = presets.replace('"res://model2d.tscn",', '"res://parameter_layer_checks.gd", "res://model2d.tscn",')
            presets = presets.replace('"res://model2d.tscn",', '"res://custom-effects.tscn", "res://custom_effect_checks.gd", "res://model2d.tscn",')
            if args.examples:
                presets = presets.replace('"res://model2d.tscn",', '"res://example-visual_novel.tscn", "res://example-rpg_dialogue.tscn", "res://character_example_checks.gd", "res://addons/gd_cubism/examples/character_workflows/visual_novel.tscn", "res://addons/gd_cubism/examples/character_workflows/rpg_dialogue.tscn", "res://model2d.tscn",')
            if args.audio_timing:
                presets = presets.replace('"res://model2d.tscn",', '"res://controller_audio_timing_checks.gd", "res://model2d.tscn",')
            (project / 'export_presets.cfg').write_text(presets.replace('"res://model2d.tscn",', '"res://lip-sync.tscn", "res://lip_sync_checks.gd", "res://hit_checks.gd", "res://look_checks.gd", "res://procedural_checks.gd", "res://autoplay.tscn", "res://autoplay_checks.gd", "res://expression_api_checks.gd", "res://motion_api_checks.gd", "res://model2d.tscn",'))
        execute('checked-export', [sys.executable, str(ROOT / 'tools/checked_export.py'), '--project', str(project), '--preset', 'Model2D', '--output', str(output), '--redot-bin', engine, '--mode', args.mode, '--report', str(run / 'checked.json')])
        project.rename(run / 'source-not-available')
        try:
            execute('exported-node', [str(output / ('game.exe' if os.name == 'nt' else 'game')), '--headless', '--script', 'res://model2d_checks.gd', '--quit-after', '10000'], 'CUBISM_MODEL2D_PASS', output)
            if args.motion:
                execute('exported-motion', [str(output / ('game.exe' if os.name == 'nt' else 'game')), '--headless', '--script', 'res://motion_api_checks.gd', '--quit-after', '10000'], 'CUBISM_MOTION_API_PASS', output)
                execute('exported-expression', [str(output / ('game.exe' if os.name == 'nt' else 'game')), '--headless', '--script', 'res://expression_api_checks.gd', '--quit-after', '10000'], 'CUBISM_EXPRESSION_API_PASS', output)
                execute('exported-autoplay', [str(output / ('game.exe' if os.name == 'nt' else 'game')), '--headless', '--script', 'res://autoplay_checks.gd', '--quit-after', '10000'], 'CUBISM_AUTOPLAY_PASS', output)
                execute('exported-procedural', [str(output / ('game.exe' if os.name == 'nt' else 'game')), '--headless', '--script', 'res://procedural_checks.gd', '--quit-after', '10000'], 'CUBISM_PROCEDURAL_PASS', output)
                execute('exported-parameter-layers', [str(output / ('game.exe' if os.name == 'nt' else 'game')), '--headless', '--script', 'res://parameter_layer_checks.gd', '--quit-after', '10000'], 'CUBISM_PARAMETER_LAYERS_PASS', output)
                execute('exported-custom-effects', [str(output / ('game.exe' if os.name == 'nt' else 'game')), '--headless', '--script', 'res://custom_effect_checks.gd', '--quit-after', '10000'], 'CUBISM_CUSTOM_EFFECTS_PASS', output)
                execute('exported-look', [str(output / ('game.exe' if os.name == 'nt' else 'game')), '--headless', '--script', 'res://look_checks.gd', '--quit-after', '10000'], 'CUBISM_LOOK_PASS', output)
                execute('exported-hit', [str(output / ('game.exe' if os.name == 'nt' else 'game')), *hit_flags, '--script', 'res://hit_checks.gd', '--quit-after', '10000', *hit_args], 'CUBISM_HIT_PASS', output)
                execute('exported-lip', [str(output / ('game.exe' if os.name == 'nt' else 'game')), '--headless', '--audio-driver', 'Dummy', '--script', 'res://lip_sync_checks.gd', '--quit-after', '10000'], 'CUBISM_LIP_SYNC_PASS', output)
                execute('exported-controller', [str(output / ('game.exe' if os.name == 'nt' else 'game')), '--headless', '--audio-driver', 'Dummy', '--script', 'res://controller_checks.gd', '--quit-after', '10000'], 'CUBISM_CONTROLLER_PASS', output)
                execute('exported-controller-utilities', [str(output / ('game.exe' if os.name == 'nt' else 'game')), '--headless', '--script', 'res://controller_utility_checks.gd', '--quit-after', '10000'], 'CUBISM_CONTROLLER_UTILITIES_PASS', output)
                execute('exported-controller-state', [str(output / ('game.exe' if os.name == 'nt' else 'game')), '--headless', '--script', 'res://controller_state_checks.gd', '--quit-after', '10000'], 'CUBISM_CONTROLLER_STATE_PASS', output)
                if args.examples:
                    example_args = []
                    if args.graphics:
                        captures = run / 'examples-exported'; captures.mkdir()
                        example_args = ['--', '--captures', str(captures)]
                    execute('exported-character-examples', [str(output / ('game.exe' if os.name == 'nt' else 'game')), *hit_flags, '--audio-driver', 'Dummy', '--script', 'res://character_example_checks.gd', '--quit-after', '10000', *example_args], 'CUBISM_CHARACTER_EXAMPLES_PASS', output)
                if args.audio_timing:
                    execute('exported-controller-audio-timing', [str(output / ('game.exe' if os.name == 'nt' else 'game')), '--headless', '--audio-driver', 'Dummy', '--script', 'res://controller_audio_timing_checks.gd', '--quit-after', '10000'], 'CUBISM_CONTROLLER_AUDIO_TIMING_PASS', output)
            if args.graphics:
                execute('exported-debug-overlay', [str(output / ('game.exe' if os.name == 'nt' else 'game')), *hit_flags, '--script', 'res://debug_overlay_checks.gd', '--quit-after', '10000'], 'CUBISM_DEBUG_OVERLAY_PASS', output)
                execute('exported-mask-quality', [str(output / ('game.exe' if os.name == 'nt' else 'game')), *hit_flags, '--script', 'res://mask_quality_checks.gd', '--quit-after', '10000'], 'CUBISM_MASK_QUALITY_PASS', output)
                execute('exported-fallback', [str(output / ('game.exe' if os.name == 'nt' else 'game')), *hit_flags, '--script', 'res://fallback_checks.gd', '--quit-after', '10000', *(['--', '--motion'] if args.motion else [])], 'CUBISM_FALLBACK_PASS', output)
                execute('exported-alpha', [str(output / ('game.exe' if os.name == 'nt' else 'game')), *hit_flags, '--script', 'res://alpha_checks.gd', '--quit-after', '10000'], 'CUBISM_ALPHA_RUNTIME_PASS', output)
                execute('exported-mask-policy', [str(output / ('game.exe' if os.name == 'nt' else 'game')), *hit_flags, '--script', 'res://mask_policy_checks.gd', '--quit-after', '10000', *(['--', '--motion'] if args.motion else [])], 'CUBISM_MASK_POLICY_PASS', output)
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
