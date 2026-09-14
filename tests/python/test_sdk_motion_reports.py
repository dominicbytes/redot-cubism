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


    def test_look_coordinates_are_finite_and_complete(self):
        fixture = {'model': 'character.model3.json', 'resource': 'res://character.res',
                   'motions': [{'group': 'Idle', 'index': 0}]}
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'fixtures.json'
            for value in (None, {}, True, [1], [1, 2, 3], [True, 0], [float('nan'), 0],
                          [0, float('inf')], [1e8, 0], ['1', 2]):
                bad = copy.deepcopy(fixture)
                bad['motions'][0]['look'] = value
                path.write_text(json.dumps([bad]))
                with self.subTest(value=value), self.assertRaises(ValueError): load_fixtures(path)
            path.write_text(json.dumps([fixture]))
            self.assertEqual(load_fixtures(path)[0]['motions'][0]['look'], [])
            self.assertFalse(load_fixtures(path)[0]['motions'][0]['loop'])

    def test_expression_switch_identity_and_time_are_validated(self):
        fixture = {'model': 'character.model3.json', 'resource': 'res://character.res',
                   'motions': [{'group': 'Idle', 'index': 0}]}
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'fixtures.json'
            for switch in (None, [], {'id': 'Smile'}, {'id': 'Smile', 'step': 0},
                           {'id': 'Smile', 'step': True}, {'id': 'Smile', 'step': 1.5},
                           {'id': '', 'step': 1}, {'id': 7, 'step': 1},
                           {'id': 'Smile', 'step': 36001}, {'id': 'Smile', 'step': 1, 'typo': True}):
                bad = copy.deepcopy(fixture)
                bad['motions'][0]['expression_switch'] = switch
                path.write_text(json.dumps([bad]))
                with self.subTest(switch=switch), self.assertRaises(ValueError): load_fixtures(path)
            for switch in ({}, {'id': '笑顔', 'step': 30}):
                fixture['motions'][0]['expression_switch'] = switch
                path.write_text(json.dumps([fixture]))
                self.assertEqual(load_fixtures(path)[0]['motions'][0]['expression_switch'], switch)

    def test_effect_selection_is_typed_and_defaults_off(self):
        fixture = {'model': 'character.model3.json', 'resource': 'res://character.res',
                   'motions': [{'group': 'Idle', 'index': 0}]}
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'fixtures.json'
            path.write_text(json.dumps([fixture]))
            motion = load_fixtures(path)[0]['motions'][0]
            self.assertEqual((motion['expression'], motion['physics'], motion['pose'], motion['breath']), ('', False, False, False))
            for key, value in [('expression', None), ('expression', True), ('physics', 1), ('physics', 'false'), ('pose', None), ('breath', 1), ('breath', 'false'), ('breath', None), ('loop', 1), ('loop', 'false'), ('loop', None)]:
                bad = copy.deepcopy(fixture)
                bad['motions'][0][key] = value
                path.write_text(json.dumps([bad]))
                with self.assertRaises(ValueError): load_fixtures(path)
            fixture['motions'][0].update(expression='笑顔', physics=True, pose=True, breath=True, look=[125.5, -300.0], loop=True, expression_switch={})
            path.write_text(json.dumps([fixture]))
            self.assertEqual(load_fixtures(path)[0]['motions'][0], fixture['motions'][0])


if __name__ == '__main__':
    unittest.main()
