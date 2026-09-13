# SPDX-License-Identifier: MIT
"""Check native mask sizing without requiring licensed model data or a GPU."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class MaskSizeTest(unittest.TestCase):
    def test_bounded_geometry(self):
        output = Path(os.environ.get('CUBISM_TEST_BUILD_DIR', ROOT / '.local-build'))
        output.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='mask-size-', dir=output) as directory:
            binary = Path(directory) / 'mask-size-checks'
            subprocess.run([os.environ.get('CXX', 'c++'), '-std=c++17', '-DNDEBUG',
                            '-Wall', '-Wextra', '-Werror', '-I', str(ROOT / 'src'),
                            str(ROOT / 'tests/native/mask_size_checks.cpp'), '-o', str(binary)],
                           check=True, capture_output=True, text=True, timeout=60)
            result = subprocess.run([str(binary)], check=True, capture_output=True,
                                    text=True, timeout=10)
            self.assertIn('CUBISM_MASK_SIZE checks=808 failures=0', result.stdout)


if __name__ == '__main__':
    unittest.main()
