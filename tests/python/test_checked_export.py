# SPDX-License-Identifier: MIT
import importlib.util
import argparse
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

ADDON = Path(__file__).resolve().parents[2] / 'demo/addons/gd_cubism/editor'
sys.path.insert(0, str(ADDON))
spec = importlib.util.spec_from_file_location('cubism_checked_export', ADDON / 'checked_export.py')
checked = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checked)


class CheckedExportTest(unittest.TestCase):
    def test_windows_identity_probe_copies_running_editor(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            editor, probe = root / 'editor.exe', root / 'probe.exe'
            editor.write_bytes(b'pinned editor')
            with patch.object(checked.os, 'link', side_effect=AssertionError('Windows must not hard-link the running editor')):
                checked.stage_identity_editor(editor, probe, 'Windows')
            self.assertEqual(probe.read_bytes(), editor.read_bytes())
            probe.unlink()

    def test_engine_children_use_private_project_when_output_is_inside_source(self):
        class StopAfterExport(Exception):
            pass

        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory) / 'project'
            project.mkdir()
            (project / 'project.godot').write_text('[application]\n')
            (project / 'export_presets.cfg').write_text('[preset.0]\n')
            (project / 'asset.txt').write_text('source')
            output = project / 'output'
            output.mkdir()
            (output / checked.MANIFEST).write_text('{}')
            (output / 'old.txt').write_text('previous build')
            args = argparse.Namespace(project=project, output=output, name='game', preset='Textures',
                                      mode='debug', redot_bin='redot.exe', timeout=10)
            child_projects = []
            snapshot_had_asset = []
            snapshot_had_output = []
            snapshot_parent_ignored = []

            def fake_execute(command, log, cwd, env, timeout, marker=None):
                if '--version' in command:
                    return '26.2.stable.official.4f5b14aba'
                child_projects.append(Path(command[command.index('--path') + 1]))
                snapshot_had_asset.append((child_projects[-1] / 'asset.txt').read_text() == 'source')
                snapshot_had_output.append((child_projects[-1] / 'output').exists())
                snapshot_parent_ignored.append((child_projects[-1].parent / '.gdignore').is_file())
                if '--cubism-preflight' in command:
                    preflight = {'ok': True, 'build': {'redot_version': '26.2.stable.official.4f5b14aba'},
                                 'preset': {'platform': 'Windows Desktop', 'architecture': 'x86_64',
                                            'embedded_pck': False, 'encrypted_pck': False,
                                            'encrypted_directory': False,
                                            'project_hash': checked.sha256(project / 'project.godot'),
                                            'presets_hash': checked.sha256(project / 'export_presets.cfg')},
                                 'raw_hashes': {}, 'files': []}
                    Path(command[-1]).write_text(json.dumps(preflight))
                    return 'CUBISM_EXPORT_PREFLIGHT_PASS'
                raise StopAfterExport

            with patch.object(checked, 'execute', fake_execute), patch.object(checked.platform, 'system', return_value='Windows'):
                with self.assertRaises(StopAfterExport):
                    checked.checked_export(args)
            self.assertEqual(len(child_projects), 2)
            self.assertEqual(child_projects[0], child_projects[1])
            self.assertNotEqual(child_projects[0], project)
            self.assertEqual(snapshot_had_asset, [True, True])
            self.assertEqual(snapshot_had_output, [False, False])
            self.assertEqual(snapshot_parent_ignored, [True, True])
            self.assertFalse(child_projects[0].exists())
            self.assertTrue((args.work / '.gdignore').is_file())
            self.assertEqual(json.loads((args.work / 'source-project.json').read_text())['source'], str(project))
            self.assertFalse((output.parent / '.output.cubism-export.lock').exists())
            self.assertEqual((output / 'old.txt').read_text(), 'previous build')

    def test_snapshot_rejects_file_link_outside_project(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            project, snapshot = root / 'project', root / 'snapshot'
            project.mkdir()
            link = project / 'link.txt'
            link.write_text('placeholder')
            outside = root / 'outside.txt'
            outside.write_text('outside')
            real_is_symlink, real_resolve = Path.is_symlink, Path.resolve

            def is_symlink(path):
                return path == link or real_is_symlink(path)

            def resolve(path, *args, **kwargs):
                return outside if path == link else real_resolve(path, *args, **kwargs)

            with patch.object(Path, 'is_symlink', is_symlink), patch.object(Path, 'resolve', resolve):
                with self.assertRaisesRegex(ValueError, 'link escapes'):
                    checked.copy_project_snapshot(project, snapshot, ())

    def test_snapshot_excludes_previous_work_for_in_project_output(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory).resolve() / 'project'
            project.mkdir()
            (project / 'project.godot').write_text('source')
            output = project / 'output'
            output.mkdir()
            old_work = project / '.output.cubism-export-old'
            (old_work / 'previous').mkdir(parents=True)
            (old_work / 'previous' / 'large.bin').write_bytes(b'old build')
            private = project / '.cubism-project-current'
            private.mkdir()
            snapshot = private / 'project'
            checked.copy_project_snapshot(project, snapshot, (output, private), output=output)
            self.assertFalse((snapshot / old_work.name).exists())
            self.assertFalse((snapshot / 'output').exists())

    def test_snapshot_fails_on_unreadable_subdirectory(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            project, snapshot = root / 'project', root / 'snapshot'
            hidden = project / 'unreadable'
            hidden.mkdir(parents=True)
            (hidden / 'asset.txt').write_text('required')
            real_scandir = checked.os.scandir

            def scandir(path):
                if Path(path) == hidden:
                    raise PermissionError('simulated access denied')
                return real_scandir(path)

            with patch.object(checked.os, 'scandir', side_effect=scandir):
                with self.assertRaises(PermissionError):
                    checked.copy_project_snapshot(project, snapshot, ())

    def test_snapshot_cleanup_failure_preserves_prior_build(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            project, output = root / 'project', root / 'output'
            project.mkdir()
            (project / 'project.godot').write_text('[application]\n')
            (project / 'export_presets.cfg').write_text('[preset.0]\n')
            output.mkdir()
            (output / checked.MANIFEST).write_text('old')
            (output / 'old.txt').write_text('prior build')
            editor = root / 'redot.exe'
            editor.write_bytes(b'editor')
            args = argparse.Namespace(project=project, output=output, name='game', preset='P',
                                      mode='debug', redot_bin=str(editor), timeout=10)
            version = '26.2.stable.official.4f5b14aba'

            def fake_execute(command, log, cwd, env, timeout, marker=None):
                if '--version' in command:
                    return version
                if '--cubism-preflight' in command:
                    Path(command[-1]).write_text(json.dumps({
                        'ok': True, 'build': {'redot_version': version}, 'models': 0,
                        'preset': {'platform': 'Windows Desktop', 'architecture': 'x86_64',
                                   'embedded_pck': False, 'encrypted_pck': False, 'encrypted_directory': False,
                                   'project_hash': checked.sha256(project / 'project.godot'),
                                   'presets_hash': checked.sha256(project / 'export_presets.cfg')},
                        'raw_hashes': {}, 'files': []}))
                    return 'CUBISM_EXPORT_PREFLIGHT_PASS'
                if '--export-debug' in command:
                    game = Path(command[-1])
                    game.write_bytes(b'game')
                    game.with_suffix('.pck').write_bytes(b'pack')
                    return ''
                if '--main-pack' in command:
                    Path(command[-1]).write_text('{}')
                    return 'CUBISM_EXPORT_IDENTITY_PASS'
                if '--script' in command:
                    Path(command[-1]).write_text(json.dumps({'ok': True, 'models': 0,
                                                           'motions': 0, 'expressions': 0, 'build': {}}))
                    return 'CUBISM_EXPORTED_SMOKE_PASS'
                raise AssertionError(command)

            real_rmtree = checked.shutil.rmtree

            def blocked_cleanup(path, *a, **kw):
                if Path(path).name.startswith('.cubism-project-'):
                    raise PermissionError('simulated Windows snapshot lock')
                return real_rmtree(path, *a, **kw)

            with patch.object(checked, 'execute', fake_execute), \
                    patch.object(checked.platform, 'system', return_value='Windows'), \
                    patch.object(checked, 'binary_architecture', return_value='x86_64'), \
                    patch.object(checked, 'inspect_pack', return_value={'engine_version': [26, 2, 0], 'files': {}}), \
                    patch.object(checked, 'stage_identity_editor', side_effect=lambda editor, probe, target: probe.write_bytes(b'probe')), \
                    patch.object(checked.shutil, 'rmtree', blocked_cleanup):
                with self.assertRaises(PermissionError):
                    checked.checked_export(args)
            self.assertEqual((output / 'old.txt').read_text(), 'prior build')
            self.assertEqual((output / checked.MANIFEST).read_text(), 'old')

    def test_postcommit_lock_cleanup_reports_pass_with_warning(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            project, output, editor, report = (root / name for name in ('project', 'output', 'redot.exe', 'report.json'))
            project.mkdir()
            (project / 'project.godot').write_text('[application]\n')
            (project / 'export_presets.cfg').write_text('[preset.0]\n')
            output.mkdir()
            (output / checked.MANIFEST).write_text('old')
            (output / 'old.txt').write_text('prior build')
            editor.write_bytes(b'editor')
            version = '26.2.stable.official.4f5b14aba'

            def fake_execute(command, log, cwd, env, timeout, marker=None):
                if '--version' in command:
                    return version
                if '--cubism-preflight' in command:
                    Path(command[-1]).write_text(json.dumps({
                        'ok': True, 'build': {'redot_version': version}, 'models': 0,
                        'preset': {'platform': 'Windows Desktop', 'architecture': 'x86_64',
                                   'embedded_pck': False, 'encrypted_pck': False, 'encrypted_directory': False,
                                   'project_hash': checked.sha256(project / 'project.godot'),
                                   'presets_hash': checked.sha256(project / 'export_presets.cfg')},
                        'raw_hashes': {}, 'files': []}))
                    return 'CUBISM_EXPORT_PREFLIGHT_PASS'
                if '--export-debug' in command:
                    game = Path(command[-1])
                    game.write_bytes(b'game')
                    game.with_suffix('.pck').write_bytes(b'pack')
                    return ''
                if '--main-pack' in command:
                    Path(command[-1]).write_text('{}')
                    return 'CUBISM_EXPORT_IDENTITY_PASS'
                if '--script' in command:
                    Path(command[-1]).write_text(json.dumps({'ok': True, 'models': 0,
                                                           'motions': 0, 'expressions': 0, 'build': {}}))
                    return 'CUBISM_EXPORTED_SMOKE_PASS'
                raise AssertionError(command)

            real_unlink = Path.unlink
            lock = root / '.output.cubism-export.lock'

            def blocked_unlink(path, missing_ok=False):
                if path == lock:
                    raise PermissionError('simulated Windows lock handle')
                return real_unlink(path, missing_ok=missing_ok)

            argv = ['checked_export.py', '--project', str(project), '--preset', 'P', '--output', str(output),
                    '--mode', 'debug', '--redot-bin', str(editor), '--report', str(report)]
            with patch.object(checked, 'execute', fake_execute), \
                    patch.object(checked.platform, 'system', return_value='Windows'), \
                    patch.object(checked, 'binary_architecture', return_value='x86_64'), \
                    patch.object(checked, 'inspect_pack', return_value={'engine_version': [26, 2, 0], 'files': {}}), \
                    patch.object(checked, 'stage_identity_editor', side_effect=lambda editor, probe, target: probe.write_bytes(b'probe')), \
                    patch.object(Path, 'unlink', blocked_unlink), patch.object(sys, 'argv', argv):
                exit_code = checked.main()
            status = json.loads(report.read_text())
            self.assertEqual(exit_code, 0)
            self.assertEqual(status['status'], 'PASS')
            self.assertEqual(json.loads((output / checked.MANIFEST).read_text())['status'], 'PASS')
            self.assertIn(str(lock), status['cleanup_warning'])
            self.assertTrue(lock.exists())
            self.assertEqual((Path(status['work']) / 'previous' / 'old.txt').read_text(), 'prior build')

    def test_native_build_matches_requested_package(self):
        for platform in ('Linux', 'Windows'):
            for mode in ('debug', 'release'):
                build = {'platform': platform.lower(), 'arch': 'x86_64', 'target': 'template_' + mode}
                checked.check_native_build(build, platform, mode)
                for field, incorrect in (('platform', 'macos'), ('arch', 'arm64'), ('target', 'editor'),
                                         ('target', 'template_debug' if mode == 'release' else 'template_release')):
                    with self.subTest(platform=platform, mode=mode, field=field, value=incorrect):
                        with self.assertRaisesRegex(ValueError, 'native build ' + field):
                            checked.check_native_build(dict(build, **{field: incorrect}), platform, mode)
                for field in build:
                    missing = dict(build)
                    del missing[field]
                    with self.assertRaisesRegex(ValueError, 'native build ' + field):
                        checked.check_native_build(missing, platform, mode)

    def test_promotes_complete_directory_and_retains_previous(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output, stage, previous = (root / p for p in ('output', 'stage', 'previous'))
            output.mkdir()
            (output / checked.MANIFEST).write_text('{}')
            (output / 'old-library.so').write_bytes(b'old')
            stage.mkdir()
            (stage / 'new-library.so').write_bytes(b'new')
            checked.promote(stage, output, previous)
            self.assertEqual((previous / 'old-library.so').read_bytes(), b'old')
            self.assertFalse((output / 'old-library.so').exists())
            self.assertEqual((output / 'new-library.so').read_bytes(), b'new')

    def test_failed_promotion_restores_previous_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output, stage, previous = (root / p for p in ('output', 'stage', 'previous'))
            output.mkdir()
            (output / checked.MANIFEST).write_text('old')
            stage.mkdir()
            rename = Path.rename
            def fail_stage(path, target):
                if path == stage:
                    raise OSError('Simulated promotion failure')
                return rename(path, target)
            with patch.object(Path, 'rename', fail_stage), self.assertRaisesRegex(OSError, 'promotion'):
                checked.promote(stage, output, previous)
            self.assertEqual((output / checked.MANIFEST).read_text(), 'old')
            self.assertTrue(stage.exists())

    def test_unmanaged_output_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output, stage = root / 'output', root / 'stage'
            output.mkdir()
            (output / 'user.txt').write_text('preserve')
            stage.mkdir()
            with self.assertRaisesRegex(ValueError, 'not a managed'):
                checked.promote(stage, output, root / 'previous')
            self.assertEqual((output / 'user.txt').read_text(), 'preserve')

    def test_changed_or_external_input_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'model.json').write_text('{}')
            digest = checked.sha256(root / 'model.json')
            checked.check_sources(root, {'res://model.json': digest})
            (root / 'model.json').write_text('changed')
            with self.assertRaisesRegex(ValueError, 'changed'):
                checked.check_sources(root, {'res://model.json': digest})
            with self.assertRaisesRegex(ValueError, 'changed'):
                checked.check_sources(root, {'res://../outside': digest})

    def test_native_headers(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'binary'
            header = bytearray(64)
            header[:6] = b'\x7fELF\x02\x01'
            struct.pack_into('<H', header, 18, 62)
            path.write_bytes(header)
            self.assertEqual(checked.binary_architecture(path), 'x86_64')
            struct.pack_into('<H', header, 18, 183)
            path.write_bytes(header)
            self.assertEqual(checked.binary_architecture(path), 'unsupported')
            header = bytearray(64)
            header[:2] = b'MZ'
            struct.pack_into('<I', header, 60, 64)
            path.write_bytes(header + b'PE\0\0' + struct.pack('<H', 0x8664))
            self.assertEqual(checked.binary_architecture(path), 'x86_64')
            path.write_bytes(b'not a native binary')
            with self.assertRaisesRegex(ValueError, 'Unsupported native'):
                checked.binary_architecture(path)
