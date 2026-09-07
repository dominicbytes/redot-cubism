# Implementation handoff

The canonical behavioral contract and ordered stages are in
[the porting plan](../../redot_live2d_cubism_importer_codex_plan.md).

On 2026-09-07 the user explicitly authorized implementing and testing the plugin,
forking MizunagiKB/gd_cubism as dominicbytes/redot-cubism, and saving the port there.
This overrides the earlier planning-only boundary and proposed organization remote.
Source publication to that fork is authorized. It does not assert approval to
redistribute proprietary Core, SDK packages, private models, or binary releases.

PR 0/1 and the Linux portion of SDK-free PR 2A are READY_FOR_IMPLEMENTATION.
Current checkpoint: [PR 0/1 report](pr-01-report.md) and
[Linux PR 2A report](pr-02a-report.md). Linux debug/release SDK-free import,
restart, internal-process and actual exported-template checks now pass.
The user also authorized the official SDK download on 2026-09-07. The download
page requires acceptance of both Live2D license agreements; action-time consent
has been requested before checking that box. The full native stage requires
the matched R5 SDK and permitted model fixture. Windows build/runtime qualification remains
required. Later feature stages retain the canonical plan's dependency gates.

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

Open access: the connector identifies dominicbytes but exposes no fork operation.
The user reports signing into Chrome, but the browser tool currently exposes only
the unauthenticated Codex browser. A connected route or the user-created fork is
pending while independent local work proceeds.
