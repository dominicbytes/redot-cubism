# Manifest syntax validation

`CubismManifestParser.parse_manifest(json, source_path)` performs native,
filesystem-independent validation using Redot JSON. `source_path` must identify
a `.model3.json` under `res://`. This API is the initial PR5 parser layer, not
the editor importer or authorization to load the returned paths.

The result contains:

- `ok`: whether syntax, supported field types and lexical paths passed.
- `manifest`: the parsed object with recognized file references normalized to
  `res://` paths; empty on failure. Texture and motion array order is retained.
  Unknown JSON fields are preserved with Redot's JSON numeric representation.
- `dependencies`: sorted, unique recognized file paths. On failure this may be
  incomplete; it is not proof of a valid model or an engine dependency watcher.
- `diagnostics`: at most 32 error objects, each containing `path` and `message`.

The parser accepts model settings version 3 and checks MOC, texture, optional
JSON, expression, motion, sound, fade, layout, group and hit-area field types.
Expression names and group/hit-area identifiers must be unique. Motion identity
is its group plus array index; repeated motion file references remain valid.
Relative separators and dot segments are normalized without changing case.
Absolute paths, schemes, drives, control characters and project-root traversal
are rejected. NUL escapes are rejected before Redot can replace them during
decoding. Known references require their lowercase Cubism JSON/MOC suffix,
`.png` textures or `.wav`/`.ogg` audio. No resource loader is called.

Fixed limits are 4 MiB of UTF-8 JSON, 4096 characters per string and resolved
path, 32 levels of nesting, 65536 tree nodes, 4096 file references, 64 textures,
64 motion groups, 512 motions per group and 512 expressions. Diagnostic output
is bounded even when a manifest contains many invalid references.

Applying physical containment and existence checks, missing optional file
policy, referenced JSON schemas, MOC consistency/version/texture indices,
imported resource types and deterministic texture provisioning still belong to
the unfinished importer layer. Empty texture arrays are retained here; deciding
whether a model permits them requires MOC inspection. Raw JSON duplicate object
keys follow Redot's parser behavior; this layer checks semantic IDs represented
in arrays, not raw duplicate JSON keys.

## Expression JSON conversion

`CubismManifestParser.parse_expression(json, expression_id, source_path)`
returns `ok`, bounded `diagnostics`, a typed `expression` resource (null on
failure), and parsed `source_data` (empty on failure). `source_path` must be a
contained lexical `res://` path ending in `.exp3.json`. No file is opened.

`Parameters` must be an array of at most 4096 objects with nonempty String IDs
and finite Framework-float values. Ordered repeated IDs are retained. Blend
names are Add, Multiply or Overwrite; absent/null Blend defaults to Add,
matching the pinned SDK. Unknown blend names are rejected rather than silently
using the SDK's fallback. Optional fade values must be finite numbers; absent
values resolve to the pinned Framework's 1-second expression default. If `Type`
is present it must equal `Live2D Expression`; an absent Type remains compatible.

The common JSON size, string, nesting, node and NUL checks apply. Unknown data
is preserved in `source_data` for importer metadata handling. Physical file
checks, descriptor registration in the model catalog and expression playback
are separate steps. Source values are not applied to a live Cubism model here.

## Physical file validation

`CubismManifestParser.validate_project_file(path)` checks a normalized `res://`
path against the canonical physical project directory. It returns `path`,
`message` and one of these `status` values:

- `file`: the resolved target is a regular file inside the project.
- `missing`: the contained path does not exist.
- `unsafe`: malformed input or a resolved path outside the project.
- `error`: inspection failed, a symlink is dangling/cyclic, or the target is
  not a regular file.

Only `missing` can be considered for optional-file leniency. An unresolved
symlink is not treated as an ordinary missing file: weak canonicalization alone
can leave a dangling link pointing outside the project unresolved. Containment
compares path components, not string prefixes. Unicode and contained symlinks
are supported; Windows filesystem qualification remains pending.

This is a filesystem snapshot for importing source assets, not a PCK resource
lookup, extension allowlist, or atomic guarantee against concurrent filesystem
replacement. The importer must combine syntax validation, this check, file
validation and resource-type checks. No import/load path is wired to it yet.
Run `tools/run_path_tests.py --library <native-library> --output <persistent-dir>`
with `REDOT_BIN` set to test 18 cases using real task-owned symlinks. The output
directory retains fixtures, logs and the tested binary identity. Symlink setup
requires host support and permissions; failure is not a passing test.

The native test script `tests/native/project/manifest_checks.gd` exercises 49
cases without model files. `tools/run_native_tests.py` runs it in both the
source project and exported game, alongside the existing licensed native suite.

## Motion JSON validation

`parse_motion(json, group, index, source_path)` returns `ok`, bounded
`diagnostics`, and a `CubismMotionDescriptor` (null on failure). It shares the
JSON size, nesting, string and node limits above and validates a project-relative
`.motion3.json` source path. It does not read files or invoke the SDK.

