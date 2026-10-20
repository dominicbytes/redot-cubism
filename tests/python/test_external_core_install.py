# SPDX-License-Identifier: MIT
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
import external_core_install as transaction
import install_linux_external_core as linux
import install_windows_external_core as windows
from test_install_windows_external_core import pe_with_import


class ExternalCoreInstallTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.repo = self.root / "repo"
        self.sdk = self.root / "sdk"
        self.addon = self.root / "addon"
        self.repo.mkdir()
        (self.addon / "bin").mkdir(parents=True)
        self.descriptor = self.addon / "gd_cubism.gdextension"
        self.original = b'[configuration]\nentry_symbol = "fixture"\n'
        self.descriptor.write_bytes(self.original)
        self.sources = {}
        self.destinations = {}
        pins = {}
        for platform, filename in (("windows", "Live2DCubismCore.dll"),
                                   ("linux", "libLive2DCubismCore.so")):
            relative = "dll/" + platform + "/x86_64/" + filename
            source = self.sdk / "Core" / relative
            source.parent.mkdir(parents=True)
            source.write_bytes(("approved " + platform).encode())
            self.sources[platform] = source
            self.destinations[platform] = self.addon / "bin" / filename
            pins[relative] = hashlib.sha256(source.read_bytes()).hexdigest()
        (self.repo / "DEPENDENCIES.json").write_text(json.dumps({
            "cubism_sdk": {"core_library_sha256": pins}}))
        (self.addon / "bin/libgd_cubism.windows.release.x86_64.dll").write_bytes(pe_with_import())
        (self.addon / "bin/libgd_cubism.linux.release.x86_64.so").write_bytes(b"synthetic dynamic ELF")
        self.readelf = mock.patch.object(linux, "inspect_dynamic_library")
        self.readelf.start()
        self.addCleanup(self.readelf.stop)

    def install(self, platform):
        return {"windows": windows, "linux": linux}[platform].install(self.repo, self.sdk, self.addon)

    def assert_clean(self):
        self.assertFalse(list(self.addon.rglob(".core-install-*")))

    def test_both_install_orders_and_repetition(self):
        for order in (("windows", "linux"), ("linux", "windows")):
            with self.subTest(order=order):
                self.descriptor.write_bytes(self.original)
                for platform in order:
                    self.install(platform)
                original = self.descriptor.read_bytes()
                for platform in order:
                    self.install(platform)
                    self.assertEqual(self.destinations[platform].read_bytes(),
                                     self.sources[platform].read_bytes())
                self.assertEqual(self.descriptor.read_bytes(), original)
                self.assertIn(windows.DEPENDENCY_LINE, original.decode())
                self.assertIn(linux.DEPENDENCY_LINE, original.decode())
                self.assert_clean()

    def test_dependency_merge_preserves_other_sections_and_formatting(self):
        for module in (windows, linux):
            text = '[dependencies]\n' + module.DEPENDENCY_LINE.replace(' = ', '=') + '\n[other]\nkey = 1\n'
            self.assertEqual(module.descriptor_with_dependency(text), text)
            other = '[dependencies]\ncustom = {}\n[other]\nkey = 1\n'
            updated = module.descriptor_with_dependency(other)
            self.assertIn('custom = {}\n', updated)
            self.assertTrue(updated.endswith('[other]\nkey = 1\n'))
            self.assertEqual(module.descriptor_with_dependency(updated), updated)
            with self.assertRaisesRegex(ValueError, "differs"):
                module.descriptor_with_dependency('[dependencies]\n' +
                    module.DEPENDENCY_LINE.split('=')[0] + '= {}\n')

    def test_dependency_values_preserve_quoted_whitespace(self):
        for platform, module in (("windows", windows), ("linux", linux)):
            with self.subTest(platform=platform):
                line = module.DEPENDENCY_LINE
                formatted = line.replace(' = ', '\t=\t').replace(': ', '\t:\t')
                text = '[dependencies]\n' + formatted + '\n'
                self.assertEqual(module.descriptor_with_dependency(text), text)
                for changed in (line.replace('Cubism', 'Cub ism'),
                                line.replace(': ""', ': " "')):
                    self.descriptor.write_text('[dependencies]\n' + changed + '\n')
                    before = self.descriptor.read_bytes()
                    with self.assertRaisesRegex(ValueError, "differs"):
                        self.install(platform)
                    self.assertEqual(self.descriptor.read_bytes(), before)
                    self.assertFalse(self.destinations[platform].exists())
                    self.assert_clean()

    def test_hard_linked_outputs_are_rejected(self):
        outside = self.root / "sentinel"
        outside.write_bytes(b"unrelated sentinel")
        for platform in ("windows", "linux"):
            for target in (self.destinations[platform], self.descriptor):
                with self.subTest(platform=platform, target=target.name):
                    old = target.read_bytes() if target.exists() else None
                    target.unlink(missing_ok=True)
                    try:
                        os.link(outside, target)
                    except OSError as error:
                        self.skipTest("Hard links unavailable: " + type(error).__name__)
                    try:
                        with self.assertRaisesRegex(ValueError, "hard links"):
                            self.install(platform)
                        self.assertEqual(outside.read_bytes(), b"unrelated sentinel")
                    finally:
                        target.unlink()
                        if old is not None:
                            target.write_bytes(old)
                    self.assert_clean()

    def test_symlinked_outputs_are_rejected(self):
        outside = self.root / "sentinel"
        outside.write_bytes(b"unrelated sentinel")
        for platform in ("windows", "linux"):
            for target in (self.destinations[platform], self.descriptor, self.addon / "bin"):
                with self.subTest(platform=platform, target=target.name):
                    directory = target.is_dir()
                    saved = target.with_name(target.name + ".saved")
                    if target.exists():
                        target.rename(saved)
                    try:
                        try:
                            target.symlink_to(saved if directory else outside, target_is_directory=directory)
                        except OSError as error:
                            self.skipTest("Symlinks unavailable: " + type(error).__name__)
                        with self.assertRaisesRegex(ValueError, "links|reparse"):
                            self.install(platform)
                        self.assertEqual(outside.read_bytes(), b"unrelated sentinel")
                    finally:
                        target.unlink(missing_ok=True)
                        if saved.exists():
                            saved.rename(target)
                    self.assert_clean()

    @unittest.skipUnless(os.name == "nt", "Windows junction fixture")
    def test_junction_bin_is_rejected(self):
        outside = self.root / "outside"
        outside.mkdir()
        binary = self.addon / "bin/libgd_cubism.windows.release.x86_64.dll"
        shutil.copyfile(binary, outside / binary.name)
        saved = self.addon / "saved-bin"
        binary.parent.rename(saved)
        target = self.addon / "bin"
        result = subprocess.run(["cmd", "/c", "mklink", "/J", str(target), str(outside)],
                                capture_output=True)
        if result.returncode:
            saved.rename(target)
            self.skipTest("Junction creation unavailable")
        try:
            for platform in ("windows", "linux"):
                # Both adapters must reach the same output validation.
                (outside / "libgd_cubism.linux.release.x86_64.so").write_bytes(b"fixture")
                with self.assertRaisesRegex(ValueError, "reparse"):
                    self.install(platform)
                self.assertFalse((outside / self.destinations[platform].name).exists())
        finally:
            target.rmdir()
            saved.rename(target)

    def test_copy_and_hash_failures_preserve_originals(self):
        for platform in ("windows", "linux"):
            destination = self.destinations[platform]
            for installed in (False, True):
                for failure in ("copy", "hash"):
                    with self.subTest(platform=platform, installed=installed, failure=failure):
                        destination.unlink(missing_ok=True)
                        if installed:
                            destination.write_bytes(b"previous approved installation")
                        def copy(source, output):
                            if failure == "copy":
                                output.write(b"partial")
                                raise OSError("injected copy failure")
                            output.write(b"unapproved replacement")
                        with mock.patch.object(shutil, "copyfileobj", side_effect=copy):
                            with self.assertRaises((OSError, ValueError)):
                                self.install(platform)
                        self.assertEqual(self.descriptor.read_bytes(), self.original)
                        if installed:
                            self.assertEqual(destination.read_bytes(), b"previous approved installation")
                        else:
                            self.assertFalse(destination.exists())
                        self.assert_clean()

    def test_source_changed_after_initial_hash_never_becomes_live(self):
        real_copy = shutil.copyfileobj
        for platform in ("windows", "linux"):
            source = self.sources[platform]
            original = source.read_bytes()
            def copy(input_stream, output):
                source.write_bytes(b"changed after initial verification")
                real_copy(input_stream, output)
            try:
                with mock.patch.object(shutil, "copyfileobj", side_effect=copy):
                    with self.assertRaisesRegex(ValueError, "SHA-256"):
                        self.install(platform)
                self.assertFalse(self.destinations[platform].exists())
                self.assertEqual(self.descriptor.read_bytes(), self.original)
                self.assert_clean()
            finally:
                source.write_bytes(original)

    @unittest.skipUnless(os.name == "nt", "Windows protected staging fixture")
    def test_verified_windows_stages_deny_competing_writes_and_swaps(self):
        real_replace = transaction.OutputDirectory.replace
        for platform in ("windows", "linux"):
            for attack in ("write", "swap"):
                with self.subTest(platform=platform, attack=attack):
                    self.descriptor.write_bytes(self.original)
                    attempts = []
                    def replace(directory, source, target):
                        path = directory.path / source
                        if target in (self.destinations[platform].name, self.descriptor.name):
                            with self.assertRaises(PermissionError):
                                if attack == "write":
                                    path.write_bytes(b"unverified competing write")
                                else:
                                    replacement = self.root / "replacement"
                                    replacement.write_bytes(b"unverified competing swap")
                                    os.replace(replacement, path)
                            attempts.append(target)
                        return real_replace(directory, source, target)
                    with mock.patch.object(transaction.OutputDirectory, "replace", replace):
                        self.install(platform)
                    self.assertEqual(len(attempts), 2)
                    self.assertEqual(self.destinations[platform].read_bytes(), self.sources[platform].read_bytes())
                    self.assertIn(b"[dependencies]", self.descriptor.read_bytes())
                    self.assert_clean()

    @unittest.skipUnless(os.name == "nt", "Windows sharing violation fixture")
    def test_failed_windows_rollback_keeps_recovery_backup(self):
        import ctypes
        from ctypes import wintypes
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD,
            wintypes.LPVOID, wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE]
        kernel.CreateFileW.restype = wintypes.HANDLE
        kernel.CloseHandle.argtypes = [wintypes.HANDLE]
        destination = self.destinations["windows"]
        destination.write_bytes(b"previous Core")
        real_replace = transaction.OutputDirectory.replace
        handles = []
        def replace(directory, source, target):
            real_replace(directory, source, target)
            if target == destination.name:
                handle = kernel.CreateFileW(str(destination), 0x80000000, 1, None, 3, 0, None)
                if handle == wintypes.HANDLE(-1).value:
                    raise ctypes.WinError(ctypes.get_last_error())
                handles.append(handle)
        self.descriptor.chmod(0o444)
        try:
            with mock.patch.object(transaction.OutputDirectory, "replace", replace):
                with self.assertRaisesRegex(OSError, "Installation failed:.*rollback incomplete") as caught:
                    self.install("windows")
            self.assertIsInstance(caught.exception.__cause__, OSError)
            self.assertEqual(len(caught.exception.rollback_errors), 1)
            self.assertNotIn(str(self.root), str(caught.exception))
            backups = list(self.addon.rglob(".core-install-*"))
            self.assertEqual(len(backups), 1)
            self.assertEqual(backups[0].read_bytes(), b"previous Core")
            self.assertEqual(destination.read_bytes(), self.sources["windows"].read_bytes())
            self.assertEqual(self.descriptor.read_bytes(), self.original)
        finally:
            for handle in handles:
                kernel.CloseHandle(handle)
            self.descriptor.chmod(0o644)

    def test_descriptor_prepare_and_replace_failures_roll_back(self):
        real_stage = transaction.OutputDirectory.stage
        real_replace = transaction.OutputDirectory.replace
        for platform in ("windows", "linux"):
            for installed in (False, True):
                for failure in ("prepare", "replace"):
                    with self.subTest(platform=platform, installed=installed, failure=failure):
                        destination = self.destinations[platform]
                        destination.unlink(missing_ok=True)
                        if installed:
                            destination.write_bytes(b"previous Core")
                        def stage(directory, data=None, **kwargs):
                            if failure == "prepare" and data and b"[dependencies]" in data:
                                raise OSError("injected descriptor preparation failure")
                            return real_stage(directory, data=data, **kwargs)
                        def replace(directory, source, target):
                            if failure == "replace" and Path(target).name == self.descriptor.name:
                                raise OSError("injected descriptor replacement failure")
                            return real_replace(directory, source, target)
                        with mock.patch.object(transaction.OutputDirectory, "stage", stage), \
                             mock.patch.object(transaction.OutputDirectory, "replace", replace):
                            with self.assertRaises(OSError):
                                self.install(platform)
                        self.assertEqual(self.descriptor.read_bytes(), self.original)
                        if installed:
                            self.assertEqual(destination.read_bytes(), b"previous Core")
                        else:
                            self.assertFalse(destination.exists())
                        self.assert_clean()


if __name__ == "__main__":
    unittest.main()
