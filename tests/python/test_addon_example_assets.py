# SPDX-License-Identifier: MIT
import os
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
ADDON = Path(os.environ.get('CUBISM_ADDON_TEST_ROOT', ROOT / 'demo/addons/gd_cubism'))
INSTALL_PREFIX = 'res://addons/gd_cubism/'


class AddonExampleAssetsTest(unittest.TestCase):
    def test_bundled_scenes_reference_only_bundled_files(self):
        scenes = sorted(ADDON.rglob('*.tscn'))
        self.assertTrue(scenes)
        references = 0
        for scene in scenes:
            text = scene.read_text(encoding='utf-8')
            for path in re.findall(r'^\[ext_resource\b[^\n]*\bpath="(res://[^"]+)"', text, re.MULTILINE):
                references += 1
                with self.subTest(scene=scene.relative_to(ADDON), path=path):
                    self.assertTrue(path.startswith(INSTALL_PREFIX), 'resource outside installed addon')
                    self.assertTrue((ADDON / path[len(INSTALL_PREFIX):]).is_file(), 'missing bundled resource')
        self.assertGreater(references, 0)


if __name__ == '__main__':
    unittest.main()
