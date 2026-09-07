# PR 2B build-input preparation

Status: input validation tested; full PR 2B is incomplete. The prior SDK-free
checkpoint is `581f6ed`. No matched Cubism native compile or model test has run.

The production submodule now points to Redot-Engine/redot-cpp commit
`598ec78e86b2c240a023f6de13daba70f7de8610`. Its historical directory and the
`godot_cpp` include namespace are retained. `SConstruct` requires explicit SDK
selection and checks the binding revision and tracked modifications, the Redot
API fingerprint and precision, Framework source fingerprint, and recorded Core
header/library identities. The implicit custom Framework override is removed.
No SDK is selected by directory-name ordering. Build objects and generated docs
are moved outside the dependency sources so repeated builds preserve their
fingerprints.

The Framework `src` fingerprint in `DEPENDENCIES.json` was measured over 299 files
from the clean pinned public checkout. The new validator passed against the
actual pinned Redot binding, the API produced by the verified Linux editor, and
that Framework tree. Core/package hashes remain unset and reject native builds.

Commands run from the repository root:

```text
python3 -m unittest discover -s tests/python -v
python -m SCons -n platform=linux arch=x86_64 target=template_debug
```

All 22 Python tests pass: 13 source-audit regressions and nine build-input cases.
The tests use inert temporary bytes and a real temporary Git repository to check
missing/explicit roots, filenames with spaces, changed Framework/Core inputs,
unrecorded hashes, wrong/modified binding revisions, API identity and precision.
They do not implement or simulate Cubism Core. The production SCons negative
check exits 1 with an actionable `Set CUBISM_SDK_ROOT` message before compilation.

Remaining work: acquire the authorized official SDK after license consent;
record its archive/header/platform-library identities; migrate the R5 calls in
a separate commit; replace Windows Core-folder derivation with the actual SDK
toolset/CRT mapping; add build information and native runtime smoke tests; qualify
debug/release on Windows and Linux and the licensed CI/model/export gates. The
SCons native object/link path is not yet exercised because Core is unavailable.
The user-created destination is now `dominicbytes/redot_cubism`; see the
[publication status](publication-status.md) for the remaining write-access issue.

## R5 working changes after the input checkpoint

Build-input checkpoint: `51a3bf0`. A separate working diff now updates motion loop
setters, expression playback and all three legacy shader-selection branches.
The model loader rejects R5 offscreen compositing and unsupported blend pairs
before creating its renderer. The owner already clears the model on a failed
`model_load`, as verified in `GDCubismUserModel::load_model`.
See the [SDK matrix](../compatibility/cubism_sdk_matrix.md).

The method names, blend-mode object accessors and Core enum symbols were checked
against the pinned Framework headers and its official OpenGL shader-selection
source. This diff has not been compiled or run: Core is still unavailable.
Do not promote it to a native-build PASS or start later feature stages yet.
