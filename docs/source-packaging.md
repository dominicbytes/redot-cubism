# Source-only packages

`tools/package_addon.py` prepares a source archive for review. It does not build
or redistribute the Cubism SDK, Core, models or native libraries, and its result
does not qualify a release. Finish the required platform, private-CI, performance
and publication checks on the exact sanitized candidate before publishing it.

Use a full 40-character commit SHA from the sanitized source history. The local
implementation branch contains the private workbook in its history and is
intentionally rejected, even if the workbook is deleted from its tip. See
[publication status](gamedev/publication-status.md) for the existing public anchor.

```sh
python tools/check_public_history.py --ref FULL_SANITIZED_COMMIT_SHA
python tools/package_addon.py --source-only --ref FULL_SANITIZED_COMMIT_SHA \
  --output /private/review/redot-cubism-source.tar.gz
python tools/check_release_archive.py /private/review/redot-cubism-source.tar.gz \
  --source-ref FULL_SANITIZED_COMMIT_SHA
```

The packager reads committed Git objects, not working-tree files. It checks every
reachable tree, including deleted files and identical blobs renamed to private
paths. Private workbooks, local build/input folders, Git bundles, restricted SDK
content, models and native binaries are rejected, including nested archives.
The exact upstream SDK-directory `.gitignore` placeholder is allowed; it contains
only ignore rules and no SDK content.
Submodule worktrees are not bundled; their pinned revisions remain in Git and
[DEPENDENCIES.json](../DEPENDENCIES.json).

The archive must contain the exact tracked source payload, required installation
and licensing files, the expected commit prefix, and matching executable flags.
Missing, additional, duplicated or changed files are rejected. Outputs are never
overwritten. Repeating packaging for the same commit produces the same archive
bytes. A neighboring `.manifest.json` records the source revision, dependency-file
hash and contents, addon version, submodule revisions, archive hash, per-file hashes
and history audit counts. Keep that manifest
with the archive. Independently verifying an archive reconstructs the expected
payload from Git rather than trusting the neighboring manifest.

The public source workflow runs the stricter history check as well as the
existing restricted-content scanner. Passing either check alone is not a license
to publish binaries or proof that the plugin's release tests passed.
