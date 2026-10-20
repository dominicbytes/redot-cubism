# SPDX-License-Identifier: MIT
from pathlib import Path
import re
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[2]
MOJIBAKE = re.compile(r'\u00c3|\u00c2|\u00e2\u20ac|\u00f0\u0178|\u00e6\u00a8|\u00e5\u2020|\u00e9\u0192')


class TextEncodingTests(unittest.TestCase):
    def test_detects_utf8_decoded_as_cp1252(self):
        for text in ('\u00e9', '\u2013', '\u5185\u90e8', '\u6a21\u578b', '\U0001f600'):
            corrupted = text.encode('utf-8').decode('cp1252')
            with self.subTest(text=text):
                self.assertIsNotNone(MOJIBAKE.search(corrupted))
                self.assertIsNotNone(MOJIBAKE.search(corrupted.encode('utf-8').decode('cp1252')))
                self.assertIsNone(MOJIBAKE.search(text))

    def test_tracked_text_has_no_mojibake(self):
        names = subprocess.check_output([
            'git', 'ls-files', '-z', '--', 'tools/', 'tests/', 'demo/addons/', 'src/', 'docs/'
        ], cwd=ROOT).decode('utf-8').split('\0')
        for name in filter(None, names):
            data = (ROOT / name).read_bytes()
            if b'\0' in data:
                continue
            try:
                text = data.decode('utf-8')
            except UnicodeDecodeError:
                continue
            with self.subTest(file=name):
                self.assertIsNone(MOJIBAKE.search(text), 'UTF-8 text was decoded as cp1252')


if __name__ == '__main__':
    unittest.main()
