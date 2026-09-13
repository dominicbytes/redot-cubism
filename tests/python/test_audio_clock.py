# SPDX-License-Identifier: MIT
"""Replay mixer-boundary and stall samples against the native clock estimator."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class AudioClockTest(unittest.TestCase):
    def test_backend_samples(self):
        output = Path(os.environ.get('CUBISM_TEST_BUILD_DIR', ROOT / '.local-build'))
        output.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='audio-clock-', dir=output) as directory:
            binary = Path(directory) / 'audio-clock-checks'
            subprocess.run([os.environ.get('CXX', 'c++'), '-std=c++17', '-DNDEBUG',
                            '-Wall', '-Wextra', '-Werror', '-I', str(ROOT / 'src'),
                            str(ROOT / 'tests/native/audio_clock_checks.cpp'), '-o', str(binary)],
                           check=True, capture_output=True, text=True, timeout=60)
            result = subprocess.run([str(binary)], check=True, capture_output=True,
                                    text=True, timeout=10)
            self.assertIn('CUBISM_AUDIO_CLOCK checks=16 failures=0', result.stdout)


if __name__ == '__main__':
    unittest.main()
