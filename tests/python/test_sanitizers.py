# SPDX-License-Identifier: MIT
import os
import random
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from build_inputs import sanitizer_flags
from framework_patch import patch_csm_string


class SanitizerTests(unittest.TestCase):
    def test_modes_and_target_rejection(self):
        self.assertEqual(sanitizer_flags('none', 'windows'), ([], []))
        for mode in ('address', 'undefined', 'address,undefined'):
            compile_flags, link_flags = sanitizer_flags(mode, 'linux')
            self.assertIn('-fsanitize=' + mode, compile_flags)
            self.assertIn('-fsanitize=' + mode, link_flags)
            self.assertEqual('-fno-sanitize-recover=undefined' in compile_flags, 'undefined' in mode)
            with self.assertRaises(ValueError): sanitizer_flags(mode, 'windows')
        with self.assertRaises(ValueError): sanitizer_flags('unrecognized', 'linux')

    @unittest.skipUnless(sys.platform == 'linux', 'UBSan runtime probe is Linux-only')
    def test_undefined_behavior_is_fatal(self):
        output = Path(os.environ.get('CUBISM_TEST_BUILD_DIR', ROOT / '.local-build'))
        output.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='ubsan-probe-', dir=output) as directory:
            source = Path(directory) / 'probe.cpp'
            source.write_text('#include <climits>\n#include <cstdio>\nint main(int argc, char **) { volatile int value = argc > 1 ? INT_MAX : 1; int next = value + 1; std::printf("PROBE_COMPLETE %d\\n", next); return 0; }\n')
            binary = Path(directory) / 'probe'
            compile_flags, link_flags = sanitizer_flags('undefined', 'linux')
            subprocess.run([os.environ.get('CXX', 'c++'), *compile_flags, str(source), *link_flags,
                            '-o', str(binary)], check=True, capture_output=True, text=True, timeout=30)
            clean = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
            self.assertEqual(clean.returncode, 0, clean.stderr)
            self.assertIn('PROBE_COMPLETE 2', clean.stdout)
            # Deliberately omit UBSAN_OPTIONS: the build flags themselves must fail.
            env = dict(os.environ)
            env.pop('UBSAN_OPTIONS', None)
            broken = subprocess.run([str(binary), 'overflow'], env=env, capture_output=True, text=True, timeout=10)
            self.assertNotEqual(broken.returncode, 0)
            self.assertIn('signed integer overflow', broken.stderr)
            self.assertNotIn('PROBE_COMPLETE', broken.stdout)


class FrameworkHashTests(unittest.TestCase):
    def test_unreviewed_framework_rejected(self):
        with self.assertRaisesRegex(ValueError, 'reviewed hash patch input'):
            patch_csm_string(b'changed Framework source')

    @unittest.skipUnless(sys.platform == 'linux', 'UBSan hash probe is Linux-only')
    def test_hash_matches_modular_oracle(self):
        rng = random.Random(17)
        values = [b'', b'ParamAngleX', b'NullValue', b'\xff', bytes(range(256)), '表情'.encode()]
        for boundary in (0x7fffffff, 0x80000000, 0xffffffff):
            digits = []
            while boundary:
                digits.append(boundary % 31)
                boundary //= 31
            values.append(bytes(digits))
        values += [rng.randbytes(length) for length in range(1, 129)]
        output = Path(os.environ.get('CUBISM_TEST_BUILD_DIR', ROOT / '.local-build'))
        output.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='hash-probe-', dir=output) as directory:
            source = Path(directory) / 'probe.cpp'
            lines = ['#include "private/cubism_string_hash.hpp"', '#include <climits>', '#include <cstdio>',
                     'int main() { std::printf("%d\\n", CHAR_MIN < 0);']
            for data in values:
                encoded = ','.join(str(byte) for byte in data + b'\0')
                lines += ['{ const unsigned char bytes[] = {' + encoded + '};',
                          'std::printf("%d\\n", cubism_string_hash(reinterpret_cast<const char *>(bytes), ' + str(len(data)) + ', false)); }']
            lines += ['std::printf("%d\\n", cubism_string_hash("", 0, true)); return 0; }']
            source.write_text('\n'.join(lines))
            binary = Path(directory) / 'probe'
            compile_flags, link_flags = sanitizer_flags('undefined', 'linux')
            subprocess.run([os.environ.get('CXX', 'c++'), *compile_flags, '-I', str(ROOT / 'src'),
                            str(source), *link_flags, '-o', str(binary)], check=True, capture_output=True, text=True, timeout=30)
            result = subprocess.run([str(binary)], check=True, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.stderr, '')
            actual = [int(value) for value in result.stdout.splitlines()]
            signed_char = actual.pop(0)
            expected = []
            for data in values:
                value = 0
                for byte in reversed(data + b'\0'):
                    value = (value * 31 + (byte - 256 if signed_char and byte >= 128 else byte)) % (1 << 32)
                if value == 0xffffffff: expected.append(-2)
                else: expected.append(value if value < (1 << 31) else value - (1 << 32))
            self.assertEqual(actual, expected + [-2])
