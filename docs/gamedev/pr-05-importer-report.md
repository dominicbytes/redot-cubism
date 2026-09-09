# PR5 importer progress

Status: in progress. The pure native manifest parser is implemented; model
resources, the editor importer, physical path validation, runtime resource
loading and dependency invalidation are not yet implemented. PR4 visual parity
remains open while this independently testable parser layer proceeds.

The [parser contract](../manifest-parser.md) documents normalized output,
bounded diagnostics and fixed limits. It calls Redot JSON and never loads a
referenced resource or opens a referenced file. It rejects script-bearing
texture/audio suffixes before any future resource-loading stage can run.
Successful syntax validation must not be used as a file-access security gate.

The first native tests exposed two issues: the test compared JSON numeric
storage directly with a hand-built integer Dictionary, and Redot replaces a
decoded NUL escape with U+FFFD. The former oracle now compares against Redot's
own JSON representation; the parser rejects NUL escapes before decoding.
It also uses the existing releasing Dictionary copy-assignment workaround for
the pinned redot-cpp revision. That lifetime change has not yet been checked
with a new sanitizer run.

All 49 parser cases pass in the source project and exported debug/release games.
The integrated Linux debug and release suites each pass 41 checks, including the existing renderer
and lifecycle checks. The eight bundled SDK manifests also pass syntax
validation (25, 17, 21, 11, 24, 12, 9 and 9 dependencies for Haru, Hiyori, Mao,
Mark, Natori, Ren, Rice and Wanko respectively). Ren's successful syntax parse
does not establish support for its advanced runtime rendering features.

The tested working-tree debug library SHA-256 is
`f6f25dc8a5372c5cef82faa9939cca6e3ee52e01943b1d0403d1841388551642`.
The release library SHA-256 is
`bf0873f66c06bb7420745d5ed6d168f13506b6aa34b1970661d6b6e68419fe93`.
The public Python suite passes 24 tests and the staged source audit checks
253 files without restricted-file findings.
Private evidence is retained under `.local-build/evidence/manifest-parser-*`
and the persistent VM results directories with the same names.

An initial isolated editor import crashed with an unsymbolized engine stack
before the tests ran. No current core was available through coredumpctl. The
previous library control, corrected-test retry and fresh integrated imports
succeeded, but the cause has not been established. Retain this as an open
editor qualification issue rather than claiming a crash fix. Initial logs are
preserved in `manifest-parser-isolated/import.log`.
