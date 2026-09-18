# Implementation handoff

The canonical behavioral contract and ordered stages are in
[the porting plan](../../redot_live2d_cubism_importer_codex_plan.md).

On 2026-09-07 the user explicitly authorized implementing and testing the plugin,
forking MizunagiKB/gd_cubism as dominicbytes/redot-cubism, and saving the port there.
This overrides the earlier planning-only boundary and proposed organization remote.
Source publication to that fork is authorized. It does not assert approval to
redistribute proprietary Core, SDK packages, private models, or binary releases.
The user subsequently created `dominicbytes/redot_cubism` (underscore) and asked
this task to use it. On 2026-09-16, that same public fork was renamed to
`dominicbytes/redot-cubism` at the user's direction. This is the current source
destination; earlier reports retain the repository's former name.

PR 0/1 and the Linux portion of SDK-free PR 2A are READY_FOR_IMPLEMENTATION.
Current checkpoint: [PR 0/1 report](pr-01-report.md) and
[Linux PR 2A report](pr-02a-report.md). Linux debug/release SDK-free import,
restart, internal-process and actual exported-template checks now pass.
The user accepted the SDK agreements and completed the official Native 5-r.5
download on 2026-09-07. The archive and Core inputs are now fingerprinted, and
its Framework matches the pinned source. Linux debug/release native compilation and real-model motion, expression, reload
and privately exported-template smoke tests pass. Compatibility graphics smoke
has run on this host; full renderer parity is still open. Windows build/runtime qualification remains
required. Later feature stages retain the canonical plan's dependency gates.

PR 2B [build-input preparation](pr-02b-build-inputs-report.md) now selects the
pinned Redot submodule and validates explicit dependencies. Its rejection cases
pass. The [native report](pr-02b-native-report.md) records the real SDK checks;
the full cross-platform PR 2B acceptance gates remain open.

Baseline: Redot 26.2 commit 4f5b14abade2239104847d03d8f9056e4467cfcd,
redot-cpp 598ec78e86b2c240a023f6de13daba70f7de8610, GDCubism
3aaa3c9001808732c40aa3fa07460a95125d9ccc, Framework
145155d2c5bdd8d23475cef9cc3ab46d3220190c, Core SDK 5-r.5, single precision.
The GDCubism v0.9.1 tag is 60e9c61ed20d08ec19b2cb80fb492ce6344927c6;
its file tree equals the selected merge commit. Keep the selected pin.

Implementation ownership is local to this task. Checkpoints are separate Git
commits per coherent stage, with commands and coverage in stage reports.
The first checks are provenance/restricted-file auditing, public tool tests,
exact engine/API fingerprints, and SDK-free native class registration and
internal-process tests. Passing them does not establish Cubism model playback.

The user completed CLI authorization as dominicbytes. Audited source checkpoints
are published on the fork's `port/redot-26.2` branch, and public CI passes.
The project workbook upload was separately rejected
by automatic approval review; specific public-disclosure approval is pending.
Do not upload that workbook through another route without resolving the rejection.
See [publication status](publication-status.md) for the current checkpoint.

Portable runtime hardening may proceed from the tested Linux checkpoint while
Windows admission remains pending. This scheduling choice does not mark the
Windows or full native-port milestone complete, and later Linux checks cannot
stand in for Windows runtime evidence.
