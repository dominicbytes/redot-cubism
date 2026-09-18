# SPDX-License-Identifier: MIT
import hashlib
from pathlib import Path
import struct
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools'))
from pck_inspection import inspect_pack


def fixture(version=3, names=('safe.txt',), payload=b'hello'):
    entries = b''
    for name in names:
        path = name.encode()
        entries += struct.pack('<I', len(path)) + path + struct.pack('<QQ', 0, len(payload)) + hashlib.md5(payload).digest() + struct.pack('<I', 0)
    directory = struct.pack('<I', len(names)) + entries
    common = struct.pack('<6I', 0x43504447, version, 26, 2, 0, 2)
    if version == 3:
        return common + struct.pack('<QQ', 104, 104 + len(payload)) + bytes(64) + payload + directory
    return common + struct.pack('<Q', 96 + len(directory)) + bytes(64) + directory + payload


class PckInspectionTest(unittest.TestCase):
    def inspect(self, data):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'test.pck'
            path.write_bytes(data)
            return inspect_pack(path)

    def test_engine_v2_and_v3_layout(self):
        for version in (2, 3):
            result = self.inspect(fixture(version))
            self.assertEqual(result['format_version'], version)
            self.assertEqual(result['files']['safe.txt']['sha256'], hashlib.sha256(b'hello').hexdigest())

    def test_duplicate_names(self):
        with self.assertRaisesRegex(ValueError, 'Duplicate'):
            self.inspect(fixture(names=('safe.txt', 'safe.txt')))

    def test_corrupt_payload(self):
        data = bytearray(fixture())
        data[104] ^= 1
        with self.assertRaisesRegex(ValueError, 'checksum'):
            self.inspect(data)

    def test_truncated_directory(self):
        with self.assertRaisesRegex(ValueError, 'Truncated'):
            self.inspect(fixture()[:-1])

    def test_encrypted_directory(self):
        data = bytearray(fixture())
        data[20] = 1
        with self.assertRaisesRegex(ValueError, 'Unsupported'):
            self.inspect(data)

    def test_unsafe_path(self):
        for path in ('../escape', '/absolute', 'a//b', 'C:/file', 'a\\b'):
            with self.assertRaisesRegex(ValueError, 'Unsafe'):
                self.inspect(fixture(names=(path,)))

    def test_out_of_bounds_entry(self):
        data = bytearray(fixture())
        # v3 payload ends at109, followed by count, path length and eight bytes.
        struct.pack_into('<Q', data, 109 + 4 + 4 + 8, 999999)
        with self.assertRaisesRegex(ValueError, 'out-of-bounds'):
            self.inspect(data)
