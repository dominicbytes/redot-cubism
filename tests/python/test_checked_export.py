# SPDX-License-Identifier: MIT
import importlib.util
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

ADDON = Path(__file__).resolve().parents[2] / 'demo/addons/gd_cubism/editor'
sys.path.insert(0, str(ADDON))
spec = importlib.util.spec_from_file_location('cubism_checked_export', ADDON / 'checked_export.py')
checked = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checked)


class CheckedExportTest(unittest.TestCase):
    def test_promotes_complete_directory_and_retains_previous(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output, stage, previous = (root / p for p in ('output', 'stage', 'previous'))
            output.mkdir()
            (output / checked.MANIFEST).write_text('{}')
            (output / 'old-library.so').write_bytes(b'old')
            stage.mkdir()
            (stage / 'new-library.so').write_bytes(b'new')
            checked.promote(stage, output, previous)
            self.assertEqual((previous / 'old-library.so').read_bytes(), b'old')
            self.assertFalse((output / 'old-library.so').exists())
            self.assertEqual((output / 'new-library.so').read_bytes(), b'new')

    def test_failed_promotion_restores_previous_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output, stage, previous = (root / p for p in ('output', 'stage', 'previous'))
            output.mkdir()
            (output / checked.MANIFEST).write_text('old')
            stage.mkdir()
            rename = Path.rename
            def fail_stage(path, target):
                if path == stage:
                    raise OSError('Simulated promotion failure')
                return rename(path, target)
            with patch.object(Path, 'rename', fail_stage), self.assertRaisesRegex(OSError, 'promotion'):
                checked.promote(stage, output, previous)
            self.assertEqual((output / checked.MANIFEST).read_text(), 'old')
            self.assertTrue(stage.exists())

    def test_unmanaged_output_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output, stage = root / 'output', root / 'stage'
            output.mkdir()
            (output / 'user.txt').write_text('preserve')
            stage.mkdir()
            with self.assertRaisesRegex(ValueError, 'not a managed'):
                checked.promote(stage, output, root / 'previous')
            self.assertEqual((output / 'user.txt').read_text(), 'preserve')

    def test_changed_or_external_input_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'model.json').write_text('{}')
            digest = checked.sha256(root / 'model.json')
            checked.check_sources(root, {'res://model.json': digest})
            (root / 'model.json').write_text('changed')
            with self.assertRaisesRegex(ValueError, 'changed'):
                checked.check_sources(root, {'res://model.json': digest})
            with self.assertRaisesRegex(ValueError, 'changed'):
                checked.check_sources(root, {'res://../outside': digest})

    def test_native_headers(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'binary'
            header = bytearray(64)
            header[:6] = b'\x7fELF\x02\x01'
            struct.pack_into('<H', header, 18, 62)
            path.write_bytes(header)
            self.assertEqual(checked.binary_architecture(path), 'x86_64')
            struct.pack_into('<H', header, 18, 183)
            path.write_bytes(header)
            self.assertEqual(checked.binary_architecture(path), 'unsupported')
            header = bytearray(64)
            header[:2] = b'MZ'
            struct.pack_into('<I', header, 60, 64)
            path.write_bytes(header + b'PE\0\0' + struct.pack('<H', 0x8664))
            self.assertEqual(checked.binary_architecture(path), 'x86_64')
            path.write_bytes(b'not a native binary')
            with self.assertRaisesRegex(ValueError, 'Unsupported native'):
                checked.binary_architecture(path)
