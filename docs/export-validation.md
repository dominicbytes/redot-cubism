# Export validation groundwork

`CubismExportValidator.validate_model(model)` is an editor-only, read-only
precondition for the planned checked export action and the raw-file injection plugin.
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

The native export plugin calls this validation for included model/resource/scene
files, stages verified raw payloads with their original paths and `remap=false`,
and includes the ten known runtime shaders. It avoids duplicate raw entries when
normal export selection already includes those files. Texture/audio and native
extension references go through Redot's normal dependency/remap/export process.

The checked editor/CLI action, complete pre-export selection validation, and
verified output promotion are still unfinished.
Ordinary Export-menu callbacks cannot be assumed to abort an invalid export.
Full-model export remains unfinished until those components and their integration
tests are implemented. Linux debug and release tests now cover selected resources,
selected scenes, embedded models and all resources. They inspect raw archive
hashes and launch the exported model with the source project unavailable, including
actual parameter changes during motion playback. This does not qualify checked
output promotion, Windows or renderer parity.
