# Cubism texture imports

Importer format 8 provisions separate `PortableCompressedTexture2D` resources
from the validated source PNGs. It generates the full mipmap chain and uses
lossless compression. Decoded source colors, including RGB in transparent pixels,
are retained by default; alpha-border fixing is not applied. Existing
PNG files and their engine-owned import settings are unchanged, so another sprite
can continue using the same PNG with different processing settings.

With `rendering/premultiplied_alpha=true`, the importer converts to RGBA8 and
calls `Image.premultiply_alpha()` **before** generating mipmaps. Generated textures
carry the serialized `cubism_premultiplied_alpha=true` metadata marker. Runtime
and export validation reject a mismatch between this marker and the model option.
Unmarked textures remain compatible with older straight-alpha resources. The
node's read-only `premultiplied_alpha` property reports its loaded encoding;
change the import option and reload the node to change that encoding.

The renderer uses the SDK's premultiplied base-color calculation and matching
screen-color equation. Model/drawable opacity and inherited CanvasItem alpha
are each applied once. Normal, additive, multiply, masked and inverted-mask
shaders support both formats. Redot's integer RGBA8 premultiplication rounds
at most one byte differently from the pinned SDK sample's texture loader.

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
settings or alpha format selects another cache entry. A new editor session verifies serialization
again on its first import.

The implementation uses an automatically removed temporary file only to obtain
Redot's serialized resource bytes. Test logs and recovery history remain in the
persistent work folder.

The low-level `CubismModelFactory.build` retains ordinary imported PNG references
for compatibility; this policy is applied by `CubismModelImporter.import_model`
and its editor action. A factory result requesting premultiplied alpha is not
render-ready until imported textures have been provisioned. Existing runtime instances keep their settings/texture
snapshot until reloaded, as described in [resource runtime](resource-runtime.md).

Validation is in `tests/editor/texture_policy_checks.gd`, invoked by
`tools/run_importer_tests.py`. It checks complete pixel/mipmap data, actual
external dependency edges, sharing, deterministic reuse, source/sidecar
preservation, unexpected-file rejection and explicit missing-file regeneration.
The dependency suite additionally checks changed texture pixels after reimport.
The runner includes a selective texture export launched with the source project
moved away and original PNGs absent from the package, comparing exported texture
pixels and mipmap levels against independently decoded source data. Full model
raw-dependency export, renderer parity and Windows qualification are separate checks.

`tests/editor/alpha_import_checks.gd` extends importer coverage to both alpha
encodings, all pixel/mipmap bytes, resource sharing, cache isolation and switching
back to identical straight-alpha payloads. `tests/native/project/alpha_checks.gd`
checks loaded shader settings, instance isolation, save/reopen, invalid-resource
rejection and exported operation; graphics runs also capture both modes.

Run `tools/run_sdk_shader_tests.py --sdk-root <local-sdk> --output <persistent-dir>`
with `REDOT_BIN` set to the pinned engine to compare 2,016 fragment/blend cases
against six unchanged SDK OpenGL shaders. It requires Linux X11/EGL, GL headers
and a C++17 compiler; the output directory must permit execution. The report
records SDK and addon shader hashes. Cases cover both alpha formats, three blend
modes, mask inversion, coverage, texture alpha, colors, opacity, CanvasItem
modulation and transparent/translucent/opaque backgrounds. The allowed error is
two RGBA8 bytes per channel. This does not establish full SDK model/geometry
parity or Windows support.
