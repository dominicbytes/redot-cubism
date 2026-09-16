# SPDX-License-Identifier: MIT
import copy
import io
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools'))
from check_public_history import validate_history
from package_addon import REQUIRED, package, verify_archive


class SourcePackageTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / 'repo'
        self.repo.mkdir()
        self.git('init', '-q')
        self.git('config', 'user.name', 'Test')
        self.git('config', 'user.email', 'test@example.invalid')
        self.git('config', 'core.autocrlf', 'false')
        for name in REQUIRED:
            self.write(name, b'{"addon_version":"0.1.0-test"}' if name.endswith('.json') else b'Source fixture\n')
        self.sha = self.commit()

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.repo), *args], stderr=subprocess.PIPE).decode().strip()

    def write(self, name, data):
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    def commit(self):
        self.git('add', '.')
        self.git('commit', '-qm', 'fixture')
        return self.git('rev-parse', 'HEAD')

    def test_deterministic_source_and_manifest(self):
        a, b = self.root / 'a.tar.gz', self.root / 'b.tar.gz'
        first = package(self.repo, self.sha, a)
        second = package(self.repo, self.sha, b)
        self.assertEqual(a.read_bytes(), b.read_bytes())
        self.assertEqual(first, second)
        self.assertFalse(first['release_qualified'])
        self.assertEqual(first['addon_version'], '0.1.0-test')
        self.assertEqual(set(first['files']), REQUIRED)
        self.assertEqual(json.loads(Path(str(a) + '.manifest.json').read_text()), first)

    def test_dirty_files_are_not_packaged(self):
        self.write('README.md', b'uncommitted edit')
        self.write('untracked.txt', b'uncommitted addition')
        result = package(self.repo, self.sha, self.root / 'source.tar.gz')
        self.assertEqual(set(result['files']), REQUIRED)
        with tarfile.open(self.root / 'source.tar.gz', 'r:gz') as archive:
            readme = archive.extractfile('redot-cubism-' + self.sha[:12] + '/README.md').read()
        self.assertEqual(readme, b'Source fixture\n')

    def test_submodule_is_a_git_pin_without_its_worktree(self):
        self.git('update-index', '--add', '--cacheinfo', '160000,' + self.sha + ',thirdparty/bindings')
        self.git('commit', '-qm', 'pin bindings')
        sha = self.git('rev-parse', 'HEAD')
        self.write('thirdparty/bindings/private.txt', b'not part of the superproject')
        archive = self.root / 'source.tar.gz'
        result = package(self.repo, sha, archive)
        self.assertEqual(set(result['files']), REQUIRED)
        self.assertEqual(result['submodules'], {'thirdparty/bindings': self.sha})
        self.assertEqual(verify_archive(self.repo, sha, archive)['revision'], sha)

    def test_exact_sdk_placeholder_is_allowed_in_source_archive(self):
        name = 'thirdparty/CubismSdkForNative/.gitignore'
        self.write(name, b'*\n!.gitignore\n')
        sha = self.commit()
        result = package(self.repo, sha, self.root / 'source.tar.gz')
        self.assertIn(name, result['files'])

    def test_invalid_dependency_manifest_rejected_without_output(self):
        self.write('DEPENDENCIES.json', b'{}')
        sha = self.commit()
        archive = self.root / 'rejected.tar.gz'
        with self.assertRaisesRegex(ValueError, 'addon version'):
            package(self.repo, sha, archive)
        self.assertFalse(archive.exists())
        self.assertFalse(Path(str(archive) + '.manifest.json').exists())

    def test_source_verification_cli(self):
        archive = self.root / 'source.tar.gz'
        package(self.repo, self.sha, archive)
        command = [sys.executable, str(Path(__file__).resolve().parents[2] / 'tools/check_release_archive.py'),
                   str(archive), '--repo', str(self.repo), '--source-ref', self.sha]
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertEqual(json.loads(result.stdout)['revision'], self.sha)
        command[-1] = 'HEAD'
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('full commit SHA', result.stderr)
        self.git('tag', '-a', 'source-tag', '-m', 'source tag')
        command[-1] = self.git('rev-parse', 'source-tag^{tag}')
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('exact commit SHA', result.stdout)

    def test_rejects_workbook_deleted_later(self):
        self.write('docs/gamedev/source-of-truth.xlsx', b'private')
        self.commit()
        (self.repo / 'docs/gamedev/source-of-truth.xlsx').unlink()
        sha = self.commit()
        with self.assertRaisesRegex(ValueError, 'private publication content'):
            package(self.repo, sha, self.root / 'rejected.tar.gz')
        self.assertFalse((self.root / 'rejected.tar.gz').exists())

    def test_checks_same_blob_under_private_path_in_older_tree(self):
        self.write('.local-build/private.txt', b'Source fixture\n')
        self.commit()
        self.git('mv', '.local-build/private.txt', 'public.txt')
        sha = self.commit()
        with self.assertRaisesRegex(ValueError, 'private publication content'):
            validate_history(self.repo, sha)

    def test_nested_private_archive(self):
        inner = io.BytesIO()
        with zipfile.ZipFile(inner, 'w') as archive:
            archive.writestr('.local-build/results.txt', 'private')
        outer = io.BytesIO()
        with zipfile.ZipFile(outer, 'w') as archive:
            archive.writestr('inner.zip', inner.getvalue())
        self.write('bundle.zip', outer.getvalue())
        sha = self.commit()
        with self.assertRaisesRegex(ValueError, 'private publication content'):
            package(self.repo, sha, self.root / 'rejected.tar.gz')

    def test_rejects_native_blob_and_symlink(self):
        self.write('hidden.dat', b'\x7fELF synthetic')
        sha = self.commit()
        with self.assertRaisesRegex(ValueError, 'unapproved native binary'):
            validate_history(self.repo, sha)
        self.git('reset', '--hard', self.sha)
        (self.repo / 'link').symlink_to('README.md')
        sha = self.commit()
        with self.assertRaisesRegex(ValueError, 'unsupported source entry'):
            validate_history(self.repo, sha)

    def test_missing_required_and_mutable_ref(self):
        with self.assertRaisesRegex(ValueError, 'immutable'):
            package(self.repo, 'HEAD', self.root / 'bad.tar.gz')
        self.git('tag', '-a', 'fixture-tag', '-m', 'fixture tag')
        tag_object = self.git('rev-parse', 'fixture-tag^{tag}')
        with self.assertRaisesRegex(ValueError, 'exact full'):
            package(self.repo, tag_object, self.root / 'tag.tar.gz')
        (self.repo / 'NOTICE.md').unlink()
        sha = self.commit()
        with self.assertRaisesRegex(ValueError, 'Missing required'):
            package(self.repo, sha, self.root / 'bad.tar.gz')

    def test_preserves_existing_output(self):
        archive = self.root / 'existing.tar.gz'
        archive.write_bytes(b'keep')
        with self.assertRaisesRegex(ValueError, 'already exists'):
            package(self.repo, self.sha, archive)
        self.assertEqual(archive.read_bytes(), b'keep')

    def test_verifier_rejects_missing_extra_changed_and_wrong_prefix(self):
        original = self.root / 'original.tar.gz'
        package(self.repo, self.sha, original)
        with tarfile.open(original, 'r:gz') as archive:
            members = [(m, archive.extractfile(m).read() if m.isfile() else None) for m in archive]
        for alteration in ['missing', 'extra', 'changed', 'prefix', 'executable', 'duplicate']:
            candidate = self.root / (alteration + '.tar.gz')
            with tarfile.open(candidate, 'w:gz') as archive:
                for member, data in members:
                    member = copy.copy(member)
                    if member.name.endswith('/README.md'):
                        if alteration == 'missing':
                            continue
                        if alteration == 'changed':
                            data = b'X' * member.size
                        if alteration == 'executable':
                            member.mode ^= 0o111
                        if alteration == 'duplicate':
                            archive.addfile(member, io.BytesIO(data))
                    if alteration == 'prefix':
                        member.name = 'wrong/' + member.name
                    archive.addfile(member, io.BytesIO(data) if data is not None else None)
                if alteration == 'extra':
                    extra = tarfile.TarInfo('redot-cubism-' + self.sha[:12] + '/extra.txt')
                    extra.size = 1
                    archive.addfile(extra, io.BytesIO(b'X'))
            with self.subTest(alteration=alteration), self.assertRaises(ValueError):
                verify_archive(self.repo, self.sha, candidate)

    def test_wrong_revision_rejected(self):
        archive = self.root / 'original.tar.gz'
        package(self.repo, self.sha, archive)
        self.write('README.md', b'changed')
        other = self.commit()
        with self.assertRaises(ValueError):
            verify_archive(self.repo, other, archive)


if __name__ == '__main__':
    unittest.main()
