# SPDX-License-Identifier: MIT
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools'))
from run_desktop_tests import check_report


class DesktopReportTests(unittest.TestCase):
    def test_rejects_failed_checks_and_mismatched_artifacts(self):
        good = {'status': 'PASS', 'library_sha256': 'expected', 'engine_version': 'pinned',
                'checks': [{'status': 'PASS'}]}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'report.json'
            path.write_text(json.dumps(good))
            self.assertEqual(check_report(path, 'expected', 'pinned'), good)
            for change in ({'status': 'FAIL'}, {'status': 'RUNNING'}, {'library_sha256': 'old'},
                           {'engine_version': 'other'}, {'checks': [{'status': 'FAIL'}]},
                           {'checks': [{'status': 'NOT_RUN'}]}, {'checks': None}):
                with self.subTest(change=change):
                    path.write_text(json.dumps(dict(good, **change)))
                    with self.assertRaises(ValueError): check_report(path, 'expected', 'pinned')

    def test_missing_or_truncated_report_never_passes(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'report.json'
            with self.assertRaises(OSError): check_report(path, 'expected', 'pinned')
            path.write_text('{"status":')
            with self.assertRaises(ValueError): check_report(path, 'expected', 'pinned')
            for value in (None, [], 'PASS'):
                path.write_text(json.dumps(value))
                with self.assertRaises(ValueError): check_report(path, 'expected', 'pinned')


if __name__ == '__main__':
    unittest.main()
