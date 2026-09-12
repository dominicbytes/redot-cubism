# Export validation groundwork

`CubismExportValidator.validate_model(model)` is an editor-only, read-only
precondition for the planned checked export action and raw-file injection plugin.
It returns `ok`, structured `diagnostics` (`path` and `message`), and a sorted
`raw_files` list. Any failure returns an empty list, never a partial package.
Call it on the editor main thread after asset importing finishes.

Validation checks the runtime resource schema and shape, then reconstructs the
current model in memory through the import factory. This reuses path containment,
source limits, manifest and descriptor parsing, MOC consistency/version checks,
and optional-file policy. It compares source hashes, dependency fingerprints,
import settings and source references against the saved import. It does not save
or automatically reimport resources. A stale model must be reimported first.

Derived textures must remain real, contained Cubism texture resources with their
original content hashes. Motion sounds must retain real imported audio resource
references. Required texture/audio import metadata must be present; absent
optional audio remains valid when the original import allowed it.

On success, `raw_files` contains the original manifest and only its enabled,
present MOC/JSON dependencies. Textures and audio are intentionally represented
by normal resource edges, not raw-file injection entries. No folders are scanned
for extra motions or unrelated files. Revalidate bytes at packaging time to guard
against changes after validation.

This API does **not** yet provide preset selection/dependency traversal, export
injection, a checked editor/CLI action, archive verification or output promotion.
Ordinary Export-menu callbacks cannot be assumed to abort an invalid export.
Full-model export remains unfinished until those components and their integration
tests are implemented. Existing texture-only export tests do not qualify it.
