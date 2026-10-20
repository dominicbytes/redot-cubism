# SPDX-License-Identifier: MIT
"""Headless scene-preview tolerance must never hide other editor diagnostics."""
from pathlib import Path
import re
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools'))
from run_editor_tests import editor_diagnostics


class EditorDiagnosticsTests(unittest.TestCase):
    preview = ('ERROR: Parameter "t" is null.\n'
               '   at: texture_2d_get (servers/rendering/dummy/storage/texture_storage.h:115)\n')

    def has_error(self, output, headless=True):
        return bool(re.search(r'ERROR:|WARNING:|SCRIPT ERROR|runtime error:|crashed',
                              editor_diagnostics(output, headless)))

    def test_known_dummy_preview_only_in_headless_mode(self):
        for location in ('servers/rendering/dummy/storage/texture_storage.h',
                         'servers\\rendering\\dummy\\storage/texture_storage.h'):
            output = self.preview.replace('servers/rendering/dummy/storage/texture_storage.h', location)
            with self.subTest(location=location):
                self.assertFalse(self.has_error(output * 3))
                self.assertTrue(self.has_error(output, headless=False))

    def test_same_message_at_other_callsite_stays_fatal(self):
        for output in (self.preview.splitlines()[0],
                       self.preview.replace('texture_2d_get', 'texture_get_width'),
                       self.preview.replace('dummy', 'gl_compatibility'),
                       self.preview.replace(':115', ':116'),
                       self.preview.replace('"t"', '"texture"')):
            with self.subTest(output=output):
                self.assertTrue(self.has_error(output))

    def test_other_diagnostics_next_to_preview_stay_fatal(self):
        for diagnostic in ('ERROR: Unexpected texture failure', 'WARNING: Resource leaked',
                           'SCRIPT ERROR: Invalid call', 'runtime error: overflow', 'crashed'):
            with self.subTest(diagnostic=diagnostic):
                self.assertTrue(self.has_error(self.preview + diagnostic))

    def test_clean_output_unchanged(self):
        output = 'CUBISM_EDITOR_WORKFLOW checks=50 failures=0\nCUBISM_EDITOR_WORKFLOW_PASS\n'
        self.assertEqual(editor_diagnostics(output, True), output)
        self.assertEqual(editor_diagnostics(output, False), output)


if __name__ == '__main__':
    unittest.main()
