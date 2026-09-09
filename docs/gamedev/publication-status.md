# Source publication status

The user-created public fork is
[`dominicbytes/redot_cubism`](https://github.com/dominicbytes/redot_cubism).
It is a fork of `MizunagiKB/gd_cubism`; `main` was verified at
`3aaa3c9001808732c40aa3fa07460a95125d9ccc` on 2026-09-07. The local `origin`
now uses that URL. The local implementation branch is `port/redot-26.2`.

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
at `eec01e1e152edf9b980b97b977d873ac0d73b7d0`.
[Public source CI passed](https://github.com/dominicbytes/redot_cubism/actions/runs/34168700703).
Each uploaded commit excludes the workbook, so the public commit IDs differ:

| Local | Public |
| --- | --- |
| `9f33623` | `aa6688f` |
| `581f6ed` | `91cc780` |
| `51a3bf0` | `b4bfda4` |
| `3e76058` | `196a472` |
| `1ca0e16` | `eec01e1` |

Automatic approval review also rejected public upload of
`source-of-truth.xlsx`, citing local paths and internal status records. Specific
user approval was requested. Until resolved, any public checkpoint must omit
this workbook from every uploaded commit, not merely delete it at the tip.
The workbook remains in local history and must not be pushed indirectly.

The SDK-backed mechanical port is published. Lifecycle hardening is the next
working checkpoint. Windows qualification, measured renderer parity, importer,
controller/audio and later feature stages remain incomplete.
