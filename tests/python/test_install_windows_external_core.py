# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Redot Cubism contributors
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from install_windows_external_core import DEPENDENCY_LINE, descriptor_with_dependency, install
from windows_pe import imported_dlls


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


class WindowsExternalCoreInstallerTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo"
        self.sdk = self.root / "sdk"
        self.addon = self.root / "addon"
        self.source = self.sdk / "Core/dll/windows/x86_64/Live2DCubismCore.dll"
        self.binary = self.addon / "bin/libgd_cubism.windows.release.x86_64.dll"
        self.descriptor = self.addon / "gd_cubism.gdextension"
        self.source.parent.mkdir(parents=True)
        self.binary.parent.mkdir(parents=True)
        self.repo.mkdir()
        self.source.write_bytes(b"pinned Core fixture")
        self.binary.write_bytes(pe_with_import())
        self.descriptor.write_text("[configuration]\nentry_symbol = \"fixture\"\n")
        digest = hashlib.sha256(self.source.read_bytes()).hexdigest()
        (self.repo / "DEPENDENCIES.json").write_text(json.dumps({
            "cubism_sdk": {"core_library_sha256": {
                "dll/windows/x86_64/Live2DCubismCore.dll": digest}}}))

    def test_pe_import_reader(self):
        self.assertEqual(imported_dlls(pe_with_import()), ["Live2DCubismCore.dll"])
        with self.assertRaisesRegex(ValueError, "PE"):
            imported_dlls(b"not a binary")

    def test_installs_verified_core_and_export_mapping(self):
        destination = install(self.repo, self.sdk, self.addon)
        self.assertEqual(destination.read_bytes(), self.source.read_bytes())
        self.assertIn(DEPENDENCY_LINE, self.descriptor.read_text())
        original = self.descriptor.read_text()
        install(self.repo, self.sdk, self.addon)
        self.assertEqual(self.descriptor.read_text(), original)

    def test_preserves_other_platform_dependency(self):
        text = '[dependencies]\n\nlinux.x86_64 = {"bin/libLive2DCubismCore.so": ""}\n'
        updated = descriptor_with_dependency(text)
        self.assertIn("linux.x86_64", updated)
        self.assertIn(DEPENDENCY_LINE, updated)

    def test_rejects_wrong_existing_mapping(self):
        with self.assertRaisesRegex(ValueError, "differs"):
            descriptor_with_dependency('[dependencies]\nwindows.x86_64 = {"wrong.dll": ""}\n')

    def test_rejects_missing_changed_and_static_inputs(self):
        self.source.unlink()
        with self.assertRaisesRegex(ValueError, "missing"):
            install(self.repo, self.sdk, self.addon)
        self.source.write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "does not match"):
            install(self.repo, self.sdk, self.addon)
        self.source.write_bytes(b"pinned Core fixture")
        self.binary.write_bytes(pe_with_import(b"KERNEL32.dll"))
        with self.assertRaisesRegex(ValueError, "windows_core_link=dynamic"):
            install(self.repo, self.sdk, self.addon)


if __name__ == "__main__":
    unittest.main()
