# SPDX-License-Identifier: MIT
import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('benchmarks', Path(__file__).resolve().parents[2] / 'tools/run_benchmarks.py')
bench = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bench)


class BenchmarkTests(unittest.TestCase):
    def report(self):
        summary = bench.summarize([{key: value for key in bench.METRICS} for value in range(1, 101)])
        return {'status': 'PASS', 'identity': {'runner_id': 'dedicated-test', 'engine': 'pinned'},
                'scenarios': {name: {'summary': copy.deepcopy(summary)} for name in bench.SCENARIOS}}

    def test_distribution(self):
        summary = self.report()['scenarios']['static']['summary']['frame_usec']
        self.assertEqual(summary, {'mean': 50.5, 'median': 50.5, 'p95': 95, 'p99': 99})

    def test_invalid_measurements(self):
        for bad in (float('nan'), float('inf'), -1, 'invalid', True):
            samples = [{key: 1 for key in bench.METRICS} for _ in range(100)]
            samples[-1]['frame_usec'] = bad
            with self.assertRaises(ValueError): bench.summarize(samples)
        with self.assertRaises(ValueError): bench.summarize([])

    def test_reviewed_relative_gate(self):
        baseline = self.report()
        current = copy.deepcopy(baseline)
        current['scenarios']['crowd']['summary']['renderer_update_usec']['p95'] = 110
        self.assertEqual(bench.compare(current, baseline, .2), [])
        failures = bench.compare(current, baseline, .1)
        self.assertEqual(len(failures), 1)
        self.assertEqual(failures[0]['scenario'], 'crowd')
        self.assertEqual(failures[0]['metric'], 'renderer_update_usec')

    def test_rejects_unmatched_or_failed_baseline(self):
        for mutation in ('runner', 'engine', 'failed', 'missing'):
            baseline = self.report()
            current = self.report()
            if mutation == 'runner': baseline['identity']['runner_id'] = 'other'
            if mutation == 'engine': baseline['identity']['engine'] = 'different'
            if mutation == 'failed': baseline['status'] = 'FAIL'
            if mutation == 'missing': del baseline['scenarios']['hidden']
            with self.assertRaises(ValueError): bench.compare(current, baseline, .1)
        current = self.report()
        current['identity']['runner_id'] = ''
        with self.assertRaises(ValueError): bench.compare(current, current, .1)

    def test_zero_baseline_and_invalid_threshold(self):
        baseline = self.report()
        current = self.report()
        baseline['scenarios']['hidden']['summary']['mask_requests']['p95'] = 0
        self.assertEqual(len(bench.compare(current, baseline, .2)), 1)
        for value in (-1, float('nan'), float('inf')):
            with self.assertRaises(ValueError): bench.compare(current, baseline, value)
