# Export validation groundwork

`CubismExportValidator.validate_model(model)` is an editor-only, read-only
precondition shared by the checked export action and the raw-file injection plugin.
It returns `ok`, structured `diagnostics` (`path` and `message`), and a sorted
`raw_files` list. Any failure returns an empty list, never a partial package.
Call it on the editor main thread after asset importing finishes.

Validation checks the runtime resource schema and shape, then reconstructs the
current model in memory through the import factory. This reuses path containment,
source limits, manifest and descriptor parsing, MOC consistency/version checks,
and optional-file policy. It compares source hashes, dependency fingerprints,
import settings and source references against the saved import. It does not save
or automatically reimport resources. A stale model must be reimported first.

Imported models also carry a stored `runtime_extension` resource reference to the
addon descriptor. This gives Redot a real dependency for selecting the matching
native library and generating its extension startup list. Importer format 6
rebuilds older resources to add this edge.

Derived textures must remain real, contained Cubism texture resources with their
original content hashes. Motion sounds must retain real imported audio resource
references. Required texture/audio import metadata must be present; absent
optional audio remains valid when the original import allowed it.

On success, `raw_files` contains the original manifest and only its enabled,
present MOC/JSON dependencies. Textures and audio are intentionally represented
by normal resource edges, not raw-file injection entries. No folders are scanned
for extra motions or unrelated files. Revalidate bytes at packaging time to guard
against changes after validation.

`validate_file(path)` validates models embedded in one exported resource or scene
and returns `models` and `raw_hashes`. External resource references are left to
their own engine export callbacks, preserving export exclusions. Stored arrays,
dictionaries and resource properties are traversed with cycle/size/depth bounds.
For packed scenes, validation also inspects stored node properties and resolves
native node types through inherited scenes and instance overrides. A nonempty
legacy Cubism `assets` string requires a matching `_legacy_model` imported-resource
edge. [Prepare and save the legacy scene](legacy-compatibility.md), or assign an
imported resource to its `model` property. Missing or mismatched bridges produce
a scene/node diagnostic. Empty Cubism nodes and unrelated scripts' `assets` properties
are allowed. Validation inspects scene state without instantiating scene nodes.

The native export plugin calls this validation for included model/resource/scene
files, stages verified raw payloads with their original paths and `remap=false`,
and includes the ten known runtime shaders. It avoids duplicate raw entries when
normal export selection already includes those files. Texture/audio and native
extension references go through Redot's normal dependency/remap/export process.

The shared editor preflight is in `addons/gd_cubism/editor/export_preflight.gd`.
It reads the named preset without rewriting it, follows the scanned resource
dependency graph, includes autoloads with the target preset's feature overrides,
and applies include/exclude filters. It supports selected scenes/resources,
all resources, exclude-selected and customized modes on Linux/Windows Desktop
presets. Customized directory rules inherit as in pinned Redot. Missing selected
files, unresolved dependency UIDs, directory symlinks, stale models, missing
shaders and filters that cut required resource edges produce diagnostics with no
partial file/hash list. File enumeration is bounded at 100,000 entries.
Linux execution is covered by the integration matrix; Windows execution remains
a separate required platform gate.

Run the preflight through the normal editor lifecycle (after installing the
matching native addon and these editor scripts):

```sh
"$REDOT_BIN" --headless --editor --path /path/to/project --quit-after 10000 -- \
  --cubism-preflight "Existing preset name" /path/to/fresh-preflight-report.json
```

The command returns zero with `CUBISM_EXPORT_PREFLIGHT_PASS` only when validation
succeeds; invalid input returns nonzero. The JSON report contains the selected
files, validated resource/scene files, model count and raw/shader hashes. CI
callers must also require the marker and report, reject engine diagnostics, and
enforce a wall-clock timeout; an interrupted editor can leave no final report.
This command validates only. It does not start packaging or replace any build.

The combined pipeline is available from **Project → Tools → Validate and Export
Cubism**. Save project changes first, choose an existing preset and build mode,
then choose a directory for the complete build. Python 3.10 or newer is required;
the dialog accepts its executable path (`CUBISM_PYTHON_BIN` supplies the default).
The same pipeline can be run from a source checkout:

```sh
python tools/checked_export.py --project /path/to/project \
  --preset "Existing preset name" --mode release --output /path/to/complete-build
```

Set `REDOT_BIN` or pass `--redot-bin`. Installed addons ship the equivalent
`addons/gd_cubism/editor/checked_export.py`. The output argument names a directory,
not an executable. `--name` sets the executable filename. The checker currently
requires an x86_64 runner on the target Linux/Windows OS and an unencrypted,
standalone PCK; unsupported layouts fail explicitly without changing presets.
Windows execution still requires separate platform validation.

The pipeline runs preflight, packages into a fresh sibling work directory,
checks raw/shader hashes and executable/shared-library architecture, and runs an
external smoke script against the staged game/PCK. The smoke loads selected and
embedded models, starts a motion from each populated group, exercises expressions,
checks finite parameters and verifies native dependency identity. It does not
require every valid motion to visibly move parameters. Renderer parity is a
separate graphics test. The helper directory's addon-owned `.gdignore` excludes
editor scripts from normal export discovery. The checker also rejects archives
containing helpers (including compiled scripts), covering manually configured
presets that bypass discovery. A late export callback alone cannot undo scripts
already compiled by Redot's earlier GDScript exporter.

Only a passing build is promoted as a complete directory. Existing managed builds
are retained as `previous` inside that run's work directory, including when a
failed promotion must roll back. Nonempty unmanaged directories are refused.
Failed validation, packaging, archive inspection or playback returns nonzero;
the prior output remains intact. Reports and logs remain in the adjacent hidden
`.OUTPUT.cubism-export-*` directory. `cubism-export.json` in successful output
records dependency revisions and artifact hashes. `--report` writes a final
status JSON for automation; `--timeout` controls each engine phase's wall limit.
Concurrent exports to the same output are refused by a lock file. If a host crash
leaves that lock behind, verify its recorded process has stopped before removing it.

Linux debug/release integration tests cover a Unicode project/output/executable
path, complete build replacement, and preservation of the previous output after
missing-MOC, packaging and smoke-test failures. The actual editor menu action and
rendered dialogs are also tested. This qualification covers imported
`CubismModelResource` workflows. Legacy scenes using only the `assets` string
without a saved bridge are rejected before packaging. `tools/run_legacy_export_tests.py` covers
direct, inherited, instanced and embedded legacy scenes, unrelated properties,
absence of node instantiation and preservation of a previous build.
Ordinary Export-menu callbacks cannot be assumed to abort an invalid export.
The complete PR9 release gate remains open until the combined-action tests and
remaining package/platform checks pass. Linux debug and release tests cover selected resources,
selected scenes, embedded models and all resources. They inspect raw archive
hashes and launch the exported model with the source project unavailable, including
actual parameter changes during motion playback. Windows and renderer parity
remain separate qualification gates.
