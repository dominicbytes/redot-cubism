# SPDX-License-Identifier: MIT
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


class DocumentationBuildTest(unittest.TestCase):
    def test_generation_precedes_marker_and_preserves_guides(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo = Path(__file__).resolve().parents[2]
            script = (repo / 'SConspage').read_text()
            # Exercise the real SCons graph without fetching remote documentation.
            script = 'import subprocess\nimport sys\n' + script.replace(
                'action=["npx antora --fetch $SOURCE"]',
                'action=[lambda target, source, env: '
                'subprocess.call([sys.executable, "generate.py"])]')
            (root / 'SConspage').write_text(script)
            (root / 'generate.py').write_text(
                'from pathlib import Path\n'
                'output = Path(".local-build/upstream-docs")\n'
                'assert not (output / ".nojekyll").exists()\n'
                'assert Path("docs-src/modules/ROOT/pages/en/license.adoc").is_file()\n'
                'output.mkdir(parents=True, exist_ok=True)\n'
                '(output / "index.html").write_text("generated")\n')
            (root / 'docs').mkdir()
            guide = root / 'docs/guide.md'
            guide.write_bytes(b'maintained guide\n')
            for language in ('en', 'ja'):
                (root / 'docs-src/modules/ROOT/pages' / language).mkdir(parents=True)
            (root / 'LICENSE.adoc').write_text('license')
            (root / 'LICENSE.en.adoc').write_text('license')
            (root / 'docs-site').mkdir()
            shutil.copyfile(repo / 'docs-site/antora-playbook.yml',
                            root / 'docs-site/antora-playbook.yml')
            result = subprocess.run([sys.executable, '-m', 'SCons', '-Q', '-f', 'SConspage'],
                                    cwd=root, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(guide.read_bytes(), b'maintained guide\n')
            self.assertTrue((root / '.local-build/upstream-docs/index.html').is_file())
            self.assertTrue((root / '.local-build/upstream-docs/.nojekyll').is_file())


if __name__ == '__main__':
    unittest.main()