Version 3, positive finite Framework-float duration/frame rate, boolean loop,
and typed curves are required. Each curve has a nonempty ID and one of the
Model, Parameter or PartOpacity targets, in that order as required by the pinned
SDK's playback loops. Linear, Bezier, stepped and inverse-stepped segments are
decoded without conversion. Truncated/unknown segments, nonnumeric coordinates,
and endpoint times that do not increase at float precision are rejected. Each
curve requires an initial point and at least one segment. Declared curve,
segment and point counts must match decoded arrays before SDK allocation.

Events retain their input order, Unicode text and time in typed resources;
times must lie within the motion duration. The event count must match (an absent
count is accepted only with no events). `TotalUserDataSize` is retained and
checked as a finite number, but not recomputed: the pinned motion parser does
not consume it. Unknown metadata and all original curves are retained in the
descriptor's metadata. Missing or negative motion-level fades resolve to one
second, matching the pinned SDK. Per-curve fades remain in the preserved data.

The importer still needs to apply model-manifest fade overrides and sound
associations. This helper does not create Redot Animation tracks, play motion,
or qualify the complete importer/runtime pipeline.

## Bounded physical JSON reads

`read_project_json(path)` returns `ok`, `status`, `path`, `message` and `text`.
It first applies `validate_project_file`, then opens the physical project path
with FileAccess, without ResourceLoader or resource remapping. It refuses files
larger than 4 MiB before allocating a buffer and rejects a short read or a change
in length during the read. Failed reads always return empty text.

UTF-8 is checked for invalid/truncated sequences, overlong encodings, surrogate
code points, out-of-range code points and embedded NUL before decoding with a
Redot String. An initial UTF-8 BOM is accepted and removed. Empty files and
non-JSON text can be read; the schema parser must subsequently reject invalid
JSON. The helper does not parse, execute, import or create any resource.

This is an editor source-file operation, not a PCK resource reader. Physical
containment is a snapshot; the helper does not claim an atomic defense against
concurrent symlink replacement or same-length content changes. Callers must
attach the manifest property path to read diagnostics when resolving dependencies.

## Pose JSON validation

`parse_pose(json)` returns `ok`, bounded `diagnostics`, `pose` (the original
parsed dictionary, empty on failure), and `fade_in_seconds`. It uses the shared
JSON limits, rejects wrong structural types and empty part/link IDs, and requires
`Groups` to contain arrays of part objects. Optional `Type` must be `Live2D Pose`.
Missing/null links are accepted. Empty groups and repeated IDs remain ordered
as in the source; no speculative deduplication or link-graph traversal occurs.

Absent/null/negative fades resolve to 0.5 seconds, matching the pinned SDK.
Zero is retained, and other fades must fit a finite Framework float. Original
metadata is preserved; the resolved fade is reported separately. This validates
JSON structure without reading files, resolving IDs against a MOC, creating a
live SDK pose or proving pose playback behavior. Those remain importer/runtime
integration checks.

## Physics JSON validation

`parse_physics(json)` returns `ok`, bounded `diagnostics` and the unchanged
parsed `physics` dictionary (empty on failure). Version 3 and typed metadata,
forces, settings, normalization values, particles and input/output objects are
required. All consumed numeric values must fit finite Framework floats.
Declared setting/input/output/particle counts must match the actual arrays.
Each setting requires a root particle and nonempty input/output arrays because
the pinned SDK takes their addresses before iteration. Output particle indices
must be integral, non-root and within that setting's particle array.

Only X, Y and Angle callback types and Parameter source/destination targets are
accepted. IDs must be nonempty and Reflect must be boolean. Absent FPS follows
the SDK's zero/variable-step default. Explicit FPS is limited to 0–1000 as a fixed
import policy to bound SDK fixed-step work. Normalization values, weights,
particle values and source ordering are preserved without speculative clamping.
Unknown metadata is retained under the shared JSON size/node limits.

This validates structure before SDK allocation. It does not resolve parameter
IDs against the MOC, run the physics simulation, prove numerical stability for
all finite inputs, or wire the file into the editor importer. Those remain
runtime/importer qualification requirements.

## User-data and display-info validation

`parse_user_data(json)` returns `ok`, bounded `diagnostics` and `user_data`
(empty on failure). Version 3 and an exact `Meta.UserDataCount` are required
before the SDK's count-driven entry reads. Entries require nonempty string
Target/Id and a string Value; empty values and unknown target names are preserved.
Optional TotalUserDataSize must be a nonnegative integer but is not recomputed:
the pinned consumer does not use it, and byte/character semantics are not assumed.

`parse_display_info(json)` returns `ok`, `diagnostics` and `display_info` (empty
on failure). Version 3 is required. Optional Parameters, ParameterGroups and
Parts arrays contain objects with unique nonempty IDs per collection and string
Names. Optional GroupId is a string and may be empty. CombinedParameters, when
present, is an array of arrays of nonempty parameter IDs. Original names, order
and unknown metadata are retained. IDs may repeat across different collections.

Both use the shared JSON bounds. Neither resolves IDs against the MOC, traverses
or validates group relationships, loads files, or creates SDK/runtime objects.
Consumers must validate relationships before treating group metadata as a tree.

Successful `read_project_json` results also include `sha256` and `byte_length`
from the exact raw bytes decoded. The hash includes any initial BOM even though
the returned text omits that BOM. Failed reads do not supply a fingerprint.
