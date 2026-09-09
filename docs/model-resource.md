# CubismModelResource

`CubismModelResource` is a native, serializable Redot `Resource` for imported
model data. Creating or loading one does not create a Cubism model or renderer.
The editor importer and runtime resource-loading adapter are still pending.
Saving a resource is not evidence that its contents describe a valid model.

The stored properties follow the implementation plan:

| Properties | Type |
| --- | --- |
| `source_model_path`, `source_hash`, `moc_path` | String |
| `moc_version`, `import_schema_version` | int |
| `texture_paths`, `dependency_paths`, `import_warnings` | PackedStringArray |
| `eye_blink_parameter_ids`, `lip_sync_parameter_ids` | PackedStringArray |
| `layout`, `dependency_fingerprints`, `motion_groups` | Dictionary |
| `sdk_compatibility`, `import_options`, `metadata` | Dictionary |
| `textures` | Array[Texture2D] |
| `expressions` | Array |
| `hit_areas` | Array[Dictionary] containing ID/name mappings |
| `physics_path`, `pose_path`, `user_data_path`, `display_info_path` | String |
| `canvas_size`, `canvas_origin` | Vector2 |
| `pixels_per_unit` | float |

Every property has a corresponding native `set_<name>` and `get_<name>` method.
Setters emit `changed`. Schema version defaults to 1; other fields start empty
or zero. `metadata` retains unknown JSON metadata when the importer populates
it. [Motion/expression descriptors](descriptors.md) provide native resources
for the animation catalogs; importer population remains pending.

Texture arrays preserve index order and carry real Redot resource references;
path arrays alone do not establish engine dependencies. Shared references stay
shared after saving and loading. The resource contains no dedicated native
model, motion, allocator, renderer RID or generated-node storage.

Like ordinary Redot resources, these properties are editable and collections
are shared. Runtime instances must treat imported data as read-only and keep
their own state. Consumers still need to validate schema, paths, MOC data and
texture indices before invoking Cubism. This class does not grant permission to
load arbitrary files or make manually constructed descriptors valid.

`tests/native/project/resource_checks.gd` tests all stored fields, Unicode,
repeat-save determinism and an external imported texture dependency. The
integrated native runner executes it in both the source project and exported
game; runtime-created resources are written under its isolated `user://`.
