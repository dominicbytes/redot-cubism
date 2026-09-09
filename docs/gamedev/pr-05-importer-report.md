# PR5 importer progress

Status: in progress. The pure native manifest parser, physical path helper and
model resource container and typed motion/expression descriptors are implemented;
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

## Typed motion and expression descriptors

Native `CubismMotionDescriptor`, `CubismMotionEvent`,
`CubismExpressionDescriptor` and `CubismExpressionParameter` resources now
provide the planned data fields, typed nested arrays, real AudioStream and
optional Animation references, and ADD/MULTIPLY/OVERWRITE operation constants.
The [descriptor contract](../descriptors.md) distinguishes storage from the
still-pending importer and playback implementation.

Thirty assertions verify defaults, all motion scalar metadata, Unicode event
payloads and expression identities, all three parameter operations, typed
nested-resource restoration, optional Animation storage, audio duration and an
external audio dependency visible through ResourceLoader. The runner generates
its own 10 ms silent PCM WAV before import; no third-party audio is committed.
Audio is not played in these tests, and no synchronization claim is made.
The existing harness exports all resources; selective dependency reachability
and the checked-export pipeline remain separate unfinished requirements.

Debug and release each pass all 45 integrated checks, including descriptor tests
in both source and exported execution. The working-tree debug library SHA-256 is
`3d23f8f713155e4f3e72e69bf7606e8e6d7998510311db100a47c851200a95d3`.
The release library SHA-256 is
`cb07bc0a78a64525676c16fbb648431326a7d02e1e512949d39d9da54abb6f60`.
The public suite passes 24 tests and the staged source audit passes 263 files.
Private reports and logs are retained under `.local-build/evidence/descriptors-*`
and matching persistent VM result directories. Descriptor source parsing,
stable-ID generation/validation and runtime consumption remain pending.

## Expression source validation

`CubismManifestParser.parse_expression` now validates expression JSON and
constructs a typed expression resource. Shared object parsing retains the
existing size, nesting, node, finite-number and NUL safeguards. Parameter
objects, values, fades, optional Type and blend names receive field-specific
diagnostics; failures return no partial descriptor. Ordered repeated IDs and
unknown source metadata are retained. Default fades and absent/null blend
behavior follow the pinned Framework; unknown blend names are rejected instead
of silently falling back to Add. The API opens no files and applies no values
to a model.

Thirty-six expression checks pass in source and exported execution, including
the fixture's eight expressions and malformed/bounded input cases. Separately,
all 32 expressions declared across the eight SDK sample manifests parse with
matching IDs, values, operations and fades. This is source-to-descriptor
validation, not expression playback equivalence.

Debug and release each pass all 47 integrated native/export checks. Working-tree
library hashes:

- Debug: `8e200e8dcaec41cb37c016383154712d511b412bc7770bf3005016dc1a770fbd`.
- Release: `5ed30f2df506a7c5026bcc96439cb3ca55c0a7d47e0c833ffa9d6a785c0afe9a`.

Private evidence is retained under `.local-build/evidence/expression-parser-*`
and `all-sdk-expressions.log`. The public suite passes 24 tests and the staged
source audit passes 264 files. Motion/physics/pose source validation, bounded
file reading, importer registration/population and runtime integration remain
unfinished.

## Motion validation checkpoint

Added `CubismManifestParser.parse_motion` and native descriptor population. The
validator checks decoded segment lengths/types and allocation counts before
SDK use, validates SDK curve target ordering, and preserves source curves,
metadata and typed user-data events. Motion-level default/negative fades match
the pinned Framework. Manifest fade overrides, sound association and file reads
remain importer work; no Animation conversion or new playback path is enabled.

The regression adds 63 assertions including all four segment forms, malformed
counts/segments, event bounds, default fades, Unicode and Haru motion fixtures.
A separate private check accepted all 50 motions declared across eight SDK
sample manifests and compared preserved metadata, duration, loop and identity.
The first run's metadata comparison incorrectly compared pre-JSON integer
serialization against decoded floats; corrected to compare decoded data. That
failure was a test oracle issue, not evidence of changed curve values.

Linux debug and release each passed 49 integrated native/export checks, including
63 motion assertions in both source and exported runs. Debug library SHA-256:
`96adca488ba21355fa8ec0526da6b0b843cfe3974d67d298a19da0f0484e2df8`;
release: `28cf495a280ab94be842967399a04e4db82124cf8e2f841e87fde4fbf1c33f7e`.
Public Python tests: 24 passed; source audit: 265 files passed. These are local
working-tree builds following 5844244, not a new clean public release. Evidence
is retained under `.local-build/evidence/motion-parser-*` and
`all-sdk-motions.log`. ASan and Windows qualification of this code remain pending.

## Bounded JSON source reads

Added `read_project_json(path)`: physical containment, FileAccess rather than
ResourceLoader, a 4 MiB cap checked before allocation, short-read/length-change
rejection, strict UTF-8 validation and Redot String decoding. It returns no text
on failure. BOM handling delegates to Redot so exactly one initial BOM is
removed. JSON syntax/schema parsing remains a separate required step. The
physical path check is a snapshot, not an atomic defense against concurrent
replacement. This helper is not yet wired into the editor importer.

Final debug and release builds passed 27 decoding/read cases and 18 real
filesystem containment cases each. Tests cover size boundaries, Unicode,
contained/external links, missing/dangling paths, malformed UTF-8, embedded NUL
and single/double BOM inputs. Final debug library:
`3ce61a61f6f89b7ec5c6a0908c76435642785c8d30a835880d21207285e169ea`;
release: `db8395c0e84e5b1032a7f5e2df73d00bbabe60b4f7ceb9d7ee56d30d0cedc8a3`.

Before the isolated BOM correction, the broader native/export suite passed 49
checks in each variant (debug
`56753eeb1504774bb3bab74f40f4e1e8da983de1ec5361f7c2d95aa909239caa`,
release `ef13acfb4409d42ff81d75e03629899ddd1f82ef5477df0a0052f3a65094a153`).
Those checks do not invoke the new physical reader; the changed decoding path
was retested with the final focused suites above. Public Python tests: 24 passed;
final staged source audit: 266 files passed. Reports/logs are retained locally
under `.local-build/evidence/json-read-*`. Windows and ASan remain pending.
