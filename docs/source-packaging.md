# Source-only packages

`tools/package_addon.py` prepares a source archive for review. It does not build
or redistribute the Cubism SDK, Core, models or native libraries, and its result
does not qualify a release. Finish the required platform, private-CI, performance
and publication checks on the exact sanitized candidate before publishing it.

Use a full 40-character commit SHA from the public source history. The history
check rejects restricted content even if it has been deleted from the selected
tip. See [current status](current-status.md) for public previews and qualification
limits.

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

Publication checks inspect file and archive-member bytes for local drive, home,
user, mounted-drive, AppData and network-share paths, including ASCII and both
UTF-16 byte orders and alignments. Exact native-file hash approvals do not bypass
these checks. Reviewed generic documentation examples and engine URLs are allowed;
new private paths must be replaced with relative paths or placeholders. Structured
contributor identities, contributor trailers and automated generation credits are
also rejected in published payloads.

Commit authors, committers and messages are checked for every commit reachable
from the audited revision. `metadata_base` in `tools/publication-policy.json` is
empty, which selects this complete audit. File contents are also checked
throughout the full reachable history. All history and packaging commands accept
`--metadata-base FULL_ANCESTOR_SHA` to audit only metadata after a reviewed
ancestor, or `--metadata-base=` to audit all commit metadata explicitly.
The default policy is read from the audited commit, so uncommitted policy edits
do not change the result. A baseline must resolve to an ancestor of that commit.
