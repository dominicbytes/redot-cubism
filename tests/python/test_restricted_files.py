# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Redot Cubism contributors
import hashlib
import io
import sys
from pathlib import Path
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from check_restricted_files import inspect_bytes


def zipped(name, data):
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, "w") as archive:
        archive.writestr(name, data)
    return stream.getvalue()


class RestrictedFilesTest(unittest.TestCase):
    def test_core_path(self):
        self.assertTrue(inspect_bytes("libLive2DCubismCore.a", b"synthetic"))

    def test_core_header_renamed(self):
        self.assertTrue(inspect_bytes("innocent.h", b"CSM_API unsigned int csmGetVersion(void);"))

    def test_model_signature_renamed(self):
        self.assertTrue(inspect_bytes("image.bin", b"MOC3 synthetic"))

    def test_prose_is_not_a_core_header(self):
        self.assertFalse(inspect_bytes("README.md", b"Do not commit Live2DCubismCore.h or .moc3"))

    def test_unapproved_native_binary(self):
        self.assertTrue(inspect_bytes("bin/addon.so", b"synthetic"))

    def test_native_signature_renamed(self):
        self.assertTrue(inspect_bytes("image.dat", b"\x7fELF synthetic"))

    def test_invalid_archive(self):
        self.assertTrue(inspect_bytes("package.zip", b"not a zip"))

    def test_exact_native_approval(self):
        data = b"synthetic approved library"
        approval = {"bin/addon.so": hashlib.sha256(data).hexdigest()}
        self.assertFalse(inspect_bytes("bin/addon.so", data, approval))
        self.assertTrue(inspect_bytes("bin/addon.so", data + b"changed", approval))

    def test_core_not_approved_by_native_allowlist(self):
        data = b"synthetic"
        name = "Live2DCubismCore.dll"
        self.assertTrue(inspect_bytes(name, data, {name: hashlib.sha256(data).hexdigest()}))

    def test_archive_and_nested_archive(self):
        for data in [zipped("model.moc3", b"synthetic"), zipped("inner.zip", zipped("model.moc3", b"synthetic"))]:
            self.assertTrue(inspect_bytes("package.zip", data))

    def test_safe_archive(self):
        self.assertFalse(inspect_bytes("package.zip", zipped("src/code.cpp", b"// MIT")))

    def test_archive_path_escape(self):
        self.assertTrue(inspect_bytes("package.zip", zipped("../outside", b"x")))

    def test_archive_budget(self):
        self.assertTrue(inspect_bytes("package.zip", zipped("safe", b"xxx"), budget=[2, 1]))


if __name__ == "__main__":
    unittest.main()
