# SPDX-License-Identifier: MIT
"""Runtime families must not weaken the binding ABI or export-template checks."""
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from build_inputs import supported_engine
from binding_patch import patch_variant, NEW


class EngineVersionsTest(unittest.TestCase):
    pins = json.loads((Path(__file__).resolve().parents[2] / "DEPENDENCIES.json").read_text())

    def test_supported_runtime_families(self):
        for version in ("26.2.stable.official.4f5b14aba", "26.3.stable.official.85e520394",
                        "26.3.stable.custom_build.85e520394", "26.2.stable.mono.official.4f5b14aba"):
            with self.subTest(version=version):
                self.assertTrue(supported_engine(version, self.pins))

    def test_unverified_runtime_families_rejected(self):
        for version in ("4.3.stable.official.abc", "26.1.stable.official.abc", "26.4.stable.official.abc",
                        "26.3.dev.custom_build.abc", "26.3", "26.3.stable.official.abc extra"):
            with self.subTest(version=version):
                self.assertFalse(supported_engine(version, self.pins))

    def test_variant_cleanup_delegates_unknown_types_to_engine(self):
        source = "if (unlikely(needs_deinit[get_type()])) { destroy(); }"
        self.assertIn(NEW, patch_variant(source))
        with self.assertRaisesRegex(ValueError, "expected cleanup lookup"):
            patch_variant("changed binding source")


if __name__ == "__main__":
    unittest.main()
