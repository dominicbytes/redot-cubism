# Source publication status

> Historical upload record: the public commit and CI result below describe an
> earlier sanitized checkpoint. The tested baseline for the current evidence is
> `90f8d18298369a3ecd942928806ed52269e5871c`; source-only packaging/history
> commits after that baseline are not automatically covered. See
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

Subsequent local work includes imported model resources, `CubismModel2D`, native
motions/expressions, controller/audio cues, checked exports, editor tooling and
renderer fixes. The [current documentation](../README.md) describes those APIs;
[renderer measurements](pr-04-renderer-report.md) and [benchmarks](../benchmarks.md)
record later coverage and its limits. Those additions require a fresh filtered
publication; do not push the unfiltered local history containing the workbook.

Windows native/editor/export checks, live desktop CI, full visual acceptance,
dedicated performance thresholds, remaining editor checks and final package/legal
review are still open. The port remains unqualified for release. This file records
the known upload checkpoint; inspect the remote before making the final push.
