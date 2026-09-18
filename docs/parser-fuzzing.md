# Bounded parser fuzz gate

This is the SDK-free input-robustness gate from plan §20.10. It calls the
production `CubismManifestParser` manifest, motion and expression methods,
including their lexical path normalization and dependency deduplication. Import
options go through `CubismModelFactory.build_with_options` with a guaranteed
missing source path: validation runs first, then file lookup fails before any
model or proprietary Core input. An extra boundary case calls
`CubismManifestParser.read_project_json` on malformed UTF-8. The GDExtension
may initialize Core when it loads; no fuzz case supplies a MOC or SDK model.

Run from a **clean full source commit**, with matching privately built
production libraries and the pinned Redot editor. The output must be a new
private directory outside the checkout:

```sh
python tools/run_parser_fuzz.py --editor /path/to/redot.windows.editor.x86_64.exe \
  --editor-sha256 EXPECTED_EDITOR_SHA256 \
  --library /private/libgd_cubism.windows.debug.x86_64.dll \
  --library-sha256 EXPECTED_LIBRARY_SHA256 --variant debug \
  --source-ref FULL_CLEAN_SOURCE_SHA --output /private/fuzz-debug
```

Use `--variant release` with the matching release library for the other build.
The runner copies only the tracked full addon, its selected native library,
and a test-only worker into a private project. For release, the private
descriptor maps the editor's debug feature to the release library. A bounded
`--editor --import --quit-after 1000` pass discovers native classes before any
fuzz case; a second preflight script checks class registration. Both must have
clean logs. The editor `--version` setup query has an 8-second timeout and the
same parent-owned output cap; because it exits immediately, it is outside the
Windows Job, and it executes no fuzz API.

`--list-cases` prints the corpus without launching Redot. `--seed 0x...` selects
a reproducible corpus (default `0x2010c0b15a`). `--case manifest-00` replays one
named case twice in fresh processes; the exact seed, source, editor, library,
case bytes and result hashes are recorded. The 96 regular cases include the
two public ABI JSON fixtures and minimal valid parser controls, then seeded
UTF-8 insert/replace mutations, truncations, deep JSON, numeric extremes,
duplicate keys, Unicode normalization, path separators/traversal, repeated
dependencies, and unusual/long typed option keys. Every target has 16 cases.
Twelve explicit boundaries add JSON at 4 MiB ±1 byte, strings at 4096/4097
characters, depth 32/33, nodes 65536/65537, references 4096/4097, and a
malformed UTF-8 file read, plus a 2 MiB unknown import-option key. The
4096-reference path is reachable through
repeated manifest motions; this run does not separately exercise the project
import file-count setting.

Each case runs twice in fresh headless editor processes. The worker records
typed resource values rather than instance IDs, normalized manifest and
dependency values, and raw structured diagnostics. It checks text
`path`/`message` fields before canonicalization. The parent checks known-valid
and known-rejected controls, sorted unique dependencies, physical containment
for accepted paths, option rejection stage and absence of a loaded model,
diagnostic count/bytes and the 4096-character import-option path bound, and
identical canonical results. A failure stops the
campaign after its second bounded replay. The exact case, logs, contract and
result hashes remain in `fuzz-report.json`; `failure-case.json` can be replayed
and minimized before any product fix.

Test bounds are explicit campaign limits, **not a mathematical proof of
safety**: regular input at most 64 KiB, boundary transport at most 8 MiB,
at most 32 diagnostics and 1 MiB of encoded diagnostics, an 8 MiB result-file
polling rejection, and a hard 256 KiB parent-written engine log cap. Regular
children have 8 seconds, boundary children 20 seconds, import preflight 90
seconds, and the campaign 35 minutes. Windows fuzz and preflight children use
a queried 2 GiB aggregate JobObject memory limit and kill-on-close; the
worker's ready gate prevents parser calls until Job assignment succeeds.
Linux uses a 2 GiB per-worker `RLIMIT_AS` (not an aggregate process-tree
memory cap) and a process group for cleanup; that path still needs its own VM
run. Both report observed peak working set/RSS, and Windows also reports peak
Job memory. The result-file size is polled, so it can briefly overshoot its
limit before the child is stopped. No 4 MiB-scale random campaign or
proprietary Core fuzzing is claimed.

Create `STOP.requested` in the output directory to stop an active campaign;
the supervisor terminates its owned child tree and records an aborted report.
The same cleanup runs on interruption. This separate licensed-library gate is
not part of public Python CI, which has no production native library.
