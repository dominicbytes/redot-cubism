# PR5 importer progress

Status: in progress. The pure native manifest parser, physical path helper and
model resource container are implemented; typed motion/expression descriptors,
the editor importer, runtime resource
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

## Physical project containment

The native `validate_project_file` helper now resolves the actual project root
through Redot ProjectSettings and inspects physical filesystem paths. It
distinguishes contained regular files, contained missing files, unsafe paths
and inspection errors. Path-component comparison rejects similarly named
siblings. Dangling or looping symlinks fail closed rather than becoming
optional-file warnings. It does not load resources or read asset contents.

Eighteen real-filesystem cases pass in both Linux debug and release builds,
including Unicode, contained/external links, a missing child under an external
directory link, dangling links, a loop and lexical escapes. The test process
runs outside the project directory, exercising independence from the current
working directory. The focused runner retains its symlink fixtures and logs in
the persistent output directory; it creates links after editor import so the
test does not claim EditorFileSystem symlink traversal coverage.

The updated debug and release builds each pass all 41 integrated native/export checks.
Current working-tree library hashes:

- Debug: `d43ceda94c3e49980c287b5727c3d1b8c6655cd333f55dd857538996edff966c`.
- Release: `4d17472b5b0ef3123666167e0390a99fd44cebdc1c1e9b38e5ca33799e7eb033`.

The public suite passes 24 tests; the staged source audit passes 255 files.
Evidence is retained under `.local-build/evidence/physical-path-*`. Windows,
concurrent filesystem replacement, virtual exported resources and actual
importer integration remain outside this helper's qualified coverage.

## Serializable model data

`CubismModelResource` now stores the plan's model metadata, ordered texture
references, typed hit-area dictionaries and dependency/import metadata as a
native Redot Resource. It contains no dedicated runtime handles or renderer
state. The [resource contract](../model-resource.md) describes the API and its
limits. The class does not itself validate that a manually constructed model
resource is safe or complete; importer/runtime validation remains required.

The resource test verifies 36 conditions: defaults, all stored fields, Unicode,
repeat-save determinism, a fresh ResourceLoader round trip, shared texture
identity, pixel payload and an external texture visible through the engine's
dependency API. The initial test incorrectly expected a texture saved under
`user://` to remain an external dependency. Redot embedded it. The corrected
test uses an actual imported project texture, matching the required import
contract; production code did not change to accommodate that test correction.

Debug and release each pass all 43 integrated checks, including resource tests
in the source project and exported game. The working-tree debug library SHA-256 is
`1aac2dcf03832cbdff448cd6e72812627d75c3d52f50ec64f76c0c8c2ef206bc`.
The release library SHA-256 is
`ff288d994099d56682a654da5575a121ab4db728076363b7594e54c92b3cb837`.
The public suite passes 24 tests and the staged source audit passes 259 files.
Evidence is retained in `.local-build/evidence/model-resource-*` and the
persistent VM results with matching names. This proves resource serialization,
not first-class model importing, a complete descriptor schema, reimport
tracking or runtime loading from these resources.
