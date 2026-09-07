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

Before publication, all 22 public tests passed again; the tracked-file audit
checked 212 files and the history audit checked 1,134 file versions without
restricted content. This establishes source-check coverage, not Cubism playback.

No port commits have been uploaded yet. The GitHub integration reads the fork
but Git tree creation returns HTTP 403, `Resource not accessible by integration`.
The signed-in browser's GitHub CLI authorization form remains disabled.
There was no successful write, branch creation, or remote CI run.

Automatic approval review also rejected public upload of
`source-of-truth.xlsx`, citing local paths and internal status records. Specific
user approval was requested. Until resolved, any public checkpoint must omit
this workbook from every uploaded commit, not merely delete it at the tip.
The workbook remains in local history and must not be pushed indirectly.

Uncompiled R5 adaptations remain a separate working diff. The matched SDK/Core
and model fixture are still unavailable. Native compilation, playback, graphics,
Windows qualification, and later feature stages remain incomplete.
