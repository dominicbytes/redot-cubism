# Cubism texture imports

Importer format 3 provisions separate `PortableCompressedTexture2D` resources
from the validated source PNGs. It generates the full mipmap chain and uses
lossless compression. Decoded source colors, including RGB in transparent pixels,
are retained; alpha-border fixing and premultiplication are not applied. Existing
PNG files and their engine-owned import settings are unchanged, so another sprite
can continue using the same PNG with different processing settings.

The original PNG paths remain in model metadata and dependency fingerprints.
The model's `textures` array contains real external Resource references to
`res://cubism_generated/textures/<sha256>.res`. The hash covers the complete
serialized texture, with a fixed internal resource ID for deterministic output.
Identical results share a resource across models and repeat imports. Redot's
lossless PNG/WebP encoding choice may affect the stored bytes and filename, but
neither mode changes decoded pixels. The resource includes its mipmaps; runtime
loading does not regenerate them or require the PNG import settings.

These are persistent project assets, outside `.godot`. Keep referenced generated
textures with saved model resources when copying or versioning a game project.
They are shared across model imports and are not registered as a single model's
disposable `gen_files`. Older revisions remain available to scenes/resources
that still reference them; the importer does not automatically delete assets.
Remove an old revision only after checking its resource references. Generated
model textures must not enter the public addon source/package as test fixtures.

Before decoding, the importer rechecks the PNG's physical containment, size and
hash against the factory's validation. Before loading an existing generated
resource, it compares that file to the hash of a freshly serialized texture.
A mismatched file is rejected without loading or overwriting it, and the previous
model resource is preserved. Move the mismatched file aside and repeat Import
Cubism Model. That action also recreates missing generated textures. Filesystem
checks are snapshots, not atomic protection against concurrent replacement.

An editor-session cache holds at most 128 source/encoding-to-output hash mappings.
It retains no image buffers or texture objects. Reused files are still checked
against the recorded hash before loading; unchanged textures need not be compressed
again for every model that references them. Changing PNG bytes or lossless encoder
settings selects another cache entry. A new editor session verifies serialization
again on its first import.

The implementation uses an automatically removed temporary file only to obtain
Redot's serialized resource bytes. Test logs and recovery history remain in the
persistent work folder.

The low-level `CubismModelFactory.build` retains ordinary imported PNG references
for compatibility; this policy is applied by `CubismModelImporter.import_model`
and its editor action. Existing runtime instances keep their settings/texture
snapshot until reloaded, as described in [resource runtime](resource-runtime.md).

Validation is in `tests/editor/texture_policy_checks.gd`, invoked by
`tools/run_importer_tests.py`. It checks complete pixel/mipmap data, actual
external dependency edges, sharing, deterministic reuse, source/sidecar
preservation, unexpected-file rejection and explicit missing-file regeneration.
The dependency suite additionally checks changed texture pixels after reimport.
Linux debug and release each pass all 13 importer integration checks on pinned
Redot 26.2, including a selective texture export launched with the source project
moved away and original PNGs absent from the package. Exported texture pixels and
mipmap levels match independently decoded source data. Full model raw-dependency
export, renderer parity and Windows qualification remain separate gates.
