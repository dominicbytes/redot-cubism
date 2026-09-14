# SPDX-License-Identifier: MIT
import contextlib
import io
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import types
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools'))
import run_licensed_tests as licensed
import run_tests


class LicensedRunnerTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.pins = json.loads((licensed.ROOT / 'DEPENDENCIES.json').read_text())
        (self.root / 'DEPENDENCIES.json').write_text(json.dumps(self.pins))
        (self.root / 'tools').mkdir()
        (self.root / 'tools/requirements-visual.txt').write_text('Pillow==12.3.0\n')
        self.env = {key: 'fixture' for key in licensed.REQUIRED}
        for key in ('REDOT_BIN', 'CUBISM_MODEL', 'CUBISM_TEMPLATE_DEBUG', 'CUBISM_TEMPLATE_RELEASE',
                    'CUBISM_MOTION_FIXTURES', 'CUBISM_VISUAL_FIXTURES', 'CUBISM_VISUAL_LIMITS',
                    'CUBISM_BENCHMARK_BASELINE', 'CUBISM_SANITIZER_RUNTIME'):
            path = self.root / key
            path.write_text('{}')
            self.env[key] = str(path)
        for key in ('REDOT_CPP_ROOT', 'CUBISM_SDK_ROOT', 'CUBISM_MOTION_PROJECT',
                    'CUBISM_VISUAL_PROJECT', 'CUBISM_BENCHMARK_PROJECT'):
            path = self.root / key
            path.mkdir()
            self.env[key] = str(path)
        self.env['CUBISM_BENCHMARK_RELATIVE_THRESHOLD'] = '0.10'
        self.modules = {'SCons': types.SimpleNamespace(__version__=self.pins['toolchain']['scons']),
                        'PIL': types.SimpleNamespace(__version__='12.3.0')}
        self.calls = []

    def execute(self, target='linux', failure=None, change=None, missing=False, env=None, timed_out=False):
        self.calls = []

        def spawn(command, **kwargs):
            self.calls.append((command, kwargs))
            if '-m' in command:
                mode = next(c.removeprefix('target=template_') for c in command if c.startswith('target='))
                suffix = 'dll' if target == 'win32' else 'so'
                platform_name = 'windows' if target == 'win32' else 'linux'
                output = self.root / ('demo/addons/gd_cubism/bin/libgd_cubism.' + platform_name + '.' + mode + '.x86_64.' + suffix)
                output.parent.mkdir(parents=True, exist_ok=True)
                output.write_bytes(mode.encode())
                name = Path(kwargs['env']['CUBISM_BUILD_DIR']).name
            else:
                output = Path(command[command.index('--output') + 1])
                name = output.name
                library = Path(command[command.index('--library') + 1]) if '--library' in command else None
                report = {'status': 'PASS', 'engine_version': self.pins['redot']['version'],
                          'library_sha256': licensed.sha256(library) if library else None,
                          'checks': [{'status': 'PASS'}]}
                if name == 'identity':
                    filename = 'host.json'
                    (output / 'extension_api.json').write_text('{}')
                elif name.startswith('tests-'):
                    filename = 'desktop-test/desktop-report.json'
                    report['stages'] = [{'name': n, 'status': 'PASS'} for n in licensed.DESKTOP_STAGES]
                elif name.startswith(('sdk-motion-', 'visual-')):
                    filename = 'visual-report.json' if name.startswith('visual-') else 'sdk-motion-report.json'
                    report.update(cases=[{'status': 'PASS'}], limits={'reviewed': True})
                elif name == 'benchmark-debug':
                    filename = 'benchmark-report.json'
                    report.update(qualification='BASELINE_COMPARISON_PASS', regressions=[],
                                  scenarios={s: {} for s in licensed.SCENARIOS},
                                  identity={'engine_version': self.pins['redot']['version']})
                else:
                    filename = 'native-report.json'
                    report['sanitizer'] = {'tested': True, 'addon_sanitizers': ['address', 'undefined'],
                                           'framework_sanitizers': ['address', 'undefined'], 'cycles': 250}
                if name == failure and change is not None:
                    report.update(change)
                if not (name == failure and missing):
                    destination = output / filename
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    destination.write_text(json.dumps(report))
            failed = name == failure
            wait = Mock(side_effect=[subprocess.TimeoutExpired('runner', 1800), 0]) if failed and timed_out else Mock(return_value=9 if failed and change is None and not missing else 0)
            return Mock(pid=12345, wait=wait)

        with patch.object(licensed, 'ROOT', self.root), patch.dict(os.environ, self.env if env is None else env, clear=True), patch.dict(sys.modules, self.modules), patch.object(sys, 'platform', target), patch.object(subprocess, 'Popen', side_effect=spawn), patch.object(subprocess, 'check_output', side_effect=lambda *a, **k: '' if k.get('text') else b''), patch.object(os, 'killpg', create=True) as kill, contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            code = licensed.main(['--output', str(self.root / 'results')])
        reports = sorted((self.root / 'results').glob('licensed-*/licensed-desktop.json'), key=lambda p: p.stat().st_mtime_ns)
        return code, json.loads(reports[-1].read_text()), kill

    def test_linux_runs_both_variants_and_every_required_suite(self):
        code, report, _ = self.execute()
        self.assertEqual(code, 0)
        self.assertEqual([s['name'] for s in report['checks']], [
            'identity', 'build-debug', 'build-release', 'tests-debug', 'sdk-motion-debug',
            'sdk-motion-manual-debug', 'visual-debug', 'tests-release', 'sdk-motion-release',
            'sdk-motion-manual-release', 'visual-release', 'benchmark-debug', 'build-asan-ubsan', 'sanitizers'])
        self.assertFalse(report['release_qualified'])
        self.assertTrue(report['cubism_model_tests_selected'])
        commands = [c for c, _ in self.calls]
        self.assertEqual(sum('--uncapped-manual-step' in c for c in commands), 2)
        for command in commands:
            if '--uncapped-manual-step' in command:
                self.assertEqual(command[command.index('--fps') + 1], '2')
                self.assertEqual(command[command.index('--steps') + 1:command.index('--uncapped-manual-step')], ['1', '2', '4', '6'])
        benchmark = next(c for c in commands if 'tools/run_benchmarks.py' in c)
        for option, key in (('--baseline', 'CUBISM_BENCHMARK_BASELINE'), ('--runner-id', 'CUBISM_BENCHMARK_RUNNER_ID')):
            self.assertEqual(benchmark[benchmark.index(option) + 1], self.env[key])
        self.assertEqual(benchmark[benchmark.index('--relative-threshold') + 1], '0.1')
        self.assertIn('sanitize=address,undefined', commands[-2])
        self.assertIn('--sanitizer-library', commands[-1])

    def test_windows_routes_native_builds_without_linux_sanitizers(self):
        env = dict(self.env)
        del env['CUBISM_SANITIZER_RUNTIME']
        code, report, _ = self.execute('win32', env=env)
        self.assertEqual(code, 0)
        self.assertEqual(len(report['checks']), 12)
        self.assertTrue(all('debug_crt=no' in c and 'platform=windows' in c for c, _ in self.calls if '-m' in c))
        self.assertTrue(report['libraries']['release']['path'].endswith('.dll'))

    def test_missing_inputs_and_invalid_thresholds_stop_before_builds(self):
        changes = [{key: ''} for key in (*licensed.REQUIRED, 'CUBISM_SANITIZER_RUNTIME')]
        changes += [{'CUBISM_BENCHMARK_RELATIVE_THRESHOLD': value} for value in ('nan', 'inf', '-1', 'text')]
        changes += [{'CUBISM_VISUAL_LIMITS': str(self.root / 'missing')}, {'CUBISM_SDK_ROOT': str(self.root / 'missing')}]
        for change in changes:
            with self.subTest(change=change):
                code, report, _ = self.execute(env=dict(self.env, **change))
                self.assertEqual(code, 2)
                self.assertEqual(report['status'], 'FAIL')
                self.assertEqual(self.calls, [])

    def test_failed_command_stops_subsequent_stages(self):
        for name in ('identity', 'build-debug', 'tests-debug', 'sdk-motion-manual-debug', 'visual-release', 'benchmark-debug', 'build-asan-ubsan', 'sanitizers'):
            with self.subTest(name=name):
                code, report, _ = self.execute(failure=name)
                self.assertEqual(code, 1)
                self.assertEqual(report['checks'][-1]['name'], name)
                self.assertEqual(report['checks'][-1]['exit_code'], 9)

    def test_toolchain_mismatch_stops_before_builds(self):
        for name in ('SCons', 'PIL'):
            previous = self.modules[name]
            self.modules[name] = types.SimpleNamespace(__version__='wrong')
            with self.subTest(name=name):
                code, report, _ = self.execute()
                self.assertEqual(code, 2)
                self.assertTrue(report['configuration_error'])
                self.assertEqual(self.calls, [])
            self.modules[name] = previous

    def test_incomplete_or_mismatched_reports_cannot_pass_with_zero_exit(self):
        mutations = [('tests-debug', {'stages': []}), ('sdk-motion-debug', {'cases': []}),
                     ('visual-debug', {'cases': [{'status': 'MEASURED'}]}), ('visual-debug', {'limits': None}),
                     ('visual-debug', {'library_sha256': 'wrong'}), ('visual-debug', {'engine_version': None}),
                     ('benchmark-debug', {'qualification': 'MEASURED_ONLY'}), ('benchmark-debug', {'scenarios': {}}),
                     ('benchmark-debug', {'regressions': [{}]}), ('sanitizers', {'sanitizer': {'tested': True}})]
        good_sanitizer = {'tested': True, 'addon_sanitizers': ['address', 'undefined'],
                          'framework_sanitizers': ['address', 'undefined'], 'cycles': 250}
        mutations += [('sanitizers', {'sanitizer': dict(good_sanitizer, **change)}) for change in (
            {'addon_sanitizers': ['address']}, {'framework_sanitizers': ['address']}, {'tested': 1}, {'cycles': 249})]
        for name, change in mutations:
            with self.subTest(name=name, change=change):
                code, report, _ = self.execute(failure=name, change=change)
                self.assertEqual(code, 1)
                self.assertEqual(report['checks'][-1]['name'], name)
                self.assertEqual(report['checks'][-1]['exit_code'], 0)
        self.assertEqual(self.execute(failure='visual-debug', missing=True)[0], 1)

    @unittest.skipIf(os.name == 'nt', 'POSIX process group cleanup')
    def test_timeout_terminates_process_tree_and_fails(self):
        code, report, kill = self.execute(failure='build-debug', timed_out=True)
        self.assertEqual(code, 1)
        self.assertEqual(report['checks'][-1]['exit_code'], 124)
        kill.assert_called_once_with(12345, signal.SIGKILL)

    def test_frontend_propagates_the_complete_runner_result(self):
        for code in (0, 1, 2):
            with patch.object(sys, 'argv', ['run_tests.py', '--suite', 'licensed-desktop', '--output', str(self.root)]), patch.object(licensed, 'main', return_value=code) as run:
                self.assertEqual(run_tests.main(), code)
                run.assert_called_once_with(['--output', str(self.root)])


if __name__ == '__main__':
    unittest.main()
