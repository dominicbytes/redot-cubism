# PR 0/1: host admission and repository bootstrap

Implementation is in progress. This checkpoint preserves upstream history and
adds provenance, dependency identities, restricted-file checks, public CI and
test tooling. Cubism native rendering and playback are not yet tested.

## Validation

- Linux editor: `26.2.stable.official.4f5b14aba`.
- Editor SHA-256: `11d299e0f01a63574e612c64718ca3037a65540139dec7b93a87650ee9aab2f3`.
- Generated API SHA-256: `177e7796166929b2193c9cce2fd32f59601a0147d0d1e7fe904b94e8f69f6577`.
- Generated interface SHA-256: `4cd695e86b92e2bf4e60bbe19ce137faf41205da1cf94f29e069afec0f7bf320`.
- Generated interface is byte-identical to the pinned redot-cpp interface.
- API reports Redot 26.2 and Godot compatibility 4.5.2, single precision.
- 13 Python scanner tests pass, including nested archive, signature, traversal,
  size limit, invalid archive and exact native-library hash cases.
- 1,075 historical upstream file blobs pass the restricted-file audit.
- 190 initially staged files pass the tracked-content audit. The final source
  suite is rerun after subsequent source changes.

Commands (working directory: repository root):

```text
REDOT_BIN=<verified editor> python tools/verify_dependencies.py --output <private evidence directory>
python tools/run_tests.py --suite public --output <private evidence directory>
python tools/check_restricted_files.py --history HEAD
git diff --check
```

Dependency commits are in `DEPENDENCIES.json`. The toolchain observed is Python
3.14.7, SCons 4.11.1, GCC 16.2.1 and GNU ld 2.47. The actual SDK archive, Core
version/library hashes, private model and Windows runner remain unavailable.
Public CI has been defined but has not run remotely. Missing licensed suites
return a nonzero configuration error, rather than reporting a skip as a pass.

## Host storage

The shared 9p mount rejects Git config-lock chmod operations. Source remains in
the requested folder, with Git metadata in a task-local directory. A local Git
bundle checkpoint is kept under ignored `.local-build` so history can be restored
if temporary metadata disappears. A normal clone on a native filesystem does not
require this workaround. No desktop/system settings were changed.

## Publication

The user authorizes a source fork at dominicbytes/redot-cubism. Creation awaits an
authenticated fork-capable route. No Core/SDK/model data has been obtained, staged
or published. Binary release remains unapproved and unqualified.
