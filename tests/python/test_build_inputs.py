# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Redot Cubism contributors
"""Input rejection tests use inert temporary bytes, never a Core implementation."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from build_inputs import binding_root, core_library, sdk_roots, sha256, source_hash


class BuildInputsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.sdk = self.root / "SDK with spaces"
        self.core = self.sdk / "Core"
        self.framework = self.sdk / "Framework"
        for relative in ("Core/include/Live2DCubismCore.h", "Framework/src/CubismFramework.cpp", "Framework/src/Model/CubismModel.cpp"):
            path = self.sdk / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("inert build-input test fixture\n")
        self.pins = {
            "cubism_framework": {"source_sha256": source_hash(self.framework / "src")},
            "cubism_sdk": {"archive_sha256": "recorded-test-identity", "core_header_sha256": sha256(self.core / "include/Live2DCubismCore.h"), "core_library_sha256": {}},
        }
        self.options = {"CUBISM_SDK_ROOT": str(self.sdk)}

    def test_explicit_root_with_spaces(self):
        self.assertEqual(sdk_roots(self.options, self.pins), (self.core, self.framework))

    def test_no_discovery_when_sdk_is_missing(self):
        for name in ("CubismSdkForNative-5-r.1", "CubismSdkForNative-5-r.5"):
            (self.root / name).mkdir()
        with self.assertRaisesRegex(ValueError, "Set CUBISM_SDK_ROOT"):
            sdk_roots({}, self.pins)

    def test_first_missing_required_file(self):
        (self.core / "include/Live2DCubismCore.h").unlink()
        with self.assertRaisesRegex(ValueError, "Core/include/Live2DCubismCore.h"):
            sdk_roots(self.options, self.pins)

    def test_explicit_framework_overrides_sdk_default(self):
        separate = self.root / "pinned-framework"
        self.framework.rename(separate)
        result = sdk_roots(dict(self.options, CUBISM_FRAMEWORK_ROOT=str(separate)), self.pins)
        self.assertEqual(result[1], separate)

    def test_changed_framework_rejected(self):
        (self.framework / "src/CubismFramework.cpp").write_text("changed source")
        with self.assertRaisesRegex(ValueError, "Framework source does not match"):
            sdk_roots(self.options, self.pins)

    def test_unrecorded_sdk_identity_rejected(self):
        for field in ("archive_sha256", "core_header_sha256"):
            with self.subTest(field=field):
                pins = copy.deepcopy(self.pins)
                pins["cubism_sdk"][field] = None
                with self.assertRaisesRegex(ValueError, "Record.*SHA-256"):
                    sdk_roots(self.options, pins)

    def test_changed_core_header_rejected(self):
        (self.core / "include/Live2DCubismCore.h").write_text("wrong version")
        with self.assertRaisesRegex(ValueError, "Core header SHA-256 does not match"):
            sdk_roots(self.options, self.pins)

    def test_unrecorded_and_changed_library_rejected(self):
        lib = self.core / "lib/test.a"
        lib.parent.mkdir()
        lib.write_text("inert library identity test")
        with self.assertRaisesRegex(ValueError, "Record.*Core library"):
            core_library(lib, self.core, self.pins)
        self.pins["cubism_sdk"]["core_library_sha256"]["lib/test.a"] = sha256(lib)
        core_library(lib, self.core, self.pins)
        lib.write_text("changed")
        with self.assertRaisesRegex(ValueError, "Core library SHA-256 does not match"):
            core_library(lib, self.core, self.pins)

    def test_binding_revision_modification_and_api_identity(self):
        cpp = self.root / "bindings"
        cpp.mkdir()
        (cpp / "SConstruct").write_text("inert binding identity fixture")
        def git(*args):
            return subprocess.check_output(["git", "-C", str(cpp), *args], stderr=subprocess.STDOUT, text=True).strip()
        git("init", "-q")
        git("add", "SConstruct")
        git("-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-qm", "fixture")
        self.pins["redot_cpp"] = {"commit": git("rev-parse", "HEAD")}
        api = self.root / "api.json"
        api.write_text(json.dumps({"redot_header": {"version_major": 26, "version_minor": 2, "precision": "single"}}))
        self.pins["redot"] = {"api_sha256": sha256(api)}
        options = {"REDOT_CPP_ROOT": str(cpp)}
        self.assertEqual(binding_root(self.root, options, self.pins, str(api), "single"), cpp)
        with self.assertRaisesRegex(ValueError, "precision=single"):
            binding_root(self.root, options, self.pins, str(api), "double")
        with self.assertRaisesRegex(ValueError, "Set custom_api_file"):
            binding_root(self.root, options, self.pins, None, "single")
        api.write_text("changed API")
        with self.assertRaisesRegex(ValueError, "Redot API SHA-256 does not match"):
            binding_root(self.root, options, self.pins, str(api), "single")
        (cpp / "SConstruct").write_text("modified binding")
        with self.assertRaisesRegex(ValueError, "modified tracked files"):
            binding_root(self.root, options, self.pins, str(api), "single")
        self.pins["redot_cpp"]["commit"] = "0" * 40
        with self.assertRaisesRegex(ValueError, "pinned redot-cpp commit"):
            binding_root(self.root, options, self.pins, str(api), "single")


if __name__ == "__main__":
    unittest.main()
