# Model resource factory

`CubismModelFactory.build(source_path, strict_optional_files=false)` is a physical
project-source operation. It returns `ok`, bounded `diagnostics`, `warnings`,
and `model` (a CubismModelResource on success, null on failure). It does not save
the result, register an editor importer, or instantiate a rendering node.

The factory validates the model manifest and physical references, inspects a
consistency-checked MOC with temporary SDK objects, and populates canvas data,
MOC version, resource edges, descriptors, groups, hit areas, layout, metadata and
SHA-256 fingerprints. Temporary SDK objects are destroyed before returning.
Offscreen models, unsupported blends and invalid drawable texture indices fail.

Manifest motion fades override nonnegative motion-level values. Declared motions
are required; missing physics, pose, expressions, user data, display info or audio
warn by default and fail in strict-optional mode. Malformed or unsafe references
always fail. Missing optional paths remain indexed with a `missing` fingerprint
so a future editor invalidation service can detect their arrival.

Limits: 4 MiB JSON, 64 MiB other source files, 512 MiB cumulative processed source
bytes; PNG dimensions at most 16384 per axis, 64 megapixels per texture and 128
megapixels cumulatively (powers of 1024). PNG signature/IHDR dimensions are checked
before ResourceLoader. Decoding still belongs to Redot. JSON fingerprints use
the exact bytes decoded, including any initial BOM. Physical containment remains
a snapshot; simultaneous source replacement is not an atomic transaction.

The factory requires already imported PNG/WAV/OGG assets. It does not yet provision
the Cubism-owned texture sampling policy, validate all IDs against the MOC,
resolve display group graphs, apply the full planned importer option set, register
an automatic importer, or track changes. See the [explicit editor import](editor-import.md)
and [runtime resource adapter](resource-runtime.md) for the current integration.
Saving a factory result does not establish checked export or full rendering parity.
