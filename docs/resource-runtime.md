# Resource-backed runtime loading

Assign a `CubismModelResource` to `GDCubismUserModel.model`. This bridges the
importer to the existing renderer and motion/expression APIs while the preferred
`CubismModel2D` API is being implemented. Assigning `assets` selects legacy loading
and clears `model`; assigning `model` clears `assets`. Tree exit unloads native
state, and reentry reloads the selected source. Explicit reassignment reloads the
model. Requests made during native loading are deferred through the existing
lifecycle guards.

Each runtime owns a complete `ICubismModelSetting` implementation with copied,
stable UTF-8 buffers, SDK-interned ID handles, ordered motion/texture entries, and
layout. The adapter never reads the original `.model3.json`. It does not mutate
the shared resource. Mutating a resource after loading does not update an existing
runtime; explicitly reassign it to reload. Texture references and raw dependency
fingerprints are copied for that runtime too.

The imported path uses supplied texture resources directly. It reads the raw MOC,
motion, expression, physics, pose and user-data files through Redot FileAccess,
which also works inside PCKs. Raw inputs must match their stored SHA-256 hashes;
JSON is decoded and schema-validated before SDK parsing. Limits are 4 MiB JSON,
64 MiB MOC and 512 MiB cumulative raw inputs per load. Unsafe or non-normalized
resource paths, unsupported resource schemas, texture-index/blend mismatches,
invalid MOCs and stale raw data fail loading. This does not replace checked
export: texture/audio imports, unused optional metadata and the complete exported
closure still require the planned validation service.

Layout uses the pinned SDK's lowercase keys (`width`, `height`, `x`, `y`,
`center_x`, `center_y`, `top`, `bottom`, `left`, `right`). Unknown keys remain
ignored by the SDK. The SDK's default height-two normalization is divided out to
preserve the existing pixel-sized drawing when layout is empty. One layout unit
therefore corresponds to half the untransformed canvas height in pixels. Redot
flips the Y axis. The resulting transform is baked into drawable vertices used by
rendering, masks, bounds and mesh-based hit areas; the node transform remains
available for placement in the scene. Singular or non-finite layout transforms
fail loading.

The integration tests exercise resource motion playback, shared-instance
isolation, handle invalidation, tree reentry, legacy/resource switching, invalid
paths, stale hashes, deferred replacement during loading, layout geometry,
Unicode filenames/group names, and loading without the original manifest.
The native runner can compare resource and legacy captures with the same model
and step sequence, and exercises the resource path from an exported PCK after
moving the source project away. That export still uses the test harness's broad
raw-file include filter; selective and checked export remain pending.
