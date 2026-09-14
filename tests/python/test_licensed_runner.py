# SPDX-License-Identifier: MIT
import contextlib
import copy
import hashlib
import io
import json
import os
from pathlib import Path
import platform
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
                    'CUBISM_MOTION_FIXTURES', 'CUBISM_BENCHMARK_BASELINE', 'CUBISM_SANITIZER_RUNTIME'):
            path = self.root / key
            path.write_text('{}')
            self.env[key] = str(path)
        for key in ('REDOT_CPP_ROOT', 'CUBISM_SDK_ROOT', 'CUBISM_MOTION_PROJECT',
                    'CUBISM_BENCHMARK_PROJECT'):
            path = self.root / key
            path.mkdir()
            self.env[key] = str(path)
        self._write_visual_matrix()
        self.env['CUBISM_BENCHMARK_RELATIVE_THRESHOLD'] = '0.10'
        self.modules = {'SCons': types.SimpleNamespace(__version__=self.pins['toolchain']['scons']),
                        'PIL': types.SimpleNamespace(__version__='12.3.0')}
        self.calls = []

    def _write_visual_matrix(self, matrix=None, limits_platform=None):
        visual = self.root / 'visual'
        visual.mkdir(exist_ok=True)
        projects = {}
        for encoding in ('straight', 'premultiplied'):
            project = visual / ('project-' + encoding)
            project.mkdir(exist_ok=True)
            (project / 'project.godot').write_text('[application]\n')
            projects[encoding] = project
        entries = []
        core_hash = next(iter(self.pins['cubism_sdk']['core_library_sha256'].values()))
        for family_id in licensed.VISUAL_FAMILIES:
            family, encoding = family_id.rsplit('-', 1)
            image = visual / (family_id + '.png')
            image.write_bytes(('reference-' + family_id).encode())
            model = dict(resource='res://model.res', manifest_sha256='a' * 64, moc_sha256='b' * 64,
                         texture_sha256=['c' * 64], premultiplied_alpha=encoding == 'premultiplied', mask_quality=2,
                         mvp=[1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
                         parameters={'angle': 0}, parts={'body': 1})
            cases = []
            for case_id in sorted(licensed.VISUAL_CASES[family]):
                models = [copy.deepcopy(model) for _ in range(licensed.VISUAL_MODEL_COUNTS[family])]
                cases.append(dict(id=case_id, size=[512, 512], image=image.name,
                                  image_sha256=hashlib.sha256(image.read_bytes()).hexdigest(), models=models))
            fixtures = visual / (family_id + '-fixtures.json')
            fixtures.write_text(json.dumps({'reference': {
                'framework_sha256': self.pins['cubism_framework']['source_sha256'],
                'core_sha256': core_hash, 'executable_sha256': 'd' * 64,
                'description': 'Independent SDK test fixture ' + family_id}, 'cases': cases}))
            limits = visual / (family_id + '-limits.json')
            limits.write_text(json.dumps({'fixtures_sha256': licensed.sha256(fixtures), 'review': 'Unit test policy',
                'platform': limits_platform or platform.system(), 'renderer': 'gl_compatibility', 'adapter': 'fixture',
                'cases': {case_id: dict(rgb_rms=1, alpha_rms=1, rgb_max=3, alpha_max=3)
                          for case_id in sorted(licensed.VISUAL_CASES[family])}}))
            entries.append({'id': family_id, 'project': str(projects[encoding]),
                            'fixtures': str(fixtures), 'limits': str(limits)})
        self.matrix = {'schema_version': 1, 'families': entries} if matrix is None else matrix
        path = visual / 'matrix.json'
        path.write_text(json.dumps(self.matrix))
        self.env['CUBISM_VISUAL_MATRIX'] = str(path)

    def execute(self, target='linux', failure=None, change=None, missing=False, env=None, timed_out=False,
                changed_input=None):
        self.calls = []
        changed_files = []
        system_name = 'Windows' if target == 'win32' else 'Linux'
        if env is None or env.get('CUBISM_VISUAL_MATRIX') == self.env['CUBISM_VISUAL_MATRIX']:
            for entry in self.matrix['families']:
                limits = Path(entry['limits'])
                data = json.loads(limits.read_text())
                data['platform'] = system_name
                limits.write_text(json.dumps(data))

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
                elif name.startswith('sdk-motion-'):
                    filename = 'sdk-motion-report.json'
                    report.update(cases=[{'status': 'PASS'}])
                elif name.startswith('visual-'):
                    filename = 'visual-report.json'
                    fixtures = Path(command[command.index('--fixtures') + 1])
                    limits = Path(command[command.index('--limits') + 1])
                    fixture_data = json.loads(fixtures.read_text())
                    report.update(fixtures_sha256=licensed.sha256(fixtures),
                                  cases=[{'id': case['id'], 'status': 'PASS'}
                                         for case in fixture_data['cases']],
                                  limits=json.loads(limits.read_text()))
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
                if name == changed_input:
                    limits = Path(command[command.index('--limits') + 1])
                    changed_files.append((limits, limits.read_bytes()))
                    policy = json.loads(limits.read_text())
                    policy['review'] += ' changed after preflight'
                    limits.write_text(json.dumps(policy))
                if not (name == failure and missing):
                    destination = output / filename
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    destination.write_text(json.dumps(report))
            failed = name == failure
            wait = Mock(side_effect=[subprocess.TimeoutExpired('runner', 1800), 0]) if failed and timed_out else Mock(return_value=9 if failed and change is None and not missing else 0)
            return Mock(pid=12345, wait=wait)

        with patch.object(licensed, 'ROOT', self.root), patch.dict(os.environ, self.env if env is None else env, clear=True), patch.dict(sys.modules, self.modules), patch.object(sys, 'platform', target), patch.object(licensed.platform, 'system', return_value=system_name), patch.object(subprocess, 'Popen', side_effect=spawn), patch.object(subprocess, 'check_output', side_effect=lambda *a, **k: '' if k.get('text') else b''), patch.object(os, 'killpg', create=True) as kill, contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            code = licensed.main(['--output', str(self.root / 'results')])
        for path, contents in changed_files:
            path.write_bytes(contents)
        reports = sorted((self.root / 'results').glob('licensed-*/licensed-desktop.json'), key=lambda p: p.stat().st_mtime_ns)
        return code, json.loads(reports[-1].read_text()), kill

    def test_linux_runs_both_variants_and_every_required_suite(self):
        code, report, _ = self.execute()
        self.assertEqual(code, 0)
        expected = ['identity', 'build-debug', 'build-release']
        for mode in ('debug', 'release'):
            expected += ['tests-' + mode, 'sdk-motion-' + mode, 'sdk-motion-manual-' + mode]
            expected += ['visual-' + mode + '-' + family_id for family_id in licensed.VISUAL_FAMILIES]
        expected += ['benchmark-debug', 'build-asan-ubsan', 'sanitizers']
        self.assertEqual([s['name'] for s in report['checks']], expected)
        self.assertEqual(report['visual_matrix']['families'], list(licensed.VISUAL_FAMILIES))
        self.assertEqual(report['visual_matrix']['sha256'], licensed.sha256(self.env['CUBISM_VISUAL_MATRIX']))
        self.assertEqual(len(report['visual_matrix']['snapshots']), 8)
        self.assertTrue(all(len(snapshot['case_ids']) == len(licensed.VISUAL_CASES[snapshot['id'].rsplit('-', 1)[0]])
                            for snapshot in report['visual_matrix']['snapshots']))
        self.assertFalse(report['release_qualified'])
        self.assertTrue(report['cubism_model_tests_selected'])
        commands = [c for c, _ in self.calls]
        visual = [c for c in commands if 'tools/run_visual_tests.py' in c]
        self.assertEqual(len(visual), 16)
        self.assertEqual(len({c[c.index('--output') + 1] for c in visual}), 16)
        for entry in self.matrix['families']:
            selected = [c for c in visual if c[c.index('--fixtures') + 1] == entry['fixtures']]
            self.assertEqual(len(selected), 2)
            self.assertTrue(all(c[c.index('--limits') + 1] == entry['limits'] for c in selected))
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
        self.assertEqual(len(report['checks']), 26)
        self.assertTrue(all('debug_crt=no' in c and 'platform=windows' in c for c, _ in self.calls if '-m' in c))
        self.assertTrue(report['libraries']['release']['path'].endswith('.dll'))

    def test_missing_inputs_and_invalid_thresholds_stop_before_builds(self):
        changes = [{key: ''} for key in (*licensed.REQUIRED, 'CUBISM_SANITIZER_RUNTIME')]
        changes += [{'CUBISM_BENCHMARK_RELATIVE_THRESHOLD': value} for value in ('nan', 'inf', '-1', 'text')]
        changes += [{'CUBISM_VISUAL_MATRIX': str(self.root / 'missing')}, {'CUBISM_SDK_ROOT': str(self.root / 'missing')}]
        for change in changes:
            with self.subTest(change=change):
                code, report, _ = self.execute(env=dict(self.env, **change))
                self.assertEqual(code, 2)
                self.assertEqual(report['status'], 'FAIL')
                self.assertEqual(self.calls, [])

    def test_failed_command_stops_subsequent_stages(self):
        for name in ('identity', 'build-debug', 'tests-debug', 'sdk-motion-manual-debug',
                     'visual-release-additive-premultiplied', 'benchmark-debug', 'build-asan-ubsan', 'sanitizers'):
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
                     ('visual-debug-effects-straight', {'cases': [{'status': 'MEASURED'}]}),
                     ('visual-debug-effects-straight', {'limits': None}),
                     ('visual-debug-effects-straight', {'library_sha256': 'wrong'}),
                     ('visual-debug-effects-straight', {'engine_version': None}),
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
        self.assertEqual(self.execute(failure='visual-debug-effects-straight', missing=True)[0], 1)

    def test_visual_report_must_match_selected_family_snapshot(self):
        entry = next(item for item in self.matrix['families'] if item['id'] == 'effects-straight')
        fixture_data = json.loads(Path(entry['fixtures']).read_text())
        cases = [{'id': case['id'], 'status': 'PASS'} for case in fixture_data['cases']]
        limits = json.loads(Path(entry['limits']).read_text())
        changed_limits = copy.deepcopy(limits)
        changed_limits['review'] = 'Different reviewed policy'
        mutations = [
            {'cases': cases[:-1]},
            {'cases': [*cases[:-1], copy.deepcopy(cases[0])]},
            {'cases': [*cases[:-1], {'id': 'relabelled', 'status': 'PASS'}]},
            {'fixtures_sha256': '0' * 64},
            {'limits': changed_limits},
        ]
        for change in mutations:
            with self.subTest(change=change):
                code, report, _ = self.execute(failure='visual-debug-effects-straight', change=change)
                self.assertEqual(code, 1)
                self.assertEqual(report['checks'][-1]['exit_code'], 0)
        code, report, _ = self.execute(changed_input='visual-debug-effects-straight')
        self.assertEqual(code, 1)
        self.assertIn('changed after matrix preflight', report['checks'][-1]['error'])

    def test_visual_matrix_rejects_missing_duplicate_unknown_and_reused_families(self):
        variants = []
        missing = copy.deepcopy(self.matrix); missing['families'].pop(); variants.append(missing)
        duplicate = copy.deepcopy(self.matrix); duplicate['families'][-1] = copy.deepcopy(duplicate['families'][0]); variants.append(duplicate)
        unknown = copy.deepcopy(self.matrix); unknown['families'][0]['id'] = 'neutral-straight'; variants.append(unknown)
        reused = copy.deepcopy(self.matrix)
        reused['families'][1]['fixtures'] = reused['families'][0]['fixtures']
        reused['families'][1]['limits'] = reused['families'][0]['limits']
        variants.append(reused)
        malformed = copy.deepcopy(self.matrix); malformed['schema_version'] = 2; variants.append(malformed)
        for matrix in variants:
            with self.subTest(matrix=matrix):
                path = Path(self.env['CUBISM_VISUAL_MATRIX'])
                path.write_text(json.dumps(matrix))
                code, report, _ = self.execute()
                self.assertEqual(code, 2)
                self.assertTrue(report['configuration_error'])
                self.assertEqual(self.calls, [])
        Path(self.env['CUBISM_VISUAL_MATRIX']).write_text(json.dumps(self.matrix))

    def test_visual_matrix_malformed_family_id_types_save_configuration_failure(self):
        for value in (None, 7, [], {}):
            with self.subTest(value=value):
                matrix = copy.deepcopy(self.matrix)
                matrix['families'][0]['id'] = value
                Path(self.env['CUBISM_VISUAL_MATRIX']).write_text(json.dumps(matrix))
                code, report, _ = self.execute()
                self.assertEqual(code, 2)
                self.assertEqual(report['status'], 'FAIL')
                self.assertTrue(report['configuration_error'])
                self.assertEqual(self.calls, [])
        Path(self.env['CUBISM_VISUAL_MATRIX']).write_text(json.dumps(self.matrix))

    def test_visual_matrix_rejects_truncated_cases_and_wrong_encoding(self):
        entry = next(item for item in self.matrix['families'] if item['id'] == 'effects-straight')
        fixtures = Path(entry['fixtures']); limits = Path(entry['limits'])
        original_fixtures, original_limits = fixtures.read_bytes(), limits.read_bytes()
        data = json.loads(fixtures.read_text()); removed = data['cases'].pop()['id']; fixtures.write_text(json.dumps(data))
        policy = json.loads(limits.read_text()); policy['fixtures_sha256'] = licensed.sha256(fixtures)
        policy['cases'].pop(removed); limits.write_text(json.dumps(policy))
        self.assertEqual(self.execute()[0], 2)
        self.assertEqual(self.calls, [])
        fixtures.write_bytes(original_fixtures); limits.write_bytes(original_limits)

        entry = next(item for item in self.matrix['families'] if item['id'] == 'transforms-premultiplied')
        fixtures = Path(entry['fixtures']); limits = Path(entry['limits'])
        data = json.loads(fixtures.read_text())
        for case in data['cases']:
            for model in case['models']:
                model['premultiplied_alpha'] = False
        fixtures.write_text(json.dumps(data))
        policy = json.loads(limits.read_text()); policy['fixtures_sha256'] = licensed.sha256(fixtures)
        limits.write_text(json.dumps(policy))
        self.assertEqual(self.execute()[0], 2)
        self.assertEqual(self.calls, [])

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
