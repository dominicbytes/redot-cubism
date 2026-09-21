# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Redot Cubism contributors
import hashlib
import io
import sys
import tarfile
from pathlib import Path
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from check_restricted_files import inspect_bytes


def pe_with_import(name=b"Live2DCubismCore.dll"):
    data = bytearray(0x600)
    data[:2] = b"MZ"
    data[0x3C:0x40] = (0x80).to_bytes(4, "little")
    data[0x80:0x84] = b"PE\0\0"
    data[0x84:0x98] = (0x8664).to_bytes(2, "little") + (1).to_bytes(2, "little") + bytes(12) + (240).to_bytes(2, "little") + bytes(2)
    optional = 0x98
    data[optional:optional + 2] = (0x20B).to_bytes(2, "little")
    data[optional + 120:optional + 128] = (0x1100).to_bytes(4, "little") + (40).to_bytes(4, "little")
    section = optional + 240
    data[section:section + 8] = b".rdata\0\0"
    data[section + 8:section + 24] = ((0x400).to_bytes(4, "little") +
                                              (0x1000).to_bytes(4, "little") +
                                              (0x400).to_bytes(4, "little") +
                                              (0x200).to_bytes(4, "little"))
    data[0x300:0x314] = bytes(12) + (0x1150).to_bytes(4, "little") + bytes(4)
    data[0x350:0x350 + len(name) + 1] = name + b"\0"
    return bytes(data)


def zipped(name, data):
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, "w") as archive:
        archive.writestr(name, data)
    return stream.getvalue()


class RestrictedFilesTest(unittest.TestCase):
    def test_core_path(self):
        self.assertTrue(inspect_bytes("libLive2DCubismCore.a", b"synthetic"))

    def test_exact_upstream_sdk_placeholder(self):
        name = "thirdparty/CubismSdkForNative/.gitignore"
        self.assertFalse(inspect_bytes(name, b"*\n!.gitignore\n", public=True))
        self.assertFalse(inspect_bytes("source.tar.gz!prefix/" + name,
                                      b"*\n!.gitignore\n", public=True))
        self.assertTrue(inspect_bytes(name, b"MOC3 hidden content", public=True))
        self.assertTrue(inspect_bytes(name + ".h", b"*\n!.gitignore\n", public=True))

    def test_renamed_tar_archives(self):
        for mode in ("w", "w:gz", "w:xz", "w:bz2"):
            stream = io.BytesIO()
            with tarfile.open(fileobj=stream, mode=mode) as archive:
                entry = tarfile.TarInfo("model.dat")
                entry.size = 4
                archive.addfile(entry, io.BytesIO(b"MOC3"))
            with self.subTest(mode=mode):
                self.assertTrue(inspect_bytes("innocent.dat", stream.getvalue()))

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

    def test_approved_windows_addon_must_import_external_core(self):
        name = "bundle.zip!addons/gd_cubism/bin/libgd_cubism.windows.release.x86_64.dll"
        dynamic = pe_with_import()
        static = pe_with_import(b"KERNEL32.dll")
        self.assertFalse(inspect_bytes(name, dynamic, {name: hashlib.sha256(dynamic).hexdigest()}))
        problems = inspect_bytes(name, static, {name: hashlib.sha256(static).hexdigest()})
        self.assertTrue(any("external Cubism Core" in problem for problem in problems))

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
