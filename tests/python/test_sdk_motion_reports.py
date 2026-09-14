# SPDX-License-Identifier: MIT
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools'))
from run_sdk_motion_tests import compare_states, load_fixtures


class SDKMotionReportTests(unittest.TestCase):
    def test_numeric_difference_is_reported(self):
        expected = {'parameters': {'目': 0.5}, 'parts': {'body': 1.0}}
        actual = copy.deepcopy(expected)
        self.assertEqual(compare_states(expected, actual), [])
        actual['parameters']['目'] = 0.6
        self.assertEqual(compare_states(expected, actual), [
            {'group': 'parameters', 'id': '目', 'expected': 0.5, 'actual': 0.6}])

    def test_incomplete_and_nonfinite_results_never_pass(self):
        good = {'parameters': {'angle': 0.0}, 'parts': {'body': 1.0}}
        for group in ('parameters', 'parts'):
            for value in (None, {}, {'wrong': 0}, {next(iter(good[group])): float('nan')},
                          {next(iter(good[group])): float('inf')}, {next(iter(good[group])): True}):
                with self.subTest(group=group, value=value):
                    bad = copy.deepcopy(good)
                    bad[group] = value
                    with self.assertRaises(ValueError): compare_states(good, bad)
        with self.assertRaises(ValueError): compare_states({'parameters': {}, 'parts': {}}, {'parameters': {}, 'parts': {}})

    def test_fixture_selection_is_explicit(self):
        fixture = {'model': 'character.model3.json', 'resource': 'res://character.res',
                   'motions': [{'group': '待機', 'index': 0}]}
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'fixtures.json'
            path.write_text(json.dumps([fixture]), encoding='utf-8')
            self.assertEqual(load_fixtures(path)[0]['model'], str(Path(folder) / fixture['model']))
            for value in ([], {}, [dict(fixture, resource='../character.res')],
                          [dict(fixture, motions=[])], [dict(fixture, motions=[{'group': 'Idle', 'index': -1}])]):
                path.write_text(json.dumps(value), encoding='utf-8')
                with self.assertRaises(ValueError): load_fixtures(path)


    def test_effect_selection_is_typed_and_defaults_off(self):
        fixture = {'model': 'character.model3.json', 'resource': 'res://character.res',
                   'motions': [{'group': 'Idle', 'index': 0}]}
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'fixtures.json'
            path.write_text(json.dumps([fixture]))
            motion = load_fixtures(path)[0]['motions'][0]
            self.assertEqual((motion['expression'], motion['physics'], motion['pose'], motion['breath']), ('', False, False, False))
            for key, value in [('expression', None), ('expression', True), ('physics', 1), ('physics', 'false'), ('pose', None), ('breath', 1), ('breath', 'false'), ('breath', None)]:
                bad = copy.deepcopy(fixture)
                bad['motions'][0][key] = value
                path.write_text(json.dumps([bad]))
                with self.assertRaises(ValueError): load_fixtures(path)
            fixture['motions'][0].update(expression='笑顔', physics=True, pose=True, breath=True)
            path.write_text(json.dumps([fixture]))
            self.assertEqual(load_fixtures(path)[0]['motions'][0], fixture['motions'][0])


if __name__ == '__main__':
    unittest.main()
