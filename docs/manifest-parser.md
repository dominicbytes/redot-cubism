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
