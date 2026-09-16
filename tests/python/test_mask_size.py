# SPDX-License-Identifier: MIT
"""Check native mask sizing without requiring licensed model data or a GPU."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from native_test_compile import compiler_command

ROOT = Path(__file__).resolve().parents[2]


class MaskSizeTest(unittest.TestCase):
    def test_bounded_geometry(self):
        output = Path(os.environ.get('CUBISM_TEST_BUILD_DIR', ROOT / '.local-build'))
        output.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='mask-size-', dir=output) as directory:
            binary = Path(directory) / ('mask-size-checks.exe' if os.name == 'nt' else 'mask-size-checks')
            subprocess.run(compiler_command(ROOT / 'tests/native/mask_size_checks.cpp', binary, ROOT / 'src'),
                           check=True, capture_output=True, text=True, timeout=60)
            result = subprocess.run([str(binary)], check=True, capture_output=True,
                                    text=True, timeout=10)
            self.assertIn('CUBISM_MASK_SIZE checks=808 failures=0', result.stdout)


if __name__ == '__main__':
    unittest.main()
