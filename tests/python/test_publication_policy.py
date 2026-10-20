# SPDX-License-Identifier: MIT
import hashlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from check_public_history import validate_history, validate_metadata
from check_restricted_files import inspect_bytes
from package_addon import package
from publication_policy import inspect_attribution, inspect_commit, inspect_local_paths
import test_source_package


def local_paths():
    # Synthetic values assembled so this source itself contains no private paths.
    return ["C:" + "/" + "Users" + "/example/project/file.pdb",
            "Q:" + "\\build\\example\\file.cpp",
            "/home" + "/example/project/file",
            "Users" + "\\example\\project\\file",
            "\\\\" + "example-host\\share\\file",
            "/mnt" + "/" + "q/example/project/file",
            "App" + "Data/Local/example/file"]


class PublicationBytesTest(unittest.TestCase):
    def test_ascii_and_both_utf16_alignments(self):
        for path in local_paths():
            for encoding in ("ascii", "utf-16le", "utf-16be"):
                for prefix in (b"", b"!", b"z"):
                    self.assertTrue(inspect_local_paths(prefix + path.encode(encoding), native=True))
            for data in (path.encode(), path.encode("utf-16le"), b"!" + path.encode("utf-16le")):
                with self.subTest(path_kind=path[:1], encoding_size=len(data)):
                    self.assertTrue(inspect_local_paths(data))
                    self.assertTrue(inspect_bytes("docs/note.txt", data))

    def test_unicode_and_punctuation_drive_paths_in_all_payloads(self):
        paths = ("Q:" + "/" + "example/caf\u00e9/file.pdb",
                 "Q:" + "\\" + "@example\\file.cpp",
                 "Q:" + "/" + "\u00e9xample/file.pdb")
        for path in paths:
            for encoding in ("utf-8", "utf-16le", "utf-16be"):
                for prefix in (b"", b"!"):
                    with self.subTest(encoding=encoding, prefix=prefix, path_kind=path[3:4]):
                        data = prefix + path.encode(encoding)
                        self.assertTrue(inspect_bytes("docs/note.txt", data))
                        native = b"MZfixture" + data
                        name = "addon.dll"
                        approved = {name: hashlib.sha256(native).hexdigest()}
                        self.assertTrue(any("identifying local path" in problem
                                            for problem in inspect_bytes(name, native, approved)))
                        inner = io.BytesIO()
                        with zipfile.ZipFile(inner, "w", zipfile.ZIP_DEFLATED) as archive:
                            archive.writestr("note.txt", data)
                        outer = io.BytesIO()
                        with zipfile.ZipFile(outer, "w", zipfile.ZIP_DEFLATED) as archive:
                            archive.writestr("inner.zip", inner.getvalue())
                        self.assertTrue(inspect_bytes("bundle.zip", outer.getvalue()))

    def test_quoted_formatting_escapes_are_not_drive_paths(self):
        for quote in ("'", '"'):
            formatting = quote + "\\t" + ":" + "\\t" + quote
            for encoding in ("utf-8", "utf-16le", "utf-16be"):
                self.assertFalse(inspect_local_paths(formatting.encode(encoding)))
                self.assertTrue(inspect_local_paths((quote + "t:" + "\\t" + quote).encode(encoding)))
        self.assertTrue(inspect_local_paths(("T:" + "/" + "t").encode()))

    def test_reviewed_examples_urls_and_relative_paths(self):
        for text in ("C:/file", "C:/path/to/sdk/Core", "C:\\path\\to\\sdk\\Core",
                     "https://example.invalid/project/docs", "res://addons/gd_cubism/bin",
                     "docs/guide.md", "$SDK/Core", "./relative/file",
                     "/usr/include/stdio.h", "Users must install Core", "version 1.0"):
            for encoding in ("ascii", "utf-16le"):
                self.assertFalse(inspect_local_paths(text.encode(encoding)), text)
        self.assertTrue(inspect_local_paths(("file:///" + local_paths()[0]).encode()))
        self.assertTrue(inspect_local_paths(("C:" + "/file-private").encode()))
        self.assertTrue(inspect_local_paths(("C:" + "/path/to-private/sdk").encode()))

    def test_approved_native_bytes_still_checked(self):
        for path in local_paths():
            for encoding in ("ascii", "utf-16le"):
                data = b"MZfixture" + path.encode(encoding)
                name = "bin/addon.dll"
                problems = inspect_bytes(name, data, {name: hashlib.sha256(data).hexdigest()})
                self.assertTrue(any("identifying local path" in p for p in problems))
                self.assertFalse(any("unapproved" in p for p in problems))

    def test_nested_archive_payloads_and_member_names(self):
        for path in local_paths():
            for encoding in ("ascii", "utf-16le"):
                inner = io.BytesIO()
                with zipfile.ZipFile(inner, "w") as archive:
                    archive.writestr("note.txt", path.encode(encoding))
                outer = io.BytesIO()
                with zipfile.ZipFile(outer, "w") as archive:
                    archive.writestr("inner.zip", inner.getvalue())
                self.assertTrue(inspect_bytes("bundle.zip", outer.getvalue()))
            stream = io.BytesIO()
            with zipfile.ZipFile(stream, "w") as archive:
                archive.writestr(path, b"innocent")
            self.assertTrue(inspect_bytes("bundle.zip", stream.getvalue()))

    def test_archive_cli_cannot_approve_identifying_binary(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            name = "addon.dll"
            data = b"MZ\0" + local_paths()[0].encode("utf-16le")
            archive_path = root / "bundle.zip"
            with zipfile.ZipFile(archive_path, "w") as archive:
                archive.writestr(name, data)
            approved = root / "approved.json"
            approved.write_text(json.dumps({"bundle.zip!" + name: hashlib.sha256(data).hexdigest()}))
            result = subprocess.run([sys.executable,
                str(Path(__file__).resolve().parents[2] / "tools/check_release_archive.py"),
                str(archive_path), "--approved-native", str(approved)], text=True, capture_output=True)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn("identifying local path", result.stdout)

    def test_attribution_in_published_bytes_and_approved_native(self):
        identity = "Co" + "dex <tool@example.invalid>"
        credits = ("Generated" + " with " + identity, "Generated" + " with a build tool",
                   "Co-authored" + "-by: " + identity,
                   "Co-authored" + "-by: Person <person@example.invalid>",
                   "Author: " + identity, identity,
                   "Author: " + identity.split(" <")[0],
                   "Committer: " + identity.split(" <")[0],
                   "author " + identity + " 1700000000 +0000",
                   "committer " + identity + " 1700000000 -0430")
        for credit in credits:
            for encoding in ("ascii", "utf-16le", "utf-16be"):
                data = credit.encode(encoding)
                self.assertTrue(inspect_attribution(data))
                self.assertTrue(inspect_bytes("docs/note.md", data))
                name = "addon.dll"
                native_data = b"MZ\0" + data + b"\0\0"
                self.assertTrue(inspect_bytes(name, native_data, {name: hashlib.sha256(native_data).hexdigest()}))
                self.assertTrue(inspect_commit("Human", "Human", credit))
                stream = io.BytesIO()
                with zipfile.ZipFile(stream, "w", zipfile.ZIP_DEFLATED) as archive:
                    archive.writestr("note.md", data)
                self.assertTrue(inspect_bytes("bundle.zip", stream.getvalue()))
        for text in ("Author: Person <person@example.invalid>", "generated output", "Document tooling",
                     "Author: Person", "Committer: Person",
                     "author Person <person@example.invalid> 1700000000 +0000",
                     "The author checker detects Co" + "dex identities.",
                     "Document Co" + "dex author records"):
            self.assertFalse(inspect_attribution(text.encode()))

    def test_identity_and_trailer_scope(self):
        for identity in ("Co" + "dex <tool@example.invalid>", "Clau" + "de <tool@example.invalid>",
                         "Human <bot@open" + "ai.com>", "G" + "PT <tool@example.invalid>",
                         "S" + "ol <tool@example.invalid>"):
            self.assertTrue(inspect_commit(identity, "Human <human@example.invalid>", "Fix issue"))
            self.assertTrue(inspect_commit("Human <human@example.invalid>", identity, "Fix issue"))
        trailer = "Co-authored" + "-by: Person <person@example.invalid>"
        self.assertTrue(inspect_commit("Human", "Human", "Fix issue\n\n" + trailer))
        self.assertFalse(inspect_commit("Human", "Human", "Document identity checks"))


class PublicationMetadataTest(unittest.TestCase):
    def setUp(self):
        # Reuse the source packager's complete neutral Git fixture.
        self.fixture = test_source_package.SourcePackageTest()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.repo = self.fixture.repo
        self.base = self.fixture.sha

    def test_base_excludes_known_history_but_not_new_metadata(self):
        identity = "Co" + "dex <tool@example.invalid>"
        self.fixture.git("commit", "--allow-empty", "--author", identity, "-qm", "fixture")
        legacy = self.fixture.git("rev-parse", "HEAD")
        with self.assertRaisesRegex(ValueError, "identity"):
            validate_metadata(self.repo, legacy)
        self.assertEqual(validate_metadata(self.repo, legacy, legacy), 0)
        self.fixture.git("commit", "--allow-empty", "-qm", "human fixture")
        current = self.fixture.git("rev-parse", "HEAD")
        self.assertEqual(validate_metadata(self.repo, current, legacy), 1)
        self.fixture.write("tools/publication-policy.json", json.dumps({"metadata_base": legacy}).encode())
        current = self.fixture.commit()
        self.assertEqual(validate_history(self.repo, current)["metadata_commits"], 2)
        # Uncommitted policy edits must not affect an immutable source audit.
        self.fixture.write("tools/publication-policy.json", b'{"metadata_base":"missing-ref"}')
        self.assertEqual(validate_history(self.repo, current)["metadata_commits"], 2)
        self.fixture.git("commit", "--allow-empty", "--author", identity, "-qm", "new fixture")
        bad = self.fixture.git("rev-parse", "HEAD")
        with self.assertRaisesRegex(ValueError, "identity"):
            package(self.repo, bad, self.fixture.root / "rejected.tar.gz")
        self.assertFalse((self.fixture.root / "rejected.tar.gz").exists())

    def test_new_trailer_and_local_metadata_paths_are_rejected(self):
        for message in ("fixture\n\nCo-authored" + "-by: Person <person@example.invalid>",
                        "fixture " + local_paths()[0]):
            self.fixture.git("reset", "--hard", self.base)
            self.fixture.git("commit", "--allow-empty", "-qm", message)
            with self.assertRaises(ValueError):
                validate_history(self.repo, "HEAD", self.base)

    def test_base_must_exist_and_be_ancestor(self):
        with self.assertRaisesRegex(ValueError, "baseline is unavailable"):
            validate_metadata(self.repo, self.base, "missing-ref")
        self.fixture.git("commit", "--allow-empty", "-qm", "future fixture")
        future = self.fixture.git("rev-parse", "HEAD")
        with self.assertRaisesRegex(ValueError, "ancestor"):
            validate_metadata(self.repo, self.base, future)

    def test_removed_baseline_after_history_rewrite_has_actionable_cli_error(self):
        old_branch = self.fixture.git("symbolic-ref", "--short", "HEAD")
        self.fixture.git("checkout", "--orphan", "rewritten-history")
        self.fixture.write("tools/publication-policy.json", json.dumps({"metadata_base": self.base}).encode())
        current = self.fixture.commit()
        self.fixture.git("branch", "-D", old_branch)
        self.fixture.git("reflog", "expire", "--expire=now", "--all")
        self.fixture.git("gc", "--prune=now")
        missing = subprocess.run(["git", "-C", str(self.repo), "cat-file", "-e", self.base],
                                 capture_output=True)
        self.assertNotEqual(missing.returncode, 0)
        command = [sys.executable,
                   str(Path(__file__).resolve().parents[2] / "tools/check_public_history.py"),
                   "--repo", str(self.repo), "--ref", current]
        for override in ([], ["--metadata-base", "missing-ref"]):
            result = subprocess.run(command + override, text=True, capture_output=True)
            self.assertEqual(result.returncode, 1)
            message = json.loads(result.stdout)["error"]
            for guidance in ("baseline is unavailable", "Fetch complete history", "history was rewritten",
                             "reviewed replacement ancestor", "--metadata-base '' audits all metadata"):
                self.assertIn(guidance, message)
            self.assertNotIn(str(self.repo.resolve()), result.stdout + result.stderr)
            self.assertEqual(result.stderr, "")
        rejected = self.fixture.root / "rejected.tar.gz"
        with self.assertRaisesRegex(ValueError, "baseline is unavailable"):
            package(self.repo, current, rejected)
        self.assertFalse(rejected.exists())
        for override, count in (("", 1), (current, 0)):
            result = subprocess.run(command + ["--metadata-base", override], text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(json.loads(result.stdout)["metadata_commits"], count)

    def test_paths_in_deleted_file_are_rejected(self):
        self.fixture.write("docs/note.md", local_paths()[0].encode("utf-16le"))
        self.fixture.commit()
        (self.repo / "docs/note.md").unlink()
        sha = self.fixture.commit()
        with self.assertRaisesRegex(ValueError, "identifying local path"):
            validate_history(self.repo, sha, self.base)


if __name__ == "__main__":
    unittest.main()
