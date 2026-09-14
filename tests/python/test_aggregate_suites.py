# SPDX-License-Identifier: MIT
import contextlib
import io
import json
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools'))
import run_tests


class AggregateSuiteTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.library = self.root / 'library.so'
        self.library.write_bytes(b'fixture library')
        self.other = self.root / 'other.so'
        self.other.write_bytes(b'opposite variant')
        self.template = self.root / 'template'
        self.template.touch()
        self.good = {'status': 'PASS', 'library_sha256': run_tests.sha256(self.library),
                     'engine_version': json.loads((run_tests.ROOT / 'DEPENDENCIES.json').read_text())['redot']['version'],
                     'checks': [{'status': 'PASS'}], 'graphics': True}
        self.prepared = self.root / 'prepared.json'
        self.prepared.write_text(json.dumps(self.good))

    def arguments(self, suite):
        args = ['run_tests.py', '--suite', suite, '--library', str(self.library),
                '--output', str(self.root / 'results')]
        if suite == 'editor':
            return args + ['--native-report', str(self.prepared)]
        return args + ['--importer-report', str(self.prepared), '--template', str(self.template),
                       '--other-library', str(self.other), '--export-mode', 'release']

    def invoke(self, suite, replacement=None, failing_stage=None, exit_code=0, missing=False):
        commands = []
        pattern = suite + '-*/' + suite + '.json'
        before = set((self.root / 'results').glob(pattern))

        def spawn(command, **kwargs):
            commands.append(command)
            output = Path(command[command.index('--output') + 1])
            names = {'editor': 'editor', 'selection': 'selection', 'checked-export': 'checked-export',
                     'legacy-export': 'legacy-export', 'legacy-bridge': 'legacy-bridge', 'export-identity': 'export-identity'}
            report = dict(self.good)
            fail = output.name == failing_stage
            if fail and replacement is not None:
                report.update(replacement)
            if not (fail and missing):
                (output / (names[output.name] + '-report.json')).write_text(json.dumps(report))
            return Mock(returncode=exit_code if fail else 0, communicate=Mock(return_value=('child log\n', None)))

        with patch.object(sys, 'argv', self.arguments(suite)), patch.object(run_tests.subprocess, 'Popen', side_effect=spawn), contextlib.redirect_stdout(io.StringIO()):
            code = run_tests.main()
        report_path, = set((self.root / 'results').glob(pattern)) - before
        return code, json.loads(report_path.read_text()), commands

    def test_editor_runs_graphics_and_keeps_scoped_report(self):
        code, report, commands = self.invoke('editor')
        self.assertEqual(code, 0)
        self.assertEqual(report['status'], 'PASS')
        self.assertFalse(report['release_qualified'])
        self.assertTrue(report['cubism_model_tests_selected'])
        self.assertNotIn('--headless', commands[0])
        self.assertIn('--native-report', commands[0])

    def test_export_runs_all_five_stages_in_dependency_order(self):
        code, report, commands = self.invoke('export')
        self.assertEqual(code, 0)
        self.assertEqual([Path(c[1]).name for c in commands], [
            'run_export_selection_tests.py', 'run_checked_export_tests.py', 'run_legacy_export_tests.py',
            'run_legacy_bridge_tests.py', 'run_export_identity_tests.py'])
        self.assertIn('--preflight', commands[0])
        self.assertIn('--ui', commands[1])
        self.assertIn('--graphics', commands[3])
        for i in (0, 1, 3):
            self.assertIn('release', commands[i])
        self.assertEqual(commands[4][commands[4].index('--bridge-report') + 1], report['checks'][3]['report'])
        self.assertEqual(commands[4][commands[4].index('--wrong-library') + 1], str(self.other))

    def test_child_failure_stops_later_exports(self):
        code, report, commands = self.invoke('export', failing_stage='checked-export', exit_code=7)
        self.assertEqual(code, 1)
        self.assertEqual(report['status'], 'FAIL')
        self.assertEqual(len(commands), 2)
        self.assertEqual(report['checks'][-1]['exit_code'], 7)

    def test_zero_exit_does_not_override_failed_incomplete_or_wrong_reports(self):
        for change in ({'status': 'FAIL'}, {'status': 'RUNNING'}, {'checks': [{'status': 'NOT_RUN'}]},
                       {'library_sha256': 'wrong'}, {'engine_version': 'wrong'}, {'graphics': False}):
            with self.subTest(change=change):
                code, _, _ = self.invoke('editor', replacement=change, failing_stage='editor')
                self.assertEqual(code, 1)

    def test_missing_report_cannot_reuse_previous_pass(self):
        self.assertEqual(self.invoke('editor')[0], 0)
        self.assertEqual(self.invoke('editor', failing_stage='editor', missing=True)[0], 1)
        self.assertEqual(len(list((self.root / 'results').glob('editor-*'))), 2)

    def test_required_inputs_and_prepared_identity_fail_before_launch(self):
        for suite in ('editor', 'export'):
            for change in ({'status': 'RUNNING'}, {'library_sha256': None}, {'engine_version': 'wrong'}):
                self.prepared.write_text(json.dumps(dict(self.good, **change)))
                with patch.object(sys, 'argv', self.arguments(suite)), patch.object(run_tests.subprocess, 'Popen') as spawn, contextlib.redirect_stderr(io.StringIO()):
                    with self.assertRaises(SystemExit): run_tests.main()
                    spawn.assert_not_called()
        self.library.unlink()
        with patch.object(sys, 'argv', self.arguments('editor')), contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit): run_tests.main()

    @unittest.skipIf(sys.platform == 'win32', 'POSIX process-group timeout behavior')
    def test_timeout_kills_child_process_group(self):
        child = Mock(pid=12345, communicate=Mock(side_effect=[subprocess.TimeoutExpired('runner', 1800), ('partial log', None)]))
        with patch.object(sys, 'argv', self.arguments('editor')), patch.object(run_tests.subprocess, 'Popen', return_value=child), patch.object(run_tests.os, 'killpg') as kill, contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(run_tests.main(), 1)
        kill.assert_called_once_with(12345, signal.SIGKILL)
        report = json.loads(next((self.root / 'results').glob('editor-*/editor.json')).read_text())
        self.assertEqual(report['checks'][0]['exit_code'], 124)


if __name__ == '__main__':
    unittest.main()
