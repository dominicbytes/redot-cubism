# SPDX-License-Identifier: MIT
import os
from pathlib import Path
import sys
import textwrap
import unittest
from unittest.mock import patch

WORKFLOW = Path(__file__).resolve().parents[2] / '.github' / 'workflows' / 'desktop-functional.yml'


def step_script(name):
    lines = WORKFLOW.read_text(encoding='utf-8').splitlines()
    start = lines.index('      - name: ' + name)
    run = next(index for index in range(start, len(lines)) if lines[index].strip() == 'run: |')
    body = []
    for line in lines[run + 1:]:
        if line.strip() and not line.startswith(' ' * 10):
            break
        body.append(line)
    return textwrap.dedent('\n'.join(body))


class LicensedWorkflowTests(unittest.TestCase):
    def launch(self, series, environment):
        calls = []
        env = {'GITHUB_RUN_ID': '7', 'GITHUB_RUN_ATTEMPT': '2', 'REDOT_RUNTIME_SERIES': series,
               'CUBISM_WORK_ROOT': os.path.abspath('work')}
        env.update(environment)

        def run(arguments, check):
            calls.append((arguments, dict(os.environ)))

        with patch.dict(os.environ, env, clear=True), patch('subprocess.run', run):
            exec(compile(step_script('Build and qualify both variants'), str(WORKFLOW), 'exec'), {})
        return calls

    def runtime_inputs(self):
        inputs = {}
        for series in ('26_2', '26_3'):
            for key in ('REDOT_BIN', 'CUBISM_TEMPLATE_DEBUG', 'CUBISM_TEMPLATE_RELEASE',
                        'CUBISM_BENCHMARK_BASELINE'):
                inputs[key + '_' + series] = key.lower() + '-' + series
        return inputs

    def test_each_runtime_selects_its_own_inputs(self):
        for series in ('26.2', '26.3'):
            with self.subTest(series=series):
                suffix = series.replace('.', '_')
                (arguments, env), = self.launch(series, self.runtime_inputs())
                for key in ('REDOT_BIN', 'CUBISM_TEMPLATE_DEBUG', 'CUBISM_TEMPLATE_RELEASE',
                            'CUBISM_BENCHMARK_BASELINE'):
                    self.assertEqual(env[key], key.lower() + '-' + suffix)
                self.assertEqual(env['REDOT_BINDING_BIN'], 'redot_bin-26_2')
                self.assertEqual(Path(arguments[arguments.index('--output') + 1]).parts[-3:],
                                 ('7', '2', series))

    def test_missing_inputs_fail_with_named_diagnostics(self):
        for missing in ('CUBISM_BENCHMARK_BASELINE_26_3', 'REDOT_BIN_26_2'):
            with self.subTest(missing=missing):
                inputs = self.runtime_inputs()
                del inputs[missing]
                with self.assertRaises(SystemExit) as raised:
                    self.launch('26.3', inputs)
                self.assertIn(missing, str(raised.exception))

    def test_engine_jobs_queue_instead_of_replacing_each_other(self):
        text = WORKFLOW.read_text(encoding='utf-8')
        self.assertIn("engine: ['26.2', '26.3']", text)
        self.assertIn('group: cubism-licensed-${{ matrix.platform }}', text)
        self.assertIn('queue: max', text)


if __name__ == '__main__':
    unittest.main()
