# SPDX-License-Identifier: MIT
"""Replay mixer-boundary and stall samples against the native clock estimator."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from native_test_compile import compiler_command

ROOT = Path(__file__).resolve().parents[2]


class AudioClockTest(unittest.TestCase):
    def test_backend_samples(self):
        output = Path(os.environ.get('CUBISM_TEST_BUILD_DIR', ROOT / '.local-build'))
        output.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='audio-clock-', dir=output) as directory:
            binary = Path(directory) / ('audio-clock-checks.exe' if os.name == 'nt' else 'audio-clock-checks')
            subprocess.run(compiler_command(ROOT / 'tests/native/audio_clock_checks.cpp', binary, ROOT / 'src'),
                           check=True, capture_output=True, text=True, timeout=60)
            result = subprocess.run([str(binary)], check=True, capture_output=True,
                                    text=True, timeout=10)
            self.assertIn('CUBISM_AUDIO_CLOCK checks=19 failures=0', result.stdout)


if __name__ == '__main__':
    unittest.main()
