# SPDX-License-Identifier: MIT
import copy
import hashlib
import json
from pathlib import Path
import platform
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools'))
from run_visual_tests import load_fixtures, measure_pixels, validate_limits


class VisualReportTests(unittest.TestCase):
    def test_rgb_and_alpha_are_independent_on_foreground_union(self):
        reference = bytes([100, 50, 0, 255, 0, 0, 0, 0])
        actual = bytes([103, 54, 0, 255, 0, 0, 0, 10])
        result = measure_pixels(reference, actual)
        self.assertEqual(result['foreground_pixels'], 2)
        self.assertAlmostEqual(result['rgb_rms'], (25 / 6) ** 0.5)
        self.assertAlmostEqual(result['alpha_rms'], 50 ** 0.5)
        self.assertEqual(result['rgb_max'], 4)
        self.assertEqual(result['alpha_max'], 10)
        self.assertEqual(result['rgb_pixels_above_3'], 1)
        self.assertEqual(result['alpha_pixels_above_3'], 1)

    def test_empty_and_mismatched_captures_cannot_pass(self):
        for left, right in [(b'', b''), (bytes(4), bytes(4)), (bytes(4), bytes(8)), (bytes(3), bytes(3))]:
            with self.assertRaises(ValueError): measure_pixels(left, right)

    def test_limits_require_exact_reviewed_reference_and_finite_values(self):
        valid = {'fixtures_sha256': 'a' * 64, 'review': 'Test-only policy', 'platform': platform.system(),
                 'renderer': 'gl_compatibility', 'adapter': 'fixture adapter',
                 'cases': {'neutral': dict(rgb_rms=1, alpha_rms=1, rgb_max=3, alpha_max=3)}}
        validate_limits(valid, 'a' * 64, ['neutral'])
        for field, value in [('fixtures_sha256', 'b' * 64), ('review', ''), ('adapter', ''), ('cases', {})]:
            invalid = copy.deepcopy(valid); invalid[field] = value
            with self.assertRaises(ValueError): validate_limits(invalid, 'a' * 64, ['neutral'])
        for value in [float('nan'), float('inf'), -1, 256, True]:
            invalid = copy.deepcopy(valid); invalid['cases']['neutral']['rgb_rms'] = value
            with self.assertRaises(ValueError): validate_limits(invalid, 'a' * 64, ['neutral'])

    def test_reference_identity_and_affine_state_are_required(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); image = root / 'reference.png'; image.write_bytes(b'image identity')
            model = dict(resource='res://model.res', manifest_sha256='a' * 64, moc_sha256='b' * 64,
                         texture_sha256=['c' * 64], premultiplied_alpha=False, mask_quality=2,
                         mvp=[1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
                         parameters={'angle': 0}, parts={'body': 1})
            case = dict(id='neutral', size=[512, 512], image='reference.png',
                        image_sha256=hashlib.sha256(image.read_bytes()).hexdigest(), models=[model])
            reference = dict(framework_sha256='d' * 64, core_sha256='e' * 64,
                             executable_sha256='f' * 64, description='Independent SDK capture')
            valid = dict(reference=reference, cases=[case]); path = root / 'fixtures.json'
            pins = {'cubism_framework': {'source_sha256': 'd' * 64},
                    'cubism_sdk': {'core_library_sha256': {'fixture-core': 'e' * 64}}}
            path.write_text(json.dumps(valid)); self.assertEqual(load_fixtures(path, pins)['cases'][0]['image'], str(image))
            for field, value in [('resource', '../escape.res'), ('mvp', [0] * 16), ('texture_sha256', []), ('premultiplied_alpha', 'false')]:
                invalid = copy.deepcopy(valid); invalid['cases'][0]['models'][0][field] = value
                path.write_text(json.dumps(invalid))
                with self.assertRaises(ValueError): load_fixtures(path, pins)
            invalid = copy.deepcopy(valid); invalid['cases'][0]['image_sha256'] = '0' * 64
            path.write_text(json.dumps(invalid))
            with self.assertRaises(ValueError): load_fixtures(path, pins)


if __name__ == '__main__':
    unittest.main()
