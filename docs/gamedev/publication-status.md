# Source publication status

## Cubism for Redot source

The combined Windows and Linux port is on `main` in
[dominicbytes/redot-cubism](https://github.com/dominicbytes/redot-cubism).
The integration PRs target this Redot repository, not the original Godot
project. See the [quick start](../quick-start.md) and
[current status](../current-status.md) for installation and known limits.
The source repository does not include SDK/Core binaries or model assets.

A **PREVIEW** binary release for Redot 26.2 single precision and GL Compatibility
is being prepared on the
[preview release page](https://github.com/dominicbytes/redot-cubism/releases/tag/redot-26.2-preview-2026-09-20).
The planned ZIPs target Windows x86_64 and Linux x86_64; Linux requires glibc
2.43 or newer. They contain native libraries that statically link Cubism Core,
with its separate terms and notices. This preview does not broaden the tested
platform or renderer scope or constitute complete release qualification.
Earlier branch and draft-PR states below are historical checkpoints.

## Development checkpoint before integration on 2026-09-18

The latest tested source is `02e15cfdfb4a42df2b5ba4979f2c3d31d3b0b9ec`
on [`fix/linux-checked-export-ui-pid`](https://github.com/dominicbytes/redot-cubism/tree/fix/linux-checked-export-ui-pid),
with [draft PR #2](https://github.com/dominicbytes/redot-cubism/pull/2) within
the user's fork. Both public source checks passed at that commit. The fork's
`main` remains at upstream baseline `3aaa3c9001808732c40aa3fa07460a95125d9ccc`;
no PR targets the original GDCubism project.

Focused Linux native legacy/raw and managed debug/release exported audio/reentry
checks passed on that source. Matching Windows debug/release native builds and
changed-path runtime checks passed. The Windows Mono source probe and saved
debug/release exports functioned, but the first plain run of **each** managed
export reported an unresolved ObjectDB leak warning at exit. See the
[Windows validation snapshot](../windows-validation-2026-09-18.md) and
[current status](../current-status.md) for scope and older evidence attribution.
Publication remains source-only: SDK files, model assets, binaries and private
test artifacts are absent. A binary release is not qualified.

## Earlier Windows integration checkpoint

An earlier source-only Redot port snapshot was published on
[`review/windows-integration`](https://github.com/dominicbytes/redot-cubism/tree/review/windows-integration)
in `dominicbytes/redot-cubism`, with [draft PR #1](https://github.com/dominicbytes/redot-cubism/pull/1)
targeting that same repository. No PR is being submitted to the Godot upstream.
That branch's native parser checkpoint is
`a6133baf7b45c20a6550a9b6949ac25885bb1267`: rebuilt Windows debug and
release libraries passed 108 bounded parser cases twice each after correcting
invalid import-option diagnostic types and lengths.
The real-model importer retest also passed 23 stages per variant, including
88 option assertions. See
[current status](../current-status.md#windows-parser-robustness-checkpoint)
for exact library identities and scope. This does not qualify a binary release
or establish a Linux fuzz result.

The preceding published qualification snapshot is
`b338d9cd8527321bfa566ca827e3696a59a79dd3`.
[Public push CI](https://github.com/dominicbytes/redot-cubism/actions/runs/35292818863)
passed all 110 Python tests and its source/history/format checks. Draft PR CI
also passed at its merge commit. The private source mirror at
`00e3d521652df6e28ab8420ea5b0928f49303e55` passed hosted source CI. No
licensed native job has executed for this snapshot. SDK files, private models
and binaries are not published.
The complete Windows debug/release ten-stage suites passed at earlier source
`55dd0604d605586e79f65664d448f78d9a8dad36` with the frozen integrated
DLLs. The `b338d9c` addon-icon change passed separate fresh whole-addon import,
installed-host export/texture and source-absent exported lifecycle retests. Neither
result is a binary-release qualification. On `b338d9c`, a separate SDK-free
Windows ABI fixture passed 8/8 debug and 8/8 release checks. A private
production-importer coexistence check passed four fresh-import/restart phases
per variant with a deliberately installed lower-priority generic JSON importer;
it does not establish stock automatic `.model3.json` discovery. These scoped
checks also do not qualify a binary release.
See [current status](../current-status.md) for exact Linux and Windows runtime
identities and remaining qualification gates. At that checkpoint, the default branch had not been
changed to this development port; follow the [source setup](../quick-start.md#get-the-source).

## Historical upload record

> Historical upload record: the public commit and CI result below describe an
> earlier sanitized checkpoint. Later Linux and Windows checks have separate
> source identities; source-only packaging/history commits are not automatically
> covered by them. See
> [current status](../current-status.md) before treating any checkpoint as current.

The user-created public fork, renamed on 2026-09-16, is
[`dominicbytes/redot-cubism`](https://github.com/dominicbytes/redot-cubism).
It is a fork of `MizunagiKB/gd_cubism`; `main` was verified at
`3aaa3c9001808732c40aa3fa07460a95125d9ccc` on 2026-09-07. The local
implementation branch is `port/redot-26.2`; historical upload links below retain
the fork's former URL, which redirects to its current name.

Source checkpoints prepared for publication:

| Local commit | Scope | Evidence |
| --- | --- | --- |
| `9f33623` | Provenance and source checks | [PR 0/1](pr-01-report.md) |
| `581f6ed` | SDK-free Linux ABI/import/export spike | [PR 2A](pr-02a-report.md) |
| `51a3bf0` | Explicit pinned build-input validation | [PR 2B preparation](pr-02b-build-inputs-report.md) |
| `1ca0e16` | Matched R5 native Linux port | [Native SDK report](pr-02b-native-report.md) |

Before publication, all 22 public tests passed again; the tracked-file audit
checked 212 files and the history audit checked 1,134 file versions without
restricted content. This establishes source-check coverage, not Cubism playback.

The user completed GitHub CLI authorization, resolving the write-access blocker.
The source checkpoints above are published on
[`port/redot-26.2`](https://github.com/dominicbytes/redot_cubism/tree/port/redot-26.2)
at `2572e1f2108e0c0430c967f0e3d396dffa0a2329`.
[Public source CI passed](https://github.com/dominicbytes/redot_cubism/actions/runs/34400285433).
Each uploaded commit excludes the workbook, so the public commit IDs differ:

| Local | Public |
| --- | --- |
| `9f33623` | `aa6688f` |
| `581f6ed` | `91cc780` |
| `51a3bf0` | `b4bfda4` |
| `3e76058` | `196a472` |
| `1ca0e16` | `eec01e1` |
| `e414595` | `2572e1f` |

Automatic approval review also rejected public upload of
`source-of-truth.xlsx`, citing local paths and internal status records. Specific
user approval was requested. Until resolved, any public checkpoint must omit
this workbook from every uploaded commit, not merely delete it at the tip.
The workbook remains in local history and must not be pushed indirectly.

The recorded upload above contains the mechanical port and Linux-tested lifecycle
checkpoint. Its clean public-commit debug and release builds each passed 19
checks; source-identical lifecycle code passed 250 ASan cycles, handles and
loading-removal tests. These are historical results for that checkpoint, not
qualification of the later local implementation.

At that historical checkpoint, subsequent local work added imported model
resources, `CubismModel2D`, native motions/expressions, controller/audio cues,
checked exports, editor tooling and renderer fixes. The
[current documentation](../README.md) describes those APIs;
[renderer measurements](pr-04-renderer-report.md) and [benchmarks](../benchmarks.md)
record later coverage and its limits. The sanitized Redot review branch has
since published the verified source snapshot above; the unfiltered local history
containing the workbook remains unsuitable for publication.

The [current status](../current-status.md) separates the full Windows suite,
the latest addon-asset retest, and older Linux results by source identity.
Licensed native CI, a stable dedicated performance baseline, external-input
Windows editor acceptance, full current-source cross-platform desktop
qualification, and final package/legal review remain open. The port remains
unqualified for release.
